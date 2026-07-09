---
name: team-plan
description: Use when starting a new multi-task project requiring agent team coordination on agents-workbench branch
user-invocable: true
argument-hint: <project-description>
---

# Team Planning Phase

## Team Structure

You are the **Team Lead**. You coordinate work from the `agents-workbench` branch. You do NOT make technical decisions.

**Mandatory Roles (spawn in this order):**

1. **Principal Engineer** (spawn first): Senior technical authority. Architecture, Go/K8s conventions, security review. See `agents/principal-engineer.md` for full role definition. Location: `agents-workbench` (read-only).
2. **QA Engineer** (spawn second): Test quality, mutation testing, integration verification, PR readiness gate. See `agents/qa-engineer.md`. Location: `agents-workbench` (read-only).
3. **Workers (1-3)**: Implement tasks following TDD. Create **draft PRs only**. Location: dedicated worktrees.

**Team Size Limits:**
- Maximum 5 spawned agents: 1 Principal Engineer + 1 QA + up to 3 Workers
- You (Lead) do not count toward this limit
- More than 3 tasks: use waves (Principal Engineer and QA persist, Workers rotate)

## Communication Protocol

- **Workers to Principal Engineer:** Design decisions (present >=3 options with trade-offs)
- **Workers to QA:** Ready for testing (feature name, summary, test status, draft PR URL)
- **QA to Principal Engineer:** Quality issues requiring design changes

## Planning Workflow

**Prerequisites:** Must be on `agents-workbench` branch.

**Reference:** Read `references/planning-methodology.md` for decomposition rules, estimation, risk scoring, wave planning, and output format.

**Pre-flight — is this a team job?** Confirm BOTH hold before planning a team: the tasks are genuinely independent (no shared files, no cross-task dependencies) AND the work's value justifies multi-agent's ~15× token cost. If either fails, say which criterion failed and use the solo path (`superpowers:subagent-driven-development`) instead — a one-Worker "team" is usually a solo job. This gate is binding; the steps below assume the team path.

**Steps:**

1. **Verify branch:** `git branch --show-current` must show `agents-workbench`.

2. **Validate branch sync** (from `references/planning-methodology.md` Section 6):
   - `git fetch origin` then check behind/ahead counts
   - Behind >0: warn user, recommend merge
   - Behind >50: **hard gate** — refuse to plan until synced

3. **Brainstorm approach:** What are we building? What are the independent tasks? Present >=3 options.
   - **Panel hook-point (A/B):** When a planning fork is a genuine design decision (architecture, security posture, API shape, irreversible/outward-facing) — never trivial/reversible choices — the Lead surfaces it as an `AskUserQuestion` with exactly one `(Recommended)` option and the reasoning in the option descriptions. If you run a recommendation-review panel, handle its verdict: HOLD → proceed with the recommended option; DISSENT → queue the augmented question for the user; ERROR → re-ask original.

4. **Decompose work:** Use Task 0 pattern (shared infrastructure first). Score complexity (1-4). Validate independence. One concern per task. For each task's internal breakdown, use `superpowers:writing-plans` to produce the bite-sized TDD steps (failing test → minimal impl → verify → commit) — do not hand-roll a different task format.

5. **Assess risks:** Score each risk (likelihood x impact). Mitigate or stop-and-reassess for blockers.

6. **Ask branching strategy:** MANDATORY question. Options:
   - One branch per task (recommended for independent work)
   - Shared feature branch (tightly related features)
   - Single branch (small projects)

7. **Plan waves** (if >3 tasks): Max 3 per wave. Dependencies in earlier waves. Risk-first. Use wave transition checklist.

8. **Write plan:** Invoke `superpowers:writing-plans` for the bite-sized task breakdown, then layer the team-specific sections around it (Task List with Worker+Wave columns, Risk Register, Wave Plan, Branch Strategy, Dependencies Map, Success Criteria — see methodology reference). Save the combined plan to `.agents/plans/<project-name>.md`. (Do not edit the `writing-plans` plugin; the Team path is the executor per CLAUDE.md's Execution Model.)

9. **Update AGENTS.md:** Record task assignments, branch strategy, wave plan.

## Common Mistakes

| Mistake | Fix |
|---------|-----|
| Creating generic teammates without roles | Use Principal Engineer + QA + Workers |
| "Team Lead (me) - Principal Engineer" | Lead coordinates, PE is a SEPARATE agent |
| Spawning N agents for N tasks (no limit) | Max 5. Use waves. |
| Workers making architectural decisions | Workers escalate to Principal Engineer |

---

## Arguments

User arguments: $ARGUMENTS
