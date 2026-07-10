#!/bin/bash
# test_skill_integration.sh — end-to-end harness for the /done skill
set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DONE_BIN="$(cd "$SCRIPT_DIR/.." && pwd)/done.sh"
HOOK="$(cd "$SCRIPT_DIR/../../../hooks" && pwd)/done-hook.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

PASS=0
FAIL=0

# Common setup
UUID="donesk01-aaaa-bbbb-cccc-000000000001"
HOME_DIR="$TMP/h1"
mkdir -p "$HOME_DIR/.claude/audit/session-goals" "$HOME_DIR/.claude/audit"
TRANSCRIPT="$HOME_DIR/projects/fake/$UUID.jsonl"
mkdir -p "$(dirname "$TRANSCRIPT")"; touch "$TRANSCRIPT"

cat > "$HOME_DIR/.claude/audit/session-goals/$UUID.md" <<'GOAL'
## Initial 2026-05-18T10:00:00Z
Goal: ship done-hook v1
Acceptance:
- ./done-hook_test.sh passes
- shellcheck clean
- spec committed
GOAL

cat > "$HOME_DIR/.claude/audit/bash-commands-$(date -u +%Y-%m-%d).log" <<'LOG'
2026-05-18T14:30:00Z	./done-hook_test.sh	exit=0
2026-05-18T14:31:00Z	shellcheck ~/.claude/hooks/done-hook.sh	exit=0
2026-05-18T14:32:00Z	git commit -s -m "docs(specs): add design"	exit=0
LOG

# Run the Stop hook first to seed the outcomes log
echo "{\"transcript_path\":\"$TRANSCRIPT\"}" | HOME="$HOME_DIR" bash "$HOOK" >/dev/null 2>&1

# Scenario 1: /done confirm with mocked NAT returning AGREE → user.verdict=MET written
DONE_FAKE_NAT_RESPONSE=$'VERDICT: AGREE\nRATIONALE: all three bullets supported.\nGAPS: n/a' \
  HOME="$HOME_DIR" CLAUDE_SESSION_ID="$UUID" \
  bash "$DONE_BIN" confirm >/dev/null 2>&1

LATEST=$(grep "\"session\":\"$UUID\"" "$HOME_DIR/.claude/audit/session-outcomes-"*.log | tail -1)
if echo "$LATEST" | grep -q '"verdict":"MET"' && \
   echo "$LATEST" | grep -q '"nat_verdict":"AGREE"' && \
   echo "$LATEST" | grep -q '"evaluator":"nat-goal-evaluator"'; then
  echo "PASS: /done confirm AGREE -> MET + nat-goal-evaluator"; PASS=$((PASS+1))
else
  echo "FAIL: /done confirm AGREE — latest entry missing expected fields"
  echo "  got: $LATEST"; FAIL=$((FAIL+1))
fi

# Scenario 2: /done abandon "blocked by Y" → user.verdict=ABANDONED, evaluator=user_only, no NAT
UUID2="donesk02-aaaa-bbbb-cccc-000000000002"
HOME_DIR2="$TMP/h2"
mkdir -p "$HOME_DIR2/.claude/audit/session-goals" "$HOME_DIR2/.claude/audit"
cp "$HOME_DIR/.claude/audit/session-goals/$UUID.md" "$HOME_DIR2/.claude/audit/session-goals/$UUID2.md"
TRANSCRIPT2="$HOME_DIR2/projects/fake/$UUID2.jsonl"
mkdir -p "$(dirname "$TRANSCRIPT2")"; touch "$TRANSCRIPT2"
echo "{\"transcript_path\":\"$TRANSCRIPT2\"}" | HOME="$HOME_DIR2" bash "$HOOK" >/dev/null 2>&1

# DONE_FAKE_NAT_RESPONSE unset — if NAT is accidentally called, it errors
HOME="$HOME_DIR2" CLAUDE_SESSION_ID="$UUID2" \
  bash "$DONE_BIN" abandon "blocked by Y" >/dev/null 2>&1

LATEST2=$(grep "\"session\":\"$UUID2\"" "$HOME_DIR2/.claude/audit/session-outcomes-"*.log | tail -1)
if echo "$LATEST2" | grep -q '"verdict":"ABANDONED"' && \
   echo "$LATEST2" | grep -q '"reason":"blocked by Y"' && \
   echo "$LATEST2" | grep -q '"evaluator":"user_only"'; then
  echo "PASS: /done abandon — ABANDONED + user_only + reason"; PASS=$((PASS+1))
else
  echo "FAIL: /done abandon — latest entry missing expected fields"
  echo "  got: $LATEST2"; FAIL=$((FAIL+1))
fi

# Scenario 3: DONE_NAT_MODEL override reaches the NAT dispatch (defect-2 wire).
# The fake substitutes {MODEL} with the model arg it received; if the wire is
# dropped, the rationale carries the default (or a raw {MODEL}) and this fails.
UUID3="donesk03-aaaa-bbbb-cccc-000000000003"
HOME_DIR3="$TMP/h3"
mkdir -p "$HOME_DIR3/.claude/audit/session-goals" "$HOME_DIR3/.claude/audit"
cp "$HOME_DIR/.claude/audit/session-goals/$UUID.md" "$HOME_DIR3/.claude/audit/session-goals/$UUID3.md"
TRANSCRIPT3="$HOME_DIR3/projects/fake/$UUID3.jsonl"
mkdir -p "$(dirname "$TRANSCRIPT3")"; touch "$TRANSCRIPT3"
echo "{\"transcript_path\":\"$TRANSCRIPT3\"}" | HOME="$HOME_DIR3" bash "$HOOK" >/dev/null 2>&1

