---
name: test-review
description: Test and CI review — detect theater tests vs real tests, e2e suite quality, GitHub Actions and Prow config correctness. Triggered by "review these tests", "is this a real test", "review the workflow", "review this e2e", or /test-review
user-invocable: true
tools:
  - Read
  - Grep
  - Glob
  - Bash
---

# Test Review

Systematic review of test, e2e, and CI changes. Flags theater tests, flaky e2e
patterns, and CI misconfiguration — not style.

## Process

1. **Scope the diff** to test and CI files:

```bash
git diff --name-only HEAD~1 | grep -Ei '_test\.|(^|/)e2e|\.github/workflows/|prow|OWNERS|\.ya?ml$'
```

2. **Run available CI linters** (and flag their absence if the repo ships CI without them):

```bash
if command -v actionlint >/dev/null; then actionlint; else echo "actionlint not installed"; fi
```

3. **Walk the checklist** (`references/test-review-checklist.md`):
   - Theater-test detection, e2e/integration quality, GitHub Actions, Prow

4. **Apply the deletion test** to every test touched: would it fail if the code
   under test were deleted? If not, it is theater.

5. **Report findings:**
   - file:line for each issue
   - Category: theater-test / flakiness / ci-config / coverage-gap
   - Severity: must-fix / should-fix / consider
   - Reason: which checklist item flagged it

## Dispatched mode (pr-review integration)

When invoked by the pr-review dispatcher, read `references/test-review-checklist.md`,
review ONLY the changed lines in the PR diff, and return a findings list. Each
finding has:

- `file` — repo-relative path
- `line` — NEW-file (RIGHT-side) line number
- `description` — 1–2 sentences
- `category` — theater-test / flakiness / ci-config / coverage-gap
- `severity` — must-fix / should-fix / consider
- `reason` — which checklist item flagged it

Take NO external actions of any kind in dispatched mode — findings are returned
as data, never posted.

## Scope

Changed files only unless explicitly asked for a full-suite review.

## Gotchas

- Don't demand 100% coverage — flag gaps only in behavior the PR claims to add.
- Don't flag what actionlint or checkconfig already catches — but DO note when the
  repo ships CI yet lacks those linters.
- Don't rewrite the test strategy — flag issues within the existing approach.
- A green run proves nothing about a test's value; judge by the deletion test, not
  the pass.
