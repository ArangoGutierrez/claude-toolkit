#!/bin/bash
# ai-tell-guard_test.sh - harness for ai-tell-guard.py (SCRIPT_DIR-relative).
#
# The subject is resolved relative to this file, never via $HOME/.claude/...:
# a $HOME path would exercise the deployed copy and make worktree TDD theater.
#
# Tell characters are built with printf UTF-8 byte escapes, never as literals,
# because bash 3.2 has no $'\uXXXX' and a literal here would trip the guard
# itself once this repo is deployed.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
HOOK="$SCRIPT_DIR/ai-tell-guard.py"

# BSD mktemp with no template ignores TMPDIR and uses the darwin user temp dir,
# which a sandboxed shell cannot write. Pass a TMPDIR-rooted template, and abort
# on failure: an empty TMP would silently retarget every fixture write at /.
TMP=$(mktemp -d "${TMPDIR:-/tmp}/ai-tell-guard.XXXXXX")
if [ -z "$TMP" ] || [ ! -d "$TMP" ]; then
    echo "FAILED ai-tell-guard_test: could not create a temp dir"
    exit 1
fi
trap 'rm -rf "$TMP"' EXIT

FAILED=0
TOTAL=0

EMOJI=$(printf '\xf0\x9f\x9a\x80')   # U+1F680 rocket
EMDASH=$(printf '\xe2\x80\x94')      # U+2014 em dash

fail() { echo "FAIL $1"; echo "  got: $2"; FAILED=$((FAILED + 1)); }

# run <payload> [VAR=val ...] -> sets RC and ERR.
# `2>&1 >/dev/null` binds stderr to the capture, then drops stdout: the block
# message the hook writes to stderr is what every assertion below inspects.
# shellcheck disable=SC2069
run() {
    local payload="$1"
    shift
    ERR=$(printf '%s' "$payload" | env "$@" "$HOOK" 2>&1 >/dev/null)
    RC=$?
}

# expect_block <name> <payload> <exact-substring-of-message> [VAR=val ...]
expect_block() {
    TOTAL=$((TOTAL + 1))
    local name="$1" payload="$2" want="$3"
    shift 3
    run "$payload" "$@"
    [ "$RC" = 2 ] || fail "$name rc" "expected 2, got $RC (stderr: $ERR)"
    case "$ERR" in
        *"$want"*) ;;
        *) fail "$name message" "expected substring [$want] in: $ERR" ;;
    esac
}

# expect_allow <name> <payload> [VAR=val ...]
expect_allow() {
    TOTAL=$((TOTAL + 1))
    local name="$1" payload="$2"
    shift 2
    run "$payload" "$@"
    [ "$RC" = 0 ] || fail "$name rc" "expected 0, got $RC (stderr: $ERR)"
    [ -z "$ERR" ] || fail "$name noisy" "expected empty stderr, got: $ERR"
}

write_payload() {  # <file_path> <content>
    printf '{"tool_name":"Write","tool_input":{"file_path":"%s","content":"%s"}}' "$1" "$2"
}
edit_payload() {   # <file_path> <new_string>
    printf '{"tool_name":"Edit","tool_input":{"file_path":"%s","old_string":"placeholder","new_string":"%s"}}' "$1" "$2"
}
notebook_payload() {  # <notebook_path> <new_source>
    printf '{"tool_name":"NotebookEdit","tool_input":{"notebook_path":"%s","new_source":"%s"}}' "$1" "$2"
}

F="$TMP/doc.md"

# --- Detection: every category blocks, and names its exact matched text ---

# 1: emoji
expect_block "test1 emoji" "$(write_payload "$F" "ship it $EMOJI now")" \
    "emoji: \"$EMOJI\" (line 1)"

# 2: em-dash
expect_block "test2 em-dash" "$(write_payload "$F" "one ${EMDASH} two")" \
    "em-dash: \"$EMDASH\" (line 1)"

# 3: Co-Authored-By trailer
expect_block "test3 trailer-coauthor" "$(write_payload "$F" "Co-Authored-By: Claude")" \
    'claude-trailer: "Co-Authored-By: Claude" (line 1)'

# 4: Generated with [Claude Code]
expect_block "test4 trailer-generated" "$(write_payload "$F" "Generated with [Claude Code]")" \
    'claude-trailer: "Generated with [Claude Code]" (line 1)'

# 5: filler phrase
expect_block "test5 filler-phrase" "$(write_payload "$F" "Let us delve into the design.")" \
    'filler-phrase: "delve into" (line 1)'

