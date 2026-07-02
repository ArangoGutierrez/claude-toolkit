# Skills and Commands Reference

This document is the complete reference for all slash commands and skills available across Claude Code and Cursor IDE in this configuration.

Both tools support extensible automation through commands and skills, and both enforce the same engineering workflow: brainstorm before implementing, write failing tests first, isolate work in git worktrees, sign every commit, and submit work for structured review before merging.

**Claude Code** uses "skills" provided by the superpowers plugin. Skills are workflow templates stored as markdown files that guide the AI through structured processes — brainstorming, TDD cycles, debugging investigations, verification, and code review. They are invoked as `/superpowers:skill-name` or triggered automatically by the AI when the context makes them relevant.

**Cursor** uses two distinct extension points:

- **Commands** (`.cursor/commands/`): Slash commands invoked by the user. Each command defines a multi-step workflow, often orchestrating several specialized agents.
- **Skills** (`.cursor/skills-cursor/`): Configuration management skills for creating and updating Cursor artifacts like rules, agents, and commands. These are built-in to this configuration and managed automatically.

Both ecosystems are complementary. You can run Claude Code in the terminal and Cursor in the editor simultaneously on the same repository. The same hooks, the same commit conventions, and the same worktree model apply in both.

For configuration details, see [Claude Code Configuration](claude-code.md) and [Cursor Configuration](cursor.md).

---

## Claude Code Skills (Superpowers Plugin)

These skills are provided by the superpowers plugin and live in the Claude Code plugin registry. Invoke them explicitly with `/superpowers:<skill-name>`, or let the AI invoke them automatically when the workflow calls for it.

| Skill | Purpose | When Used |
|-------|---------|-----------|
| `brainstorming` | Collaborative design exploration: generates 2–3 options with trade-offs, requires explicit user approval before proceeding | MANDATORY before any implementation task. The only exemptions are typos, comments, running tests, reading files, and answering questions |
| `writing-plans` | Creates detailed implementation plans with TDD phases, exact file paths, shell commands, and a numbered task list | After a design option has been approved in brainstorming |
| `executing-plans` | Executes an approved plan task-by-task in a separate session, with checkpoints between tasks for review | For launching plan execution in a fresh context, reducing context-window pollution |
| `subagent-driven-development` | Dispatches a fresh subagent per task with a two-stage review gate (spec review + quality review) | For executing a plan within the current session, where per-task isolation matters |
| `dispatching-parallel-agents` | Detects independent tasks and launches them concurrently, each in its own worktree | When two or more tasks have no shared state or file overlap |
| `test-driven-development` | Enforces the RED → GREEN → REFACTOR cycle with explicit phase signals; blocks implementation without a failing test | During any implementation work. Pairs with the `tdd-guard.sh` hook |
| `systematic-debugging` | Structured bug investigation: reproduce → isolate → hypothesize → verify → fix. Requires evidence before proposing a change | When encountering bugs, test failures, or unexpected behavior |
| `using-git-worktrees` | Creates an isolated git worktree branched from the remote default ref, placing it in `.worktrees/<name>/` | Before starting any feature work. Enforced by the `enforce-worktree.sh` hook |
| `finishing-a-development-branch` | Guides branch completion: runs verification, presents options (merge, open PR, or clean up), and updates `AGENTS.md` | When implementation is complete and all tests pass |
| `verification-before-completion` | Requires running the actual verification commands (build, test, lint) and confirming their output before claiming a task is done | Before committing or opening a PR |
| `requesting-code-review` | Formats and submits work for review with a structured report covering changes, test coverage, and open questions | After completing implementation and passing verification |
| `receiving-code-review` | Handles incoming review feedback with technical rigor — evaluates each comment on merit, not deference | When receiving feedback on a PR or in-session review |
| `writing-skills` | Creates and validates new skill files before adding them to the plugin registry; checks format, description quality, and trigger coverage | When creating a new skill to add to the superpowers plugin |
| `using-superpowers` | Introduction to the skill system: explains what skills exist, how to find them, and how to invoke them | At the start of a new conversation, or when onboarding to this toolchain |

### Invocation Patterns

