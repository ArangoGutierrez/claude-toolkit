---
name: go-review
description: Go-specific code review — errors, concurrency, performance, idioms. Triggered by "review Go code", "Go best practices", or /go-review
user-invocable: true
tools:
  - Read
  - Grep
  - Glob
  - Bash
---

# Go Review

Systematic Go code review. Only flags correctness, performance, and maintainability — not style.

## Process

1. **Static analysis:**

   ```bash
   golangci-lint run --new-from-rev=HEAD~1 ./...
   ```

2. **Walk checklist** (see `references/go-review-checklist.md`):
   - Error handling, concurrency, performance, interfaces

3. **Report findings:**
   - file:line for each issue
   - Category: correctness / performance / maintainability
   - Severity: must-fix / should-fix / consider
   - Suggested fix (code snippet)

## Dispatched mode (pr-review integration)

When invoked by the pr-review dispatcher, the reviewer reads
`references/go-review-checklist.md`, reviews ONLY the changed lines in the PR diff,
and returns a findings list where each finding has: `file` (repo-relative path),
`line` (NEW-file/RIGHT-side line number), a 1–2 sentence `description`, `category`
(correctness / performance / maintainability), `severity` (must-fix / should-fix /
consider), and `reason` (which checklist item flagged it). Take no external action
of any kind in dispatched mode — findings are returned as data.

## Scope

Changed files only unless explicitly asked for full package review.

## Gotchas

- Don't flag style that gofmt/golangci-lint handles
- Don't suggest premature optimization
- Don't redesign architecture during review
- Respect existing patterns
