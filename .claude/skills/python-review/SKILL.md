---
name: python-review
description: Python code review specialized for AI/MLOps/agent codebases — typing (pyright), async correctness, agent-loop invariants, ML reproducibility, model serialization safety. Triggered by "review Python", "review this agent code", "review the training pipeline", or /python-review
user-invocable: true
tools:
  - Read
  - Grep
  - Glob
  - Bash
---

# Python Review

Systematic Python review for AI/MLOps/agent codebases. Flags correctness, typing,
async, agent-loop, and reproducibility issues — not style that formatters own.

## Process

1. **Static analysis** (run only the tools the project already configures; never
   install anything into the project):
   - `pyright` on changed files when the project uses it (or `mypy` if that is the
     project's checker — check `pyproject.toml` / `mypy.ini` / `setup.cfg`).
   - `ruff check` on changed files when the project configures ruff.

2. **Walk checklist** (see `references/python-review-checklist.md`):
   - Core correctness & typing, async correctness, agent-building invariants,
     ML reproducibility & serialization safety, packaging & environment.

3. **Report findings:**
   - `file:line` for each issue
   - Category: correctness / security / reproducibility / performance
   - Severity: must-fix / should-fix / consider
   - Suggested fix (code snippet)

## Dispatched mode (pr-review integration)

When invoked by the `pr-review` dispatcher, read
`references/python-review-checklist.md`, review ONLY the changed lines in the PR
diff, and return a findings list. Each finding has:

- `file` — repo-relative path
- `line` — NEW-file / RIGHT-side line number
- `description` — 1–2 sentences
- `category` — correctness / security / reproducibility / performance
- `severity` — must-fix / should-fix / consider
- `reason` — which checklist item flagged it

Take no external actions in dispatched mode — findings are returned as data.

## Scope

Changed files only unless explicitly asked for a full-package review.

## Gotchas

- Don't flag style that black/ruff already handle.
- Don't demand type annotations on private helpers in an untyped codebase —
  type the public boundaries first.
- Respect the project's framework choices; review within them, don't rewrite.
- Guard every static-analysis command: run it only if the repo configures it.
