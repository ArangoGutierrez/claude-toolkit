#!/bin/bash
# test_goal_skill.sh — integration harness for the /goal skill
# Skill implementations vary; this harness exercises the skill's behavior
# via a thin shell wrapper at .claude/skills/goal/goal.sh (created in Task 12).
set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
GOAL_BIN="$(cd "$SCRIPT_DIR/.." && pwd)/goal.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

PASS=0
FAIL=0

# Helper: run the goal binary with a fake HOME and a session-id file.
run_goal() {
  local home="$1"; shift
  local uuid="$1"; shift
  mkdir -p "$home/.claude/sessions"
  echo "{\"sessionId\":\"$uuid\"}" > "$home/.claude/sessions/$$.json"
  HOME="$home" CLAUDE_SESSION_ID="$uuid" bash "$GOAL_BIN" "$@"
}

UUID1="goalt001-aaaa-bbbb-cccc-000000000001"
HOME1="$TMP/h1"

# Scenario 1: empty session → /goal creates Initial stanza
INPUT1=$'Goal: ship X\nAcceptance:\n- one\n- two'
run_goal "$HOME1" "$UUID1" "$INPUT1" >/dev/null 2>&1
FILE1="$HOME1/.claude/audit/session-goals/$UUID1.md"
if [ ! -f "$FILE1" ]; then
  echo "FAIL: scenario 1 — goal file not created"; FAIL=$((FAIL+1))
elif ! grep -q "^## Initial " "$FILE1"; then
  echo "FAIL: scenario 1 — Initial stanza header missing"; FAIL=$((FAIL+1))
elif ! grep -q "Goal: ship X" "$FILE1"; then
  echo "FAIL: scenario 1 — Goal line missing"; FAIL=$((FAIL+1))
else
  echo "PASS: scenario 1 — Initial stanza written"; PASS=$((PASS+1))
fi

# Scenario 2: existing file → /goal appends Amendment stanza
INPUT2=$'Goal: ship Y\nAcceptance:\n- three'
run_goal "$HOME1" "$UUID1" "$INPUT2" >/dev/null 2>&1
if ! grep -q "^## Amendment " "$FILE1"; then
  echo "FAIL: scenario 2 — Amendment header missing"; FAIL=$((FAIL+1))
elif [ "$(grep -c '^## ' "$FILE1")" -ne 2 ]; then
  echo "FAIL: scenario 2 — expected exactly 2 stanzas, got $(grep -c '^## ' "$FILE1")"; FAIL=$((FAIL+1))
else
  echo "PASS: scenario 2 — Amendment stanza appended"; PASS=$((PASS+1))
fi

# Scenario 3: malformed input (no Goal: line) → warning but written
UUID3="goalt003-aaaa-bbbb-cccc-000000000003"
HOME3="$TMP/h3"
INPUT3="not-a-goal-format"
STDERR3=$(run_goal "$HOME3" "$UUID3" "$INPUT3" 2>&1 >/dev/null)
FILE3="$HOME3/.claude/audit/session-goals/$UUID3.md"
if ! echo "$STDERR3" | grep -q "missing 'Goal: '"; then
  echo "FAIL: scenario 3 — no warning emitted"; FAIL=$((FAIL+1))
elif [ ! -f "$FILE3" ]; then
  echo "FAIL: scenario 3 — file not written despite warning"; FAIL=$((FAIL+1))
else
  echo "PASS: scenario 3 — malformed input warns but writes"; PASS=$((PASS+1))
fi

# Scenario 4: 'amend' keyword stripped, behavior unchanged
UUID4="goalt004-aaaa-bbbb-cccc-000000000004"
HOME4="$TMP/h4"
INPUT4=$'amend Goal: stripped X\nAcceptance:\n- one'
run_goal "$HOME4" "$UUID4" "$INPUT4" >/dev/null 2>&1
FILE4="$HOME4/.claude/audit/session-goals/$UUID4.md"
if grep -q "^amend Goal:" "$FILE4"; then
  echo "FAIL: scenario 4 — 'amend' keyword leaked into stanza"; FAIL=$((FAIL+1))
elif ! grep -q "Goal: stripped X" "$FILE4"; then
  echo "FAIL: scenario 4 — Goal line missing after strip"; FAIL=$((FAIL+1))
else
  echo "PASS: scenario 4 — 'amend' keyword stripped"; PASS=$((PASS+1))
fi

# Scenario A: cwd has a git origin → stanza records 'Origin: <url>'
UUID_A="goalt00a-aaaa-bbbb-cccc-00000000000a"
HOME_A="$TMP/hA"
INPUT_A=$'Goal: scenario A\nAcceptance:\n- one'
WORK_A="$TMP/repoA"
mkdir -p "$WORK_A"
( cd "$WORK_A" && git init -q && git remote add origin git@example.com:foo/bar.git )
( cd "$WORK_A" && run_goal "$HOME_A" "$UUID_A" "$INPUT_A" >/dev/null 2>&1 )
FILE_A="$HOME_A/.claude/audit/session-goals/$UUID_A.md"
if [ ! -f "$FILE_A" ]; then
  echo "FAIL: scenario A — goal file not created"; FAIL=$((FAIL+1))