```
# Explicit invocation
/superpowers:brainstorming

# With context passed inline
/superpowers:writing-plans implement the OAuth2 refresh-token flow

# The AI will invoke automatically in many cases, e.g.:
# "Let me brainstorm before we proceed..." → triggers brainstorming
# "There's a test failure, let me investigate..." → triggers systematic-debugging
```

---

## Local Claude Code Skills (this repo)

These skills ship in `.claude/skills/` and deploy to `~/.claude/skills/`. Each has a human-facing README following the standard in [skill-readme-template.md](skill-readme-template.md) — what it does, when to use it, worked examples, setup, and gotchas. The `SKILL.md` beside each README is the machine-facing procedure the agent follows; the README explains *use*, the SKILL.md owns the *procedure*.

| Skill | What it does |
|-------|--------------|
| [`/eureka`](../.claude/skills/eureka/README.md) | Capture a breakthrough before it evaporates |
| [`/go-review`](../.claude/skills/go-review/README.md) | Systematic Go code review for correctness, concurrency, and performance |
| [`/goal`](../.claude/skills/goal/README.md) | Record the session goal and acceptance criteria |
| [`/handoff`](../.claude/skills/handoff/README.md) | Capture session state for a fresh start |
| [`/k8s-debug`](../.claude/skills/k8s-debug/README.md) | Ordered triage for Kubernetes GPU workload failures |
| [`/kickoff`](../.claude/skills/kickoff/README.md) | Turn a rough idea into a scoped, goal-tracked start |
| [`/pr-review-ingest`](../.claude/skills/pr-review-ingest/README.md) | Turn PR review comments into rule proposals |
| [`/reflection`](../.claude/skills/reflection/README.md) | Turn session mistakes into curated rules |
| [`/skill-eval`](../.claude/skills/skill-eval/README.md) | Measure skill discoverability |
| [`/tdd-protocol`](../.claude/skills/tdd-protocol/README.md) | The Red → Green → Mutate → Refactor cycle |
| [`/team-plan`](../.claude/skills/team-plan/README.md) | Scope a multi-task project before spawning an agent team |
| [`/team-execute`](../.claude/skills/team-execute/README.md) | Spawn the agent team to implement an approved plan |
| [`/team-shutdown`](../.claude/skills/team-shutdown/README.md) | Retire a completed team engagement |
| [`/worktree-guide`](../.claude/skills/worktree-guide/README.md) | Branch model and commands for agents-workbench worktrees |

The three `team-*` skills are also exposed as slash commands in `.claude/commands/`. Note the two copies have drifted: the command files predate the skills' current form (they still use the "Distinguished Systems Engineer" role name and `team/lib/architect-*.md` reference paths, where the skills use "Principal Engineer" and `.claude/agents/*.md`). The SKILL.md trio is the source of truth for the process; reconciling the command copies is a tracked follow-up. The next section documents the commands as they currently exist.

---

## Claude Code Team Commands

These are slash commands in `.claude/commands/` that coordinate multi-agent team workflows. They are invoked as `/team-plan`, `/team-execute`, and `/team-shutdown`. Each command defines a phase of the team lifecycle. (The command files lag the `team-*` skills — see the note in the previous section; the per-skill READMEs describe the current process.)

### Team Structure

All three commands share the same team structure:

- **Team Lead (you):** Coordinates from the `agents-workbench` branch. Does not make technical decisions.
- **Distinguished Systems Engineer:** Senior technical authority. Makes architectural decisions, reviews PRs for architecture/security violations, triages external review bot comments. Reads from `team/lib/architect-*.md` reference material. Location: `agents-workbench` (read-only).
- **QA Agent:** Validates implementations against CI pipelines, verifies quality gates, blocks merges if issues found. Only agent authorized to promote draft PRs to ready-for-review (`gh pr ready`). Location: `agents-workbench` (read-only).
- **Workers (1–3):** Implement tasks following TDD in dedicated worktrees. Escalate design decisions to Distinguished Engineer. Create draft PRs only. Report to QA when ready for testing.

Team size is capped at 5 spawned agents (1 Distinguished Engineer + 1 QA + up to 3 Workers). For more than 3 tasks, work is organized in waves — Distinguished Engineer and QA persist across waves while Workers rotate.

### Commands

