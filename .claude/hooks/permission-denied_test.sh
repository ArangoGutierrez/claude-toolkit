#!/bin/bash
# Test permission-denied.sh logs and emits hint.
set -euo pipefail

HOOK="$HOME/.claude/hooks/permission-denied.sh"
TMP=$(mktemp -d)
trap "rm -rf $TMP" EXIT

# Test 1: Bash denial — log entry + Bash-specific hint
INPUT='{"tool_name":"Bash","tool_input":{"command":"gh pr view 5"},"reason":"not_in_allow_list"}'
STDERR=$(echo "$INPUT" | HOME="$TMP" CLAUDE_SESSION_ID=t1 "$HOOK" 2>&1 >/dev/null)
LOG="$TMP/.claude/audit/permission-denials-$(date +%Y-%m-%d).log"

if ! grep -q 'tool:Bash' "$LOG"; then
    echo "FAIL test1: log entry missing tool name"
    cat "$LOG"
    exit 1
fi
if ! grep -q 'gh pr view 5' "$LOG"; then
    echo "FAIL test1: log entry missing input"
    exit 1
fi
if ! echo "$STDERR" | grep -qi 'allow list\|sandbox\|settings.json'; then
    echo "FAIL test1: hint not emitted to stderr"
    echo "STDERR: $STDERR"
    exit 1
fi

# Test 2: WebFetch denial — domain hint
INPUT='{"tool_name":"WebFetch","tool_input":{"url":"https://example.com"},"reason":"domain_not_allowlisted"}'
STDERR=$(echo "$INPUT" | HOME="$TMP" CLAUDE_SESSION_ID=t2 "$HOOK" 2>&1 >/dev/null)
if ! echo "$STDERR" | grep -qi 'allowlist\|allowedDomains'; then
    echo "FAIL test2: WebFetch hint missing"
    exit 1
fi

# Test 3: unknown tool — generic hint
INPUT='{"tool_name":"FrobNicate","tool_input":{},"reason":"unknown"}'
STDERR=$(echo "$INPUT" | HOME="$TMP" CLAUDE_SESSION_ID=t3 "$HOOK" 2>&1 >/dev/null)
if ! echo "$STDERR" | grep -qi 'denied\|settings.json'; then
    echo "FAIL test3: generic hint missing"
    exit 1
fi

echo "PASS"
