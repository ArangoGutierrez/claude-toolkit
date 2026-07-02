# /worktree-guide — branch model and commands for agents-workbench worktrees

`/worktree-guide` loads the `agents-workbench` branch model into context:
which branch is read-only coordination space, the exact command to cut a
properly-based worktree for implementation, and the enforcement hooks that
keep the two apart. It's a reference skill — invoking it surfaces the
protocol, it doesn't touch git state on its own.

## When to use it

- Starting implementation work and need the exact command to create a
  worktree branched from the correct remote ref, not a stale local branch.
- Unsure which files are safe to edit directly on `agents-workbench` without
  tripping the write-blocking hook.
- Working from a fork and need the upstream-vs-origin remote detection logic.
- Cleaning up a worktree after its PR merges.
- **Not for:** orchestrating a multi-agent team end to end — that's
  [`team-plan`](../team-plan/) (planning) and [`team-execute`](../team-execute/)
  (spawning Principal Engineer/QA/Workers); worktree-guide is the underlying
  worktree mechanics both of those rely on.

## Examples

    > /worktree-guide
    → Loads the branch model and flow into context: `agents-workbench` is
      read-only for source (plan there instead), feature branches live under
      `.worktrees/`, and the flow is Plan → Create worktree → Implement
      (TDD) → Push/PR → Cleanup.

    > /worktree-guide (working in a fork with an `upstream` remote configured)
    → Surfaces the remote-detection command, which resolves `upstream`'s
      default branch first and falls back to `origin` only when `upstream`
      isn't configured — so the worktree bases off the fork's real default
      branch instead of a possibly stale local `main`.

## Notes

- `enforce-worktree.sh` blocks writes to source code on `agents-workbench`,
  allowing only coordination files: `AGENTS.md`, `.agents/*`, `.worktrees/*`,
  `docs/plans/*`, `docs/audits/*`, `docs/design-languages/*`, `CLAUDE.md`,
  `.claudeignore`, `.gitignore`, and the Cursor equivalents (`.cursor/rules/*`,
  `.cursor/AGENTS.md`, `.cursorrules`) — the hook's `case` block is the
  authoritative list. A blocked write there is expected behavior — move the
  work into a worktree instead.
- `prevent-push-workbench.sh` blocks pushing `agents-workbench` to any
  remote; it's meant to stay a local-only coordination branch.
- Related: [`team-plan`](../team-plan/), [`team-execute`](../team-execute/).
  Index: [`docs/skills-and-commands.md`](../../../docs/skills-and-commands.md).
