"""Black-box tests for check_skill_frontmatter.py.

Each rule gets a fixture that the rule flips, and every assertion compares the
exact output lines and exit code. Test names carry the rule code
(test_rule_e3_...) so check_skill_frontmatter_mutants.sh can select one rule's
tests with -k rule_e3.
"""
import importlib.util
import os
import subprocess
import sys

import pytest

HERE = os.path.dirname(os.path.abspath(__file__))
SCRIPT = os.path.join(HERE, "check_skill_frontmatter.py")
SUMMARY_CLEAN = "0 errors, 0 warnings, 1 files checked"
SUMMARY_ONE_ERROR = "1 errors, 0 warnings, 1 files checked"


def write_skill(root, dirname, frontmatter, body="Body text.\n"):
    skill_dir = root / dirname
    skill_dir.mkdir(parents=True)
    path = skill_dir / "SKILL.md"
    path.write_text("---\n" + frontmatter + "---\n" + body, encoding="utf-8")
    return str(path)


def run(*args):
    proc = subprocess.run([sys.executable, SCRIPT] + [str(arg) for arg in args],
                          capture_output=True, text=True)
    return proc.returncode, proc.stdout.splitlines(), proc.stderr


def load_checker():
    """Import the checker from SCRIPT without leaving a __pycache__ beside it."""
    sys.dont_write_bytecode = True
    spec = importlib.util.spec_from_file_location("check_skill_frontmatter", SCRIPT)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def test_clean_skill_with_every_allowed_key_passes(tmp_path):
    write_skill(tmp_path, "good-skill", (
        "name: good-skill\n"
        "description: Formats tables. Use when a test needs a clean skill.\n"
        "license: MIT\n"
        "compatibility: Needs Python 3.9 or later\n"
        "metadata:\n"
        "  author: test\n"
        "allowed-tools: Bash Read\n"
        "disable-model-invocation: true\n"
        "user-invocable: false\n"
        "argument-hint: <path>\n"
        "arguments: path\n"
        "model: inherit\n"
        "effort: high\n"
        "context: fork\n"
        "agent: general-purpose\n"
        "background: false\n"
        "hooks: {}\n"
        "paths: src/**\n"
        "disallowed-tools: Write\n"
        "shell: bash\n"
    ))
    assert run(tmp_path) == (0, [SUMMARY_CLEAN], "")


def test_single_file_path_is_checked(tmp_path):
    path = write_skill(tmp_path, "file-skill", "name: file-skill\ndescription: Use when asked.\n")
    assert run(path) == (0, [SUMMARY_CLEAN], "")


def test_rule_e1_invalid_yaml_reports_the_line(tmp_path):
    path = write_skill(tmp_path, "bad-yaml", (
        "name: bad-yaml\n"
        "description: Post-earnings review: fetches a transcript. Use when asked.\n"
    ))
    rc, out, _ = run(tmp_path)
    assert (rc, out) == (1, [
        path + ":3: E1 frontmatter is not valid YAML (mapping values are not allowed here); "
               "quote the value on this line",
        path + ":3: E2 description: value contains ': '; quote the whole value",
        "2 errors, 0 warnings, 1 files checked",
    ])


def test_rule_e1_missing_frontmatter_block(tmp_path):
    skill_dir = tmp_path / "no-block"
    skill_dir.mkdir()
    path = skill_dir / "SKILL.md"
    path.write_text("# Just a heading\n", encoding="utf-8")
    rc, out, _ = run(tmp_path)
    assert (rc, out) == (1, [
        str(path) + ":1: E1 no frontmatter block; start the file with a --- line "
                    "and close the block with another",
        SUMMARY_ONE_ERROR,
    ])


def test_rule_e1_frontmatter_that_is_not_a_mapping(tmp_path):
    path = write_skill(tmp_path, "list-skill", "- just\n- a list\n")
    rc, out, _ = run(tmp_path)
    assert (rc, out) == (1, [
        path + ":2: E1 frontmatter is not a mapping of keys to values",
        SUMMARY_ONE_ERROR,
    ])


