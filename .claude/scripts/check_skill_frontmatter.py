#!/usr/bin/env python3
"""Check SKILL.md frontmatter against the agentskills.io spec.

Harnesses that follow the spec give the model only `name` and `description`,
so a skill whose frontmatter they cannot parse, or whose guidance sits in a key
they ignore, fires at the wrong time or not at all.

Rules (errors fail the run; warnings print and never fail):
  E1  the frontmatter block exists (no byte order mark), repeats no key and
      parses as a YAML mapping
  E2  no unquoted ': ' or ' #' in a plain top-level value
  E3  name: a-z, 0-9 and single hyphens, at most 64 characters, equal to its directory
  E4  description: non-empty, at most 1024 characters
  E5  every key is a spec key or an allowed Claude Code extension
  E6  allowed-tools: one space-separated string
  E7  compatibility: at most 500 characters
  W1  description carries a selection cue ("Use when ...")

Usage: check_skill_frontmatter.py [--exclude GLOB]... PATH...
Exit:  0 no errors, 1 errors, 2 usage error, unreadable path, a PATH with no
       SKILL.md under it, or PyYAML missing.
"""
import argparse
import collections
import fnmatch
import os
import re
import sys

try:
    import yaml
except ImportError:  # main() reports this as exit 2; check_text() raises
    yaml = None

SPEC_KEYS = frozenset({
    "name", "description", "license", "compatibility", "metadata", "allowed-tools",
})
# Claude Code skill keys as documented in 2026-09. A key added to Claude Code
# later fails E5 until it is listed here.
EXTENSION_KEYS = frozenset({
    "disable-model-invocation", "user-invocable", "argument-hint", "arguments",
    "model", "effort", "context", "agent", "background", "hooks", "paths",
    "disallowed-tools", "shell",
})
ALLOWED_KEYS = SPEC_KEYS | EXTENSION_KEYS
KEY_ADVICE = {
    "when_to_use": "move its text into description after 'Use when'",
    "triggers": "move its text into description",
    "tools": ("not a skill key (subagent syntax) and nothing reads it; delete it, "
              "or use allowed-tools / disallowed-tools"),
}
NAME_RE = re.compile(r"^[a-z0-9]+(-[a-z0-9]+)*$")
TOP_KEY_RE = re.compile(r"^([A-Za-z0-9_.-]+):(.*)$")
CUE_RE = re.compile(
    r"\b(use (only |this |it )?when|use (this|for|to)|triggers? (on|when|by)"
    r"|triggered by|trigger with|when the user)\b",
    re.IGNORECASE,
)
QUOTED_OR_BLOCK = ("'", '"', "|", ">", "[", "{")

# subject names what a finding is about, independent of its wording, so a
# caller can tell a new error from one the file already had.
Finding = collections.namedtuple("Finding", "path line code subject message")


def format_finding(finding):
    return "%s:%d: %s %s" % (finding.path, finding.line, finding.code, finding.message)


def _split_frontmatter(text):
    """Return the frontmatter lines (file line 2 onward), or None without a block."""
    lines = text.split("\n")
    if not lines or lines[0].rstrip() != "---":
        return None
    for index in range(1, len(lines)):
        if lines[index].rstrip() == "---":
            return lines[1:index]
    return None


def _top_level_entries(fm_lines):
    """List every top-level key as [key, file line, raw value parts], in order."""
    entries = []
    for offset, line in enumerate(fm_lines):
        match = TOP_KEY_RE.match(line)
        if match:
            entries.append([match.group(1), offset + 2, [match.group(2).strip()]])
        elif entries and line[:1] in (" ", "\t"):
            entries[-1][2].append(line.strip())
    return entries