| Command | Phase | Purpose |
|---------|-------|---------|
| `/team-plan` | Planning | Validates branch source, brainstorms approach (≥3 options), decomposes work into scored tasks, chooses branching strategy, writes structured plan to `.agents/plans/`, updates `AGENTS.md` |
| `/team-execute` | Execution | Creates worktrees, spawns agents in mandatory order (Distinguished Engineer → QA → Workers), coordinates TDD implementation, manages draft PR → QA validation → Distinguished Engineer review → merge cycle |
| `/team-shutdown` | Shutdown | Verifies all PRs merged, runs TeamDelete to shut down agents, removes worktrees, updates `AGENTS.md` with final status, runs context cleanup |

### Communication Protocol

- **Workers → Distinguished Engineer:** Design decisions (present ≥3 options with trade-offs)
- **Workers → QA:** Ready for testing (feature name, summary, test status, draft PR URL)
- **QA → Distinguished Engineer:** Quality issues requiring design changes
- **Distinguished Engineer → Workers:** Consolidated review feedback (own review + triaged external bot comments)

### Supporting Files

The team commands depend on reference material in `.claude/team/`:

| File | Used By | Purpose |
|------|---------|---------|
| `team/lib/planning-guide.md` | `/team-plan` | Task decomposition methodology and wave construction rules |
| `team/lib/branch-validator.md` | `/team-plan`, `/team-execute` | Validates branch source is up-to-date before creating worktrees |
| `team/lib/qa-validator.md` | QA Agent | Full validation checklist: git signatures, language checks, CI replication, PR metadata |
| `team/lib/decision-template.md` | Distinguished Engineer | ADR template for recording architectural decisions |
| `team/lib/architect-*.md` (7 files) | Distinguished Engineer | Reference material covering patterns, security, distributed systems, infrastructure, observability, decisions, validation |

---

## Cursor Slash Commands

Commands are markdown files in `.cursor/commands/`. Each defines a workflow that the AI follows when you type the corresponding slash command in Cursor. Many commands orchestrate multiple specialized subagents in sequence or in parallel.

### Planning and Research

These commands help you understand a problem before touching any code.

| Command | Description | Agents Orchestrated |
|---------|-------------|-------------------|
| `/architect {problem}` | Full architecture exploration with parallel prototyping. Generates 3–5 options, stress-tests the top recommendation, runs two parallel prototypes, and synthesizes a final recommendation with evidence. Use `--quick` to skip prototyping for early or reversible decisions; use `--proto N` to control how many prototypes run | `arch-explorer` → `devil-advocate` → `prototyper` x2 (parallel) → `synthesizer` |
| `/research #{n}` or `/research {topic}` | Deep research on a GitHub issue or codebase topic. For issues: fetches title, body, labels, comments, and linked PRs; classifies type, severity, scope, and complexity; traces to source files; compares 2–3 solution approaches. For a brainstorm idea (`brainstorm: {idea}`): runs a SWOT analysis with bull/bear/base cases | `researcher` |
| `/issue #{n}` | Analyzes a GitHub issue end-to-end: fetches metadata, classifies it, traces affected files, designs 2–3 approaches, breaks the work into atomic tasks (1 task = 1 commit), and writes or updates `AGENTS.md` with the task list and a feature branch name | `task-analyzer` |

### Implementation

These commands execute work. They all assume an `AGENTS.md` task list exists (created by `/issue` or `/task`).

