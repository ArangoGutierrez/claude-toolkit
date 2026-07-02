#!/bin/bash
# reflection-staleness.sh — SessionStart hook
# Checks if /reflection has been run in the last 7 days.
# Looks for timestamp file: ~/.claude/audit/.last-reflection
# If stale or missing, outputs a non-blocking reminder.
# Exit 0 always (never blocks session start).

set -euo pipefail

TIMESTAMP_FILE="${HOME}/.claude/audit/.last-reflection"
STALE_DAYS=7

if [[ ! -f "$TIMESTAMP_FILE" ]]; then
    echo "REMINDER: /reflection has never been run. Consider running it to analyze session patterns and update rules/."
    exit 0
fi

LAST_RUN=$(cat "$TIMESTAMP_FILE")
LAST_RUN_EPOCH=$(date -j -f "%Y-%m-%d" "$LAST_RUN" +%s 2>/dev/null || date -d "$LAST_RUN" +%s 2>/dev/null || echo 0)
[ "$LAST_RUN_EPOCH" -eq 0 ] && exit 0
NOW_EPOCH=$(date +%s)
DIFF_DAYS=$(( (NOW_EPOCH - LAST_RUN_EPOCH) / 86400 ))

if [[ "$DIFF_DAYS" -ge "$STALE_DAYS" ]]; then
    echo "REMINDER: /reflection last ran ${DIFF_DAYS} days ago (${LAST_RUN}). Consider running it to check for new patterns."
fi

exit 0
