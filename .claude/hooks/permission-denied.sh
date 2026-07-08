#!/bin/bash
# permission-denied.sh - log denied tool calls and emit suggestion
# Hook event: PermissionDenied (Claude Code 2.x)
# Exit 0 always — informational only, never blocks.

set -o pipefail

INPUT=$(cat)
TOOL=$(echo "$INPUT" | jq -r '.tool_name // .tool // "unknown"')
REASON=$(echo "$INPUT" | jq -r '.reason // "unspecified"')
INPUT_SUMMARY=$(echo "$INPUT" | jq -r '.tool_input | tostring' 2>/dev/null | head -c 200)

LOG_DIR="$HOME/.claude/audit"
mkdir -p "$LOG_DIR" 2>/dev/null
LOG_FILE="$LOG_DIR/permission-denials-$(date +%Y-%m-%d).log"

TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
SESSION_ID="${CLAUDE_SESSION_ID:-unknown}"

echo "$TIMESTAMP | session:$SESSION_ID | tool:$TOOL | reason:$REASON | input:$INPUT_SUMMARY" >> "$LOG_FILE"

# Emit hint based on tool
case "$TOOL" in
    Bash)
        echo "Hint: Bash command not in allow list. Add to settings.json permissions.allow or use /sandbox." >&2
        ;;
    WebFetch)
        echo "Hint: WebFetch domain not allowlisted. Add to remote-settings.json sandbox.network.allowedDomains." >&2
        ;;
    Write|Edit)
        echo "Hint: Write/Edit blocked. Check enforce-worktree.sh allowlist or branch context." >&2
        ;;
    *)
        echo "Hint: tool '$TOOL' denied. Check settings.json permissions and managed-settings.json deny list." >&2
        ;;
esac

exit 0
