# /team-shutdown — retire a completed team engagement

`/team-shutdown <project-name>` closes out a multi-agent team once its tasks
are merged or explicitly abandoned: it verifies completion, tears down the
spawned team via TeamDelete, removes leftover worktrees, and records final
status in `AGENTS.md`. It is the last of three phases
(`/team-plan` → `/team-execute` → `/team-shutdown`) and will not barrel
through if PRs are still open — it warns and asks for confirmation instead.

## When to use it

- All feature branches for a team are merged (or a task was explicitly
  abandoned) and the team infrastructure is still running.
- You want a single pass that shuts down every spawned agent, removes every
  `.worktrees/<feature>` directory, and updates `AGENTS.md` with final status.
- You're about to start a new team engagement and need the previous one's
  agents, worktrees, and context out of the way first.
- You want the finished team's context out of the way before the next task
  (start a fresh session or `/handoff`; no manual `/compact` step is needed).
- **Not for:** cleanup while PRs are still open for review — that's still
  `/team-execute`'s review cycle; `team-shutdown` warns rather than force-
  closing work in progress.

## Examples

    > /team-shutdown payment-retry
    → `git branch --merged` shows every feature branch merged. Runs
      TeamDelete (shuts down the Principal Engineer, QA Agent, and all
      Workers), removes each `.worktrees/<feature>` directory, confirms
      `git worktree list` shows only the main tree, then updates `AGENTS.md`
      marking every task complete.

    > /team-shutdown payment-retry
    → Two of three feature branches are still unmerged. The skill warns that
      PRs are open and asks for confirmation before proceeding — it does not
      silently discard work in progress.

## Notes

- The `/team-shutdown` slash name is provided by this skill
  (`.claude/skills/team-shutdown/SKILL.md`); invoke it directly, or let the
  agent trigger it automatically once it recognizes a team is done.
- Order matters: TeamDelete runs before worktree removal, never after —
  leftover team infrastructure wastes resources and pollutes context.
- Final step: move on with a fresh session or `/handoff` — context is
  auto-summarized as it grows, so no manual `/compact` step is required.
- Related: [`team-plan`](../team-plan/) plans the work,
  [`team-execute`](../team-execute/) runs it, `team-shutdown` closes it out;
  [`worktree-guide`](../worktree-guide/) explains the agents-workbench model.
  Index: [`docs/skills-and-commands.md`](../../../docs/skills-and-commands.md).