# 6: filler word
expect_block "test6 filler-word" "$(write_payload "$F" "A comprehensive rewrite.")" \
    'filler-word: "comprehensive" (line 1)'

# --- Clean text passes ---

# 7: clean prose
expect_allow "test7 clean" "$(write_payload "$F" "The parser reads stdin and exits 0 on success.")"

# --- Field extraction across the three tools ---

# 8: Edit reads new_string
expect_block "test8 edit-new_string" "$(edit_payload "$F" "before ${EMDASH} after")" \
    "em-dash: \"$EMDASH\" (line 1)"

# 9: NotebookEdit reads new_source
expect_block "test9 notebook-new_source" "$(notebook_payload "$TMP/nb.ipynb" "print('done $EMOJI')")" \
    "emoji: \"$EMOJI\" (line 1)"

# 10: only the NEW text is inspected, never the file on disk.
# The repo already holds hundreds of files with emoji and em-dashes; reading
# from disk would re-litigate every one of them on the next edit.
DIRTY="$TMP/dirty.md"
printf 'legacy %s prose with a comprehensive %s tell\n' "$EMOJI" "$EMDASH" > "$DIRTY"
expect_allow "test10 disk-ignored" "$(edit_payload "$DIRTY" "a plain replacement line")"

# --- Exemptions ---

# 11: path substring
mkdir -p "$TMP/testdata"
expect_allow "test11 testdata-path" "$(write_payload "$TMP/testdata/x.md" "fixture $EMOJI")"

# 12: self-exemption by basename (the rule file lists the patterns it bans)
expect_allow "test12 self-exempt" \
    "$(write_payload "$TMP/anti-ai-tells.md" "$EMOJI ${EMDASH} Co-Authored-By: Claude comprehensive delve into")"

# 13: env bypass
expect_allow "test13 env-off" "$(write_payload "$F" "ship it $EMOJI")" AI_TELL_GUARD=off

# --- Fail open ---

# 14: no file_path in the payload
expect_allow "test14 no-path" \
    "$(printf '{"tool_name":"Write","tool_input":{"content":"tell %s here"}}' "$EMOJI")"

# 15: malformed JSON on stdin
expect_allow "test15 malformed-json" 'NOT-JSON{{{'

# --- Discrimination: whole-word matching, not substring ---

# 16: "delivery" must not match "delve"
expect_allow "test16 delivery-not-delve" "$(write_payload "$F" "delivery of the package")"

# 17: "scrutinize" must not match "utilize"
expect_allow "test17 scrutinize-not-utilize" "$(write_payload "$F" "scrutinize the data")"

# 20 and 21 are the fixtures that actually exercise the word boundary. Cases 16
# and 17 do not: "delivery" does not contain "delve" and "scrutinize" does not
# contain "utilize", so dropping the \b leaves both green. These two DO contain
# a banned word as a substring, so they flip the moment the boundary is lost.
# 20: "robustness" contains "robust"
expect_allow "test20 robustness-not-robust" "$(write_payload "$F" "robustness of the parser")"

# 21: a code identifier must survive; \b does not fire on an underscore
expect_allow "test21 identifier-not-word" "$(write_payload "$F" "call robust_parser() here")"

# --- Decoding robustness ---

# 18: an ascii-forced locale must not hide a tell. sys.stdin.read() under
# PYTHONCOERCECLOCALE=0 PYTHONUTF8=0 LC_ALL=C decodes the em-dash bytes to
# surrogates ('a\udce2\udc80\udc94b') and the detector silently misses them;
# reading sys.stdin.buffer and decoding utf-8 explicitly is what keeps this green.
expect_block "test18 ascii-locale" "$(write_payload "$F" "one ${EMDASH} two")" \
    "em-dash: \"$EMDASH\" (line 1)" \
    PYTHONCOERCECLOCALE=0 PYTHONUTF8=0 LC_ALL=C

# --- Every distinct match is reported, with its own line number ---

# 19: two categories on two different lines
expect_block "test19 multi-line-number" \
    "$(write_payload "$F" "intro $EMOJI\nplain middle line\nclosing ${EMDASH} end")" \
    "em-dash: \"$EMDASH\" (line 3)"
expect_block "test19 multi-first-category" \
    "$(write_payload "$F" "intro $EMOJI\nplain middle line\nclosing ${EMDASH} end")" \
    "emoji: \"$EMOJI\" (line 1)"

if [ "$FAILED" -ne 0 ]; then
    echo "FAILED ai-tell-guard_test: $FAILED failed assertions across $TOTAL cases"
    exit 1
fi

echo "PASS ai-tell-guard_test: $TOTAL/$TOTAL cases"
exit 0