def test_rule_e1_unclosed_frontmatter_block(tmp_path):
    skill_dir = tmp_path / "open-block"
    skill_dir.mkdir()
    path = skill_dir / "SKILL.md"
    path.write_text("---\nname: open-block\ndescription: Use when asked.\n", encoding="utf-8")
    rc, out, _ = run(tmp_path)
    assert (rc, out) == (1, [
        str(path) + ":1: E1 no frontmatter block; start the file with a --- line "
                    "and close the block with another",
        SUMMARY_ONE_ERROR,
    ])


def test_rule_e1_byte_order_mark(tmp_path):
    skill_dir = tmp_path / "bom-skill"
    skill_dir.mkdir()
    path = skill_dir / "SKILL.md"
    path.write_bytes(b"\xef\xbb\xbf---\nname: bom-skill\ndescription: Use when asked.\n---\nBody.\n")
    rc, out, _ = run(tmp_path)
    assert (rc, out) == (1, [
        str(path) + ":1: E1 file starts with a UTF-8 byte order mark; save it without one",
        SUMMARY_ONE_ERROR,
    ])


def test_rule_e1_duplicate_key(tmp_path):
    # PyYAML keeps the last value without a word; other parsers keep the first.
    path = write_skill(tmp_path, "dup-skill", (
        "name: dup-skill\n"
        "description: Use when asked.\n"
        "description: Second.\n"
    ))
    rc, out, _ = run(tmp_path)
    assert (rc, out) == (1, [
        path + ":3: W1 description has no selection cue; add a 'Use when ...' clause",
        path + ":4: E1 duplicate key 'description' (first on line 3); parsers disagree on "
               "which value wins, keep one",
        "1 errors, 1 warnings, 1 files checked",
    ])


def test_crlf_line_endings_pass(tmp_path):
    skill_dir = tmp_path / "crlf-skill"
    skill_dir.mkdir()
    (skill_dir / "SKILL.md").write_bytes(
        b"---\r\nname: crlf-skill\r\ndescription: Use when asked.\r\n---\r\nBody.\r\n")
    assert run(tmp_path) == (0, [SUMMARY_CLEAN], "")


def test_crlf_text_passes_check_text_directly():
    # The CLI reads files in text mode, which turns CRLF into LF before check_text
    # sees it; a caller that passes in-memory text (the hook) does not.
    text = "---\r\nname: crlf-skill\r\ndescription: Use when asked.\r\n---\r\nBody.\r\n"
    assert load_checker().check_text("/skills/crlf-skill/SKILL.md", text) == []


def test_non_utf8_file_exits_2_naming_it(tmp_path):
    skill_dir = tmp_path / "latin-skill"
    skill_dir.mkdir()
    path = skill_dir / "SKILL.md"
    path.write_bytes(b"---\nname: latin-skill\ndescription: Use when asked \xe9\n---\nBody.\n")
    assert run(tmp_path) == (
        2, [], "check_skill_frontmatter: %s is not UTF-8 (invalid continuation byte)\n" % path)


def test_rule_e2_colon_on_a_continuation_line(tmp_path):
    path = write_skill(tmp_path, "wrapped-skill", (
        "name: wrapped-skill\n"
        "description: Use when asked about a\n"
        "  second: line\n"
    ))
    rc, out, _ = run(tmp_path)
    assert (rc, out) == (1, [
        path + ":3: E2 description: value contains ': '; quote the whole value",
        path + ":4: E1 frontmatter is not valid YAML (mapping values are not allowed here); "
               "quote the value on this line",
        "2 errors, 0 warnings, 1 files checked",
    ])


def test_rule_e2_hash_cuts_the_value(tmp_path):
    # The parsed description is "Watch the": the cue after ' #' is gone, so W1 fires too.
    path = write_skill(tmp_path, "hash-skill", (
        "name: hash-skill\n"
        "description: Watch the #ops thread. Use when asked.\n"
    ))
    rc, out, _ = run(tmp_path)
    assert (rc, out) == (1, [
        path + ":3: E2 description: value contains ' #', which starts a YAML comment "
               "and cuts the value; quote the whole value",
        path + ":3: W1 description has no selection cue; add a 'Use when ...' clause",
        "1 errors, 1 warnings, 1 files checked",
    ])


