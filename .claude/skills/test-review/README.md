# /test-review — review test, e2e, and CI changes for theater tests and misconfiguration

`/test-review` (also auto-triggered by phrases like "review these tests", "is this
a real test", "review the workflow", or "review this e2e") scopes the diff to test
and CI files, walks a test-and-CI-specific checklist, and reports each finding as
`file:line` with a category, severity, and the checklist item that flagged it. It
detects theater tests (tests that pass even when their subject is broken), flaky
e2e patterns, and GitHub Actions / Prow misconfiguration — not style.

## When to use it

- Before requesting human review on a PR that adds or changes tests, e2e suites, or
  CI config, to catch theater tests and CI foot-guns first.
- When you want to know whether a specific test actually asserts anything — the
  deletion test (would it fail if the code under test were deleted?) is the headline
  check.
- When reviewing a GitHub Actions workflow or Prow job for security and correctness
  (SHA-pinned actions, least-privilege permissions, injection-safe `run:` steps,
  regex triggers that actually match).
- Say "review these tests" or "review this workflow" to trigger it automatically, or
  invoke `/test-review` directly.
- **Not for:** general code correctness (use `/go-review` or a language-specific
  review) or style nits a formatter/linter already handles.

## Examples

    > /test-review
    → Scopes the diff to `*_test.*`, `e2e`, `.github/workflows/`, Prow, and OWNERS
      files, runs actionlint if present, walks the theater-test / e2e-quality /
      GitHub Actions / Prow checklist, then reports each finding as `file:line`,
      category (theater-test/flakiness/ci-config/coverage-gap), severity
      (must-fix/should-fix/consider), and the checklist item that flagged it.

    > is this a real test or theater?
    → Applies the deletion test and the tautological-assertion, guard-fixture, and
      over-mocking checks from section 1, and explains for each assertion whether it
      would fail when the subject is broken.

## Dispatched mode

The `pr-review` dispatcher can invoke this skill as its test-and-CI reviewer. In
that mode it reads `references/test-review-checklist.md`, reviews only the changed
lines in the PR diff, and returns a structured findings list (`file`, `line`,
`description`, `category`, `severity`, `reason`) as data — it takes no external
actions of its own. See the "Dispatched mode" section of `SKILL.md` for the exact
contract.

## Setup

Optional: `actionlint` on `PATH` sharpens the GitHub Actions pass, and Prow's
`checkconfig` sharpens the Prow pass. The skill runs them when present and notes
their absence when a repo ships CI without them; neither is required.

## Notes

- Won't demand 100% coverage — it flags gaps only in behavior the PR claims to add.
- Won't re-flag what actionlint or checkconfig already catches; it fills the gaps
  those linters miss (theater tests, injection risk, trigger-regex intent).
- Pairs well with `superpowers:requesting-code-review` once findings are fixed.
- Index: [`docs/skills-and-commands.md`](../../../docs/skills-and-commands.md).
