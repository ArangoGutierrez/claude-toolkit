# /eureka — capture a breakthrough before it evaporates

`/eureka` (also triggered by "breakthrough", "key insight", or "document
discovery") prompts you for Problem / Insight / Implementation / Impact, then
writes a structured Markdown document to `docs/breakthroughs/`. The bar is
"would this surprise a senior engineer?" — routine solutions don't qualify.

## When to use it

- You just solved something non-obvious and want it on record before the
  context evaporates.
- You want a searchable, dated trail of insights across projects, not just a
  commit message that explains *what* changed but not *why it worked*.
- The insight might generalize into a team convention (a candidate for a
  `rules/` file update), not just a one-off fix.
- **Not for:** routine debugging or well-documented knowledge — those add
  noise, not signal. Recurring mistakes and session patterns go through
  [`reflection`](../reflection/) instead.

## Examples

    > /eureka
    → Prompts for Problem, Insight, Implementation, Impact, then writes
      docs/breakthroughs/2026-07-02-<slug>.md with those four sections plus a
      Date/Tags/Project header. If the insight implies a new convention, it
      then proposes an update to the relevant rules/ file.

    > "key insight: the retry storm was caused by clock skew between pods,
      not the backoff config"
    → The natural-language trigger fires the same flow as /eureka — same
      prompts, same output document.

## Notes

- Output path (`docs/breakthroughs/YYYY-MM-DD-<slug>.md`) is an interim
  location until a cross-IDE memory architecture ships.
- The Insight section must be specific enough to be actionable — vague
  restatements of the problem don't pass the bar.
- Related: [`reflection`](../reflection/) for recurring mistakes and session
  patterns rather than one-off breakthroughs. Index:
  [`docs/skills-and-commands.md`](../../../docs/skills-and-commands.md).
