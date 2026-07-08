#!/bin/bash
# Test bash-audit-log.sh redacts credentials before append.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
HOOK="$SCRIPT_DIR/bash-audit-log.sh"
TMP_HOME=$(mktemp -d)
trap "rm -rf $TMP_HOME" EXIT

# Test 1: URL-embedded credential
INPUT='{"tool_input":{"command":"git clone https://user:GHP_SECRETxyz@github.com/foo/bar"},"cwd":"/tmp"}'
echo "$INPUT" | HOME="$TMP_HOME" CLAUDE_SESSION_ID=t1 "$HOOK"
LOG="$TMP_HOME/.claude/audit/bash-commands-$(date +%Y-%m-%d).log"

if grep -q 'GHP_SECRETxyz' "$LOG"; then
    echo "FAIL: token leaked to log"
    cat "$LOG"
    exit 1
fi
if ! grep -q '<redacted>@github.com' "$LOG"; then
    echo "FAIL: redaction marker missing"
    cat "$LOG"
    exit 1
fi

# Test 2: --token flag
INPUT='{"tool_input":{"command":"curl -H Authorization --token=ABC123 https://api"},"cwd":"/tmp"}'
echo "$INPUT" | HOME="$TMP_HOME" CLAUDE_SESSION_ID=t2 "$HOOK"
if grep -q 'ABC123' "$LOG"; then
    echo "FAIL: --token value leaked"
    exit 1
fi

# Test 3: non-credential command unchanged
INPUT='{"tool_input":{"command":"ls -la /tmp"},"cwd":"/tmp"}'
echo "$INPUT" | HOME="$TMP_HOME" CLAUDE_SESSION_ID=t3 "$HOOK"
if ! grep -q 'ls -la /tmp' "$LOG"; then
    echo "FAIL: benign command corrupted"
    exit 1
fi

# Test 4: token-only URL (CI pattern)
INPUT='{"tool_input":{"command":"git clone https://GHTOKEN_xyz123@github.com/foo/bar"},"cwd":"/tmp"}'
echo "$INPUT" | HOME="$TMP_HOME" CLAUDE_SESSION_ID=t4 "$HOOK"
if grep -q 'GHTOKEN_xyz123' "$LOG"; then
    echo "FAIL: token-only URL leaked"
    exit 1
fi
if ! grep -q '<redacted>@github.com' "$LOG"; then
    echo "FAIL: token-only URL redaction marker missing"
    exit 1
fi

# Test 5: real session_id from hook input JSON is recorded in the log line
INPUT='{"session_id":"test-sess-123","tool_input":{"command":"echo hi"},"cwd":"/tmp"}'
echo "$INPUT" | HOME="$TMP_HOME" "$HOOK"
if ! grep -q 'session:test-sess-123' "$LOG"; then
    echo "FAIL: real session_id from hook input JSON not recorded"
    cat "$LOG"
    exit 1
fi

# Test 6: JSON without session_id falls back to session:unknown
INPUT='{"tool_input":{"command":"echo hi again"},"cwd":"/tmp"}'
echo "$INPUT" | HOME="$TMP_HOME" "$HOOK"
if ! tail -1 "$LOG" | grep -q 'session:unknown'; then
    echo "FAIL: missing session_id should fall back to session:unknown"
    cat "$LOG"
    exit 1
fi

echo "PASS"
