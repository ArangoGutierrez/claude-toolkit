#!/bin/bash
# Test context-watch.sh emits nudge when transcript size exceeds threshold.
set -uo pipefail

HOOK="$HOME/.claude/hooks/context-watch.sh"
TMP=$(mktemp -d)
trap "rm -rf $TMP" EXIT

# Synthesize a "transcript" file at threshold size
LARGE_FILE="$TMP/big.jsonl"
yes 'x' | head -c 800000 > "$LARGE_FILE"  # ~800KB ≈ ~200K tokens via /4 estimate

# Test 1: large transcript via direct transcript_path → emit nudge
INPUT="{\"transcript_path\":\"$LARGE_FILE\"}"
STDERR=$(echo "$INPUT" | "$HOOK" 2>&1 >/dev/null)
if ! echo "$STDERR" | grep -qiE 'context.*9[0-9]\b|/handoff'; then
    echo "FAIL test1: nudge not emitted for large transcript"
    echo "STDERR: $STDERR"
    exit 1
fi

# Test 2: small transcript → silent
SMALL_FILE="$TMP/small.jsonl"
echo '{"hi":"there"}' > "$SMALL_FILE"
INPUT="{\"transcript_path\":\"$SMALL_FILE\"}"
STDERR=$(echo "$INPUT" | "$HOOK" 2>&1 >/dev/null)
if [ -n "$STDERR" ]; then
    echo "FAIL test2: nudge emitted for small transcript: $STDERR"
    exit 1
fi

# Test 3: missing transcript_path → silent (no error, no nudge)
INPUT='{}'
STDERR=$(echo "$INPUT" | "$HOOK" 2>&1 >/dev/null)
RC=$?
if [ -n "$STDERR" ]; then
    echo "FAIL test3: produced output on empty input: $STDERR"
    exit 1
fi
[ "$RC" = "0" ] || { echo "FAIL test3: hook errored on missing transcript_path (exit=$RC)"; exit 1; }

# Test 4: nonexistent transcript_path → silent (no error)
INPUT='{"transcript_path":"/tmp/does-not-exist-'$$'.jsonl"}'
STDERR=$(echo "$INPUT" | "$HOOK" 2>&1 >/dev/null)
RC=$?
if [ -n "$STDERR" ]; then
    echo "FAIL test4: produced output on nonexistent path: $STDERR"
    exit 1
fi
[ "$RC" = "0" ] || { echo "FAIL test4: hook errored on missing file (exit=$RC)"; exit 1; }

echo "PASS"
