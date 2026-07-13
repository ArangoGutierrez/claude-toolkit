# /python-review — Python review for AI/MLOps/agent codebases

`/python-review` (also auto-triggered by phrases like "review Python", "review this
agent code", or "review the training pipeline") runs the project's configured static
analysis, walks a Python-specific review checklist, and reports each finding as
`file:line` with a category, severity, and suggested fix. It targets correctness,
typing, async, agent-loop invariants, and ML reproducibility — not style already
handled by black/ruff.

## When to use it

- Before requesting human review on a Python PR, to catch typing, async, agent-loop,
  and reproducibility issues first.
- When reviewing LLM tool-use agents, ML training/eval pipelines, or model
  serialization code, where the sharp edges are async correctness, loop bounds,
  prompt-injection surface, and unsafe deserialization.
- Say "review Python", "review this agent code", or "review the training pipeline"
  to trigger it automatically, or invoke `/python-review` directly.
- **Not for:** style or formatting nits — those are black/ruff's job, and this skill
  explicitly skips them.

## Examples

    > /python-review
    → Runs `pyright` (or the project's `mypy`) and `ruff check` on the changed
      files when the project configures them, walks the correctness / async /
      agent-invariant / reproducibility / packaging checklist, then reports each
      finding as `file:line`, category (correctness/security/reproducibility/
      performance), severity (must-fix/should-fix/consider), and a suggested fix.

    > review this agent loop for safety
    → Same checklist and format, focused on the agent-building section: iteration
      and budget bounds, tool-argument validation, strict output parsing (never
      eval/exec), tool output as untrusted data, and retry/backoff behavior.

## Dispatched mode

The `pr-review` dispatcher can invoke this skill to review a PR diff. In that mode
the reviewer reads `references/python-review-checklist.md`, reviews only the changed
lines, and returns a structured findings list (`file`, `line`, `description`,
`category`, `severity`, `reason`) as data — it takes no external actions.

## Setup

The static-analysis step uses whatever the repo already configures: `pyright` or
`mypy` for typing, `ruff check` for lint. The skill runs them via its `Bash` tool
permission and never installs tools into the project — if none are configured, it
skips straight to the checklist walk.

## Notes

- Won't redesign architecture or demand annotations on private helpers in an untyped
  codebase — it flags issues at the public boundaries and within the existing
  framework choices.
- Pairs well with `superpowers:requesting-code-review` once findings are fixed.
- Index: [`docs/skills-and-commands.md`](../../../docs/skills-and-commands.md).
