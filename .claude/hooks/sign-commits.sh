#!/bin/bash
# sign-commits.sh - Ensure all commits are signed (-s -S)
# Hook: PreToolUse (matcher: Bash)
#
# Exit 0 = allow
# Exit 2 = block (stderr becomes Claude's feedback)

set -uo pipefail

# Read JSON input from stdin
INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')

# Extract the git commit portion from potentially chained commands.
# Handles: "git commit ...", "cmd && git commit ...", "cmd; git commit ...", etc.
COMMIT_PART=$(echo "$COMMAND" | grep -oE '(^|[;&|]+\s*)git commit[^;&|]*' | sed 's/^[;&| ]*//')

# No git commit found anywhere — allow
if [ -z "$COMMIT_PART" ]; then
    exit 0
fi

# Check for -s or --signoff in the commit portion
has_signoff=false
if echo "$COMMIT_PART" | grep -qE '(\s|^)-[a-zA-Z]*s|--signoff'; then
    has_signoff=true
fi

# Check for -S or --gpg-sign in the commit portion
has_signature=false
if echo "$COMMIT_PART" | grep -qE '(\s|^)-[a-zA-Z]*S|--gpg-sign'; then
    has_signature=true
fi

# If both present, allow
if [ "$has_signoff" = true ] && [ "$has_signature" = true ]; then
    exit 0
fi

# Build message about what's missing
missing=""
if [ "$has_signoff" = false ]; then
    missing="-s (signoff)"
fi
if [ "$has_signature" = false ]; then
    if [ -n "$missing" ]; then
        missing="$missing and -S (GPG signature)"
    else
        missing="-S (GPG signature)"
    fi
fi

# Block and tell Claude what to add
echo "Blocked: All commits must be signed. Add $missing flags. Use: git commit -s -S -m \"message\"" >&2
exit 2
