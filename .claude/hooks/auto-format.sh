#!/bin/bash
# auto-format.sh - Auto-format files after Write/Edit operations
# Hook: PostToolUse (matcher: Write|Edit)
#
# Detects file type and runs the appropriate formatter.
# Always exits 0 — formatting failures should not block the agent.
set -uo pipefail

INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // .tool_input.path // empty')
[ -z "$FILE_PATH" ] && exit 0
[ ! -f "$FILE_PATH" ] && exit 0

case "$FILE_PATH" in
    *.go)
        if command -v goimports &>/dev/null; then
            goimports -w "$FILE_PATH" 2>/dev/null
        elif command -v gofmt &>/dev/null; then
            gofmt -w "$FILE_PATH" 2>/dev/null
        fi
        ;;
    *.ts|*.tsx|*.js|*.jsx)
        if command -v biome &>/dev/null; then
            biome format --write "$FILE_PATH" 2>/dev/null
        elif command -v prettier &>/dev/null; then
            prettier --write "$FILE_PATH" 2>/dev/null
        fi
        ;;
    *.py)
        if command -v ruff &>/dev/null; then
            ruff format "$FILE_PATH" 2>/dev/null
        elif command -v black &>/dev/null; then
            black -q "$FILE_PATH" 2>/dev/null
        fi
        ;;
esac

exit 0