def test_rule_e2_hash_in_a_value_on_the_next_line(tmp_path):
    # A plain value may start on the line after its key; ' #' cuts it the same way.
    path = write_skill(tmp_path, "nextline-skill", (
        "name: nextline-skill\n"
        "description:\n"
        "  Use when asked about the #ops channel.\n"
    ))
    rc, out, _ = run(tmp_path)
    assert (rc, out) == (1, [
        path + ":3: E2 description: value contains ' #', which starts a YAML comment "
               "and cuts the value; quote the whole value",
        SUMMARY_ONE_ERROR,
    ])


@pytest.mark.parametrize("value", [
    "'Review: a thing. Use when asked.'",
    '"Watch the #ops thread. Use when asked."',
    ">-\n  Review: a thing #1. Use when asked.",
])
def test_rule_e2_quoted_and_block_values_pass(tmp_path, value):
    write_skill(tmp_path, "safe-skill", "name: safe-skill\ndescription: " + value + "\n")
    assert run(tmp_path) == (0, [SUMMARY_CLEAN], "")


def test_rule_e3_name_must_match_directory(tmp_path):
    path = write_skill(tmp_path, "my-skill", "name: other-skill\ndescription: Use when asked.\n")
    rc, out, _ = run(tmp_path)
    assert (rc, out) == (1, [
        path + ":2: E3 name 'other-skill' does not match its directory 'my-skill'",
        SUMMARY_ONE_ERROR,
    ])


@pytest.mark.parametrize("name", ["My_Skill", "-lead", "trail-", "double--hyphen", "a" * 65])
def test_rule_e3_name_charset_and_length(tmp_path, name):
    path = write_skill(tmp_path, name, "name: " + name + "\ndescription: Use when asked.\n")
    rc, out, _ = run(tmp_path)
    assert (rc, out) == (1, [
        path + ":2: E3 name %r must be 1-64 characters of a-z, 0-9 and single hyphens, "
               "with no hyphen at either end" % name,
        SUMMARY_ONE_ERROR,
    ])


def test_rule_e3_missing_name(tmp_path):
    path = write_skill(tmp_path, "nameless", "description: Use when asked.\n")
    rc, out, _ = run(tmp_path)
    assert (rc, out) == (1, [path + ":1: E3 name is missing", SUMMARY_ONE_ERROR])


def test_rule_e4_description_over_1024(tmp_path):
    text = "Use when asked. " + "x" * 1009
    path = write_skill(tmp_path, "long-skill", "name: long-skill\ndescription: " + text + "\n")
    rc, out, _ = run(tmp_path)
    assert (rc, out) == (1, [
        path + ":3: E4 description is 1025 characters; the limit is 1024",
        SUMMARY_ONE_ERROR,
    ])


def test_rule_e4_description_of_exactly_1024_passes(tmp_path):
    text = "Use when asked. " + "x" * 1008
    write_skill(tmp_path, "edge-skill", "name: edge-skill\ndescription: " + text + "\n")
    assert run(tmp_path) == (0, [SUMMARY_CLEAN], "")


def test_rule_e4_missing_description(tmp_path):
    path = write_skill(tmp_path, "bare-skill", "name: bare-skill\n")
    rc, out, _ = run(tmp_path)
    assert (rc, out) == (1, [path + ":1: E4 description is missing or empty", SUMMARY_ONE_ERROR])


@pytest.mark.parametrize("value", ['""', "' '"])
def test_rule_e4_empty_description(tmp_path, value):
    path = write_skill(tmp_path, "empty-skill", "name: empty-skill\ndescription: " + value + "\n")
    rc, out, _ = run(tmp_path)
    assert (rc, out) == (1, [path + ":3: E4 description is missing or empty", SUMMARY_ONE_ERROR])


@pytest.mark.parametrize("key, advice", [
    ("tools", "not a skill key (subagent syntax) and nothing reads it; delete it, "
              "or use allowed-tools / disallowed-tools"),
    ("when_to_use", "move its text into description after 'Use when'"),
    ("triggers", "move its text into description"),
    ("user_invocable", "use '-' instead of '_'"),
    ("color", "not in the spec or the Claude Code extension list"),
])
def test_rule_e5_unknown_keys_name_the_fix(tmp_path, key, advice):
    path = write_skill(tmp_path, "keyed-skill",
                       "name: keyed-skill\ndescription: Use when asked.\n" + key + ": x\n")
    rc, out, _ = run(tmp_path)
    assert (rc, out) == (1, [
        path + ":4: E5 unknown key '%s': %s" % (key, advice),
        SUMMARY_ONE_ERROR,
    ])


