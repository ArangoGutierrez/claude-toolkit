# /team-execute — spawn the agent team to implement an approved plan

`/team-execute <project-name>` reads the plan `team-plan` wrote to
`.agents/plans/<project-name>.md`, creates one git worktree per task, and spawns
the team in mandatory order: Principal Engineer, then QA Engineer, then up to 3
Workers. It is a hard gate, not best-effort: it refuses to run if you aren't on
`agents-workbench`, if no plan exists, or if the branch is more than 50 commits
behind the default branch (sync first — the gate exists to avoid conflict-heavy
PRs).

## When to use it

- A plan already exists at `.agents/plans/<project>.md` from `team-plan` and
  you're moving from planning into implementation.
- The work spans two or more source files or needs a design decision — the
  bar for team execution over solo work.
- You want draft PRs (`gh pr create --draft`) gated by a Principal Engineer
  architecture/security review and a QA validation pass before anything is
  promoted to ready-for-review.
- You're starting a later wave of the same project — the Principal Engineer
  and QA persist across waves, only Workers rotate.
- **Not for:** a project with no plan yet (run `team-plan` first — this skill
  refuses without one), nor single-file fixes — use
  `superpowers:test-driven-development` directly instead of spinning up a team.

## Examples

    > /team-execute gpu-scheduler-retry
    → Verifies agents-workbench is in sync, creates `.worktrees/<feature>` per
      task, then spawns Principal Engineer -> QA Engineer -> up to 3 Workers in
      that order. Workers implement via TDD and open draft PRs; QA runs
      CI-equivalent checks and is the only agent allowed to run `gh pr ready`.

    > /team-execute gpu-scheduler-retry   (agents-workbench 80 commits behind origin/main)
    → Refuses to execute and tells you to merge the default branch in first —
      the "behind more than 50 commits" gate exists to avoid conflict-heavy PRs.

## Setup

Requires the `gh` CLI authenticated for the target repo and a plan already
written by `team-plan`. The role definitions the spawned agents read at
startup live in `.claude/agents/principal-engineer.md` and
`.claude/agents/qa-engineer.md`.

## Notes

- Team size is capped at 5 spawned agents (Principal Engineer + QA + up to 3
  Workers). More than 3 tasks uses waves; Principal Engineer and QA persist
  across waves, Workers rotate.
- Workers are forbidden from running `gh pr ready` — only QA promotes a draft
  PR, and only after its review cycle (QA validation, Principal Engineer
  review, external bot triage) fully passes.
- This workflow has two entry points that should stay in sync: the
  `/team-execute` slash command and this auto-triggerable skill.
- Related: [`team-plan`](../team-plan/) (writes the plan this skill consumes),
  [`team-shutdown`](../team-shutdown/) (tears down agents and worktrees when
  done), [`worktree-guide`](../worktree-guide/) (the agents-workbench branch
  model). Index:
  [`docs/skills-and-commands.md`](../../../docs/skills-and-commands.md).
