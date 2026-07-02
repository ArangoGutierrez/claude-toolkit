#!/bin/bash
# prevent-push-workbench.sh - Block pushing agents-workbench to any remote
# Hook: PreToolUse (matcher: Bash)
#
# agents-workbench is a local-only branch. Never pushed.
#
# Exit 0 = allow
# Exit 2 = block (stderr becomes Claude's feedback)
set -uo pipefail

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')

# Only process git push commands
echo "$COMMAND" | grep -qE "^\s*git\s+push" || exit 0

# Block if pushing agents-workbench by name
if echo "$COMMAND" | grep -qE "\bagents-workbench\b"; then
    echo "BLOCKED: agents-workbench is a local-only branch and must NEVER be pushed to any remote." >&2
    echo "This branch is the local coordination hub. Only feature branches from worktrees should be pushed." >&2
    exit 2
fi

# Block if on agents-workbench and doing a bare/implicit push
BRANCH=$(git branch --show-current 2>/dev/null)
if [ "$BRANCH" = "agents-workbench" ]; then
    if echo "$COMMAND" | grep -qE "git\s+push\s*$" || \
       echo "$COMMAND" | grep -qE "git\s+push\s+(-[a-zA-Z]+\s+)*\S+\s*$" || \
       echo "$COMMAND" | grep -qE "\bHEAD\b"; then
        echo "BLOCKED: You are on agents-workbench. This branch must NEVER be pushed." >&2
        echo "Switch to a worktree to push feature branches:" >&2
        echo "  cd .worktrees/<name> && git push -u origin <branch>" >&2
        exit 2
    fi
fi

exit 0
