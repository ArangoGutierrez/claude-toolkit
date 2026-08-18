#!/usr/bin/env python3
"""ai-tell-guard.py - block AI watermarks in text the model is about to write.

Hook: PreToolUse (matcher: Write|Edit|NotebookEdit)

Reads the hook JSON payload on stdin.
  exit 0 = allow
  exit 2 = block, and stderr becomes Claude's feedback
No other exit code is ever returned; a detection is never exit 1.

Only the NEW text is inspected, never the file on disk. The repo already holds
hundreds of markdown files with emoji and em-dashes, and reading from disk would
re-litigate every one of them on the next unrelated edit.

Tool coverage: Write, Edit and NotebookEdit have their new text scanned for every
category. Bash commands are scanned for the two commit-trailer regexes ONLY, which
closes the `git commit -m "...Co-Authored-By: Claude"` bypass without blocking a
legitimate grep or sed that happens to carry a banned word.

Fail-open policy, and its boundary: malformed JSON, a missing path, a missing
content field, or any unexpected exception BEFORE detection allows the write. This
guard protects style, not an irreversible external action, so a crash in it must
never wedge the session. Guards that gate irreversible outward-facing actions make
the opposite choice and fail closed; this one deliberately does not.

The boundary is detection. Once a tell has been found the process exits 2 no matter
what happens afterwards: a failure while formatting or writing the message degrades
to a minimal ASCII message, never to an allow. A crafted path holding a lone
surrogate used to raise inside report() and turn a detected block into a silent
allow.

Every tell pattern below is written as an escape sequence, so this file stays
pure ASCII and carries no invisible characters of its own.
"""

import json
import os
import re
import sys

# --- Exemptions -------------------------------------------------------------

EXEMPT_PATH_PARTS = (
    "/testdata/",
    "/fixtures/",
    "/locales/",
    "/i18n/",
    "/node_modules/",
    "/.git/",
)

EXEMPT_SUFFIXES = (
    ".snap",
    ".lock",
    ".min.js",
)

# Full filenames, matched on the basename. A plain endswith would also exempt
# my-package-lock.json and notgo.sum.
EXEMPT_BASENAMES = (
    "package-lock.json",
    "go.sum",
)

# Deliberate bypass: these three files ARE the pattern list. A guard cannot hold
# its own patterns, its own test fixtures, or the rule that documents them without
# blocking every edit to itself. This matches the basename ANYWHERE on disk, so an
# unrelated file named anti-ai-tells.md in any directory is exempt too. That is
# wider than "narrow" and is the accepted cost of a self-hosting guard.
SELF_EXEMPT_BASENAMES = (
    "ai-tell-guard.py",
    "ai-tell-guard_test.sh",
    "anti-ai-tells.md",
)

# --- Detectors --------------------------------------------------------------

EMOJI_RE = re.compile(
    "["
    "\U0001F300-\U0001FAFF"
    "\U0001F000-\U0001F0FF"
    "\U0001F1E6-\U0001F1FF"
    "\U00002600-\U000027BF"
    "\U00002B00-\U00002BFF"
    "\U0000FE0F"
    "]"
)

EM_DASH_RE = re.compile("\U00002014")

TRAILER_RES = (
    re.compile(r"Co-Authored-By:\s*Claude", re.IGNORECASE),
    re.compile(r"Generated with \[?Claude Code\]?", re.IGNORECASE),
)

FILLER_PHRASES = (
    "You're absolutely right",
    "You are absolutely right",
    "I apologize for the confusion",
    "It's worth noting that",
    "It is worth noting that",
    "delve into",
    "In today's fast-paced world",
    "Let me know if you need anything else",
    "I hope this helps",
    "As an AI",
    "It's important to note",
)

PHRASE_RES = tuple(
    re.compile(re.escape(phrase), re.IGNORECASE) for phrase in FILLER_PHRASES
)

FILLER_WORDS = (
    "comprehensive",
    "robust",
    "seamless",
    "seamlessly",
    "leverage",
    "leverages",
    "leveraging",
    "utilize",
    "utilizes",
    "utilizing",
    "delve",
    "intricate",
    "crucial",
    "pivotal",
    "meticulous",
    "meticulously",
    "showcase",
    "realm",
    "testament",
    "elevate",
    "embark",
    "furthermore",
    "moreover",
    "underscore",
)

# Whole-word only, so "delivery" does not match "delve" and "scrutinize" does
# not match "utilize". This is a requirement, not an optimization.
WORD_RE = re.compile(r"\b(?:" + "|".join(FILLER_WORDS) + r")\b", re.IGNORECASE)

CONTENT_FIELDS = ("content", "new_string", "new_source")

# The whole block message becomes Claude's feedback, so it is bounded. A 20k line
# file with three filler words per line otherwise emits 2.3 MB of stderr.
MAX_REPORTED = 20
MAX_TEXT = 80
MAX_SUBJECT = 200


def is_exempt(path):
    """Return True when this path is outside the guard's remit.

    Normalize first: on the raw string /repo/.git/../src/main.go contains
    "/.git/" and would buy an exemption for a file that is not in .git at all.
    """
    normalized = os.path.normpath(path)
    if any(part in normalized for part in EXEMPT_PATH_PARTS):
        return True
    if any(normalized.endswith(suffix) for suffix in EXEMPT_SUFFIXES):
        return True
    basename = os.path.basename(normalized)
    return basename in EXEMPT_BASENAMES or basename in SELF_EXEMPT_BASENAMES


