#!/bin/bash
# enforce-worktree.sh - Block source code writes on agents-workbench branch
# Hook: PreToolUse (matcher: Write, Edit)
#
# On agents-workbench: only agent coordination files are writable.
# Source code changes must happen in a worktree.
#
# Exit 0 = allow
# Exit 2 = block (stderr becomes Claude's feedback)

set -o pipefail

INPUT=$(cat)

# Not in a git repo? Allow.
GIT_ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || exit 0

# Not on agents-workbench? Allow.
BRANCH=$(git branch --show-current 2>/dev/null)
[ "$BRANCH" = "agents-workbench" ] || exit 0

# Extract file path from tool input
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // .tool_input.path // empty')
[ -z "$FILE_PATH" ] && exit 0

# Only govern files INSIDE this repo. An absolute path outside the repo root
# (e.g. the global ~/.claude memory/config dirs — not repo source) must be
# allowed: otherwise the prefix-strip below leaves it absolute and the
# repo-relative allowlist never matches it, wrongly blocking the write.
case "$FILE_PATH" in
    /*)
        case "$FILE_PATH" in
            "$GIT_ROOT"/*) ;;   # inside repo: continue to the allowlist
            *) exit 0 ;;        # outside repo: allow
        esac
        ;;
esac

# Normalize: strip git root prefix to get relative path
REL_PATH="${FILE_PATH#"$GIT_ROOT"/}"
REL_PATH="${REL_PATH#./}"

# Allowed paths on agents-workbench (coordination files only)
case "$REL_PATH" in
    AGENTS.md)                    exit 0 ;;
    .agents/*)                    exit 0 ;;
    .worktrees/*)                 exit 0 ;;
    docs/plans/*)                 exit 0 ;;
    docs/audits/*)                exit 0 ;;
    docs/design-languages/*)      exit 0 ;;
    CLAUDE.md)                    exit 0 ;;
    .cursor/rules/*)              exit 0 ;;
    .cursor/AGENTS.md)            exit 0 ;;
    .gitignore)                   exit 0 ;;
    .cursorrules)                 exit 0 ;;
    .claudeignore)                exit 0 ;;
esac

# Detect default branch for the error message
DEFAULT_BRANCH=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@')
if [ -z "$DEFAULT_BRANCH" ]; then
    for candidate in main master develop; do
        if git rev-parse --verify "refs/remotes/origin/$candidate" >/dev/null 2>&1 || \
           git rev-parse --verify "refs/heads/$candidate" >/dev/null 2>&1; then
            DEFAULT_BRANCH="$candidate"
            break
        fi
    done
fi
DEFAULT_BRANCH="${DEFAULT_BRANCH:-main}"

echo "BLOCKED: Source code is READ-ONLY on agents-workbench." >&2
echo "File: $REL_PATH" >&2
echo "" >&2
echo "This branch is the coordination hub. Implementation happens in worktrees." >&2
echo "Create a worktree (ALWAYS from remote ref, never local):" >&2
echo "  git fetch upstream 2>/dev/null && BASE=\"upstream/$DEFAULT_BRANCH\" || { git fetch origin && BASE=\"origin/$DEFAULT_BRANCH\"; }" >&2
echo "  git worktree add .worktrees/<name> -b <branch-name> \"\$BASE\"" >&2
echo "" >&2
echo "Allowed files on agents-workbench:" >&2
echo "  AGENTS.md, .agents/*, .worktrees/*, docs/plans/*, docs/audits/*, docs/design-languages/*, CLAUDE.md, .cursor/rules/*, .gitignore" >&2
exit 2
