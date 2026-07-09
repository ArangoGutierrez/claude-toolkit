---
name: team-shutdown
description: Use when all team tasks are complete or abandoned and team infrastructure, worktrees, and AGENTS.md need cleanup
user-invocable: true
argument-hint: <project-name>
---

# Team Shutdown Phase

You are the **Team Lead**, tearing down a finished (or abandoned) team. This skill owns **team-level teardown only**. Per-branch finishing — verifying tests, choosing merge / PR / keep / discard, and provenance-safe worktree removal — is delegated to `superpowers:finishing-a-development-branch`. Do not hand-roll merges or `git worktree remove` here.

**When to use:** All worker tasks are complete (PRs merged) or explicitly abandoned, and the team infrastructure, worktrees, and `AGENTS.md` need cleanup.

## Shutdown Workflow

1. **Verify completion status.**
   - `gh pr list --state open` and `git branch --no-merged "$(git symbolic-ref refs/remotes/origin/HEAD | sed 's@^refs/remotes/origin/@@')"` to find any unmerged worker branches.
   - If open or unmerged work remains, list it and confirm with the user before tearing down.

2. **Finish each remaining worker branch (delegate).**
   - For every worker worktree still under `.worktrees/`, `cd` into it and invoke **`superpowers:finishing-a-development-branch`**. That skill verifies tests, presents merge / PR / keep / discard, and cleans up the worktree provenance-safely.
   - Branches already merged and cleaned during execution need no action.
   - Run this BEFORE `TeamDelete` — a torn-down agent cannot help iterate on a PR.

3. **Shut down team agents.**
   - `TeamDelete` to remove team infrastructure (Principal Engineer, QA, all Workers).
   - Do NOT skip this — leaving team infrastructure running wastes resources and pollutes context.

4. **Update `AGENTS.md`.**
   - Mark every task complete (or abandoned with reason); record final status.
   - Commit to `agents-workbench` (local only — never push).

5. **Context hygiene.**
   - Team context is large. If you're moving on to new work, start a fresh session or use `/handoff` to carry forward only what's needed. (Context is auto-summarized as it grows; no manual `/compact` step is required.)

## Common Shutdown Mistakes

| Mistake | Fix |
|---------|-----|
| Hand-rolling `git worktree remove` or merges | Delegate per-branch finishing to `superpowers:finishing-a-development-branch` |
| `TeamDelete` before finishing branches | Finish branches first; a torn-down agent can't iterate on a PR |
| Skipping the `AGENTS.md` final status | Record it for future reference |
| Pushing the `AGENTS.md` commit | `agents-workbench` is local-only; never push it |

---

## Arguments

User arguments: $ARGUMENTS
