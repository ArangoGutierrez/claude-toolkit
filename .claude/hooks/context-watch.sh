#!/bin/bash
# context-watch.sh - Nudge user near context limit
# Hook: Stop
# Exit 0 always — never blocks.

set -o pipefail

INPUT=$(cat)

# Extract transcript_path from hook input (present in Stop common input fields)
TRANSCRIPT=$(echo "$INPUT" | jq -r '.transcript_path // empty' 2>/dev/null)

# No transcript → silent exit
[ -z "$TRANSCRIPT" ] && exit 0
[ ! -f "$TRANSCRIPT" ] && exit 0

# Context window size in tokens. Override via CONTEXT_WATCH_WINDOW; default
# matches opus[1m]. A zero/non-numeric override fails open (silent exit 0)
# rather than risking a divide-by-zero below.
WINDOW="${CONTEXT_WATCH_WINDOW:-1000000}"
case "$WINDOW" in
    ''|*[!0-9]*) exit 0 ;;
esac
[ "$WINDOW" -eq 0 ] && exit 0

# Estimate tokens: bytes / 4 (rough but consistent)
BYTES=$(wc -c < "$TRANSCRIPT" 2>/dev/null || echo 0)
EST_TOKENS=$(( BYTES / 4 ))

# Threshold: 90% of the configured window
THRESHOLD=$(( WINDOW * 9 / 10 ))

if [ "$EST_TOKENS" -ge "$THRESHOLD" ]; then
    PCT=$(( EST_TOKENS * 100 / WINDOW ))
    echo "" >&2
    echo "CONTEXT WATCH: ~$(( EST_TOKENS / 1000 ))K tokens estimated (~${PCT}% of $(( WINDOW / 1000 ))K window)." >&2
    echo "Run /handoff to generate a handoff prompt and start a fresh session." >&2
fi

exit 0
