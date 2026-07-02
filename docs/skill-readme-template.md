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

<1–2 sentences: what it does and the value it delivers. This opening
paragraph IS the "purpose" — do not add a `## Purpose` heading. Name the
trigger (e.g. `/<name> <args>`) and any fail-open / safety behavior.>

## When to use it

<3–6 bullets of concrete situations — the problems it solves and the
triggers. End with a `**Not for:**` bullet naming the common mis-reach and
where that work should go instead (most of these skills have a near-neighbor).>

## Examples

<2–3 worked examples. Each is the invocation, then what happens / the
expected outcome. Use a 4-space-indented block with a literal `>` line for
the command and a `→` line for the observable result — not prose, not a
fenced block.>

    > /<name> <concrete args>
    → <what the skill produces / the observable result>

## Setup

<Only if non-trivial: env var NAMES (never values), deploy step,
dependencies. Show placeholders for any host/key (`https://your-endpoint`,
`$YOUR_API_KEY`). Omit this section entirely if there's nothing to set up.>

## Notes

<Gotchas, failure modes, related skills (link them), and a pointer back to
the index. Keep to what a user actually needs.>
```

## Rules

- **Title & slash prefix**: use `# /<name> — <tagline>` only if the skill is
  user-invocable as a slash command; for auto-triggered skills use
  `# <name> — <tagline>` with no slash. Every title carries a tagline.
- **World-safe** (this repo is public): no internal hostnames, model ids,
  employer-specific references, tokens, or private paths (never
  `/Users/<you>/…` — use `~/…`). Use placeholders (`https://your-endpoint`,
  `$YOUR_API_KEY`).
- **Examples must be real**: every example and any command you cite (a
  `Verify:` line, a test invocation) must reflect actual behavior and point
  at a file that exists — run it if unsure. Don't invent output.
- **Don't duplicate `SKILL.md`**: the README explains *use*; the SKILL.md
  defines the *procedure*. Link, don't copy.
- **Plain and technical**: no emoji, no marketing adjectives ("powerful",
  "seamless", "effortless", "revolutionary"). Imperative or second person.
- **One screen**: target ~40–90 lines; a reader should grasp purpose + an
  example without scrolling for minutes.
- **Links**: a skill README sits at `.claude/skills/<name>/README.md`, so the
  index is three levels up:
  `[docs/skills-and-commands.md](../../../docs/skills-and-commands.md)`.
  Link a sibling skill as `[<other>](../<other>/)`.
