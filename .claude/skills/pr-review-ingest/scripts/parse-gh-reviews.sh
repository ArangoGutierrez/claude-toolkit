#!/bin/bash
# parse-gh-reviews.sh — Fetch and format PR review comments
# Usage: parse-gh-reviews.sh <PR-number-or-URL>

set -euo pipefail

PR="${1:?Usage: parse-gh-reviews.sh <PR-number-or-URL>}"
PR_NUM=$(echo "$PR" | grep -oE '[0-9]+$' || echo "$PR")

echo "=== PR #${PR_NUM} Review Comments ==="
echo ""

echo "--- PR Info ---"
gh pr view "$PR_NUM" --json title,state,author,reviewDecision \
    --template '{{.title}} ({{.state}}) by {{.author.login}} — Decision: {{.reviewDecision}}' 2>/dev/null || echo "Could not fetch PR info"
echo ""
echo ""

echo "--- Review Comments ---"
gh pr view "$PR_NUM" --comments 2>/dev/null || echo "Could not fetch comments"
echo ""

echo "--- Inline Review Threads ---"
gh api "repos/{owner}/{repo}/pulls/${PR_NUM}/comments" \
    --jq '.[] | "[\(.path):\(.line // .original_line)] \(.user.login): \(.body)"' 2>/dev/null || echo "Could not fetch inline comments"
echo ""

echo "=== End PR #${PR_NUM} ==="
