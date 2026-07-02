# /goal — record the session goal and acceptance criteria

`/goal Goal: <one-line goal>` plus an `Acceptance:` list records the current
session's goal as a timestamped stanza in
`~/.claude/audit/session-goals/<session-uuid>.md`, so a later verification
step has something concrete to check the work against. It never blocks: a
missing `Goal:` line or `Acceptance:` section just prints a warning to
stderr and the input is written anyway (soft rollout, not enforcement).

## When to use it

- Start of a session — capture the goal and acceptance bullets before diving
  into implementation.
- Mid-session, once brainstorming or planning refines scope — amending
  appends a new stanza rather than overwriting the original.
- You want the working directory's git origin recorded alongside the goal,
  so a statusline or later check can flag a cwd-vs-goal mismatch.
- **Not for:** turning a vague idea into a scoped task — `/kickoff` does that
  and sets the goal for you; call `/goal` directly only once you already
  know the goal.

## Examples

    > /goal Goal: refactor the auth module
    Acceptance:
    - all existing tests still pass
    - new tests cover the token-refresh edge case
    → No goal file existed yet, so goal.sh writes a `## Initial <ts>` stanza:
      the Goal line, an `Origin: <host>/<owner>/<repo>` line (only if cwd is
      a git repo with an `origin` remote), then the Acceptance bullets.

    > /goal amend the session goal to include tests
    → The goal file already exists, so a `## Amendment <ts>` stanza is
      appended below the initial one. The leading "amend " keyword is
      stripped from the recorded text — the script decides Initial vs.
      Amendment by whether the file exists, never by parsing for that word.

    > /goal just get the auth thing working
    → No `Goal: ` line and no `Acceptance:` section, so goal.sh prints
      `[goal] WARNING: input missing 'Goal: ' line` and a matching warning
      for the missing Acceptance section to stderr, then writes the stanza
      as given.

## Setup

Deploy (`scripts/deploy.sh` rsyncs `.claude/` into `~/.claude/`) so
`~/.claude/skills/goal/goal.sh` exists. Requires `jq` on `PATH` to resolve
the session UUID; `git` is optional — used only to record the `Origin:`
line and silently skipped if the cwd isn't a git repo or has no `origin`
remote.

Session UUID resolution order: `$CLAUDE_SESSION_ID` env var, then
`~/.claude/sessions/$$.json`, then the newest file under
`~/.claude/sessions/`.

## Notes

- The goal file is one per session and append-only — stanzas accumulate, so
  the full history of how the goal evolved is preserved, not overwritten.
- Verify: `bash .claude/skills/goal/tests/test_goal_skill.sh` (from the repo
  root).
- Related: [`kickoff`](../kickoff/), which sets the session goal
  automatically as part of scoping a rough idea. Index:
  [`docs/skills-and-commands.md`](../../../docs/skills-and-commands.md).
