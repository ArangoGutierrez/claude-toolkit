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
bash_payload() {   # <command> ; shell commands carry quotes, so escape them for JSON
    local cmd=${1//\"/\\\"}
    printf '{"tool_name":"Bash","tool_input":{"command":"%s"}}' "$cmd"
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

# =====================================================================
# Fix round. Everything below pins a behaviour that a mutation could break
# while the original 22 cases stayed green.
# =====================================================================

# --- FIX-1: a detected tell must never become an allow ---

# 22: a lone surrogate in the path makes the utf-8 encode of the block message
# fail. Detection has already found the em-dash, so the verdict must stay 2.
# The old blanket except around reporting turned this into a silent allow.
SURROGATE=$(printf '\\u%s' 'd83d')
expect_block "test22 report-failure-still-blocks" \
    "$(write_payload "/tmp/${SURROGATE}.md" "a ${EMDASH} b")" \
    'em-dash:'

# --- FIX-2: the block message is bounded ---

# 23: every byte of this becomes Claude's feedback, so it has to stay small.
# 20k lines x 3 filler words used to emit 2,366,916 bytes.
BIG=$(awk 'BEGIN{for(i=0;i<20000;i++) printf "a comprehensive robust seamless line\\n"}')
TOTAL=$((TOTAL + 1))
run "$(write_payload "$F" "$BIG")"
[ "$RC" = 2 ] || fail "test23 flood rc" "expected 2, got $RC"
BYTES=$(printf '%s' "$ERR" | wc -c | tr -d ' ')
[ "$BYTES" -lt 8192 ] || fail "test23 flood size" "stderr was $BYTES bytes, want < 8192"
case "$ERR" in
    *"and "*"more"*) ;;
    *) fail "test23 flood summary" "no 'and N more' line in: $ERR" ;;
esac

# 24: one match can be huge on its own, because \s* in the trailer regex
# swallows a whitespace run. The matched text has to be clipped.
LONG_TRAILER="Co-Authored-By:$(awk 'BEGIN{for(i=0;i<200;i++) printf " "}')Claude"
TOTAL=$((TOTAL + 1))
run "$(write_payload "$F" "$LONG_TRAILER")"
[ "$RC" = 2 ] || fail "test24 clip rc" "expected 2, got $RC"
LONGEST=$(printf '%s' "$ERR" | awk '{ if (length($0) > m) m = length($0) } END { print m+0 }')
[ "$LONGEST" -le 120 ] || fail "test24 clip" "longest stderr line is $LONGEST chars, want <= 120"

# --- FIX-3: the env escape hatch is the EXACT string "off" ---

# 25: anything else still blocks. A truthy check would disable the guard for
# anyone who sets AI_TELL_GUARD=1 and no test would notice.
for V in on 1 OFF Off ""; do
    expect_block "test25 env-not-off[$V]" \
        "$(write_payload "$F" "ship it $EMOJI")" 'emoji:' AI_TELL_GUARD="$V"
done

# --- FIX-3: every path exemption has its own case ---

# 26: one per entry in EXEMPT_PATH_PARTS
for P in testdata fixtures locales i18n node_modules .git; do
    expect_allow "test26 exempt-path[$P]" "$(write_payload "$TMP/$P/x.md" "tell $EMOJI")"
done

# 27: one per entry in EXEMPT_SUFFIXES
expect_allow "test27 exempt[.snap]" "$(write_payload "$TMP/a.snap" "tell $EMOJI")"
expect_allow "test27 exempt[.lock]" "$(write_payload "$TMP/a.lock" "tell $EMOJI")"
expect_allow "test27 exempt[.min.js]" "$(write_payload "$TMP/a.min.js" "tell $EMOJI")"
expect_allow "test27 exempt[package-lock.json]" "$(write_payload "$TMP/package-lock.json" "tell $EMOJI")"
expect_allow "test27 exempt[go.sum]" "$(write_payload "$TMP/go.sum" "tell $EMOJI")"

# 28: FIX-4, the two full-filename entries match on basename, not endswith
expect_block "test28 not-package-lock" \
    "$(write_payload "$TMP/my-package-lock.json" "tell $EMOJI")" 'emoji:'
expect_block "test28 not-go-sum" "$(write_payload "$TMP/notgo.sum" "tell $EMOJI")" 'emoji:'

# --- FIX-3: matching is case-insensitive ---

# 29: dropping re.IGNORECASE has to turn these red
expect_block "test29 upper-word" "$(write_payload "$F" "A COMPREHENSIVE rewrite")" \
    'filler-word: "COMPREHENSIVE" (line 1)'
expect_block "test29 upper-trailer" "$(write_payload "$F" "CO-AUTHORED-BY: CLAUDE")" \
    'claude-trailer: "CO-AUTHORED-BY: CLAUDE" (line 1)'
expect_block "test29 lower-trailer" "$(write_payload "$F" "co-authored-by: claude")" \
    'claude-trailer: "co-authored-by: claude" (line 1)'
expect_block "test29 upper-generated" \
    "$(write_payload "$F" "GENERATED WITH [CLAUDE CODE]")" 'claude-trailer:'

# --- FIX-3: the wordlist and phraselist contents are pinned ---
# The literals below are duplicated from the subject on purpose. The point is to
# pin WHICH words ship, so deleting 22 of the 24 has to turn the suite red.

