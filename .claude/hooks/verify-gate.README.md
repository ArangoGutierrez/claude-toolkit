# verify-gate.sh — verification Stop-gate

A `Stop` hook that blocks a session **once** when code changed this session but no
test/build/lint command ran — a deterministic nudge to actually verify before
finishing.

It parses the session transcript (`transcript_path` from the Stop hook stdin) for
`Edit`/`Write` on source-extension files (code changed) and `Bash` commands matching
a verification allowlist (`go test`, `pytest`, `npm test`, `golangci-lint`, `make
test`, …). Code-changed ∧ not-verified → `exit 2` with a message to the model;
everything else → allow.

**Safety:** fail-open on any error (missing/bad transcript, `jq` failure → allow);
blocks at most once per stop-chain via `stop_hook_active`; escape hatch
`export VERIFY_GATE=off`. Pass/fail is **not** judged — the bar is "ran".

## Enable
Wired under `Stop` in `.claude/settings.json`; deployed to `~/.claude/` via
`scripts/deploy.sh`. Overrides: `VERIFY_GATE_PATTERN` (verification-command ERE),
`VERIFY_GATE_EXT` (source extensions).

## Test
`bash .claude/hooks/verify-gate_test.sh < /dev/null`
