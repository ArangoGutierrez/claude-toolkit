# Cursor IDE Configuration Reference

This document is a comprehensive reference for the `.cursor/` directory in this dotfiles repository. It covers every agent, slash command, project rule, automation hook, validation schema, and config skill — what each does, how it works, and when to use it.

## Overview

[Cursor](https://www.cursor.com/) is an AI-powered code editor built on VS Code with built-in AI agents. Where VS Code gives you an editor, Cursor adds an agent loop: the AI can read your codebase, run shell commands, edit files, and iterate until a task is complete. This configuration layers a complete engineering workflow on top of that foundation.

What this config adds:

- **12 specialized agents** — read-only research, review, and challenge agents plus two read-write implementation agents for prototyping and CI repair
- **17 slash commands** — composable workflow steps covering planning, implementation, quality, Git, and CI
- **8 project rules** — always-applied standards for the core workflow, TDD protocol, workbench branch discipline, and Go, Kubernetes, Node, Python, and Rust coding standards
- **4 automation hooks** — shell scripts wired to Cursor's hook events for auto-formatting, commit signing enforcement, dangerous command blocking, and loop iteration limiting
- **3 JSON schemas** — JSON Schema Draft-07 definitions for validating hooks configuration, hook script output, and loop/context state files
- **13 config skills** — built-in Cursor skills for managing editor configuration: creating rules, skills, hooks, and subagents; migrating commands to skills; splitting work into PRs; babysitting long agent runs; and configuring the statusline, CLI, and editor settings

File layout:

```
.cursor/
  agents/          # 12 subagent definitions (.md files)
  commands/        # 17 slash command definitions (.md files)
  rules/           # 8 project rules (.mdc files)
  hooks.json       # Hook registration: event → script mappings
  hooks/           # 4 hook scripts (.sh files)
  skills-cursor/   # 13 built-in config skills (each a directory with SKILL.md)
  schemas/         # 3 JSON Schema files for validation
```

See [Architecture](architecture.md) for a description of the agents-workbench coordination workflow that these agents and commands are designed around.

---

## Agents

Agents are specialized AI assistants defined as `.md` files in `.cursor/agents/`. Each has a YAML frontmatter block (`name`, `description`, `model`, `readonly`) and a markdown body that becomes the agent's system prompt. When Cursor delegates to an agent, it runs in an isolated context with those instructions.

Agents are grouped below by function. The `readonly` flag in the frontmatter determines whether an agent may write files or run mutating shell commands.

### Research and Analysis

These agents investigate problems, explore solution spaces, and break down work. All are read-only.

#### researcher

**File:** `.cursor/agents/researcher.md`
**Read-only:** yes

Deep-dives into a topic, issue, or codebase question and produces structured findings. Designed to be thorough rather than fast: it defines a problem statement with scope and success criteria, surveys existing solutions and prior art, and synthesizes findings into a table (`Finding | Source | Confidence | Implications`). Output includes a recommendation with rationale, risks, and next steps, plus open questions and cited sources.

Invoke this agent when you need to understand a bug's root cause, evaluate an unfamiliar library, or compare community approaches before committing to a design.

Output format: `## Research: {topic}` with sections for Problem, Findings table, Analysis, Recommendation, Open Questions, and Sources.

Constraints: read-only; must cite sources; must include confidence levels; output must be actionable.

#### arch-explorer

**File:** `.cursor/agents/arch-explorer.md`
**Read-only:** yes

Generates three to five genuinely different architectural approaches for a given problem, deliberately avoiding premature convergence on a single answer. For each approach it produces: a core idea, component list, ASCII sketch, three pros and three cons, when it shines and when it struggles, team requirements, and effort estimate. All approaches are then compared in a scoring matrix (`criterion | A1 | A2 | A3`, rated with stars), followed by a decision guide ("choose A1 if..., choose A2 if..."). An optional recommendation is included only when the context makes a clear winner apparent.

Invoke this agent at the start of any non-trivial design decision. It is typically the first step in the `/architect` pipeline.

Output format: `# Arch: {Problem}` with sections for Context, Approaches (3–5), Matrix, Guide, optional Recommendation, and Open Questions.

Constraints: read-only; minimum 3, maximum 5 approaches; genuine diversity required; coverage must be balanced.

#### task-analyzer

**File:** `.cursor/agents/task-analyzer.md`
**Read-only:** yes

Breaks a complex goal into atomic, actionable subtasks. Each subtask is sized under four hours of work, has clear dependencies, and has a measurable done-criterion. The agent outputs a dependency table (`# | Task | Depends | Effort | Done Criteria`), a sequence diagram showing critical path and what can be parallelized, a list of blockers and risks, and a recommended approach.

Invoke this agent before starting a multi-day feature or when an issue feels too large to start. Its output feeds directly into AGENTS.md task lists.

Output format: `## Task Analysis: {goal}` with Context, Tasks table, Sequence Diagram, Risks, and Recommended Approach.

Constraints: read-only; tasks must be atomic; dependencies must be explicit; done criteria must be measurable.

### Review and Validation

These agents examine existing code, APIs, or claims and produce evidence-based findings. All are read-only.

#### auditor

**File:** `.cursor/agents/auditor.md`
**Read-only:** yes

Security and reliability audit for Go and Kubernetes codebases. Examines four categories:

- **A. EffectiveGo** — race conditions, channel misuse, goroutine leaks, swallowed errors (`_ = f()`), panic misuse, unwrapped errors
- **B. Defensive coding** — input validation at public boundaries, nil safety in chains, timeout and context use for I/O, deferred `Close()` calls
- **C. K8s readiness** — graceful shutdown on SIGTERM/SIGINT, structured JSON logging, liveness/readiness probes, absence of hardcoded secrets
- **D. Security** — no tokens in code, injection prevention, output sanitization, safe error messages, authorization checks

Scope is configurable: P0 audits only the current diff (`git diff --name-only`), P1 always covers handlers, database, and auth code, and P2 performs a full codebase audit (requires the `--full` flag). Each finding is independently verified before reporting: the agent generates a question ("does file:line contain pattern?"), re-reads the file independently, and drops unconfirmed findings. The output includes a verification summary (`Generated: N | Confirmed: X | Dropped: Y`).

The agent is explicitly told not to flag style issues as critical, avoid premature optimization concerns, and ignore test patterns.

Output format: `## [Critical] {category}` with `File: path:line`, `Issue: desc`, `Fix: code`, followed by `## [Major]`, `## [Minor]`, and `## Verify Summary`.

Constraints: read-only; all findings require `file:line` evidence; CoVe gate applied; uncertainty must be flagged.

#### perf-critic

**File:** `.cursor/agents/perf-critic.md`
**Read-only:** yes

Performance specialist that requires evidence before reporting an issue. Focuses on four areas: algorithmic complexity (O(n²) loops, N+1 queries, unbounded growth), memory behavior (allocations in hot paths, leaks, large copies), concurrency (lock contention, lock scope, goroutine spawn rate), and I/O (batching, connection pooling, caching). Evidence required means: profile data, benchmark results, flame graphs, or load test metrics. Theoretical concerns or micro-benchmark speculation without supporting data are explicitly not reported.

Invoke this agent when you have actual performance data and want to identify the highest-impact bottlenecks.

Output format: `## Perf Review: {scope}` with Issues Found (with evidence), Non-Issues (with reasoning), Recommendations (prioritized), and a Measurement Plan.

Constraints: read-only; evidence required for every finding; practical not theoretical; measure before and after.

#### api-reviewer

**File:** `.cursor/agents/api-reviewer.md`
**Read-only:** yes

API design specialist covering REST, gRPC, and GraphQL. Reviews five areas:

- **Naming** — resources as nouns, actions as verbs, consistent pluralization, consistent case, no abbreviations except ID/URL/API
- **HTTP semantics** — correct status codes (GET→200/404, POST→201/400, PUT→200/404, PATCH→200/404, DELETE→204/404)
- **Request/response** — minimal required fields, sensible defaults, no internal detail leakage, ISO 8601 dates, consistent envelope
- **Versioning** — strategy exists (URL or header), backward compatibility maintained, deprecation path defined
- **Security** — authentication where needed, rate limiting, input validation, no sensitive data in URLs

Anti-patterns are called out explicitly with corrections: `GET /getUser` → `GET /users/{id}`, `POST /users/delete` → `DELETE /users/{id}`, 200 with error body → proper 4xx/5xx.

Severity: Critical (breaking changes, security issues), Major (inconsistency, poor developer experience), Minor (style, optimization).

Output format: `## API Review: {scope}` with Summary (endpoints N, issues X crit Y major Z minor), categorized findings, and a Consistency summary.

Constraints: read-only; evidence-based; constructive; pragmatic about migration cost.

#### verifier

**File:** `.cursor/agents/verifier.md`
**Read-only:** yes

Skeptical validator for completion claims. Refuses to give benefit of the doubt. For each claim it asks: what would prove this? It then checks whether that evidence exists (tests pass → actual output required; file exists → actual path required; behavior works → reproduction steps required; metrics met → actual data required), identifies gaps, and issues a verdict:

- `✓ Verified` — evidence exists and is sufficient
- `⚠ Partial` — some evidence exists but gaps remain
- `✗ Unverified` — required evidence is missing

Invoke this agent when an agent or human asserts "it's done" or "tests pass" and you want independent confirmation before merging.

Output format: `## Verification: {claim}` with Evidence Required, Evidence Found, Gaps, Verdict, and Next Steps if gaps exist.

Constraints: read-only; specific evidence required; no benefit of the doubt; clear verdict required.

#### review-triager

**File:** `.cursor/agents/review-triager.md`
**Read-only:** yes

Analyzes PR review comments, categorizes them, and drafts responses — but never posts anything automatically. This is a hard constraint, not a default: the agent's output is always drafts for human review.

Process: fetch all reviews and comments (`gh pr view --comments` or `gh api`), then categorize each as blocking (change-requested, security concern, correctness issue), non-blocking (style suggestion, nit, question, praise), actionable (has a concrete code change), or discussion (requires human judgment). Blocking and actionable items are prioritized first. For each comment, draft an appropriate response: fix description for actionable items, talking points for discussions, acknowledgment for nits. Surfaces unresolved threads, conflicting reviews, and stale reviews.

Output format: `## Review-Triage: {pr}` with Summary counts, Blocking table, Non-Blocking table, Recommended Actions, and Needs Human section.

Constraints: read-only; never post; categorize all comments; surface conflicts.

### Challenge and Synthesis

These agents attack proposals from adversarial or integrative angles. Both are read-only.

#### devil-advocate

**File:** `.cursor/agents/devil-advocate.md`
**Read-only:** yes

Contrarian reviewer that steel-mans a proposal first, then challenges it systematically. The process: state the proposal in own words, identify all claims being made, then challenge by category:

- Blockers (red) — issues that would prevent the approach from working at all
- Major risks (orange) — issues that could cause significant problems
- Minor concerns (yellow) — issues worth addressing but not fatal
- Questions (blue) — things that need clarification

For each issue: state the assumption being made, describe the problem scenario, list questions to verify, and propose a mitigation if the issue were addressed. Ends with genuine positives (the steel-man), priority-ordered mitigations, and a "kill test" — the single strongest argument against the proposal.

Invoke this agent on any significant architecture decision, technical proposal, or approach before committing to implementation.

Output format: `# Devil's Advocate: {Topic}` with My Understanding, Blockers, Major, Minor, Questions, What I Like, Recommendations, and Kill Test.

Constraints: read-only; constructive not destructive; specific not vague; mitigations required.

#### synthesizer

**File:** `.cursor/agents/synthesizer.md`
**Read-only:** yes

Combines multiple agent outputs into a single unified recommendation. Used as the final step in multi-agent pipelines (e.g., `/architect`, `/quality`). Process: catalog all inputs with source and key finding; identify consensus points with confidence; surface conflicts with analysis of why sources disagree and which is correct; weight evidence (prototype results outweigh theory, measured data outweighs opinion); then synthesize into a final recommendation with rationale, risks and mitigations, what is being traded away, and a confidence level (High/Medium/Low with reasoning).

Invoke this agent after running arch-explorer, devil-advocate, and prototyper and you need one actionable decision.

Output format: `# Synthesis: {Topic}` with Inputs, Consensus, Contentious, Recommendation (decision + evidence + risks + confidence), Dissenting views, and Next Steps.

Constraints: read-only; must attribute all sources; no new analysis introduced; clear recommendation required; uncertainty acknowledged.

### Implementation

These agents write code and make changes. Both are read-write and require working in isolated git worktrees.

#### prototyper

**File:** `.cursor/agents/prototyper.md`
**Read-only:** no (read-write)

Rapid prototype implementation for validating architectural assumptions. All prototype code is created in an isolated worktree — never written directly to the agents-workbench branch. The worktree is created at `.worktrees/prototype-{name}/` from the default branch, and prototype code lives under `.prototypes/{name}/` inside that worktree.

Process: define what to validate (one to two sentences) with success criteria and a time-box; create the worktree; implement the minimal code needed with a README containing run instructions; validate whether it works and what was learned; document findings (validated assumptions, invalidated assumptions, surprises); clean up by pushing the branch if keeping results or removing the worktree when done.

The prototype is disposable by design. Working code matters more than clean code. Gold-plating is explicitly forbidden.

Output format: `.prototypes/{name}/` directory with `README.md`, working code, and a `## Findings` section covering validated, invalidated, and surprising results.

Constraints: minimal; disposable; document learnings; no gold-plating; worktree required.

#### ci-doctor

**File:** `.cursor/agents/ci-doctor.md`
**Read-only:** no (read-write)

Diagnoses and fixes CI failures. Scope is intentionally limited to what can be fixed automatically and safely: lint errors, type errors, and simple test assertion mismatches. Anything else (flaky tests, infrastructure failures, timeouts, dependency conflicts, ambiguous failures) is skipped with a notification.

All code fixes happen in an isolated worktree created from the PR's head branch at `.worktrees/ci-fix-{number}/`. The agent fetches CI logs via `gh run view`, classifies the failure, creates the worktree, applies a minimal fix, commits with `-s -S` and conventional format (`fix(ci): {what}`), pushes, and monitors via `gh run watch`. Maximum two fix attempts per failure; after that, the issue is escalated to human attention.

Guardrails: no force-push; never modify test expectations to make them pass; never touch files outside the failure scope; never modify source code on agents-workbench.

Output format: `## CI-Doctor: {run_id}` with a table (`Failure | Category | In-Scope | Action | Result`), Diagnosis, Fix Applied, and Escalations.

Constraints: no gold-plating; minimal diff; explain all fixes; respect scope boundary; commit conventions; worktree required.

---

## Commands

Commands are slash commands defined as `.md` files in `.cursor/commands/`. They are invoked by typing `/commandname` in the Cursor chat. Each command file is plain markdown (no frontmatter) that becomes the agent's instructions for that workflow step.

Commands are grouped below by workflow phase.

### Planning and Research

#### /architect

**File:** `.cursor/commands/architect.md`

Full architecture exploration using a four-phase agent pipeline:

```
arch-explorer → devil-advocate → [prototyper × 2] → synthesizer
     |               |                  |               |
  3-5 options    challenge top    parallel impl    recommend
```

Phase 1 (Explore): launches `arch-explorer` to produce three to five approaches plus a comparison matrix. Phase 2 (Challenge): launches `devil-advocate` on the top recommendation to surface risks and blockers. Phase 3 (Prototype): launches two `prototyper` instances simultaneously, each validating a different approach in `.prototypes/{approach}/`. Phase 4 (Synthesize): launches `synthesizer` to combine all findings into a final recommendation with evidence.

Usage:

```
/architect {problem}
/architect {problem} --quick     # skip prototypes: explorer → advocate → synthesizer
/architect {problem} --proto N   # prototype top N approaches (default: 2)
```

The `--quick` flag is appropriate for early discussions or reversible decisions where prototype overhead is not justified.

Output: `# Architecture Decision: {Problem}` with Summary, Approaches table, Recommendation (with evidence, trade-offs, and risks), and Next Steps.

#### /research

**File:** `.cursor/commands/research.md`
**Read-only**

Deep research on a topic or GitHub issue. Accepts a GitHub issue number (`#N`), a freeform topic, or a `brainstorm: {idea}` prefix.

For GitHub issues: fetches title, body, labels, state, comments, and linked PRs; classifies the issue by type (bug/feat/refactor/docs/perf/sec), severity (critical/high/medium/low), scope (local/cross-cutting/architectural), and complexity (trivial/moderate/complex/unknown); investigates related files and tests; verifies understanding against the code; then compares two to three solutions with effort/risk/maintainability ratings.

For brainstorm mode: extracts concept, problem, audience, and assumptions; searches for competitors and feasibility data; analyzes through four lenses (User, Tech, Business, Risk); runs a SWOT analysis; evaluates assumptions; explores angles including MVP and full vision; outputs prioritized actions (P0/P1/P2).

Output format: `# Research: #{n} - {title}` with Summary (type and severity), Problem, Root Cause (with `file:line`), Solutions (2–3 with recommendation), and Open Questions.

#### /issue

**File:** `.cursor/commands/issue.md`

Analyzes a GitHub issue and produces a task plan. Fetches issue details from GitHub (`gh`), classifies it by type and complexity, researches affected files and existing patterns, designs two or three approaches with effort/risk/trade-off table, breaks the chosen approach into atomic tasks (one task = one change = one test = one commit), and verifies the analysis against current code.

Output goes to two places: a console summary (`## #{n}: {title}` with type, complexity, branch, and tasks), and an AGENTS.md file (created or updated, preserving existing content) with the task table in `|#|Task|Status|Commit|` format.

Branch naming convention: `{type}/issue-{n}-{slug}`.

#### /code

**File:** `.cursor/commands/code.md`

Executes the next TODO task from AGENTS.md. No arguments picks the next `[TODO]` task; `#{N}` targets a specific task number.

Flow: read AGENTS.md and find the next TODO; display the task and update its status to `[WIP]`; implement only that task with minimal changes; verify compilation, task acceptance criteria, and absence of unrelated changes; commit with `-s -S` and conventional format including issue ref and task progress (`Task: N/total`); update AGENTS.md status to `[DONE]` with the commit hash; report the commit, changed files, and next task.

Commit format: `{type}({scope}): {desc}\n\nRefs: #{issue}\nTask: {N}/{total}`

One task equals one commit. No batch commits.

#### /task

**File:** `.cursor/commands/task.md`

Full task workflow from understanding through implementation to verification. Accepts a description, a GitHub issue number, `--plan` (stop after planning for review), or `--tdd` (enforce Red/Green/Refactor).

Five phases: Understand (10% of effort — fetch context, ask at most two clarifying questions), Specify (15% — define inputs/outputs/constraints/acceptance/edge cases/out-of-scope), Plan (design two or more approaches with effort/risk/trade-off, stop for "GO" approval if `--plan`), Implement (TDD cycle if `--tdd`; update AGENTS.md throughout), Verify (compile, tests, acceptance criteria, edge cases).

Iteration budget: Trivial→1, Simple→2, Moderate→3, Complex→4; escalate to user beyond budget.

Commits use `-s -S` with conventional format. PR created with `gh pr create`; no auto-merge.

#### /loop

**File:** `.cursor/commands/loop.md`

Iterative execution that repeats a task until a completion phrase appears in output or a maximum iteration count is reached.

```
/loop {task} --done "{phrase}" --max {N}
```

Defaults: `--done "DONE"`, `--max 10`. State is tracked in `.cursor/loop-state.json` (task, completion phrase, max, current iteration count, status). The `task-loop.sh` hook enforces the limit by stopping the agent when `iteration >= limit`.

Common use: `/loop Work through AGENTS.md --done "Status: DONE" --max 15` to automatically work through all TODO tasks.

To cancel: say "cancel loop" — status is set to `cancelled` and AGENTS.md is updated.

#### /parallel

**File:** `.cursor/commands/parallel.md`

Runs independent tasks concurrently via subagents (maximum four concurrent agents).

```
/parallel task1 | task2 | task3
/parallel --analyze        # check AGENTS.md for parallelizable TODOs
/parallel --from-agents    # auto-run all parallelizable TODOs from AGENTS.md
```

Dependency detection: tasks that share a file, have explicit "after X"/"needs X" annotations, or where one tests the other are run sequentially. Tasks in different directories or covering different concerns run in parallel. Results are merged and AGENTS.md is updated.

Output: `## /parallel Results` with execution count (parallel vs sequential), changes per task, and remaining work.

#### /worktree

**File:** `.cursor/commands/worktree.md`

Worktree lifecycle management for isolated feature development. All operations use the repo's default branch as the base unless overridden.

```
/worktree create <name>           # create .worktrees/<name>, branch <name> from default
/worktree create <name> <base>    # create from specific base branch
/worktree list                    # show all worktrees with merged/active status
/worktree status                  # current worktree info, branch, dirty state
/worktree done <name>             # remove worktree + delete local + remote branch
/worktree done --all              # clean up all merged worktrees
```

Safety rails: unmerged branches require explicit confirmation before deletion; worktrees with uncommitted changes produce a warning and abort; all commits in worktrees use `-s -S`; worktree names match branch names.

### Quality and Review

#### /audit

**File:** `.cursor/commands/audit.md`

Security and reliability audit using the same four-category framework as the `auditor` agent (EffectiveGo, Defensive, K8sReady, Security). Scope: P0 = current diff only (default), P1 = handlers/db/auth (always included), P2 = full codebase (requires `--full`).

```
/audit              # P0 diff + P1 critical paths
/audit --full       # P2 full codebase
/audit --fix        # generate and apply fixes for Critical and Major findings
```

Each finding is independently verified (generate question → re-read file independently → confirm or drop) before appearing in the report. With `--fix`: each Critical/Major finding is verified, fixed, tested, and re-audited; fix commits use `fix({scope}): {desc} - Audit finding`.

Output written to `AUDIT_REPORT.md` with Critical, Major, Minor sections and a summary of generated vs confirmed vs dropped findings.

#### /quality

**File:** `.cursor/commands/quality.md`

Multi-perspective review using a parallel agent pipeline: `auditor` (security, races, leaks), `perf-critic` (N+1 queries, complexity), `api-reviewer` (if handler files are in scope), and `verifier` (test suite status). All applicable agents run simultaneously; results are synthesized into a unified report.

```
/quality              # review git diff
/quality {path}       # review file or directory
/quality #{PR}        # review GitHub PR
/quality --fast       # auditor + verifier only
/quality --api        # api-reviewer focus
/quality --perf       # perf-critic focus
```

Output: `## Quality Report: {scope}` with Risk indicator (red/yellow/green), a category table (Security/Perf/API/Tests with issue counts and severities), Blocking items (must fix), and a Verdict (Ready / Fix Required / Blocked). Critical or High severity findings always block.

#### /test

**File:** `.cursor/commands/test.md`

Detects the project's test framework and runs tests. Framework detection: `go.mod` → `go test ./...`, `package.json` → `npm test`, `pyproject.toml` or `requirements.txt` → `pytest`, `Cargo.toml` → `cargo test`.

```
/test              # full test suite
/test --quick      # tests covering files changed since HEAD~1
/test --file {p}   # tests for a specific file
```

Reports: Status (PASS/FAIL), test count (pass/total), and duration. On failure: lists failing tests with errors and suggested fixes, then chains to `/code` and back to `/test`. Updates AGENTS.md: pass → `[DONE]`, fail → `[BLOCKED: tests failing]`.

#### /self-review

**File:** `.cursor/commands/self-review.md`

Reviews the agent's own changes against main before pushing. Diffs `main..HEAD`, then evaluates each changed file across four aspects: Correct (logic, edge cases, bugs), Style (patterns, naming, debug code), Sec (secrets, input validation, error safety), and Tests (new code covered, tests meaningful).

Output uses three symbols: `✅ Good`, `⚠ Consider (file:line + suggestion)`, `❌ Fix (file:line + required)`. Summary aspect table (`Correct | Style | Sec | Tests → ✓/⚠/✗`) and Verdict (Ready / Minor fixes / Needs work). Updates AGENTS.md self-review task to `[DONE]`.

#### /review-pr

**File:** `.cursor/commands/review-pr.md`

Reviews a GitHub PR for security, bugs, and architecture. Skips closed, draft, or trivial (docs-only) PRs with "LGTM".

Three review passes: Security (credentials, injection, input validation, authorization bypass, sensitive data in errors), Bugs (logic errors, nil dereference, unhandled errors, leaks — changed code only), Architecture (patterns, separation of concerns, test coverage).

Confidence scoring: each finding starts at zero and gains +20 for each of: exact `file:line` reference, belongs to this PR, justified reasoning, independently verified, fix provided. Only findings with confidence ≥ 80 are reported. Findings between 51 and 79 become questions; findings below 50 are dropped.

Output: `## PR Review: #{n}` with Summary (files, risk areas), Blocking findings (≥80 confidence with `file:line` and fix), Health notes, Questions, and Verdict (Approved / Changes Requested / Blocked).

### Git and CI

#### /push

**File:** `.cursor/commands/push.md`

Safe push with pre-flight checks. Verifies: all tasks in AGENTS.md are `[DONE]`, tests pass (runs `/test`), and self-review is done (runs `/self-review`). Warns if any check is not satisfied.

On success: pushes with `git push -u origin HEAD`, creates a PR with `gh pr create` using a structured body (Closes #N, Summary, Changes from commits, Checklist, Testing). Updates AGENTS.md with `Status: PR_OPEN`, PR number, and link.

On failure: lists what is missing and suggests remediation steps.

#### /git-polish

**File:** `.cursor/commands/git-polish.md`

Rewrites local commits to be atomic, signed, and in conventional format. Sets up GPG signing via SSH key if not already configured. Soft-resets to a target commit, groups changes by type (chore for config, refactor for renames, feat/fix for logic by domain), verifies each group (single concern, compiles, message accurate), then commits each group with `git commit -S -s -m "type(scope): desc"`. Verifies signatures with `git log --show-signature`.

#### /merge-train

**File:** `.cursor/commands/merge-train.md`

Orchestrates merging multiple PRs in dependency order. Handles the full lifecycle: dependency graph construction, cycle detection, CI repair, rebase, and sequential merging.

```
/merge-train                           # all open approved PRs targeting default branch
/merge-train #12 #34 #56              # specific PRs
/merge-train --label ready-to-merge   # PRs with this label
/merge-train --milestone v2.1         # PRs in this milestone
/merge-train --dry-run                # build DAG and plan only, no execution
/merge-train --auto                   # skip confirmation gates
```

Five phases:

1. **Discover** — fetch PR candidates, validate (exclude drafts/closed/merged), print summary table
2. **Dependency DAG** — detect stacked branches (B targets A's head → B depends on A), explicit "depends on #N" references, and file overlap heuristics; detect cycles; print the graph with topological sort order
3. **Plan** — for each PR in sort order, assess CI status, unresolved threads, draft state, rebase need; print the full plan table; gate on `--dry-run` or user confirmation
4. **Execute** — process each PR sequentially: assess (fresh state), fix (review comments + CI failures in worktree), rebase (inside worktree with `--force-with-lease`, pre-rebase backup tag), wait-ci (15-minute timeout), merge (squash via `gh pr merge --squash --delete-branch`), verify and clean up worktree, retarget stacked downstream PRs
5. **Report** — print final table with status, actions taken, and merge SHA for each PR; note backup refs

All code modifications happen in per-PR worktrees at `.worktrees/mt-{number}/`. Draft replies to review comments are always presented to the user for approval before posting. Max one retry cycle per CI failure category before escalating to human. Pauses on conflict, unapproved PR, or unresolvable CI failure.

Safety rails: no `--no-verify`; only `--force-with-lease` never bare `--force`; no auto-post of review replies; max one retry cycle; pre-rebase backup tags; no force-push to default branch; sequential execution only; cycle detection blocks execution; worktree cleanup after each merge.

#### /context-reset

**File:** `.cursor/commands/context-reset.md`

Resets or inspects context health tracking state. The `context-monitor.sh` hook estimates token usage based on weighted factors: each iteration adds 8%, each file touched adds 2%, each completed task adds 15%, and each `/summarize` run recovers 25%.

```
/context-reset           # reset state files
/context-reset --status  # show current health
```

Health states:

| Score | State | Action |
|-------|-------|--------|
| 0–50% | Healthy | Continue |
| 50–75% | Filling | Consider `/summarize` |
| 75–90% | Critical | Run `/summarize` |
| 90%+ | Degraded | Start new session |

State is persisted in `.cursor/context-state.json`. Reset removes that file and the lock file. Use after `/summarize` to recalibrate, when stuck detection produces false positives, or at the start of a fresh session.

---

## Rules

Rules are `.mdc` files in `.cursor/rules/`. Each has YAML frontmatter controlling when Cursor applies it (`alwaysApply: true` for every session, `globs` for file-type-specific application). The body is injected into the agent's context when the rule is active.

#### core.mdc

**File:** `.cursor/rules/core.mdc`
**Applied:** always (`alwaysApply: true`)

Core workflow and invariants that apply to every session.

Workflow phases: brainstorm → plan → code → verify → PR → review → address → CI → merge.

Commit standards: always sign with `git commit -s -S` (DCO + GPG), never use `--no-verify`, never force-push to main/master.

TDD invariant: RED before GREEN (no implementation without a failing test), one phase per turn (never mix test and implementation edits), tests are contracts (never weaken tests to make implementation pass).

Verification standard: evidence before claim — run tests, lints, and scans before asserting success; `file:line` references must exist before being cited.

Date rule: source of truth is the system context date, not training data. New files always use the current year. Year ranges only when history applies.

Context economy: reference file paths rather than pasting code inline; use tables over prose; show only deltas.

#### tdd.mdc

**File:** `.cursor/rules/tdd.mdc`
**Applied:** conditionally (not always-apply; loaded when working on implementation tasks)

Detailed TDD protocol with phase signals and checkpoint gating.

Phase signals (prefix every implementation response): `[PLAN]` when designing, `[RED]` when writing a failing test, `[GREEN]` when writing minimum passing code, `[REFACTOR]` when cleaning up after green, `[CHECKPOINT]` when requesting human commit before a large refactor.

Hard rules: RED before GREEN, one phase per turn, tests are contracts (never modify to fit implementation), each PR covers at most one concern.

Checkpoint protocol: before any REFACTOR that touches more than three files or more than 50 lines of code, signal `[CHECKPOINT]`, summarize the current GREEN state, ask for human review and commit, wait for confirmation, then begin REFACTOR as a new atomic change.

Context verification: at implementation start, confirm you have API docs for external services, team conventions for the language, and existing test patterns in the repo. If any are missing, ask before writing code.

Security scans required before claiming completion: for Go — `govulncheck ./...`, `gosec ./...`, `trivy fs .`; for any project — `trivy fs .`.

#### workbench.mdc

**File:** `.cursor/rules/workbench.mdc`
**Applied:** always (`alwaysApply: true`)

Branch detection and worktree discipline for the agents-workbench workflow. Before editing any source code, check `git branch --show-current`. If the current branch is `agents-workbench`, source code is READ-ONLY — suggest a worktree instead. If inside a `.worktrees/` path, proceed normally. On any other branch, follow normal development conventions.

On the `agents-workbench` branch: coordination files are editable (AGENTS.md, `.agents/*`, `docs/plans/*`, CLAUDE.md, `.cursor/rules/*`) and any file is readable for context, but source code must not be modified directly.

Feature implementation always happens in worktrees created with `git worktree add .worktrees/<name> -b <branch> <default-branch>`. All commits in worktrees use `-s -S`. Worktrees are cleaned up after the PR merges.

In agent team setups: the lead agent stays on agents-workbench and coordinates via AGENTS.md; worker agents each operate in their own worktree for parallel implementation.

#### go.mdc

**File:** `.cursor/rules/go.mdc`
**Applied:** when editing `**/*.go` files

Go coding standards for Kubernetes-targeted projects.

Lint chain (run in order): `gofmt` → `go vet` → `golangci-lint` → `go test`.

Documentation: lines at most 80 characters; package-level comments required for all public packages.

Patterns: accept interfaces, return concrete structs; wrap errors with `fmt.Errorf("%w", err)`; context (`ctx`) is always the first parameter; always `defer Close()` for resources.

Naming: exported identifiers use PascalCase; unexported use camelCase; acronyms are consistent (URL or Url, not mixed).

Error handling: never discard with `_ = f()`; always wrap with context; use sentinel errors sparingly.

Concurrency: use mutex or channels for shared state; goroutines must have an exit strategy; always use context cancellation.

Tests: table-driven; safe to call `t.Parallel()`; test files named `*_test.go`.

Kubernetes patterns: graceful shutdown on SIGTERM/SIGINT, structured JSON logging, liveness/readiness probes, no hardcoded secrets.

Security scans (verify phase): `govulncheck ./...`, `gosec ./...`, `trivy fs .` — all three before claiming implementation complete.

#### k8s.mdc

**File:** `.cursor/rules/k8s.mdc`
**Applied:** when editing `**/*.yaml`, `**/*.yml`, `**/k8s/**`, `**/manifests/**`, `**/deploy/**`

Kubernetes manifest and operator standards.

API: use feature gates for alpha/beta APIs; document version-dependent assumptions.

Manifests: resource limits (`requests` and `limits`) required; liveness and readiness probes required; prefer environment variables or ConfigMaps over mounted volumes for configuration.

Security: no plain secrets in manifests; RBAC permissions minimal (least privilege); network policies defined; pod security standards enforced.

Operator patterns: reconcile loop must be idempotent; use the status subresource for conditions; finalizers required for cleanup; leader election required for multi-replica operators.

Helm: values schema (`values.schema.json`) required; README required; upgrade path must be tested.

---

## Hooks

Hooks are shell scripts in `.cursor/hooks/` wired to Cursor agent events via `.cursor/hooks.json`. The registration file maps three event types to scripts:

```json
{
  "version": 1,
  "hooks": {
    "afterFileEdit": [
      { "command": "~/.cursor/hooks/format.sh" }
    ],
    "beforeShellExecution": [
      { "command": "~/.cursor/hooks/sign-commits.sh" },
      { "command": "~/.cursor/hooks/security-gate.sh" }
    ],
    "stop": [
      { "command": "~/.cursor/hooks/task-loop.sh" },
      { "command": "~/.cursor/hooks/context-monitor.sh" }
    ]
  }
}
```

Hook scripts receive JSON on stdin describing the event and must write JSON to stdout describing what to do. The `hook-output.schema.json` schema defines valid responses: allow, ask (prompt user), block, modify (rewrite the command), followup (message to the agent), or error.

#### format.sh

**Event:** `afterFileEdit` (runs after every file the agent edits)

Auto-formats files based on extension. For `.go` files: runs `gofmt -w {file}` if `gofmt` is available. For `.json` files: runs `jq '.' {file}` and writes the result back if `jq` is available. Gracefully skips with `{"continue":true}` if the required tool is not installed. Errors in formatting are suppressed (`|| true`) so a format failure never blocks the agent.

Timeout: 5 seconds (configured in hooks.json).

#### sign-commits.sh

**Event:** `beforeShellExecution` (intercepts every shell command before execution)

Enforces `-s` (DCO sign-off) and `-S` (GPG signing) on all `git commit` commands. Passes non-commit commands through immediately. For commit commands, checks whether both flags are already present. If both are present, allows unchanged. If either is missing, checks whether a signing key is configured (`git config user.signingkey` or `git config gpg.format`); if a signing key exists, adds the missing flags and returns a modified command. If no signing key is configured, adds only `-s`. The modified command is returned in the hook response so Cursor executes the corrected version transparently.

#### security-gate.sh

**Event:** `beforeShellExecution`

Blocks genuinely dangerous commands before they execute. Blocked patterns: `rm -rf /`, `rm -rf ~`, the fork bomb `:(){ :|:& };:`, filesystem overwrite `> /dev/sda`, `mkfs`, and `dd if=/dev`. Any command matching a blocked pattern receives `{"continue":false,"error":"Blocked: potentially destructive command"}`.

Force pushes to main or master (`git push` with `--force` or `-f` targeting `main`/`master`) produce a warning and ask for user confirmation rather than blocking outright.

Timeout: 10 seconds (configured in hooks.json). Falls through with allow if `jq` is unavailable.

#### task-loop.sh

**Event:** `stop` (called when the agent is about to stop at the end of each iteration in loop mode)

Prevents infinite agent loops by enforcing an iteration limit. Reads `loop_iteration` and `loop_limit` from the event JSON. If `iteration >= limit`, returns `{"decision":"stop","reason":"Loop limit reached"}`. Otherwise returns `{"decision":"continue"}`. The default limit is 5 (set in hooks.json under the `loop_limit` key for this hook entry).

Used by `/loop` to enforce the `--max` parameter.

#### context-monitor.sh

**Event:** `stop`

Placeholder for context health monitoring. Currently always returns `{"decision":"continue"}` — the logic for token estimation and health state transitions lives in `/context-reset` and the state file tracked by the agent, not in this hook. The hook file exists as the integration point for future extension.

---

## Schemas

Three JSON Schema Draft-07 files in `.cursor/schemas/` validate the shape of configuration and state files. They are used for CI validation of the Cursor configuration.

#### hooks.schema.json

**File:** `.cursor/schemas/hooks.schema.json`

Validates `.cursor/hooks.json`. Requires `version` (integer ≥ 1) and `hooks` (object with three optional arrays: `afterFileEdit`, `beforeShellExecution`, `stop`). Each entry in `afterFileEdit` and `beforeShellExecution` must have a `command` field matching the pattern `~/.cursor/hooks/[a-z-]+\.sh`. Stop hook entries additionally allow a `loop_limit` integer (1–100). No additional properties are permitted in any object.

#### hook-output.schema.json

**File:** `.cursor/schemas/hook-output.schema.json`

Validates the JSON that hook scripts write to stdout. Defines seven valid response shapes using `oneOf`:

- **allow** — `{"continue":true,"permission":"allow"}` — proceed unchanged
- **ask** — `{"continue":true,"permission":"ask","user_message":"...","agent_message":"..."}` — prompt user
- **block** — `{"continue":false,"error":"..."}` — prevent execution
- **modify** — `{"continue":true,"permission":"allow","command":"..."}` — rewrite the command
- **followup** — `{"followup_message":"..."}` — send a message back to the agent (stop hooks)
- **error** — `{"error":"..."}` — hook execution failure
- **empty** — `{}` — no action needed (stop hooks)

#### state-file.schema.json

**File:** `.cursor/schemas/state-file.schema.json`

Validates `.cursor/loop-state.json` and `.cursor/context-state.json`. Defines two object shapes:

`loopState` — tracks `/loop` execution: `status` (running/stopped/complete/budget_exceeded), `task`, `max_iterations` (1–100, default 10), `current_iteration`, `completion_promise` (default "DONE"), `started_at`, and `completed_at`.

`contextState` — tracks context health: `conversation_id`, `iterations`, `files_touched`, `tasks_completed`, `summarize_count`, `health` (healthy/filling/critical/degraded), `last_recommendation`, and stuck-detection fields (`stuck_iterations`, `last_done_count`, `last_todo_count`).

---

## Skills (skills-cursor)

The `.cursor/skills-cursor/` directory contains 13 built-in Cursor config skills. These are Cursor's own internal skills for managing the editor configuration and are distinct from project skills (`.cursor/skills/`) or personal skills (`~/.cursor/skills/`). Each is a directory containing a `SKILL.md` with frontmatter and instructions.

#### create-rule

**File:** `.cursor/skills-cursor/create-rule/SKILL.md`

Guides creation of new `.mdc` rule files in `.cursor/rules/`. Gathers purpose, scope, and file patterns (asking whether the rule should always apply or only for specific file types). Produces a rule with correct frontmatter (`description`, `globs`, `alwaysApply`) and body under 500 lines. Best practices enforced: one concern per rule, actionable content, concrete examples, no verbose prose.

Triggered when: asked to create a rule, add coding standards, set up project conventions, or configure file-specific patterns.

#### create-skill

**File:** `.cursor/skills-cursor/create-skill/SKILL.md`

Guides creation of new agent skills. Distinguishes personal skills (`~/.cursor/skills/`) from project skills (`.cursor/skills/`). Produces a directory with `SKILL.md` (required) and optional `reference.md`, `examples.md`, and `scripts/`. Enforces concise descriptions (written in third person, including both WHAT and WHEN), body under 500 lines, progressive disclosure, and consistent terminology. Covers four authoring patterns: template, examples, workflow, and conditional workflow. Explicitly warns against creating skills in `~/.cursor/skills-cursor/`.

Triggered when: asked to create, write, or author a new skill.

#### create-subagent

**File:** `.cursor/skills-cursor/create-subagent/SKILL.md`

Guides creation of new agent definition files in `.cursor/agents/` (project) or `~/.cursor/agents/` (personal). Produces a `.md` file with YAML frontmatter (`name`, `description`) and a markdown body that becomes the system prompt. Covers scope selection (project vs personal), writing effective descriptions that include trigger terms and "use proactively" language, and the step-by-step creation workflow.

Triggered when: asked to create a new subagent, set up a task-specific agent, or configure a code reviewer/debugger/domain-specific assistant.

#### migrate-to-skills

**File:** `.cursor/skills-cursor/migrate-to-skills/SKILL.md`

Converts existing rules and commands to the skills format. Rules are migrated if they have a `description` but no `globs` and no `alwaysApply: true` (i.e., "Applied intelligently" rules). All commands are migrated. Conversion: rules get `name` added and `globs`/`alwaysApply` removed; commands get full frontmatter added including `disable-model-invocation: true` (so they remain user-triggered, not auto-suggested). Body content is copied character-for-character with no reformatting.

Triggered when: asked to migrate rules or commands to skills, or to convert `.mdc` files to `SKILL.md` format.

#### update-cursor-settings

**File:** `.cursor/skills-cursor/update-cursor-settings/SKILL.md`

Reads and modifies the Cursor/VS Code `settings.json` file. Knows the platform-specific paths (macOS: `~/Library/Application Support/Cursor/User/settings.json`, Linux: `~/.config/Cursor/User/settings.json`). Always reads existing settings before modifying, preserves all unrelated settings, and validates JSON before writing. Covers editor, workbench, files, terminal, and Cursor-specific settings. Notes when a restart or window reload is required.

Triggered when: asked to change editor settings, preferences, themes, font size, tab size, format-on-save, auto-save, or any `settings.json` value.
