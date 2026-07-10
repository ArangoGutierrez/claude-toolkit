#!/bin/bash
# budget-governor_test.sh — harness for budget-governor.sh (SCRIPT_DIR-relative).
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
HOOK="$SCRIPT_DIR/budget-governor.sh"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
UUID="test-session-0001"

# --- Fixtures ---
# Main transcript: msg_A appears 3x (dedup case), msg_B once. The FIRST msg_A
# occurrence carries output_tokens:30 so that last-occurrence-wins (50) is
# discriminated from first-wins (30): a `.[-1]` -> `.[0]` regression changes
# the sum (180 vs 200) and fails the exact-string asserts below.
DIR="$TMP/proj"; mkdir -p "$DIR/$UUID/subagents"
T="$DIR/$UUID.jsonl"
A_FIRST='{"type":"assistant","message":{"id":"msg_A","usage":{"input_tokens":10,"cache_creation_input_tokens":100,"cache_read_input_tokens":1000,"output_tokens":30}}}'
A='{"type":"assistant","message":{"id":"msg_A","usage":{"input_tokens":10,"cache_creation_input_tokens":100,"cache_read_input_tokens":1000,"output_tokens":50}}}'
B='{"type":"assistant","message":{"id":"msg_B","usage":{"input_tokens":5,"cache_creation_input_tokens":200,"cache_read_input_tokens":2000,"output_tokens":150}}}'
printf '%s\n%s\n%s\n%s\n' "$A_FIRST" "$A" "$A" "$B" > "$T"
# Subagents: two dispatches with labels.
echo '{"type":"assistant","message":{"id":"msg_C","usage":{"input_tokens":1,"cache_creation_input_tokens":2,"cache_read_input_tokens":3,"output_tokens":400}}}' > "$DIR/$UUID/subagents/agent-x1.jsonl"
echo '{"description":"builder-T1","agentType":"builder"}' > "$DIR/$UUID/subagents/agent-x1.meta.json"
echo '{"type":"assistant","message":{"id":"msg_D","usage":{"input_tokens":1,"cache_creation_input_tokens":2,"cache_read_input_tokens":3,"output_tokens":100}}}' > "$DIR/$UUID/subagents/agent-x2.jsonl"
echo '{"description":"critic","agentType":"adversarial-critic"}' > "$DIR/$UUID/subagents/agent-x2.meta.json"
# Expected totals: out=700 in=17 cache_w=304 cache_r=3006

GOALS="$TMP/goals"; STATE="$TMP/state"; mkdir -p "$GOALS" "$STATE"
goal_with_budget() { printf '## Initial 2026-07-08T00:00:00Z\nGoal: fixture\nBudget: %s\nAcceptance:\n- true\n' "$1" > "$GOALS/$UUID.md"; }
INPUT="{\"transcript_path\":\"$T\",\"session_id\":\"$UUID\"}"
# Order is deliberate: `2>&1` binds stderr to the command-substitution capture,
# then `>/dev/null` drops stdout — the hook's advisory (written to stderr) is
# what we assert on. SC2069 flags the terse swap idiom; it is correct here.
# shellcheck disable=SC2069
run() { echo "$INPUT" | BUDGET_GOVERNOR_GOAL_DIR="$GOALS" BUDGET_GOVERNOR_STATE_DIR="$STATE" "$@" "$HOOK" 2>&1 >/dev/null; }
fresh_state() { rm -f "$STATE/$UUID.state"; }
fail() { echo "FAIL $1"; echo "  got: $2"; exit 1; }

# Test 1: no transcript_path -> silent rc0
OUT=$(echo '{}' | "$HOOK" 2>&1 >/dev/null); RC=$?
[ "$RC" = 0 ] && [ -z "$OUT" ] || fail "test1 empty-input" "rc=$RC out=$OUT"

# Test 2: transcript ok, no goal file -> silent rc0
rm -f "$GOALS/$UUID.md"; OUT=$(run env); RC=$?
[ "$RC" = 0 ] && [ -z "$OUT" ] || fail "test2 no-goal-file" "rc=$RC out=$OUT"

# Test 3: goal without Budget line -> silent rc0
printf '## Initial x\nGoal: y\nAcceptance:\n- true\n' > "$GOALS/$UUID.md"
OUT=$(run env); RC=$?
[ "$RC" = 0 ] && [ -z "$OUT" ] || fail "test3 no-budget-line" "rc=$RC out=$OUT"

