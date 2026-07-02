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

**Steps:**

1. **Verify branch:** `git branch --show-current` must show `agents-workbench`.

2. **Validate branch sync** (from `references/planning-methodology.md` Section 6):
   - `git fetch origin` then check behind/ahead counts
   - Behind >0: warn user, recommend merge
   - Behind >50: **hard gate** — refuse to plan until synced

3. **Brainstorm approach:** What are we building? What are the independent tasks? Present >=3 options.

4. **Decompose work:** Use Task 0 pattern (shared infrastructure first). Score complexity (1-4). Validate independence. One concern per task.

5. **Assess risks:** Score each risk (likelihood x impact). Mitigate or stop-and-reassess for blockers.

6. **Ask branching strategy:** MANDATORY question. Options:
   - One branch per task (recommended for independent work)
   - Shared feature branch (tightly related features)
   - Single branch (small projects)

7. **Plan waves** (if >3 tasks): Max 3 per wave. Dependencies in earlier waves. Risk-first. Use wave transition checklist.

8. **Write plan:** Output to `.agents/plans/<project-name>.md` with all 7 required sections (see methodology reference).

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