| Command | Description | Key Features |
|---------|-------------|-------------|
| `/code` | Executes the next `[TODO]` task in `AGENTS.md`. Marks it `[WIP]`, implements only that task, verifies it compiles and meets the acceptance criteria, commits with `-s -S`, and marks it `[DONE]` with the commit hash. Use `/code #N` to target a specific task | Atomic: one task, one commit. Refuses to touch out-of-scope files |
| `/task {desc}` or `/task #{n}` | Full task workflow with budget tracking. Five phases: Understand (10%), Specify (15%), Plan (with `--plan` flag, pauses for "GO"), Implement (with `--tdd` flag for TDD cycle), Verify. Budget: Trivial=1 iteration, Simple=2, Moderate=3, Complex=4 | Structured specification table (inputs, outputs, constraints, acceptance criteria, edge cases, out-of-scope) |
| `/loop {task} --done "{phrase}" --max {N}` | Iterative execution: runs the task repeatedly until the completion phrase appears in output or `AGENTS.md` reaches `Status: DONE`, up to `--max` iterations (default 10). Tracks state in `.cursor/loop-state.json` | Useful with `/loop Work through AGENTS.md --done "Status: DONE" --max 15` to fully drain a task list |
| `/parallel task1 \| task2 \| task3` | Runs independent tasks concurrently via subagents (max 4). Detects dependencies by file overlap and explicit markers ("after X", "needs X"). Dependent tasks fall back to sequential execution. Use `--analyze` to check `AGENTS.md` for parallel opportunities without executing | Dependency detection prevents conflicting parallel writes to the same file |
| `/worktree create \| list \| status \| done` | Full worktree lifecycle management. `create <name>` branches from the remote default ref. `list` shows all worktrees with merged/active status. `status` shows current branch and dirty state. `done <name>` verifies the branch is merged before removing the worktree and deleting the branch locally and remotely. `done --all` cleans up all merged worktrees | Never deletes unmerged branches without explicit confirmation |

### Quality and Review

These commands check your work before it reaches a reviewer.

| Command | Description | Key Features |
|---------|-------------|-------------|
| `/audit` | Security and reliability audit of changed files. Default scope (P0): `git diff` only. Add `--full` for full codebase. Add `--fix` to automatically apply Critical and Major fixes, commit each with `-s -S`. Categories: effective Go patterns, defensive coding, Kubernetes readiness, and security. Each finding is independently verified before reporting | Generates `AUDIT_REPORT.md` with confirmed/dropped counts |
| `/quality` | Multi-perspective review run in parallel. Default: auditor (security, races, leaks), perf-critic (N+1 queries, complexity), api-reviewer (if HTTP handlers present), verifier (tests pass). Use `--fast` for auditor + verifier only. Use `--api` or `--perf` to focus. Critical or High findings block the verdict | Parallel agent execution required; synthesis into a single report required |
| `/test` | Detects the test runner from project files (`go.mod`, `package.json`, `pyproject.toml`, `Cargo.toml`) and runs the suite. Reports `PASS/FAIL`, count, and duration. On failure, lists failing tests with errors and suggested fixes. Use `--quick` to run only tests for files changed in the last commit. Use `--file {path}` for a single file | Updates `AGENTS.md`: passing tests → `[DONE]`, failing → `[BLOCKED:tests failing]` |
| `/self-review` | Reviews your own changes against `main`. Reads `git diff main..HEAD`, evaluates each file across four dimensions: correctness, style, security, and test coverage. Reports per-file verdicts: Good / Consider (with file:line) / Fix (with file:line and required action). Final verdict: Ready / Minor fixes / Needs work | Updates `AGENTS.md` self-review task to `[DONE]` |
| `/review-pr #{n}` | Reviews a pull request with confidence scoring. Only reports findings with confidence >= 80/100. Three passes: security (high-risk patterns), bugs (changed lines only), architecture. Each finding is re-read independently to verify before reporting. Skip conditions: closed, draft, or trivial (docs-only) PRs | Confidence scoring prevents noise: 0–50 → drop, 51–79 → question only, 80–100 → report with fix |

### Git and CI

These commands manage the git workflow from commit to merge.

| Command | Description | Key Features |
|---------|-------------|-------------|
| `/push` | Safe push with pre-flight checks. Verifies all `AGENTS.md` tasks are `[DONE]`, tests pass, and self-review is complete. Warns on any unchecked items. Runs `git push -u origin HEAD` then creates a PR via `gh pr create` with a structured body (summary, changes, checklist, testing notes). Updates `AGENTS.md` with `Status: PR_OPEN` and the PR link | Will not auto-merge. Reports the PR number and URL |
| `/git-polish` | Rewrites the local commit history into atomic, signed, conventional commits. Asks how many commits to rewrite, soft-resets to that point, groups changes by concern (chore/config, refactor/rename, feat or fix by domain), verifies each commit is single-concern, and commits with `-S -s` and a `type(scope): desc` message. Verifies signatures at the end | Requires GPG or SSH signing configured. Use before push, not after |
| `/merge-train` | Merges multiple PRs in correct dependency order. Five phases: Discover (fetch and validate PRs), DAG (build dependency graph, detect cycles), Plan (assess readiness, print merge order), Execute (sequential: assess → fix → rebase → wait-CI → merge → verify → retarget downstream), Report. Supports `--dry-run`, `--auto`, `--label`, `--milestone`. All code fixes happen in isolated worktrees (`.worktrees/mt-{number}/`) | Never force-pushes to the default branch. Pauses on any failure and reports what to do next |
| `/context-reset` | Resets the context tracking state managed by `context-monitor.sh`. Use `--status` to see current health score (0–100%) and recommendation. Use without flags to clear `.cursor/context-state.json` and recalibrate. Health bands: 0–50% Healthy, 50–75% Filling, 75–90% Critical, 90%+ Degraded | Run after `/summarize` to recalibrate the score |

