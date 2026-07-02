# Git Workflow

## Commits
- Conventional format: `feat|fix|chore|docs|test|refactor(scope): description`
- Scope matches package or subsystem name
- Body explains WHY, not WHAT (the diff shows WHAT)
- All commits signed: `-s` (DCO sign-off) and `-S` (GPG signature), enforced by hook

## Branches
- Naming: `<type>/<issue>-<short-desc>` (e.g., `feat/123-gpu-scheduling`)
- Rebase workflow — no merge commits on feature branches
- `agents-workbench` is the coordination branch — read-only for source code

## Pull Requests
- Draft first (`gh pr create --draft`), QA promotes to ready-for-review
- One concern per PR — if it touches 2 unrelated subsystems, split it
- PR body: problem statement, approach, testing done, breaking changes
- Link to issue: `Closes #N` or `Fixes #N`

## Review
- DE must post `gh pr review` comment (creates audit trail for QA)
- Address all review comments before requesting re-review
- Squash-merge to main with conventional commit message