# Test 4: under 80% (700/1000 = 70%) -> silent, no state file
goal_with_budget "1k"; fresh_state
OUT=$(run env); RC=$?
[ "$RC" = 0 ] && [ -z "$OUT" ] || fail "test4 under-threshold" "rc=$RC out=$OUT"
[ ! -f "$STATE/$UUID.state" ] || fail "test4 state-created-early" "$(cat "$STATE/$UUID.state")"

# Test 5: crossing 80% (700/800 = 87%) -> warn once, exact numbers, state=80
goal_with_budget "800"; fresh_state
OUT=$(run env)
echo "$OUT" | grep -q 'BUDGET GOVERNOR:' || fail "test5 no-warn" "$OUT"
echo "$OUT" | grep -q 'out=700 of 800 tokens (87%)' || fail "test5 wrong-sum (dedup broken?)" "$OUT"
echo "$OUT" | grep -qi 'approaching' || fail "test5 severity-word" "$OUT"
[ "$(cat "$STATE/$UUID.state")" = "80" ] || fail "test5 state" "$(cat "$STATE/$UUID.state" 2>/dev/null)"

# Test 6: idempotent re-run at same bucket -> silent
OUT=$(run env); RC=$?
[ "$RC" = 0 ] && [ -z "$OUT" ] || fail "test6 repeat-warn" "rc=$RC out=$OUT"

# Test 7: over budget (700/500 = 140%) -> OVER BUDGET, bucket 125
goal_with_budget "500"; fresh_state
OUT=$(run env)
echo "$OUT" | grep -q 'OVER BUDGET' || fail "test7 no-over-warn" "$OUT"
echo "$OUT" | grep -q '(140%)' || fail "test7 pct" "$OUT"
[ "$(cat "$STATE/$UUID.state")" = "125" ] || fail "test7 state" "$(cat "$STATE/$UUID.state" 2>/dev/null)"

# Test 8: k/m suffix parsing (0.8k == 800 -> same 87% warn)
goal_with_budget "0.8k"; fresh_state
OUT=$(run env)
echo "$OUT" | grep -q '(87%)' || fail "test8 suffix-parse" "$OUT"

# Test 9: malformed line mixed in -> still sums valid lines, rc0
goal_with_budget "800"; fresh_state
printf 'NOT-JSON{{{\n' >> "$T"
OUT=$(run env); RC=$?
[ "$RC" = 0 ] || fail "test9 rc" "rc=$RC"
echo "$OUT" | grep -q 'out=700 of 800' || fail "test9 malformed-tolerance" "$OUT"

# Test 10: VERBOSE=1 without budget -> spend line, no pct
rm -f "$GOALS/$UUID.md"; fresh_state
OUT=$(run env BUDGET_GOVERNOR_VERBOSE=1)
echo "$OUT" | grep -q 'out=700' || fail "test10 verbose-line" "$OUT"
echo "$OUT" | grep -q '%' && fail "test10 pct-without-budget" "$OUT"

# Test 11: dispatch attribution -> count + top label with exact spend
goal_with_budget "500"; fresh_state
OUT=$(run env)
echo "$OUT" | grep -q 'dispatches: 2' || fail "test11 dispatch-count" "$OUT"
echo "$OUT" | grep -q 'builder-T1 400' || fail "test11 top-label" "$OUT"

# Test 12: Budget survives a budget-less goal amendment (last Budget line in
# the FILE wins; a last-stanza-only reader loses the budget and stays silent)
goal_with_budget "800"
printf '## Amendment 2026-07-08T01:00:00Z\namended goal text, deliberately without a Budget line\n' >> "$GOALS/$UUID.md"
fresh_state
OUT=$(run env)
echo "$OUT" | grep -q 'out=700 of 800 tokens (87%)' || fail "test12 budget-lost-after-amendment" "$OUT"

# Test 13: leading-zero budget parses as decimal (0800 == 800), no bash
# octal-arithmetic error noise — expect the same clean 87% warn
goal_with_budget "0800"; fresh_state
OUT=$(run env)
echo "$OUT" | grep -q 'out=700 of 800 tokens (87%)' || fail "test13 leading-zero-budget" "$OUT"

echo "PASS budget-governor_test: 13/13"
exit 0