def find_trailers(text):
    """Return the commit-trailer tells anywhere in text.

    Matched against the whole text, not line by line, because the \\s* in the
    regex spans a newline: "Co-Authored-By:\\nClaude" is one trailer. The line
    number is derived from the match offset.
    """
    found = []
    seen = set()
    for regex in TRAILER_RES:
        for match in regex.finditer(text):
            lineno = text.count("\n", 0, match.start()) + 1
            key = ("claude-trailer", match.group(0), lineno)
            if key not in seen:
                seen.add(key)
                found.append(key)
    return found


def find_tells(content):
    """Return [(category, matched_text, line_number)] for every distinct tell."""
    found = find_trailers(content)
    seen = set(found)

    def record(category, text, lineno):
        key = (category, text, lineno)
        if key not in seen:
            seen.add(key)
            found.append(key)

    for lineno, line in enumerate(content.split("\n"), start=1):
        for match in EMOJI_RE.finditer(line):
            record("emoji", match.group(0), lineno)
        for match in EM_DASH_RE.finditer(line):
            record("em-dash", match.group(0), lineno)
        for regex in PHRASE_RES:
            for match in regex.finditer(line):
                record("filler-phrase", match.group(0), lineno)
        for match in WORD_RE.finditer(line):
            record("filler-word", match.group(0), lineno)

    found.sort(key=lambda item: item[2])
    return found


def _clip(text, limit):
    """Shorten text for display so one match cannot dominate the message."""
    if len(text) > limit:
        return text[:limit] + "..."
    return text


def _emit(message):
    """Write message to stderr as utf-8, whatever the locale.

    Under an ascii locale stderr uses the backslashreplace error handler, which
    would render the matched em-dash as a literal backslash escape instead of the
    character the model has to remove. errors="replace" keeps a crafted path from
    raising here, which used to cost the whole verdict.
    """
    data = message.encode("utf-8", errors="replace")
    stream = getattr(sys.stderr, "buffer", None)
    if stream is None:
        sys.stderr.write(message)
    else:
        stream.write(data)
        stream.flush()


def report(subject, tells):
    """Write the block message. Never called before the verdict is already 2."""
    parts = [
        "BLOCKED: AI watermark detected in %s.\n\n" % _clip(subject, MAX_SUBJECT)
    ]
    for category, text, lineno in tells[:MAX_REPORTED]:
        parts.append('  %s: "%s" (line %d)\n' % (category, _clip(text, MAX_TEXT), lineno))
    hidden = len(tells) - MAX_REPORTED
    if hidden > 0:
        parts.append("  ... and %d more\n" % hidden)
    parts.append("\nFix: em-dash -> comma, colon or parentheses. Emoji -> remove.\n")
    parts.append("     Filler -> plain specific language. Trailer -> delete.\n")
    parts.append("Bypass for a legitimate case: AI_TELL_GUARD=off\n")
    _emit("".join(parts))


def block(subject, tells):
    """Return 2, and report as a best effort.

    The verdict is decided here and cannot be changed by anything that happens
    while reporting. Any failure degrades to a minimal ASCII message, and a
    failure to emit even that is still a block.
    """
    try:
        report(subject, tells)
    except Exception:
        try:
            _emit("BLOCKED: AI watermark detected. Bypass: AI_TELL_GUARD=off\n")
        except Exception:
            pass
    return 2


def main():
    if os.environ.get("AI_TELL_GUARD") == "off":
        return 0

    # Decode explicitly rather than trusting sys.stdin: under an ascii locale
    # sys.stdin.read() turns the tell bytes into surrogates and every detector
    # silently misses them.
    raw = sys.stdin.buffer.read().decode("utf-8", errors="replace")
    payload = json.loads(raw)
    tool_input = payload.get("tool_input") or {}

    if payload.get("tool_name") == "Bash":
        return check_command(tool_input.get("command"))

    path = tool_input.get("file_path") or tool_input.get("notebook_path")
    if not path:
        return 0
    if is_exempt(path):
        return 0

    content = None
    for field in CONTENT_FIELDS:
        value = tool_input.get(field)
        if isinstance(value, str) and value:
            content = value
            break
    if content is None:
        return 0

    tells = find_tells(content)
    if not tells:
        return 0

    return block("text being written to %s" % path, tells)


def check_command(command):
    """Scan a Bash command for commit trailers only.

    Without this, `git commit -m "...Co-Authored-By: Claude"` bypasses the guard
    entirely and the trailer detector is close to inert. Only the two trailer
    regexes run here: blocking emoji, em-dashes or filler in a command would break
    an ordinary grep or sed for no gain.

    No shell parsing. A trailer is a distinctive literal string, so a regex over
    the raw command text catches `-m`, `--amend`, `-F` and heredoc forms alike,
    with none of the quote-adjacency fragility that a shell lexer exists to solve.
    Path exemptions do not apply, because there is no path.
    """
    if not isinstance(command, str) or not command:
        return 0
    tells = find_trailers(command)
    if not tells:
        return 0
    return block("the Bash command", tells)


if __name__ == "__main__":
    try:
        CODE = main()
    except Exception:
        # Fail open. Reaching here means detection never completed, because
        # everything after it runs inside block(), which cannot raise.
        CODE = 0
    sys.exit(CODE)
