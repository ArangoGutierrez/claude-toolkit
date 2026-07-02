#!/bin/bash
# analyze-sessions.sh — Aggregate bash audit logs + git activity for reflection
# Usage: analyze-sessions.sh [days=7]

set -euo pipefail

DAYS="${1:-7}"
AUDIT_DIR="${HOME}/.claude/audit"
SINCE_DATE=$(date -v-"${DAYS}"d +%Y-%m-%d 2>/dev/null || date -d "${DAYS} days ago" +%Y-%m-%d)

echo "=== Session Analysis (last ${DAYS} days, since ${SINCE_DATE}) ==="
echo ""

# 1. Bash audit log analysis
echo "--- Bash Command Patterns ---"
if ls "${AUDIT_DIR}"/bash-commands-*.log >/dev/null 2>&1; then
    echo "Log files found: $(ls "${AUDIT_DIR}"/bash-commands-*.log 2>/dev/null | wc -l | tr -d ' ')"

    echo ""
    echo "Top 10 commands:"
    cat "${AUDIT_DIR}"/bash-commands-*.log 2>/dev/null | \
        grep -v '^#' | grep -v '^$' | \
        sed 's/\t.*//' | sort | uniq -c | sort -rn | head -10

    echo ""
    echo "Error patterns:"
    cat "${AUDIT_DIR}"/bash-commands-*.log 2>/dev/null | \
        grep -i -E '(error|fail|denied|permission|refused)' | \
        head -20

    echo ""
    echo "Hook blocks:"
    cat "${AUDIT_DIR}"/bash-commands-*.log 2>/dev/null | \
        grep -i -E '(blocked|STOP|violation|forbidden)' | \
        head -10
else
    echo "No bash audit logs found in ${AUDIT_DIR}/"
fi

echo ""

# 2. Git activity
echo "--- Git Activity (last ${DAYS} days) ---"
echo "Commits:"
git log --since="${SINCE_DATE}" --oneline --no-merges 2>/dev/null | head -20 || echo "No commits"

echo ""
echo "Most changed files:"
git log --since="${SINCE_DATE}" --name-only --no-merges --pretty=format: 2>/dev/null | \
    grep -v '^$' | sort | uniq -c | sort -rn | head -10 || echo "None"

echo ""

# 3. Hook violation count
echo "--- Hook Violations ---"
if ls "${AUDIT_DIR}"/bash-commands-*.log >/dev/null 2>&1; then
    VIOLATIONS=$(cat "${AUDIT_DIR}"/bash-commands-*.log 2>/dev/null | grep -c -i 'violation\|STOP\|blocked' || true)
    echo "Total violations/blocks: ${VIOLATIONS}"
else
    echo "No audit logs to analyze"
fi

echo ""
echo "=== Analysis Complete ==="
