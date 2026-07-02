# /go-review — systematic Go code review for correctness, concurrency, and performance

`/go-review` (also auto-triggered by phrases like "review Go code" or "Go best
practices") runs static analysis, walks a Go-specific review checklist, and reports
each finding as `file:line` with a category, severity, and suggested fix. It only
flags correctness, performance, and maintainability — not style already handled by
gofmt/golangci-lint.

## When to use it

- Before requesting human review on a Go PR, to catch error-handling, concurrency,
  and performance issues first.
- When you want a review scoped to error handling, concurrency, performance, and
  interface design rather than a general sweep.
- Say "review Go code" or "Go best practices" to trigger it automatically, or
  invoke `/go-review` directly.
- **Not for:** style or formatting nits — those are gofmt/golangci-lint's job, and
  this skill explicitly skips them.

## Examples

    > /go-review
    → Runs `golangci-lint run --new-from-rev=HEAD~1 ./...` against the files
      changed since the last commit, walks the error-handling / concurrency /
      performance / interfaces checklist, then reports each finding as
      `file:line`, category (correctness/performance/maintainability), severity
      (must-fix/should-fix/consider), and a suggested fix.

    > review the whole package for concurrency bugs, not just what I changed
    → Same checklist and report format, but scoped to the full package instead
      of the default changed-files-only scope — a full-package review only runs
      when asked explicitly.

## Setup

Requires `golangci-lint` on `PATH` for the static-analysis step; the skill runs it
directly via its `Bash` tool permission. No other configuration.

## Notes

- Won't redesign architecture or suggest premature optimization during a review —
  it flags issues within the existing pattern, not a rewrite.
- Pairs well with `superpowers:requesting-code-review` once findings are fixed.
- Index: [docs/skills-and-commands.md](../../../docs/skills-and-commands.md).
