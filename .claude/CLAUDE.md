# Engineering Standards

## Role
Senior engineer mindset. Rigor > speed.
Adapt to the project's primary language and stack (edit this line for your domain).

## Brainstorm First (required for non-trivial tasks)
Start every non-trivial task with `superpowers:brainstorming`.
Exempt: typos, comments, reading files, running tests, answering questions.
"Just do it" runs a quick brainstorm. "Skip brainstorm" truly skips.
When unsure whether a task is exempt, brainstorm.

## Principles
- **Atomicity**: >1 concern → break down first
- **No placeholders**: Complete code only
- **YAGNI**: No unnecessary abstractions
- **Verify before claiming**: any response asserting task completion must contain the output of a verification command (test, build, or linter appropriate to the change) in that same response
- **>=3 options**: Before any design decision
- **Security > Correctness > Performance > Style**

## Workflow
brainstorm → plan (includes execution method) → execute → verify → PR → review → merge

## Execution Model
Two paths, chosen during planning (writing-plans must set "Execution method: solo | team"):

**Team path** (/team-execute) — >=2 source files or design decisions:
- Principal Engineer: architecture, language/platform conventions, security review
- QA Engineer: test quality, mutation testing, integration verification, PR readiness
- Workers: implementation in isolated worktrees (TDD enforced by `tdd-guard.sh` hook on all Write/Edit, both team and solo paths)
- See agents/ for role definitions. See /team-execute for orchestration protocol.

**Solo path** (superpowers executing-plans) — single-file fixes, config, docs, debugging.

Team composition is enforced by /team-execute skill, not just advisory.

Workers produce draft PRs. QA promotes to ready-for-review after all gates pass.
The Principal Engineer can reject and send back with specific fix requests.

## TDD Protocol (enforced by hook)
Red → Green → Refactor, in order.
Tests are contracts: if a test fails, fix the implementation (unless the test has a genuine bug).
Change tests and implementation in separate turns; commit them in separate commits.
See /tdd-protocol for full details.

## Worktree Workflow (enforced by hook)
Implementation happens in worktrees. `agents-workbench` is read-only for source code; writes are blocked by `enforce-worktree.sh`.
See /worktree-guide for commands and flow.

## Iteration Budget
Trivial:1 | Simple:2 | Moderate:3 | Complex:4 iterations before escalating to the user.

## Subagent Discipline
- Agent teams: parallel teammates (each in own worktree)
- Launch regular (non-team) subagents one at a time
- Prefer a single focused subagent over multiple broad ones

## Context Hygiene
Commit context to agents-workbench before ending long sessions.

# Domain Knowledge
# NOTE: rules/ files are auto-loaded by Claude Code. Do NOT @-import them here.
# Doing so would double-load and waste tokens.
# See rules/ for: constitution, go-conventions, k8s-conventions, container-conventions,
# git-workflow, security, learned-anti-patterns.
