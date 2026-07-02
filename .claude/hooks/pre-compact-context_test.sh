#!/bin/bash
# Test pre-compact-context.sh blocks when checkpoint stale AND worktree dirty.
# Note: NO `set -e` — we deliberately invoke the hook expecting non-zero exits.
set -uo pipefail

HOOK="$HOME/.claude/hooks/pre-compact-context.sh"
TMP=$(mktemp -d)
trap "rm -rf $TMP" EXIT

# Setup: fake git repo
mkdir -p "$TMP/repo" && cd "$TMP/repo"
git init -q
git config user.email t@t && git config user.name t
echo init > a && git add a && git commit -qm init
mkdir -p "$TMP/.claude/audit"

run_hook() {
    HOME="$TMP" PRECOMPACT_TEST_WORKTREE_DIR="${1:-}" SKIP_PRECOMPACT_GATE="${2:-0}" \
        "$HOOK" </dev/null >/dev/null 2>&1
    echo $?
}

# Test 1: fresh checkpoint + clean → exit 0 (allow)
touch "$TMP/.claude/audit/.last-checkpoint"
RC=$(run_hook "$TMP/repo")
[ "$RC" = "0" ] || { echo "FAIL test1: clean state should allow (got $RC)"; exit 1; }

# Test 2: stale checkpoint + clean → exit 0 (allow, no dirty work)
touch -t 202001010000 "$TMP/.claude/audit/.last-checkpoint"
RC=$(run_hook "$TMP/repo")
[ "$RC" = "0" ] || { echo "FAIL test2: stale but clean should allow (got $RC)"; exit 1; }

# Test 3: fresh checkpoint + dirty worktree → exit 0 (allow, fresh checkpoint)
touch "$TMP/.claude/audit/.last-checkpoint"
echo dirty >> "$TMP/repo/a"
RC=$(run_hook "$TMP/repo")
[ "$RC" = "0" ] || { echo "FAIL test3: fresh + dirty should allow (got $RC)"; exit 1; }

# Test 4: stale checkpoint + dirty worktree → exit 2 (BLOCK)
touch -t 202001010000 "$TMP/.claude/audit/.last-checkpoint"
RC=$(run_hook "$TMP/repo")
[ "$RC" = "2" ] || { echo "FAIL test4: stale + dirty must BLOCK (got $RC)"; exit 1; }

# Test 5: escape hatch SKIP_PRECOMPACT_GATE=1 overrides
RC=$(run_hook "$TMP/repo" "1")
[ "$RC" = "0" ] || { echo "FAIL test5: SKIP env should override (got $RC)"; exit 1; }

# Test 6: docs file with compound XY status (MM) is correctly excluded
git -C "$TMP/repo" checkout -- .  # clean non-docs dirty state left by prior tests
mkdir -p "$TMP/repo/docs"
echo orig > "$TMP/repo/docs/note.md"
git -C "$TMP/repo" add docs/note.md
echo modified > "$TMP/repo/docs/note.md"  # now staged + unstaged → AM
# Stale checkpoint to make sure we'd block if dirty:
touch -t 202001010000 "$TMP/.claude/audit/.last-checkpoint"
RC=$(run_hook "$TMP/repo")
[ "$RC" = "0" ] || { echo "FAIL test6: docs AM should NOT trigger block (got $RC)"; exit 1; }

echo "PASS"
