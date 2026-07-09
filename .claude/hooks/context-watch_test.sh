#!/bin/bash
# Test context-watch.sh emits nudge when transcript size exceeds threshold.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
HOOK="$SCRIPT_DIR/context-watch.sh"
TMP=$(mktemp -d)
trap "rm -rf $TMP" EXIT

# Synthesize a "transcript" file at threshold size
LARGE_FILE="$TMP/big.jsonl"
yes 'x' | head -c 800000 > "$LARGE_FILE"  # ~800KB ≈ ~200K tokens via /4 estimate

# Test 1: large transcript via direct transcript_path, window set to 200K
# (the old hardcoded default) → emit nudge. Explicit window because the
# hook default is now 1M (opus[1m]) — this fixture alone no longer crosses
# 90% of the default window.
INPUT="{\"transcript_path\":\"$LARGE_FILE\"}"
STDERR=$(echo "$INPUT" | CONTEXT_WATCH_WINDOW=200000 "$HOOK" 2>&1 >/dev/null)
if ! echo "$STDERR" | grep -qiE 'context.*9[0-9]\b|/handoff'; then
    echo "FAIL test1: nudge not emitted for large transcript at CONTEXT_WATCH_WINDOW=200000"
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

# Fixture for window-awareness: ~400KB ≈ 100K est tokens via /4 estimate.
MID_FILE="$TMP/mid.jsonl"
yes 'x' | head -c 400000 > "$MID_FILE"
INPUT="{\"transcript_path\":\"$MID_FILE\"}"

# Test 5: 100K-token transcript with CONTEXT_WATCH_WINDOW=100000 (90% = 90K)
# → nudge fires. Under the old hardcoded-200K-window implementation this
# fixture (100K est tokens) never crosses the fixed 180K threshold no matter
# what the env var says, so this fails against the pre-fix hook.
STDERR=$(echo "$INPUT" | CONTEXT_WATCH_WINDOW=100000 "$HOOK" 2>&1 >/dev/null)
if ! echo "$STDERR" | grep -qiE 'context.*9[0-9]\b|/handoff'; then
    echo "FAIL test5: nudge not emitted for 100K-token transcript at CONTEXT_WATCH_WINDOW=100000"
    echo "STDERR: $STDERR"
    exit 1
fi

# Test 6: same fixture, default window (no override, i.e. 1M / 90% = 900K)
# → silent. Paired with test 5, this proves the threshold genuinely tracks
# CONTEXT_WATCH_WINDOW rather than a hook that always fires regardless of it.
STDERR=$(echo "$INPUT" | "$HOOK" 2>&1 >/dev/null)
if [ -n "$STDERR" ]; then
    echo "FAIL test6: nudge emitted for 100K-token transcript at default window: $STDERR"
    exit 1
fi

# Test 7: CONTEXT_WATCH_WINDOW=0 must fail open (silent, exit 0), never
# divide-by-zero. A 0 window makes 90%-of-window == 0, so an unguarded hook
# would attempt the nudge branch even for the tiny fixture and crash computing
# EST_TOKENS*100/WINDOW.
STDERR=$(echo "$INPUT" | CONTEXT_WATCH_WINDOW=0 "$HOOK" 2>&1 >/dev/null)
RC=$?
if [ -n "$STDERR" ]; then
    echo "FAIL test7: CONTEXT_WATCH_WINDOW=0 did not fail open silently: $STDERR"
    exit 1
fi
[ "$RC" = "0" ] || { echo "FAIL test7: CONTEXT_WATCH_WINDOW=0 caused nonzero exit (exit=$RC)"; exit 1; }

# Test 8: non-numeric CONTEXT_WATCH_WINDOW must also fail open.
STDERR=$(echo "$INPUT" | CONTEXT_WATCH_WINDOW=notanumber "$HOOK" 2>&1 >/dev/null)
RC=$?
if [ -n "$STDERR" ]; then
    echo "FAIL test8: non-numeric CONTEXT_WATCH_WINDOW did not fail open silently: $STDERR"
    exit 1
fi
[ "$RC" = "0" ] || { echo "FAIL test8: non-numeric CONTEXT_WATCH_WINDOW caused nonzero exit (exit=$RC)"; exit 1; }

echo "PASS"
