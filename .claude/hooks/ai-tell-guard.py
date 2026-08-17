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

Fail-open policy: malformed JSON, a missing path, a missing content field, or any
unexpected exception allows the write. This guard protects style, not an
irreversible external action, so a crash in it must never wedge the session.
Guards that gate irreversible outward-facing actions make the opposite choice and
fail closed; this one deliberately does not.

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
    "package-lock.json",
    "go.sum",
)

# Deliberate, narrow bypass: these three files ARE the pattern list. A guard
# cannot hold its own patterns, its own test fixtures, or the rule that
# documents them without blocking every edit to itself. Matched on the exact
# basename only, so an unrelated file elsewhere gains nothing from the name.
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


def is_exempt(path):
    """Return True when this path is outside the guard's remit."""
    if any(part in path for part in EXEMPT_PATH_PARTS):
        return True
    if any(path.endswith(suffix) for suffix in EXEMPT_SUFFIXES):
        return True
    return os.path.basename(path) in SELF_EXEMPT_BASENAMES


def find_tells(content):
    """Return [(category, matched_text, line_number)] for every distinct tell."""
    found = []
    seen = set()

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
        for regex in TRAILER_RES:
            for match in regex.finditer(line):
                record("claude-trailer", match.group(0), lineno)
        for regex in PHRASE_RES:
            for match in regex.finditer(line):
                record("filler-phrase", match.group(0), lineno)
        for match in WORD_RE.finditer(line):
            record("filler-word", match.group(0), lineno)

    return found


def report(path, tells):
    """Write the block message to stderr, encoded utf-8.

    Under an ascii locale stderr uses the backslashreplace error handler, which
    would render the matched em-dash as a literal backslash escape instead of
    the character the model has to remove. Encoding explicitly keeps this
    feedback byte-identical in every locale.
    """
    parts = ["BLOCKED: AI watermark detected in text being written to %s.\n\n" % path]
    for category, text, lineno in tells:
        parts.append('  %s: "%s" (line %d)\n' % (category, text, lineno))
    parts.append("\nFix: em-dash -> comma, colon or parentheses. Emoji -> remove.\n")
    parts.append("     Filler -> plain specific language. Trailer -> delete.\n")
    parts.append("Bypass for a legitimate case: AI_TELL_GUARD=off\n")
    message = "".join(parts)

    stream = getattr(sys.stderr, "buffer", None)
    if stream is None:
        sys.stderr.write(message)
    else:
        stream.write(message.encode("utf-8"))
        stream.flush()


def main():
    if os.environ.get("AI_TELL_GUARD") == "off":
        return 0

    # Decode explicitly rather than trusting sys.stdin: under an ascii locale
    # sys.stdin.read() turns the tell bytes into surrogates and every detector
    # silently misses them.
    raw = sys.stdin.buffer.read().decode("utf-8", errors="replace")
    payload = json.loads(raw)
    tool_input = payload.get("tool_input") or {}

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

    report(path, tells)
    return 2


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception:  # fail open, see the module docstring
        sys.exit(0)