def test_rule_e5_tools_list_block(tmp_path):
    path = write_skill(tmp_path, "tools-skill", (
        "name: tools-skill\n"
        "description: Use when asked.\n"
        "tools:\n"
        "  - Read\n"
        "  - Bash\n"
    ))
    rc, out, _ = run(tmp_path)
    assert (rc, out) == (1, [
        path + ":4: E5 unknown key 'tools': not a skill key (subagent syntax) and nothing "
               "reads it; delete it, or use allowed-tools / disallowed-tools",
        SUMMARY_ONE_ERROR,
    ])


def test_rule_e6_allowed_tools_list(tmp_path):
    path = write_skill(tmp_path, "list-tools", (
        "name: list-tools\n"
        "description: Use when asked.\n"
        "allowed-tools:\n"
        "  - Bash\n"
        "  - Read\n"
    ))
    rc, out, _ = run(tmp_path)
    assert (rc, out) == (1, [
        path + ":4: E6 allowed-tools is a YAML list; write it as one space-separated string",
        SUMMARY_ONE_ERROR,
    ])


def test_rule_e6_allowed_tools_commas(tmp_path):
    path = write_skill(tmp_path, "comma-tools",
                       "name: comma-tools\ndescription: Use when asked.\nallowed-tools: Bash, Read\n")
    rc, out, _ = run(tmp_path)
    assert (rc, out) == (1, [
        path + ":4: E6 allowed-tools is comma-separated; separate tools with spaces",
        SUMMARY_ONE_ERROR,
    ])


def test_rule_e6_allowed_tools_not_a_string(tmp_path):
    path = write_skill(tmp_path, "number-tools",
                       "name: number-tools\ndescription: Use when asked.\nallowed-tools: 5\n")
    rc, out, _ = run(tmp_path)
    assert (rc, out) == (1, [
        path + ":4: E6 allowed-tools must be a space-separated string",
        SUMMARY_ONE_ERROR,
    ])


def test_rule_e7_compatibility_over_500(tmp_path):
    path = write_skill(tmp_path, "compat-skill", (
        "name: compat-skill\n"
        "description: Use when asked.\n"
        "compatibility: " + "y" * 501 + "\n"
    ))
    rc, out, _ = run(tmp_path)
    assert (rc, out) == (1, [
        path + ":4: E7 compatibility is 501 characters; the limit is 500",
        SUMMARY_ONE_ERROR,
    ])


def test_rule_w1_no_cue_is_a_warning_only(tmp_path):
    path = write_skill(tmp_path, "plain-skill", "name: plain-skill\ndescription: Formats tables.\n")
    rc, out, _ = run(tmp_path)
    assert (rc, out) == (0, [
        path + ":3: W1 description has no selection cue; add a 'Use when ...' clause",
        "0 errors, 1 warnings, 1 files checked",
    ])


@pytest.mark.parametrize("description", [
    "Use ONLY when asked.",
    "Triggers on /x.",
    "When the user asks for x.",
    "Triggered by /x.",
    "Use to format tables.",
    "Use this when tables drift.",
])
def test_rule_w1_cue_variants_pass(tmp_path, description):
    write_skill(tmp_path, "cue-skill", "name: cue-skill\ndescription: " + description + "\n")
    assert run(tmp_path) == (0, [SUMMARY_CLEAN], "")


def test_exclude_skips_matching_paths(tmp_path):
    write_skill(tmp_path, "good-skill", "name: good-skill\ndescription: Use when asked.\n")
    write_skill(tmp_path / "fixtures", "broken", "name: wrong\n")
    assert run("--exclude", "*/fixtures/*", tmp_path) == (0, [SUMMARY_CLEAN], "")


def test_directory_without_skills_exits_2(tmp_path):
    assert run(tmp_path) == (2, [], "check_skill_frontmatter: no SKILL.md under %s\n" % tmp_path)


def test_missing_path_exits_2(tmp_path):
    missing = tmp_path / "nope"
    assert run(missing) == (2, [], "check_skill_frontmatter: no such path: %s\n" % missing)


def test_no_arguments_is_a_usage_error():
    rc, out, err = run()
    assert (rc, out) == (2, [])
    assert err.endswith("error: the following arguments are required: PATH\n")
