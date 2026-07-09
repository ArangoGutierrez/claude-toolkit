#!/bin/bash
# validate-year.sh - Block new files with stale copyright/license years
# Hook: PreToolUse (matcher: Write)
#
# Prevents AI models from inserting training-data years (2024/2025)
# into copyright/license headers of newly created files.
#
# Only checks NEW files (file doesn't exist on disk yet).
# Existing files may legitimately have older years.
#
# Covers: "Copyright YYYY", "SPDX-FileCopyrightText: YYYY",
#         "(c) YYYY", "(C) YYYY", "© YYYY"
# Year ranges are valid if current year appears (e.g., 2020-2026).
#
# Exit 0 = allow
# Exit 2 = block (stderr becomes Claude's feedback)

set -o pipefail

CURRENT_YEAR=$(date +%Y)
INPUT=$(cat)

# Extract file path from tool input
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // .tool_input.path // empty')
[ -z "$FILE_PATH" ] && exit 0

# Only check NEW files — existing files may legitimately have older years
[ -f "$FILE_PATH" ] && exit 0

# Extract content being written
CONTENT=$(echo "$INPUT" | jq -r '.tool_input.content // empty')
[ -z "$CONTENT" ] && exit 0

# Find copyright/license lines with 4-digit years.
# Match lines containing copyright indicators AND a year.
# Then filter to only lines that DON'T contain the current year.
COPYRIGHT_LINES=$(echo "$CONTENT" \
    | grep -inE '(copyright|spdx-filecopyrighttext|©|\(c\))' || true)

# No copyright lines at all — nothing to validate
[ -z "$COPYRIGHT_LINES" ] && exit 0

# Check if any copyright line has a 4-digit year but lacks the current year
STALE_LINES=$(echo "$COPYRIGHT_LINES" \
    | grep -E '[0-9]{4}' \
    | grep -v "$CURRENT_YEAR" || true)

if [ -n "$STALE_LINES" ]; then
    FOUND_YEAR=$(echo "$STALE_LINES" | grep -oE '[0-9]{4}' | head -1)
    echo "BLOCKED: New file has copyright/license header with year $FOUND_YEAR instead of $CURRENT_YEAR." >&2
    echo "File: $FILE_PATH" >&2
    echo "" >&2
    echo "Stale lines found:" >&2
    echo "$STALE_LINES" >&2
    echo "" >&2
    echo "Fix: Replace $FOUND_YEAR with $CURRENT_YEAR (or use a range ending in $CURRENT_YEAR, e.g., $FOUND_YEAR-$CURRENT_YEAR)." >&2
    exit 2
fi

exit 0