---

## Cursor Skills (Configuration Management)

These are built-in skills in `.cursor/skills-cursor/`. They are invoked by the AI when you ask it to create or modify Cursor configuration artifacts. They are not typically invoked by slash command — instead they are triggered by natural-language requests like "create a new rule for TypeScript" or "add a subagent for database queries".

| Skill | Purpose |
|-------|---------|
| `create-rule` | Generates a new `.mdc` project rule in `.cursor/rules/`. Prompts for scope (always-apply vs file-specific) and glob patterns, then produces a properly formatted frontmatter + markdown rule file. Rules should be under 50 lines with concrete examples |
| `create-skill` | Guides creation of a new Cursor skill: determines purpose, storage location (personal `~/.cursor/skills/` vs project `.cursor/skills/`), trigger scenarios, and output format. Produces a `SKILL.md` with valid frontmatter, concise body (under 500 lines), and a specific third-person description that includes both what the skill does and when to invoke it |
| `create-subagent` | Generates a new agent configuration as a `.md` file in `.cursor/agents/` or `~/.cursor/agents/`. Produces required frontmatter (`name`, `description`) and a markdown system prompt that defines the agent's role, invocation workflow, constraints, and output format |
| `migrate-to-skills` | Converts legacy command files from an older format to the current skills format. Preserves behavior while updating structure to match the current `SKILL.md` schema |
| `update-cursor-settings` | Programmatically modifies Cursor configuration files, such as `~/.cursor/context-config.json`, without requiring manual JSON editing |

---

## How They Relate

Claude Code skills and Cursor commands enforce the same engineering workflow from two different vantage points.

**Claude Code skills focus on process discipline.** They are the guardrails that prevent skipping steps. The `brainstorming` skill ensures you explore options before committing to an approach. The `test-driven-development` skill enforces the RED → GREEN → REFACTOR cycle. The `verification-before-completion` skill blocks you from claiming done before running the commands that prove it. These skills operate at the level of a single engineer working in the terminal.

**Cursor commands focus on agent orchestration.** They coordinate multiple specialized agents to accomplish broader tasks. `/architect` runs four agents in sequence to explore an architecture decision. `/quality` fans out to four agents in parallel to review different risk dimensions. `/merge-train` manages a multi-PR pipeline from dependency analysis through post-merge verification. These commands operate at the level of a team — each agent is a specialist, and the command is the workflow that coordinates them.

**The same hooks enforce the same rules in both tools.** Signed commits (`sign-commits.sh`), TDD discipline (`tdd-guard.sh`), and worktree isolation (`enforce-worktree.sh`) run as Claude Code hooks. The Cursor commands independently enforce these same rules in their own flows: `/git-polish` requires `-S -s` flags, `/worktree` always branches from the remote ref, `/code` commits atomically with `-s -S`.

**You can use both tools on the same codebase.** Use Claude Code in the terminal for planning, TDD cycles, and hook-enforced discipline. Use Cursor in the editor for architecture exploration, quality reviews, and parallel execution of independent tasks. The `AGENTS.md` file serves as the shared task ledger that both tools read and update.

Cursor agents are the "specialists" (`arch-explorer`, `devil-advocate`, `auditor`, `perf-critic`). Cursor commands are the "workflows" that orchestrate them. Claude Code skills are the "discipline layer" that enforces process regardless of which tool is doing the work.
