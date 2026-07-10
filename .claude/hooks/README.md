# Hooks

Deterministic shell hooks that Claude Code runs at lifecycle events. Each hook
reads the event JSON on stdin, does one small thing, and exits — they never call
a model. Wire a hook by adding its command block to `.claude/settings.json` under
the matching event, then deploy the file into `~/.claude/` (e.g. via
`scripts/deploy.sh`). Every command below uses `$HOME/.claude/hooks/…` so the
same `settings.json` works on any machine.

Registration snippets for the three evidence-pipeline hooks follow. Each block
is additive — merge it into any existing array for that event rather than
replacing what's there.

## `bash-audit-log.sh` — PostToolUse audit log

Appends one line per Bash command the agent runs to
`~/.claude/audit/bash-commands-YYYY-MM-DD.log`
(`ISO8601 | session:<id> | cwd:<dir> | cmd: <command>`). URL-embedded
credentials and `--token`/`--password`/`--api-key`/`--secret` flag values are
redacted before the line is written, and a compound/multi-line command is folded
onto a single physical line so every sub-command shares the session marker. Always
exits 0 — logging never blocks the agent. Logs older than 30 days are pruned once
per day.

```json
"PostToolUse": [
  {
    "matcher": "Bash",
    "hooks": [
      { "type": "command", "command": "$HOME/.claude/hooks/bash-audit-log.sh" }
    ]
  }
]
```

## `verify-gate.sh` — Stop verification gate

Blocks a session **once** when code changed this session but no test/build/lint
command ran. Fail-open on any error; escape hatch `export VERIFY_GATE=off`. See
[`verify-gate.README.md`](verify-gate.README.md) for the full contract and
overrides.

```json
"Stop": [
  {
    "hooks": [
      { "type": "command", "command": "$HOME/.claude/hooks/verify-gate.sh" }
    ]
  }
]
```

## `budget-governor.sh` — Stop token-budget advisory

On Stop, sums output tokens across the session transcript (and any subagent
transcripts) and emits a one-time advisory to stderr as spend crosses 80% / 100%
of a declared budget. Purely advisory — always exits 0, never blocks.

Its one dependency is a per-session goal file; it degrades **silently** when the
file is absent, so it is safe to wire even if nothing writes goal files yet:

- Goal file: `$HOME/.claude/audit/session-goals/<session_id>.md`
- Budget line: the **last** line matching `Budget: <N|N.Nk|N.Nm>` in that file
  (e.g. `Budget: 200k`) sets the session's output-token budget.
- No goal file, or no `Budget:` line → the hook stays silent and exits 0.

Overrides: `BUDGET_GOVERNOR_GOAL_DIR`, `BUDGET_GOVERNOR_STATE_DIR`,
`BUDGET_GOVERNOR_VERBOSE=1` (always print a spend line). The full contract lives
in the hook's header comment.

```json
"Stop": [
  {
    "hooks": [
      { "type": "command", "command": "$HOME/.claude/hooks/budget-governor.sh" }
    ]
  }
]
```

## Tests

Each hook has a sibling `*_test.sh` harness that resolves its subject relative to
its own directory, so it runs from a checkout or a worktree:

```sh
bash .claude/hooks/bash-audit-log_test.sh < /dev/null
bash .claude/hooks/verify-gate_test.sh   < /dev/null
bash .claude/hooks/budget-governor_test.sh < /dev/null
```
