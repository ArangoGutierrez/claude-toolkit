#!/bin/bash
# format.sh - Auto-format on file edit
# Hook: afterFileEdit
set -euo pipefail

if ! command -v jq &>/dev/null; then
    echo '{"continue":true}'
    exit 0
fi

input=$(cat)
file=$(echo "$input" | jq -r '.path // empty')

case "$file" in
    *.go)
        if command -v gofmt &>/dev/null; then
            gofmt -w "$file" 2>/dev/null || true
        fi
        ;;
    *.json)
        if command -v jq &>/dev/null; then
            tmp=$(mktemp)
            jq '.' "$file" > "$tmp" 2>/dev/null && mv "$tmp" "$file" || rm -f "$tmp"
        fi
        ;;
esac

echo '{"continue":true}'