DONE_NAT_MODEL="fake/model-override" \
DONE_FAKE_NAT_RESPONSE=$'VERDICT: AGREE\nRATIONALE: graded by {MODEL}.\nGAPS: n/a' \
  HOME="$HOME_DIR3" CLAUDE_SESSION_ID="$UUID3" \
  bash "$DONE_BIN" confirm >/dev/null 2>&1

LATEST3=$(grep "\"session\":\"$UUID3\"" "$HOME_DIR3/.claude/audit/session-outcomes-"*.log | tail -1)
if echo "$LATEST3" | grep -q '"evaluator_rationale":"graded by fake/model-override."'; then
  echo "PASS: DONE_NAT_MODEL override reaches NAT dispatch"; PASS=$((PASS+1))
else
  echo "FAIL: DONE_NAT_MODEL override did not reach dispatch"
  echo "  got: $LATEST3"; FAIL=$((FAIL+1))
fi


# Scenario 4: /done override "custom reason" -> user.verdict=MET, evaluator=user_override,
# nat_verdict=OVERRIDDEN, custom reason preserved, NO NAT call (DONE_FAKE_NAT_RESPONSE unset;
# if override accidentally falls through to the confirm/NAT path it errors instead of writing MET).
UUID4="donesk04-aaaa-bbbb-cccc-000000000004"
HOME_DIR4="$TMP/h4"
mkdir -p "$HOME_DIR4/.claude/audit/session-goals" "$HOME_DIR4/.claude/audit"
cp "$HOME_DIR/.claude/audit/session-goals/$UUID.md" "$HOME_DIR4/.claude/audit/session-goals/$UUID4.md"
TRANSCRIPT4="$HOME_DIR4/projects/fake/$UUID4.jsonl"
mkdir -p "$(dirname "$TRANSCRIPT4")"; touch "$TRANSCRIPT4"
echo "{\"transcript_path\":\"$TRANSCRIPT4\"}" | HOME="$HOME_DIR4" bash "$HOOK" >/dev/null 2>&1

HOME="$HOME_DIR4" CLAUDE_SESSION_ID="$UUID4" \
  bash "$DONE_BIN" override custom reason preserved >/dev/null 2>&1

LATEST4=$(grep "\"session\":\"$UUID4\"" "$HOME_DIR4/.claude/audit/session-outcomes-"*.log | tail -1)
if echo "$LATEST4" | grep -q '"verdict":"MET"' && \
   echo "$LATEST4" | grep -q '"evaluator":"user_override"' && \
   echo "$LATEST4" | grep -q '"nat_verdict":"OVERRIDDEN"' && \
   echo "$LATEST4" | grep -q '"reason":"custom reason preserved"'; then
  echo "PASS: /done override -> MET + user_override + OVERRIDDEN + custom reason"; PASS=$((PASS+1))
else
  echo "FAIL: /done override — latest entry missing expected fields"
  echo "  got: $LATEST4"; FAIL=$((FAIL+1))
fi

# Scenario 5: /done override with NO goal file -> nonzero exit + the SAME
# "no goal file" error confirm uses (discriminates from the pre-fix behavior,
# where an unimplemented 'override' hits the generic unknown-subcommand arm,
# which ALSO exits nonzero — so exit code alone would pass before the fix).
UUID5="donesk05-aaaa-bbbb-cccc-000000000005"
HOME_DIR5="$TMP/h5"
mkdir -p "$HOME_DIR5/.claude/audit/session-goals" "$HOME_DIR5/.claude/audit"
# deliberately no session-goals/$UUID5.md
ERR5=$(HOME="$HOME_DIR5" CLAUDE_SESSION_ID="$UUID5" bash "$DONE_BIN" override 2>&1 >/dev/null)
RC5=$?
if [ "$RC5" -ne 0 ] && echo "$ERR5" | grep -q 'no goal file'; then
  echo "PASS: /done override with no goal file -> nonzero + 'no goal file' error"; PASS=$((PASS+1))
else
  echo "FAIL: /done override with no goal file — wrong exit/error"
  echo "  rc=$RC5 got: $ERR5"; FAIL=$((FAIL+1))
fi

# Scenario 6: DISAGREE hint names the override subcommand (static check on the
# WORKTREE copy done.sh resolves via SCRIPT_DIR, not any deployed ~/.claude copy).
if grep -q '/done override \[reason\] to record MET over NAT'"'"'s objection' "$DONE_BIN"; then
  echo "PASS: DISAGREE hint names /done override"; PASS=$((PASS+1))
else
  echo "FAIL: DISAGREE hint does not mention /done override"
  FAIL=$((FAIL+1))
fi

echo
echo "==== Results: ${PASS} passed, ${FAIL} failed ===="
[ "$FAIL" -eq 0 ]
