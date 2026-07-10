#!/bin/bash
# Test bash-audit-log.sh redacts credentials before append.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
HOOK="$SCRIPT_DIR/bash-audit-log.sh"
TMP_HOME=$(mktemp -d)
trap 'rm -rf "$TMP_HOME"' EXIT

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

# Test 7: a multi-line COMPOUND command logs as ONE physical line so EVERY
# sub-command (not just the first) shares the session marker. A downstream
# consumer that greps `session:<uuid> ` line-by-line only sees tokens on the
# marker line; before the newline-fold only sub-command 1 carried the marker,
# so tokens on lines 2..N were invisible. Tokens ALPHA7/BRAVO7/CHARLIE7 are
# unique so they cannot collide with other lines in the shared log.
INPUT='{"session_id":"comp7","tool_input":{"command":"echo ALPHA7\necho BRAVO7\necho CHARLIE7"},"cwd":"/tmp"}'
echo "$INPUT" | HOME="$TMP_HOME" "$HOOK"
for tok in ALPHA7 BRAVO7 CHARLIE7; do
    if ! grep -F "session:comp7 " "$LOG" | grep -q "$tok"; then
        echo "FAIL: compound sub-command token '$tok' not on a session-marker line"
        grep -nF "$tok" "$LOG"
        exit 1
    fi
done

# Test 8: a heredoc-bearing command folds onto ONE marker line; the heredoc BODY
# stays inert data on that line and must NOT gain its own (marker-less) line.
# Decision: the body is carried as literal `\n`-joined text alongside the marker,
# never emitted as a standalone entry — a downstream `<<` denylist then treats
# the whole line as a data-carrier, exactly as intended.
INPUT='{"session_id":"here8","tool_input":{"command":"cat > /tmp/here8.txt <<'"'"'EOF'"'"'\nHEREDOC_BODY_TOKEN8\nEOF"},"cwd":"/tmp"}'
echo "$INPUT" | HOME="$TMP_HOME" "$HOOK"
# (8a) fold: the heredoc body token appears ON the session-marker line.
if ! grep -F "session:here8 " "$LOG" | grep -q 'HEREDOC_BODY_TOKEN8'; then
    echo "FAIL: heredoc body token not folded onto the session-marker line"
    grep -nF 'HEREDOC_BODY_TOKEN8' "$LOG"
    exit 1
fi
# (8b) inertness: the heredoc body must never appear on a marker-less line.
if grep 'HEREDOC_BODY_TOKEN8' "$LOG" | grep -qv 'session:here8'; then
    echo "FAIL: heredoc body appears on a line without the session marker"
    grep -nF 'HEREDOC_BODY_TOKEN8' "$LOG"
    exit 1
fi

echo "PASS"
