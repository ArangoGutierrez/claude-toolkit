#!/bin/bash
# inject-date.sh - Inject current date/year into session context
# Hook: SessionStart (no matcher — fires on startup, resume, clear, compact)
#
# AI models often use stale years from training data (2024/2025).
# This hook injects the actual current date so the model always
# knows the correct year for copyright headers, docs, commits, etc.
#
# stdout is added as context that Claude can see and act on.
# Also works as a UserPromptSubmit hook (same output contract).
#
# Exit 0 = success (stdout added to context)
set -uo pipefail

YEAR=$(date +%Y)
DATE=$(date +"%A %B %d, %Y")

cat <<EOF
TODAY: $DATE
CURRENT YEAR: $YEAR
RULE: When writing dates or years in ANY context (copyright headers, license files, documentation, commit messages, changelogs, comments, code), always use $YEAR as the current year. Never use years from training data or copy years from existing files in the project. New files get $YEAR. Year ranges in existing files being updated should end with $YEAR.
EOF

exit 0