def check_text(path, text):
    """Return the findings for one SKILL.md, sorted by line and code."""
    if yaml is None:
        raise RuntimeError("PyYAML is required (pip install pyyaml)")
    findings = []

    def add(line, code, subject, message):
        findings.append(Finding(path, line, code, subject, message))

    if text.startswith("﻿"):  # rule:E1
        add(1, "E1", "frontmatter", "file starts with a UTF-8 byte order mark; save it without one")
        return findings
    fm_lines = _split_frontmatter(text)
    if fm_lines is None:  # rule:E1
        add(1, "E1", "frontmatter",
            "no frontmatter block; start the file with a --- line and close the block with another")
        return findings
    entries = _top_level_entries(fm_lines)

    first_line = {}
    for key, line, _parts in entries:
        if key in first_line:  # rule:E1
            add(line, "E1", "duplicate " + key,
                "duplicate key '%s' (first on line %d); parsers disagree on which value wins, "
                "keep one" % (key, first_line[key]))
        else:
            first_line[key] = line

    for key, line, parts in entries:
        first = parts[0]
        if not first or first.startswith(QUOTED_OR_BLOCK):
            continue
        joined = " ".join(part for part in parts if part)
        if ": " in joined:  # rule:E2
            add(line, "E2", key, "%s: value contains ': '; quote the whole value" % key)
        if " #" in joined:  # rule:E2
            add(line, "E2", key,
                "%s: value contains ' #', which starts a YAML comment and cuts the value; "
                "quote the whole value" % key)

    for key, line, _parts in entries:
        if key not in ALLOWED_KEYS:  # rule:E5
            if key in KEY_ADVICE:
                advice = KEY_ADVICE[key]
            elif "_" in key:
                advice = "use '-' instead of '_'"
            else:
                advice = "not in the spec or the Claude Code extension list"
            add(line, "E5", key, "unknown key '%s': %s" % (key, advice))

    try:
        data = yaml.safe_load("\n".join(fm_lines))
        error = None
    except yaml.YAMLError as exc:
        data, error = None, exc
    if error is not None:  # rule:E1
        mark = getattr(error, "problem_mark", None)
        problem = getattr(error, "problem", None) or str(error).split("\n")[0]
        add(mark.line + 2 if mark else 1, "E1", "frontmatter",
            "frontmatter is not valid YAML (%s); quote the value on this line" % problem)
    elif not isinstance(data, dict):  # rule:E1
        add(2, "E1", "frontmatter", "frontmatter is not a mapping of keys to values")

    if isinstance(data, dict):
        def line_of(key):
            return first_line.get(key, 1)

        name = data.get("name")
        directory = os.path.basename(os.path.dirname(os.path.abspath(path)))
        if name is None:  # rule:E3
            add(line_of("name"), "E3", "name", "name is missing")
        elif not isinstance(name, str) or len(name) > 64 or not NAME_RE.match(name):  # rule:E3
            add(line_of("name"), "E3", "name",
                "name %r must be 1-64 characters of a-z, 0-9 and single hyphens, "
                "with no hyphen at either end" % (name,))
        elif name != directory:  # rule:E3
            add(line_of("name"), "E3", "name",
                "name %r does not match its directory %r" % (name, directory))

        description = data.get("description")
        if not isinstance(description, str) or not description.strip():  # rule:E4
            add(line_of("description"), "E4", "description", "description is missing or empty")
        elif len(description) > 1024:  # rule:E4
            add(line_of("description"), "E4", "description",
                "description is %d characters; the limit is 1024" % len(description))
        elif not CUE_RE.search(description):  # rule:W1
            add(line_of("description"), "W1", "description",
                "description has no selection cue; add a 'Use when ...' clause")

        if "allowed-tools" in data:
            tools = data["allowed-tools"]
            if isinstance(tools, list):  # rule:E6
                add(line_of("allowed-tools"), "E6", "allowed-tools",
                    "allowed-tools is a YAML list; write it as one space-separated string")
            elif not isinstance(tools, str):  # rule:E6
                add(line_of("allowed-tools"), "E6", "allowed-tools",
                    "allowed-tools must be a space-separated string")
            elif "," in tools:  # rule:E6
                add(line_of("allowed-tools"), "E6", "allowed-tools",
                    "allowed-tools is comma-separated; separate tools with spaces")

        compatibility = data.get("compatibility")
        if isinstance(compatibility, str) and len(compatibility) > 500:  # rule:E7
            add(line_of("compatibility"), "E7", "compatibility",
                "compatibility is %d characters; the limit is 500" % len(compatibility))

    findings.sort(key=lambda finding: (finding.line, finding.code))
    return findings


def _collect(paths, excludes):
    """Return SKILL.md paths under each PATH; raise ValueError for a bad PATH."""
    files = []
    for path in paths:
        if os.path.isfile(path):
            found = [path]
        elif os.path.isdir(path):
            found = []
            for dirpath, dirnames, filenames in os.walk(path):
                dirnames.sort()
                if "SKILL.md" in filenames:
                    found.append(os.path.join(dirpath, "SKILL.md"))
        else:
            raise ValueError("no such path: %s" % path)
        found = [f for f in found if not any(fnmatch.fnmatch(f, glob) for glob in excludes)]
        if not found:
            raise ValueError("no SKILL.md under %s" % path)
        files.extend(found)
    return files


def main(argv=None):
    parser = argparse.ArgumentParser(description="Check SKILL.md frontmatter against the agentskills.io spec.")
    parser.add_argument("--exclude", action="append", default=[], metavar="GLOB",
                        help="skip SKILL.md paths matching GLOB (repeatable)")
    parser.add_argument("paths", nargs="+", metavar="PATH", help="a SKILL.md or a directory to walk")
    args = parser.parse_args(argv)
    if yaml is None:
        sys.stderr.write("check_skill_frontmatter: PyYAML is required (pip install pyyaml)\n")
        return 2
    try:
        files = _collect(args.paths, args.exclude)
    except ValueError as exc:
        sys.stderr.write("check_skill_frontmatter: %s\n" % exc)
        return 2
    texts = []
    for path in files:
        try:
            with open(path, encoding="utf-8") as handle:
                texts.append((path, handle.read()))
        except UnicodeDecodeError as exc:
            sys.stderr.write("check_skill_frontmatter: %s is not UTF-8 (%s)\n" % (path, exc.reason))
            return 2
        except OSError as exc:
            sys.stderr.write("check_skill_frontmatter: cannot read %s (%s)\n" % (path, exc.strerror))
            return 2
    errors = warnings = 0
    for path, text in texts:
        for finding in check_text(path, text):
            print(format_finding(finding))
            if finding.code.startswith("E"):
                errors += 1
            else:
                warnings += 1
    print("%d errors, %d warnings, %d files checked" % (errors, warnings, len(texts)))
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