elif ! grep -q "^Origin: example.com/foo/bar$" "$FILE_A"; then
  echo "FAIL: scenario A — Origin line missing or wrong"
  echo "  got: $(grep -E '^(Goal|Origin):' "$FILE_A" | head -4)"
  FAIL=$((FAIL+1))
else
  # Verify Origin appears BETWEEN Goal: and Acceptance: (spec ordering invariant).
  GOAL_LN=$(grep -n '^Goal: ' "$FILE_A" | head -1 | cut -d: -f1)
  ORIGIN_LN=$(grep -n '^Origin: ' "$FILE_A" | head -1 | cut -d: -f1)
  ACC_LN=$(grep -n '^Acceptance:' "$FILE_A" | head -1 | cut -d: -f1)
  if [ -z "$ORIGIN_LN" ] || [ "$ORIGIN_LN" -le "$GOAL_LN" ] || [ "$ORIGIN_LN" -ge "$ACC_LN" ]; then
    echo "FAIL: scenario A — Origin not between Goal and Acceptance (Goal=$GOAL_LN Origin=$ORIGIN_LN Acceptance=$ACC_LN)"
    FAIL=$((FAIL+1))
  else
    echo "PASS: scenario A — Origin normalized + positioned between Goal and Acceptance"; PASS=$((PASS+1))
  fi
fi

# Scenario A2: HTTPS clone of the same repo → same normalized Origin as Scenario A.
# Proves the SSH vs HTTPS false-positive class is eliminated.
UUID_A2="goalt0a2-aaaa-bbbb-cccc-0000000000a2"
HOME_A2="$TMP/hA2"
INPUT_A2=$'Goal: scenario A2\nAcceptance:\n- one'
WORK_A2="$TMP/repoA2"
mkdir -p "$WORK_A2"
( cd "$WORK_A2" && git init -q && git remote add origin https://example.com/foo/bar.git )
( cd "$WORK_A2" && run_goal "$HOME_A2" "$UUID_A2" "$INPUT_A2" >/dev/null 2>&1 )
FILE_A2="$HOME_A2/.claude/audit/session-goals/$UUID_A2.md"
if [ ! -f "$FILE_A2" ]; then
  echo "FAIL: scenario A2 — goal file not created"; FAIL=$((FAIL+1))
elif ! grep -q "^Origin: example.com/foo/bar$" "$FILE_A2"; then
  echo "FAIL: scenario A2 — HTTPS URL did not normalize to 'example.com/foo/bar'"
  echo "  got: $(grep -E '^(Goal|Origin):' "$FILE_A2" | head -4)"
  FAIL=$((FAIL+1))
else
  echo "PASS: scenario A2 — HTTPS URL normalizes to same identity as SSH"; PASS=$((PASS+1))
fi

# Scenario B: cwd has no git remote → stanza has no 'Origin:' line
UUID_B="goalt00b-aaaa-bbbb-cccc-00000000000b"
HOME_B="$TMP/hB"
INPUT_B=$'Goal: scenario B\nAcceptance:\n- one'
WORK_B="$TMP/repoB"
mkdir -p "$WORK_B"  # plain dir, no git init
( cd "$WORK_B" && run_goal "$HOME_B" "$UUID_B" "$INPUT_B" >/dev/null 2>&1 )
FILE_B="$HOME_B/.claude/audit/session-goals/$UUID_B.md"
if [ ! -f "$FILE_B" ]; then
  echo "FAIL: scenario B — goal file not created"; FAIL=$((FAIL+1))
elif grep -q "^Origin: " "$FILE_B"; then
  echo "FAIL: scenario B — Origin line should be absent"
  echo "  got: $(grep '^Origin:' "$FILE_B")"
  FAIL=$((FAIL+1))
else
  echo "PASS: scenario B — Origin omitted when cwd has no git remote"; PASS=$((PASS+1))
fi

# Scenario C: cwd is a git repo but has no 'origin' remote → stanza has no 'Origin:' line.
# Distinct from Scenario B (no .git at all) — proves goal.sh handles both no-git AND
# git-without-remote cases via the same fail-open path.
UUID_C="goalt00c-aaaa-bbbb-cccc-00000000000c"
HOME_C="$TMP/hC"
INPUT_C=$'Goal: scenario C\nAcceptance:\n- one'
WORK_C="$TMP/repoC"
mkdir -p "$WORK_C"
( cd "$WORK_C" && git init -q )  # initialize repo but do NOT add an origin remote
( cd "$WORK_C" && run_goal "$HOME_C" "$UUID_C" "$INPUT_C" >/dev/null 2>&1 )
FILE_C="$HOME_C/.claude/audit/session-goals/$UUID_C.md"
if [ ! -f "$FILE_C" ]; then
  echo "FAIL: scenario C — goal file not created"; FAIL=$((FAIL+1))
elif grep -q "^Origin: " "$FILE_C"; then
  echo "FAIL: scenario C — Origin line should be absent (git repo without origin)"
  echo "  got: $(grep '^Origin:' "$FILE_C")"
  FAIL=$((FAIL+1))
else
  echo "PASS: scenario C — Origin omitted when git repo has no origin remote"; PASS=$((PASS+1))
fi

echo
echo "==== Results: ${PASS} passed, ${FAIL} failed ===="
[ "$FAIL" -eq 0 ]
