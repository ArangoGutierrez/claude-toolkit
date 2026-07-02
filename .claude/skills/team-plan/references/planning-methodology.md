# Planning Methodology

Reference for `/team-plan` skill. Loaded on demand, not at session start.

## 1. Work Decomposition

Break the project into independent, parallelizable tasks.

1. **Identify natural boundaries** along one axis:
   - Layer: API / UI / data layer / infrastructure
   - Domain: user management / billing / notifications
   - Service: each microservice or module boundary
2. **Extract shared infrastructure** (Task 0 pattern): databases, schemas, shared types, CI config, base libraries. Build before dependent tasks.
3. **Validate independence** for each task:
   - Can it be tested without other tasks completing? If no, merge or reorder.
   - Does it touch files another task also touches? If yes, split at file boundary or sequence.
4. **Enforce one concern per task.** If description uses "and", it's likely two tasks.

## 2. Estimation

| Level | Label | Description |
|-------|-------|-------------|
| 1 | Trivial | Config change, rename, copy-paste with adaptation |
| 2 | Simple | Single-file logic, straightforward CRUD, unit tests |
| 3 | Moderate | Multi-file changes, integration points, new patterns |
| 4 | Complex | Cross-cutting concerns, unfamiliar tech, data migrations — consider splitting |

**Prioritization order:**
1. Dependency tasks first (Task 0 pattern — unblocks others)
2. Highest-risk tasks (fail fast on unknowns)
3. By complexity descending (tackle hard work early)

**Capacity rule:** Max 3 tasks executing in parallel (one per Worker). Architect and QA are shared, not task workers.

## 3. Risk Assessment

| Category | Examples |
|----------|----------|
| Technical | Unfamiliar tech, performance unknowns, complex algorithms |
| Integration | Cross-task file conflicts, API contract mismatches, shared state |
| Dependency | External API availability, upstream team deliverables |
| Data | Irreversible migrations, schema changes affecting multiple services |

**Scoring:**

| | Low Impact | Medium Impact | High Impact |
|---|-----------|---------------|-------------|
| **Low Likelihood** | Accept | Monitor | Mitigate |
| **Medium Likelihood** | Monitor | Mitigate | Mitigate |
| **High Likelihood** | Mitigate | Mitigate | **Blocker — reassess** |

**Mitigation strategies:** Spike first, interface isolation, feature flag, fallback plan.

**Stop and reassess when:** Critical unknown needs implementation to resolve, circular dependencies, external dependency has no ETA.

## 4. Wave Planning

For projects with >3 tasks, organize into sequential waves.

**Rules:**
1. Each wave: at most 3 tasks (one per Worker)
2. Dependencies MUST be in earlier waves (never same wave)
3. Highest-risk tasks in earliest feasible wave
4. Fill remaining slots by descending complexity

**Agent lifecycle:** PE and QA persist across all waves. Workers rotate (fresh worktree per task).

**Wave transition checklist (all gates before next wave):**
- [ ] All wave N PRs reviewed by PE
- [ ] All wave N PRs validated by QA
- [ ] All wave N PRs merged to default branch
- [ ] Worker worktrees removed (`git worktree remove`)
- [ ] agents-workbench AGENTS.md updated with wave N completion
- [ ] New worktrees created for wave N+1 tasks

## 5. Plan Output Format

Plan goes to `.agents/plans/<project-name>.md`. Required sections:

1. **Project Objective** — 1-2 sentences
2. **Task List** — table: #, Description, Files, Complexity(1-4), Worker, Wave
3. **Risk Register** — table: Risk, Likelihood, Impact, Mitigation
4. **Wave Plan** — if >3 tasks, groupings with rationale
5. **Branch Strategy** — one of: per-task (default), shared feature branch, single branch
6. **Dependencies Map** — explicit deps or "all independent"
7. **Success Criteria** — bullet list of "done" conditions

## 6. Branch Sync Validation (Pre-flight)

Before planning, validate agents-workbench is current:

```bash
git fetch origin
DEFAULT_BRANCH=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@')
if [ -z "$DEFAULT_BRANCH" ]; then
  for branch in main master develop; do
    git show-ref --verify --quiet refs/remotes/origin/$branch && DEFAULT_BRANCH=$branch && break
  done
fi
BEHIND=$(git rev-list --count agents-workbench..origin/$DEFAULT_BRANCH 2>/dev/null || echo "0")
AHEAD=$(git rev-list --count origin/$DEFAULT_BRANCH..agents-workbench 2>/dev/null || echo "0")
```

- **Up to date** (behind=0): proceed
- **Behind >0**: warn user, recommend `git merge origin/$DEFAULT_BRANCH`
- **Diverged** (both >0): warn user, default to merge strategy
- **Behind >50**: hard gate — refuse to plan until synced
