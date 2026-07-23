# /team-plan — scope a multi-task project before spawning an agent team

`/team-plan <project-description>` runs the planning phase of the team
lifecycle: it checks you're on `agents-workbench` and in sync with the
default branch, brainstorms three or more implementation approaches with
you, decomposes the work into complexity- and risk-scored tasks (grouped
into waves if there are more than 3), asks you to pick a branching
strategy, then writes the result to `.agents/plans/<project-name>.md` and
updates `AGENTS.md`. It only produces a plan — no agents are spawned until
[`team-execute`](../team-execute/) runs.

## When to use it

- Starting a project with more than one independent workstream, before any
  worktrees or teammates exist.
- You want tasks scored for complexity (1-4) and risk (likelihood x impact)
  up front, instead of improvising task boundaries mid-execution.
- You need a written plan artifact in `.agents/plans/` that `/team-execute`
  can pick up later, possibly in a different session.
- You want the branching strategy (per-task, shared feature branch, or
  single branch) decided before any branch is created.
- **Not for:** a single-file fix or a task one agent can finish solo — plan
  and execute it directly instead of standing up a team.

## Examples

    > /team-plan add rate limiting and audit logging to the API gateway
    → Confirms `agents-workbench` is checked out and not more than 50 commits
      behind the default branch, walks through three or more approach
      options, decomposes the work into scored tasks (e.g. rate-limiter
      middleware, audit-log sink, shared config task), asks you to choose a
      branching strategy, then writes
      `.agents/plans/api-gateway-hardening.md` and updates `AGENTS.md`.

    > /team-plan add a health-check endpoint to the metrics service
    → Decomposes into two tasks — too few for wave planning — so the plan
      skips the Wave Plan section; you pick "single branch" and the output
      covers Project Objective, Task List, Risk Register, Branch Strategy,
      Dependencies Map, and Success Criteria.

    > /team-plan migrate the billing service to the new event bus
    → `agents-workbench` is 60 commits behind the default branch, past the
      hard-gate threshold — team-plan refuses to continue until you sync.

## Setup

Requires an `agents-workbench` branch to already exist, and a resolvable
default branch on `origin` (`main`/`master`/`develop`) to validate against.
No environment variables.

## Notes

- The `/team-plan` slash name is provided by this skill
  (`.claude/skills/team-plan/SKILL.md`), which the agent can also trigger
  automatically. Invoke it via `/team-plan`.
- Mandatory spawn order in the next phase is Principal Engineer, then QA,
  then up to 3 Workers (5 agents max); more than 3 tasks means waves, with
  the Principal Engineer and QA persisting across all of them.
- Related: [`team-execute`](../team-execute/) spawns the team from this
  plan; [`team-shutdown`](../team-shutdown/) tears it down once PRs are
  merged or abandoned; [`worktree-guide`](../worktree-guide/) explains the
  agents-workbench branch model. Index:
  [`docs/skills-and-commands.md`](../../../docs/skills-and-commands.md).
