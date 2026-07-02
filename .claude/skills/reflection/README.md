# /reflection — turn session mistakes into curated rules

`/reflection` (also triggered by "analyze session", "what did I learn", or "improve
CLAUDE.md") runs one of three modes: **session analysis** mines bash-audit logs and
git history for recurring errors, **mistake capture** turns "I keep doing X" into a
tracked anti-pattern entry, and **rules curation** prunes
`rules/learned-anti-patterns.md` and flags stale rules. Every write requires your
explicit approval before it lands.

## When to use it

- After a rough session, to surface repeated errors, permission blocks, or hook
  violations you didn't consciously notice.
- The moment you catch yourself repeating a mistake — describe it and reflection
  either bumps an existing anti-pattern's `Count` or appends a new entry.
- Periodically, to prune `learned-anti-patterns.md` (drop stale `warning` entries,
  respect the 50-line cap) and check for a pattern that hit `Count >= 3` and is
  mechanically detectable enough to promote into an actual hook check.
- **Not for:** classifying PR review comments — that's
  [`pr-review-ingest`](../pr-review-ingest/), which feeds the same rules pipeline
  from reviewer feedback instead of session logs.

## Examples

    > /reflection analyze session
    → Runs `scripts/analyze-sessions.sh` (last 7 days by default), aggregating
      `bash-commands-*.log` entries and `git log` into top commands, error/permission
      lines, hook-block counts, and most-changed files. Reflection summarizes the
      patterns and proposes specific edits to CLAUDE.md or rules/ for your approval.

    > I keep forgetting to run `go vet` before committing
    → Reflection prompts for context, the fix, severity, and tags, checks
      `learned-anti-patterns.md` for a duplicate, and — once you approve — either
      bumps the matching entry's `Count`/`Since` or appends a new pattern line with
      `Count: 1` and today's date.

    > /reflection curate rules
    → Prunes `learned-anti-patterns.md` per severity (critical never pruned; warning
      pruned only if `Count < 2` and `Since` is 90+ days old; info pruned by lowest
      count once over the 50-line cap), flags any mechanically-detectable pattern at
      `Count >= 3` as a promotion candidate, and updates `audit/.last-reflection`.

## Setup

Deploy (`scripts/deploy.sh` rsyncs `.claude/` into `~/.claude/`). Session analysis
depends on the `bash-audit-log.sh` PostToolUse hook already writing to
`~/.claude/audit/bash-commands-*.log`; without it, Mode 1 reports "No bash audit
logs found" and falls back to `git log` alone. No other configuration is required.

## Notes

- Writes to `rules/learned-anti-patterns.md` are blocked outright while
  `audit/.anti-patterns.lock` exists (team-execute's QA agent is writing) — retry
  later rather than forcing it.
- `reflection-staleness.sh` reminds you at session start if `/reflection` hasn't
  run in 7+ days (tracked via `audit/.last-reflection`).
- Don't remove a rule that hasn't been tested, don't duplicate what a hook already
  catches, and don't treat a one-off (`Count` of 1) as a pattern.
- Related: [`pr-review-ingest`](../pr-review-ingest/). Index:
  [`docs/skills-and-commands.md`](../../../docs/skills-and-commands.md).
