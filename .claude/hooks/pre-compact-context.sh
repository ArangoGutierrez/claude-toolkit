#!/bin/bash
# pre-compact-context.sh - PreCompact hook (hybrid blocking)
# Blocks (exit 2) when checkpoint stale AND any worktree has uncommitted source.
# Otherwise emits preservation instructions and exits 0.

set -uo pipefail

# Always emit the preservation instructions to stdout
cat <<'EOF'
When compacting, you MUST preserve:
- The current TDD phase (Red/Green/Refactor) and which test is being worked on
- The current iteration count [Iteration X/Y]
- Any active worktree path and branch name
- The list of files modified in this session
- Any design decisions made with the user
EOF

# Escape hatch
[ "${SKIP_PRECOMPACT_GATE:-0}" = "1" ] && exit 0

CHECKPOINT="$HOME/.claude/audit/.last-checkpoint"
STALE_MIN=30

# Stale check: file missing or mtime older than N minutes
checkpoint_stale() {
    [ -f "$CHECKPOINT" ] || return 0
    local now mtime age
    now=$(date +%s)
    mtime=$(stat -f %m "$CHECKPOINT" 2>/dev/null || stat -c %Y "$CHECKPOINT" 2>/dev/null || echo 0)
    age=$(( (now - mtime) / 60 ))
    [ "$age" -ge "$STALE_MIN" ]
}

# Dirty check: at least one tracked worktree has uncommitted source
# (excludes docs/, .agents/, .worktrees/)
any_worktree_dirty() {
    # Test override
    if [ -n "${PRECOMPACT_TEST_WORKTREE_DIR:-}" ]; then
        local dirty
        dirty=$(git -C "$PRECOMPACT_TEST_WORKTREE_DIR" status --porcelain 2>/dev/null | \
            grep -vE '^.{2} (docs/|\.agents/|\.worktrees/)' | head -1)
        [ -n "$dirty" ]
        return $?
    fi

    # Real worktrees: iterate git worktree list
    if ! command -v git &>/dev/null; then return 1; fi
    local found=1
    while IFS= read -r line; do
        case "$line" in
            worktree*)
                local path="${line#worktree }"
                local dirty
                dirty=$(git -C "$path" status --porcelain 2>/dev/null | \
                    grep -vE '^.{2} (docs/|\.agents/|\.worktrees/)' | head -1)
                if [ -n "$dirty" ]; then
                    found=0
                    break
                fi
                ;;
        esac
    done < <(git worktree list --porcelain 2>/dev/null)
    return $found
}

if checkpoint_stale && any_worktree_dirty; then
    echo "" >&2
    echo "BLOCKED: PreCompact gate triggered." >&2
    echo "  - Checkpoint stale (>${STALE_MIN}m): $CHECKPOINT" >&2
    echo "  - At least one worktree has uncommitted source changes." >&2
    echo "" >&2
    echo "Resolve by EITHER:" >&2
    echo "  (1) commit pending work, OR" >&2
    echo "  (2) refresh: touch $CHECKPOINT, OR" >&2
    echo "  (3) bypass: rerun with SKIP_PRECOMPACT_GATE=1" >&2
    exit 2
fi

exit 0
