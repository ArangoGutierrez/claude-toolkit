#!/bin/bash
# session-goal-init.sh — Nudge user to capture a session goal when none exists.
# Hook: SessionStart
# Writes nudge to stdout (appears in session context) when goal is missing.
# Exit 0 always — never blocks.
# Reads the SessionStart JSON on stdin; nudges to capture a goal via /goal.
set -uo pipefail

INPUT=$(cat)

# Extract transcript_path from hook input
TRANSCRIPT=$(echo "$INPUT" | jq -r '.transcript_path // empty' 2>/dev/null)
[ -z "$TRANSCRIPT" ] && exit 0

UUID=$(basename "$TRANSCRIPT" .jsonl)
GOAL_FILE="${HOME}/.claude/audit/session-goals/${UUID}.md"

if [ ! -f "$GOAL_FILE" ]; then
  echo ""
  echo "[session-goal] No session goal set for ${UUID:0:8}."
  echo "[session-goal] Run /goal to capture one (optional in v1)."
fi

exit 0
