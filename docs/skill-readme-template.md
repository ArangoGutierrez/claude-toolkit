# Skill README standard

Every skill and command in this toolkit ships a `README.md` next to its
`SKILL.md`. The `SKILL.md` is the **agent-facing protocol** (loaded into model
context on invocation — keep it lean). The `README.md` is the **human-facing
page**: what the skill is for, when to reach for it, and concrete examples.
The central [`docs/skills-and-commands.md`](skills-and-commands.md) is the
index; each row links to one of these per-skill READMEs.

Copy the structure below. Keep it concrete — every example shows an actual
invocation and the outcome a user should expect.

```markdown
# /<name> — <one-line tagline>

<1–2 sentences: what it does and the value it delivers. Name the trigger
(`/<name> <args>`) and any fail-open / safety behavior.>

## When to use it
<3–6 bullets of concrete situations — the problems it solves and the
triggers. Pair with "When NOT to use it" if there's a common mis-reach.>

## Examples
<2–3 worked examples. Each = the invocation, then what happens / the
expected outcome. Prefer a real transcript snippet over prose.>

    > /<name> <concrete args>
    → <what the skill produces / the observable result>

## Setup
<Only if non-trivial: env vars (names only, never secret values), deploy
step, dependencies. Omit this section entirely if there's nothing to set up.>

## Notes
<Gotchas, failure modes, related skills (link them), and a pointer back to
the central reference. Keep to what a user actually needs.>
```

## Rules
- **World-safe** (this repo is public): no internal hostnames, tokens, or
  private paths in examples. Use placeholders (`https://your-endpoint`,
  `$YOUR_API_KEY`).
- **Examples must be real**: every example reflects actual behavior — run it
  if unsure. Don't invent output.
- **Don't duplicate `SKILL.md`**: the README explains *use*; the SKILL.md
  defines the *procedure*. Link, don't copy.
- **One screen where possible**: a reader should grasp purpose + an example
  without scrolling for minutes.
```
