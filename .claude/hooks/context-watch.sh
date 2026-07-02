#!/bin/bash
# context-watch.sh - Nudge user near context limit
# Hook: Stop
# Exit 0 always — never blocks.

set -uo pipefail

INPUT=$(cat)

# Extract transcript_path from hook input (present in Stop common input fields)
TRANSCRIPT=$(echo "$INPUT" | jq -r '.transcript_path // empty' 2>/dev/null)

# No transcript → silent exit
[ -z "$TRANSCRIPT" ] && exit 0
[ ! -f "$TRANSCRIPT" ] && exit 0

# Estimate tokens: bytes / 4 (rough but consistent)
BYTES=$(wc -c < "$TRANSCRIPT" 2>/dev/null || echo 0)
EST_TOKENS=$(( BYTES / 4 ))

# Threshold: 180K of typical 200K window = 90%
THRESHOLD=180000

if [ "$EST_TOKENS" -ge "$THRESHOLD" ]; then
    PCT=$(( EST_TOKENS * 100 / 200000 ))
    echo "" >&2
    echo "CONTEXT WATCH: ~$(( EST_TOKENS / 1000 ))K tokens estimated (~${PCT}% of 200K window)." >&2
    echo "Run /handoff to generate a handoff prompt and start a fresh session." >&2
fi

exit 0
