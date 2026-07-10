#!/bin/bash
# bash-audit-log.sh - Audit log every Bash command agents execute
# Hook: PostToolUse (matcher: Bash)
#
# Logs to ~/.claude/audit/bash-commands-YYYY-MM-DD.log
# Format: ISO8601 | session | cwd | exit_code | cmd
# Always exits 0 — logging should never block the agent.
set -uo pipefail

INPUT=$(cat)

COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')
COMMAND=$(echo "$COMMAND" | /usr/bin/sed -E \
  -e 's,://[^/]*:[^@/]*@,://<redacted>@,g' \
  -e 's,://[^/@:]+@,://<redacted>@,g' \
  -e 's,(--?(token|password|api[-_]?key|secret)[= ])[^[:space:]]+,\1<redacted>,gi')
[ -z "$COMMAND" ] && exit 0

# Fold embedded newlines to a literal \n so a compound/multi-line Bash call is
# ONE physical log line that carries the session marker in full. Without this,
# only the first physical line bears the "| session:<uuid> |" marker and
# sub-commands 2..N are invisible to any downstream consumer that filters the
# log line-by-line (e.g. grep -F "session:<uuid> "). Heredoc bodies fold in as
# inert `\n`-joined data on the same line — they gain no marker of their own.
# Pure-bash, no subprocess.
NL=$'\n'
ESC='\n'   # literal backslash-n
# Only LF is folded; a lone CR (CRLF/old-Mac line) persists as a raw mid-line
# byte — cosmetic, the entry stays one physical line and the marker holds.
COMMAND=${COMMAND//$NL/$ESC}

LOG_DIR="$HOME/.claude/audit"
mkdir -p "$LOG_DIR" 2>/dev/null
LOG_FILE="$LOG_DIR/bash-commands-$(date +%Y-%m-%d).log"

TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // empty')
[ -z "$SESSION_ID" ] && SESSION_ID="unknown"
CWD=$(echo "$INPUT" | jq -r '.cwd // empty')
[ -z "$CWD" ] && CWD="$(pwd)"

echo "$TIMESTAMP | session:$SESSION_ID | cwd:$CWD | cmd: $COMMAND" >> "$LOG_FILE"

# Cleanup: remove logs older than 30 days (once per day)
CLEANUP_MARKER="$LOG_DIR/.cleanup-$(date +%Y-%m-%d)"
if [ ! -f "$CLEANUP_MARKER" ]; then
    find "$LOG_DIR" -name "bash-commands-*.log" -mtime +30 -delete 2>/dev/null
    find "$LOG_DIR" -name ".cleanup-*" ! -name ".cleanup-$(date +%Y-%m-%d)" -delete 2>/dev/null
    touch "$CLEANUP_MARKER" 2>/dev/null
fi

exit 0
