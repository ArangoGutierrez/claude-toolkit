---
name: js-review
description: JavaScript/TypeScript/Node code review — async correctness, TypeScript strictness, Node patterns, dependency hygiene, JS security. Triggered by "review JavaScript", "review TypeScript", "review Node code", "JS best practices", or /js-review
user-invocable: true
tools:
  - Read
  - Grep
  - Glob
  - Bash
---

# JS Review

Systematic JavaScript/TypeScript/Node code review. Only flags correctness, security,
performance, and maintainability — not style that Prettier/ESLint already handles.

## Process

1. **Static analysis** (guard every tool — run only when the project has it configured):

```bash
# type-check, only when a tsconfig.json exists
[ -f tsconfig.json ] && npx --no-install tsc --noEmit
# the project's own lint script, only when defined in package.json
npm run --if-present lint
# dependency advisories, only for package.json / lockfile changes — report awareness,
# do NOT block on pre-existing advisories
npm audit --omit=dev   # pnpm audit --prod / yarn npm audit for those managers
```

2. **Walk checklist** (see `references/js-review-checklist.md`):
   - Async correctness, TypeScript strictness, Node runtime patterns, dependency hygiene, JS security

3. **Report findings:**
   - file:line for each issue
   - Category: correctness / security / performance / maintainability
   - Severity: must-fix / should-fix / consider
   - Suggested fix (code snippet)

## Dispatched mode (pr-review integration)

When invoked by the `pr-review` dispatcher, the reviewer reads
`references/js-review-checklist.md`, reviews ONLY changed lines in the PR diff, and returns a
findings list where each finding has:

- `file` — repo-relative path
- `line` — NEW-file (RIGHT-side) line number
- `description` — 1–2 sentences
- `category` — correctness / security / performance / maintainability
- `severity` — must-fix / should-fix / consider
- `reason` — which checklist item flagged it

No external actions of any kind in dispatched mode — findings are returned as data, never posted.

## Scope

Changed files only unless explicitly asked for a full-project review.

## Gotchas

- Don't flag style that Prettier/ESLint handles
- Don't demand a framework rewrite or migration (e.g. CJS → ESM) during review
- Respect the project's existing patterns — a CommonJS project stays CommonJS
- Don't block on pre-existing `npm audit` advisories; flag only what the change introduces
