# Planning Guide

**Purpose:** Structured planning methodology for the `/team-plan` command.
**Audience:** AI agent performing project decomposition and team coordination.

## 1. Work Decomposition

Break the project into independent, parallelizable tasks.

### Steps

1. **Identify natural boundaries** along one of these axes:
   - Layer: API / UI / data layer / infrastructure
   - Domain: user management / billing / notifications
   - Service: each microservice or module boundary
2. **Extract shared infrastructure** (Task 0 pattern): databases, schemas, shared types, CI config, base libraries. These MUST be built before dependent tasks.
3. **Validate independence** for each task:
   - Can it be tested without other tasks completing? If no, merge or reorder.
   - Does it touch files another task also touches? If yes, split at the file boundary or sequence them.
4. **Enforce one concern per task.** If a task description uses "and", it is likely two tasks.

### Example Decomposition

| Project | Bad split | Good split |
|---------|-----------|------------|
| Add user settings page | "Build settings API and UI" | Task 0: DB migration + shared types, Task 1: Settings API, Task 2: Settings UI |
| Migrate auth provider | "Swap auth library" | Task 0: Adapter interface, Task 1: New provider impl, Task 2: Migration script, Task 3: Update tests |

## 2. Estimation

Score each task's complexity to drive prioritization and wave assignment.

### Complexity Levels

| Level | Label | Description | Guideline |
|-------|-------|-------------|-----------|
| 1 | Trivial | Config change, rename, copy-paste with adaptation | < 30 min |
| 2 | Simple | Single-file logic, straightforward CRUD, unit tests | < 2 hours |
| 3 | Moderate | Multi-file changes, integration points, new patterns | < 4 hours |
| 4 | Complex | Cross-cutting concerns, unfamiliar tech, data migrations | Consider splitting further |

### Prioritization Order

Rank tasks for execution in this order:

1. **Dependency tasks first** -- anything that unblocks others (Task 0 pattern)
2. **Highest-risk tasks** -- fail fast on unknowns
3. **By complexity descending** -- tackle hard work early while context is fresh

### Capacity Rule

- Maximum 3 tasks executing in parallel (one per Worker agent)
- Architect and QA agents are shared resources, not task workers
- If a task scores Complex (4), attempt to split it. If it cannot be split, assign it to a dedicated wave with fewer parallel tasks.

## 3. Risk Assessment

Identify and document risks BEFORE execution begins.

### Risk Categories

| Category | Examples |
|----------|----------|
| Technical | Unfamiliar technology, performance unknowns, complex algorithms, data format changes |
| Integration | Cross-task file conflicts, API contract mismatches, shared state mutations |
| Dependency | External API availability, third-party library stability, upstream team deliverables |
| Data | Migrations that can't be rolled back, schema changes affecting multiple services |

### Risk Scoring

Score each risk on two axes:

| | Low Impact | Medium Impact | High Impact |
|---|-----------|---------------|-------------|
| **Low Likelihood** | Accept | Monitor | Mitigate |
| **Medium Likelihood** | Monitor | Mitigate | Mitigate |
| **High Likelihood** | Mitigate | Mitigate | **Blocker -- reassess** |

### Mitigation Strategies

- **Spike first:** Time-boxed prototype before committing to approach
- **Interface isolation:** Define contracts early so implementations can vary
- **Feature flag:** Ship behind a flag to decouple deploy from release
- **Fallback plan:** Document what to do if the approach fails

### Blocker Escalation

Stop planning and reassess when:
- A critical unknown cannot be resolved without implementation (run a spike instead)
- Two tasks have circular dependencies that cannot be broken
- Required external dependency has no ETA

## 4. Wave Planning

For projects with more than 3 tasks, organize execution into sequential waves.

### Wave Construction Rules

1. Each wave contains at most 3 tasks (one per Worker).
2. A task's dependencies MUST be in an earlier wave (never same wave).
3. Place highest-risk tasks in the earliest feasible wave.
4. Fill remaining wave slots by descending complexity.

### Agent Lifecycle Across Waves

| Agent | Lifecycle |
|-------|-----------|
| Architect | Persists across all waves. Reviews PRs, resolves design questions. |
| QA | Persists across all waves. Validates each task's PR before merge. |
| Workers (up to 3) | Rotate between waves. Each worker gets a fresh worktree per task. |

### Wave Transition Checklist

Before starting wave N+1:

- [ ] All wave N PRs reviewed by Architect
- [ ] All wave N PRs validated by QA
- [ ] All wave N PRs merged to default branch
- [ ] Worker worktrees from wave N removed (`git worktree remove`)
- [ ] `agents-workbench` AGENTS.md updated with wave N completion status
- [ ] New worktrees created for wave N+1 tasks

### Example Wave Plan

| Wave | Tasks | Rationale |
|------|-------|-----------|
| 0 | Task 0: DB migration + shared types | Infrastructure dependency -- everything else needs this |
| 1 | Task 1: Auth API, Task 2: User API, Task 3: Notification service | Independent services, all depend on wave 0 |
| 2 | Task 4: Admin dashboard, Task 5: Email templates | Depend on APIs from wave 1 |

## 5. Output Format

The plan document at `.agents/plans/<project>.md` MUST contain these sections in order.

### Required Sections

#### Project Objective
One to two sentences describing what the project delivers.

#### Task List

| # | Description | Files Affected | Complexity (1-4) | Assigned Worker | Wave # |
|---|-------------|----------------|-------------------|-----------------|--------|
| 0 | Shared DB schema + types | `db/`, `types/` | 2 | worker-1 | 0 |
| 1 | User settings API | `api/settings/` | 3 | worker-1 | 1 |
| 2 | Settings UI components | `ui/settings/` | 3 | worker-2 | 1 |
| 3 | Settings E2E tests | `tests/e2e/` | 2 | worker-3 | 1 |

#### Risk Register

| Risk | Likelihood (L/M/H) | Impact (L/M/H) | Mitigation |
|------|---------------------|-----------------|------------|
| New ORM has undocumented edge cases | M | H | Spike in wave 0; fallback to raw SQL |
| Settings UI conflicts with design system update | L | M | Pin design system version for duration |

#### Wave Plan
Include only if >3 tasks. Show wave groupings with rationale (see section 4 example).

#### Branch Strategy

Choose one and document reasoning:

| Strategy | When to use |
|----------|-------------|
| One branch per task | Default. Each task gets its own feature branch and PR. |
| Shared feature branch | Tasks are tightly coupled and touch overlapping files. |
| Monorepo paths | Multi-package repo where tasks map to distinct packages. |
| Single branch | Solo work or trivial project (avoid for team work). |

#### Dependencies Map

List explicit dependencies, or state "All tasks are independent."

```
Task 1 --> Task 0
Task 2 --> Task 0
Task 3 --> Task 1, Task 2
```

#### Success Criteria

Bullet list of conditions that define "done":
- All PRs merged to default branch
- All tests passing in CI
- No open risk-register items with High impact unmitigated
- AGENTS.md marked complete