WORDS=(comprehensive robust seamless seamlessly leverage leverages leveraging
       utilize utilizes utilizing delve intricate crucial pivotal meticulous
       meticulously showcase realm testament elevate embark furthermore moreover
       underscore)
TOTAL=$((TOTAL + 1))
[ "${#WORDS[@]}" -eq 24 ] || fail "test30 wordlist-size" "harness lists ${#WORDS[@]}, want 24"
for W in "${WORDS[@]}"; do
    expect_block "test30 word[$W]" "$(write_payload "$F" "the $W here")" \
        "filler-word: \"$W\" (line 1)"
done

PHRASES=("You're absolutely right"
         "You are absolutely right"
         "I apologize for the confusion"
         "It's worth noting that"
         "It is worth noting that"
         "delve into"
         "In today's fast-paced world"
         "Let me know if you need anything else"
         "I hope this helps"
         "As an AI"
         "It's important to note")
TOTAL=$((TOTAL + 1))
[ "${#PHRASES[@]}" -eq 11 ] || fail "test31 phraselist-size" "harness lists ${#PHRASES[@]}, want 11"
for P in "${PHRASES[@]}"; do
    expect_block "test31 phrase[$P]" "$(write_payload "$F" "x $P y")" \
        "filler-phrase: \"$P\" (line 1)"
done

# --- FIX-3: one codepoint from each of the six emoji ranges ---

# 32: deleting any single range has to turn one of these red
expect_block "test32 emoji[U+1F680 in 1F300-1FAFF]" \
    "$(write_payload "$F" "x $(printf '\xf0\x9f\x9a\x80') y")" 'emoji:'
expect_block "test32 emoji[U+1F004 in 1F000-1F0FF]" \
    "$(write_payload "$F" "x $(printf '\xf0\x9f\x80\x84') y")" 'emoji:'
expect_block "test32 emoji[U+1F1E8 in 1F1E6-1F1FF]" \
    "$(write_payload "$F" "x $(printf '\xf0\x9f\x87\xa8') y")" 'emoji:'
expect_block "test32 emoji[U+2600 in 2600-27BF]" \
    "$(write_payload "$F" "x $(printf '\xe2\x98\x80') y")" 'emoji:'
expect_block "test32 emoji[U+2B50 in 2B00-2BFF]" \
    "$(write_payload "$F" "x $(printf '\xe2\xad\x90') y")" 'emoji:'
expect_block "test32 emoji[U+FE0F]" \
    "$(write_payload "$F" "x $(printf '\xef\xb8\x8f') y")" 'emoji:'

# --- FIX-4: exemptions are checked on the normalized path ---

# 33: traversal must not buy an exemption
expect_block "test33 traversal-git" \
    "$(write_payload "/repo/.git/../src/main.go" "tell $EMOJI")" 'emoji:'
expect_block "test33 traversal-testdata" \
    "$(write_payload "/repo/testdata/../src/x.md" "tell $EMOJI")" 'emoji:'
# the genuine forms stay exempt
expect_allow "test33 real-git-path" "$(write_payload "/repo/.git/config" "tell $EMOJI")"
expect_allow "test33 real-testdata-path" "$(write_payload "/repo/testdata/x.md" "tell $EMOJI")"

# --- FIX-4: trailers match across a line break, with the right line number ---

# 34: \s* in the regex includes a newline, so per-line scanning missed this.
# The trailer starts on line 3, which pins the offset-to-line conversion.
expect_block "test34 trailer-across-newline" \
    "$(write_payload "$F" "alpha\nbeta\nCo-Authored-By:\nClaude")" 'claude-trailer:'
expect_block "test34 trailer-newline-lineno" \
    "$(write_payload "$F" "alpha\nbeta\nCo-Authored-By:\nClaude")" '(line 3)'

# --- FIX-5: the Bash commit-trailer bypass ---

# 35: trailers are scanned in a Bash command, so `git commit -m` cannot smuggle
# one past the guard.
expect_block "test35 bash-trailer" \
    "$(bash_payload 'git commit -m "feat: x" -m "Co-Authored-By: Claude <x@y>"')" \
    'claude-trailer: "Co-Authored-By: Claude"'
expect_block "test35 bash-generated" \
    "$(bash_payload 'git commit -m "Generated with [Claude Code]"')" \
    'claude-trailer: "Generated with [Claude Code]"'
expect_allow "test35 bash-clean-commit" "$(bash_payload 'git commit -m "feat: x"')"

# 36: ONLY trailers are scanned on the Bash path. Blocking filler, em-dashes or
# emoji in a command would break grep, sed and echo for no benefit.
expect_allow "test36 bash-filler-not-scanned" "$(bash_payload 'grep -rn "comprehensive" .')"
expect_allow "test36 bash-emdash-not-scanned" "$(bash_payload "sed -i 's/x/${EMDASH}/' f.txt")"
expect_allow "test36 bash-emoji-not-scanned" "$(bash_payload "echo $EMOJI")"

# 37: the env escape hatch still applies on the Bash path
expect_allow "test37 bash-env-off" \
    "$(bash_payload 'git commit -m "Co-Authored-By: Claude"')" AI_TELL_GUARD=off

if [ "$FAILED" -ne 0 ]; then
    echo "FAILED ai-tell-guard_test: $FAILED failed assertions across $TOTAL cases"
    exit 1
fi

echo "PASS ai-tell-guard_test: $TOTAL/$TOTAL cases"
exit 0
