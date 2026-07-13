# /js-review — JavaScript/TypeScript/Node review for async, types, runtime, and security

`/js-review` (also auto-triggered by phrases like "review JavaScript", "review
TypeScript", "review Node code", or "JS best practices") runs static analysis, walks a
JS-specific review checklist, and reports each finding as `file:line` with a category,
severity, and suggested fix. It only flags correctness, security, performance, and
maintainability — not style already handled by Prettier/ESLint.

## When to use it

- Before requesting human review on a JS/TS PR, to catch async, typing, Node-runtime, and
  security issues first.
- When you want a review scoped to async correctness, TypeScript strictness, Node patterns,
  dependency hygiene, and JS security rather than a general sweep.
- Say "review JavaScript", "review TypeScript", or "review Node code" to trigger it
  automatically, or invoke `/js-review` directly.
- **Not for:** style or formatting nits — those are Prettier/ESLint's job, and this skill
  explicitly skips them. It also won't demand a framework rewrite or a CJS→ESM migration.

## Examples

    > /js-review
    → Type-checks (`npx tsc --noEmit` when a tsconfig exists), runs the project's lint
      script if defined, checks `npm audit` for dependency-manifest changes, then walks
      the async / TypeScript / Node / dependency / security checklist and reports each
      finding as `file:line`, category (correctness/security/performance/maintainability),
      severity (must-fix/should-fix/consider), and a suggested fix.

    > review the whole project for async bugs, not just what I changed
    → Same checklist and report format, but scoped to the full project instead of the
      default changed-files-only scope — a full-project review only runs when asked
      explicitly.

## Dispatched mode

When the `pr-review` dispatcher invokes this skill, it reviews only the changed lines in the
PR diff and returns findings as structured data (`file`, `line`, `description`, `category`,
`severity`, `reason`) — no external actions, nothing posted. The dispatcher owns publishing.

## Setup

The static-analysis step is self-guarding: it type-checks only when a `tsconfig.json` exists,
runs lint only when the project defines a `lint` script, and runs `npm audit` only for
dependency-manifest changes. It uses the project's own toolchain via the skill's `Bash` tool
permission (`npx`, `npm`/`pnpm`/`yarn`); no other configuration. Pre-existing audit advisories
are reported as awareness, not treated as blockers.

## Notes

- Won't redesign architecture or suggest a rewrite during review — it flags issues within the
  existing pattern, and respects the project's conventions (a CommonJS project stays CommonJS).
- Pairs well with `superpowers:requesting-code-review` once findings are fixed.
- Index: [`docs/skills-and-commands.md`](../../../docs/skills-and-commands.md).
