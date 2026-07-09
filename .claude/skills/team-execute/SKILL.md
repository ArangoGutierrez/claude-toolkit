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

## Spawning guidance

### Foreground only

Spawn Workers, the Principal Engineer, and QA in the **foreground**. Agents
that run in the **background** have Write/Edit/Bash **auto-denied** — a
backgrounded worker silently cannot modify files or run commands and can
only report BLOCKED. A whole dispatch is wasted before you notice.

- Never `SendMessage`-resume a **completed** agent for implementation work:
  the resume runs in the background, where Write/Edit/Bash are denied.
  Re-dispatch a **fresh foreground** Agent instead, or apply a small,
  fully-specified fix inline.
- Treat "the worker reported BLOCKED but the diff is empty" as the signature
  of an accidental background dispatch, not a worker failure.

### Model & effort

Assign the model per role; do not leave Workers on the default (Opus) — a
multi-agent run uses ~15× the tokens of a chat, so Opus on parallel Workers
is pure waste. An Opus lead with Sonnet Workers outperformed a single-agent
Opus by 90.2% ([Anthropic multi-agent research](https://www.anthropic.com/engineering/multi-agent-research-system)); model efficiency beats raising the
token budget.

| Role | Model | Why |
|------|-------|-----|
| Team Lead (you) | Opus | Orchestration + synthesis is the judgment-heavy work |
| Principal Engineer | Opus | Architecture/security review (matches `agents/principal-engineer.md`) |
| QA Engineer | Opus | Test-quality + gate judgment (matches `agents/qa-engineer.md`) |
| Worker (default) | Sonnet | Implementation against a well-specified task |
| Worker (mechanical) | Haiku | Complexity-1 tasks: rename, config, copy-paste-with-adaptation |

Set a Worker's model when dispatching it: pass `model: "sonnet"` (or
`"haiku"`) to the `Agent` tool — the short alias resolves to the current default Sonnet/Haiku, so it won't go stale as versions increment. PE/QA inherit Opus from their agent
definitions; do not override them downward.

**Effort** is a session-level setting that applies to the Lead (you), not to
spawned subagents — the `Agent` tool exposes `model` but not effort. Keep the
Lead at `xhigh` (the global CLAUDE.md default) for coordination judgment. For
subagents the **model tier is the effort proxy**: Haiku ≈ low-effort/low-cost
(mechanical tasks), Sonnet ≈ balanced, Opus ≈ high-judgment (review). Do not try
to set per-worker effort — it is not a knob.

### Worker dispatch contract

Give every Worker dispatch four elements (a vague brief makes Workers
duplicate or misaim work):

1. **Objective** — the single outcome this Worker owns, in one sentence.
2. **Output format** — exactly what to return (e.g. draft PR URL + the status report below).
3. **Tools & sources** — which tools, files, and commands to use; what is out of bounds.
4. **Task boundaries** — the exact files/scope it may touch, and what NOT to change.

Workers report one of four statuses (from `superpowers:subagent-driven-development`):

| Status | Meaning | Lead's response |
|--------|---------|-----------------|
| `DONE` | Complete and self-reviewed | Proceed to PE/QA review |
| `DONE_WITH_CONCERNS` | Complete but doubts flagged | Read the concerns; fix correctness/scope ones before review |
| `NEEDS_CONTEXT` | Missing information | Supply it; re-dispatch a fresh foreground agent |
| `BLOCKED` | Cannot complete | Re-scope, re-dispatch with a stronger model, or escalate — never retry the same model unchanged |

The Lead owns these transitions. On `DONE_WITH_CONCERNS`, resolve any
correctness or scope concern (re-dispatch the Worker, or fix it inline) before
sending the work to PE/QA. On `BLOCKED`, triage before retrying: under-specified
task → re-scope; needs more reasoning → a stronger model; missing access or a
wrong plan → escalate to the user. §5 Error Recovery covers the wave-level fallout.

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

> Foreground only, and never `SendMessage`-resume a completed agent — see **Spawning guidance** above. Background dispatch silently disables Write/Edit/Bash.

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

Workers follow TDD (Red → Green → Refactor). Discipline is skill-driven (the `superpowers:test-driven-development` and `/tdd-protocol` skills plus the constitution's theater-test rules) — no failing test before implementation means the wrong phase, so write a test first. Hooks enforce the surrounding workflow:
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
   - **Panel hook-point (A/B):** when a "Discuss" item is a genuine design fork (architecture, security posture, API shape, irreversible/outward-facing — never trivial reversible choices), the PE/Lead surfaces it as an `AskUserQuestion` with one `(Recommended)` option (reasoning in the descriptions). If you run a recommendation-review panel, handle its verdict: HOLD → Lead proceeds with the recommended option; DISSENT → queue the augmented question for the user; ERROR → re-ask original. Workers never emit panel questions — they escalate to the PE.

4. **Worker addresses feedback**, pushes fixes

5. **QA re-validates**, checks for new comments

6. **Loop** until: PE approves AND QA passes AND no unresolved comments — capped at the task's iteration budget (Trivial 1 / Simple 2 / Moderate 3 / Complex 4). On exhaustion, stop looping and **escalate to the user** with the unresolved issues rather than spinning further.

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
| Spawning an agent in the background, or resuming a completed one | Write/Edit/Bash get auto-denied — dispatch a fresh foreground agent |

---

## Arguments

User arguments: $ARGUMENTS
