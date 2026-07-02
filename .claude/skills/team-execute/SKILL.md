---
name: team-execute
description: Use when a team plan exists in .agents/plans/ and the agent team needs to be spawned for implementation
user-invocable: true
argument-hint: <project-name>
---

# Team Execution Phase

## Team Structure

You are the **Team Lead**. You coordinate from `agents-workbench`. You do NOT make technical decisions.

**Roles:** Principal Engineer (see `agents/principal-engineer.md`), QA Engineer (see `agents/qa-engineer.md`), Workers (1-3 in worktrees).

**Limits:** Max 5 agents. >3 tasks → use waves.

## Execution Workflow

**Prerequisites:** Plan in `.agents/plans/<project>.md` (from `/team-plan`). On `agents-workbench`.

### 1. Setup

1. Verify branch: `git branch --show-current` → `agents-workbench`
2. Confirm plan exists in `.agents/plans/`
3. **Validate branch sync** (HARD GATE before worktree creation):
   ```bash
   git fetch origin
   BEHIND=$(git rev-list --count agents-workbench..origin/$(git symbolic-ref refs/remotes/origin/HEAD | sed 's@^refs/remotes/origin/@@') 2>/dev/null || echo "0")
   ```
   - Behind=0: proceed
   - Behind >0: warn user, recommend `git merge origin/<default>`, get confirmation
   - Behind >50: **refuse to execute** — sync first to avoid conflict-heavy PRs
4. Create worktrees: `git worktree add .worktrees/<feature> -b <branch> <source>`

### 2. Spawn (mandatory order)

a. **Principal Engineer FIRST** (on `agents-workbench`, read-only)
   - Reviews every worker PR for architecture, Go conventions, security
   - Posts `gh pr review --comment` (audit trail)
   - Sends consolidated feedback (one message, not per-comment)

b. **QA Engineer SECOND** (on `agents-workbench`, read-only)
   - Validates in worker's worktree (`cd .worktrees/<feature>`)
   - Runs CI-equivalent checks locally
   - Verifies PE review comment exists
   - **Sole writer** to `rules/learned-anti-patterns.md` (uses `audit/.anti-patterns.lock`)
   - Only agent authorized to run `gh pr ready`

c. **Workers LAST** (each in own worktree)
   - MUST use `gh pr create --draft` — never without `--draft`
   - FORBIDDEN from running `gh pr ready`
   - Push code → create draft PR → notify QA

### 3. Worker Implementation

Workers follow TDD (Red → Green → Refactor). Hooks enforce this:
- `tdd-guard.sh`: blocks implementation without failing test
- `enforce-worktree.sh`: blocks writes on agents-workbench
- `test-quality-lint.sh`: flags theater tests

### 4. Review Cycle

1. **QA validates** (in worker's worktree):
   - Verify PR is draft
   - Run CI-equivalent commands
   - Check PR metadata (labels, milestone, linked issue)
   - Wait for `gh pr checks` green

2. **PE reviews** full PR diff:
   - Architecture violations, security, pattern consistency
   - Posts `gh pr review` comment

3. **PE triages all feedback** (own + external bot comments):
   - Address: real bugs, security → Worker must fix
   - Ignore: false positives → document reason
   - Discuss: needs user input → escalate to Lead

4. **Worker addresses feedback**, pushes fixes

5. **QA re-validates**, checks for new comments

6. **Loop** until: PE approves AND QA passes AND no unresolved comments

7. **QA promotes**: `gh pr ready <PR-URL>`

### 5. Error Recovery

If a worker fails mid-execution:
1. Other workers in same wave continue (independent work)
2. QA halts promotion of ALL wave PRs until Lead triages
3. Lead decides: retry worker, reassign task, or abort wave
4. Failed worker's worktree preserved for debugging

### 6. Wave Management

- Wave 1: PE + QA + up to 3 Workers (tasks 1-3)
- Wave 2: Same PE + same QA + new Workers (tasks 4-6)
- DO NOT respawn PE or QA between waves
- Clean up: `git worktree remove .worktrees/<completed-feature>`
- Previous wave must complete before next starts

## Common Mistakes

| Mistake | Fix |
|---------|-----|
| Worker creates non-draft PR | Always `gh pr create --draft` |
| Worker runs `gh pr ready` | FORBIDDEN. Only QA promotes. |
| No PE review before QA gate | QA must verify `gh pr review` comment exists |
| Respawning PE/QA between waves | They persist across all waves |

---

## Arguments

User arguments: $ARGUMENTS
