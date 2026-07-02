---
name: worktree-guide
description: Use when creating worktrees or starting implementation work in isolated branches from agents-workbench
user-invocable: true
---

# agents-workbench Worktree Workflow

## Branches

- `agents-workbench` — local-only coordination hub; do not push it (`prevent-push-workbench.sh` enforces). Source code is read-only on this branch.
- Feature branches — created in `.worktrees/` from the remote default branch

## Worktree Creation (critical)

Branch from the remote ref — local `main`/`master`/`develop` may be stale.

```bash
# Detect the right remote (upstream for forks, origin otherwise)
git fetch upstream 2>/dev/null && BASE="upstream/$(git symbolic-ref refs/remotes/upstream/HEAD 2>/dev/null | sed 's@^refs/remotes/upstream/@@' || echo main)" || { git fetch origin && BASE="origin/$(git symbolic-ref refs/remotes/origin/HEAD | sed 's@^refs/remotes/origin/@@')"; }
git worktree add .worktrees/<name> -b <branch> "$BASE"
```

## Flow

1. **Plan** on agents-workbench (AGENTS.md, `.agents/plans/`)
2. **Create worktree** from remote ref (see command above)
3. **Implement** in worktree (TDD: Red → Green → Refactor)
4. **Push** feature branch, create PR
5. **Cleanup** after merge: `git worktree remove .worktrees/<name>`

## Enforcement

- `enforce-worktree.sh` hook blocks source code writes on agents-workbench
- Allowed files on agents-workbench: AGENTS.md, .agents/*, .worktrees/*, docs/plans/*, CLAUDE.md, .cursor/rules/*, .gitignore
- `prevent-push-workbench.sh` hook blocks pushing agents-workbench to any remote
