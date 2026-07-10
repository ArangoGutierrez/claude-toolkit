# validate-recommendation

A Claude Code skill that validates `(Recommended)` options in
`AskUserQuestion` calls by dispatching panelists from configurable backends.
Auto-takes the recommendation when panelists agree; surfaces dissent when
they disagree.

## How it works

1. The `validate-recommendation.sh` `PreToolUse` hook watches every
   `AskUserQuestion` call.
2. If any option label contains `(Recommended)` (and not
   `Panel-flagged`), the hook writes the tool input to a session state
   file and exits 2 (block) with a stderr message instructing Claude to
   invoke this skill.
3. SKILL.md dispatches enabled panelists from `~/.claude/panel/config.yml`
   in parallel. For each panelist:
   - Backend `nat-*`: routed to `panel dispatch` (langchain-mediated)
   - Backend `claude-subagent`: routed to the `Agent` tool with the
     configured subagent type
4. A Python aggregator reads the per-panelist verdict files and emits
   a JSON directive:
   - `HOLD` — Claude auto-proceeds with the recommendation
   - `SOFT-DISSENT` — Claude re-asks with dissent summary
   - `HARD-DISSENT` — Claude escalates to user with severity indicator
   - `ERROR` — Claude asks original question unmodified

## Configuration

### Required environment variables

These variables are required only if you configure panelists with specific
backends. If you're using only Claude subagents, no env vars are required.

| Variable | Effect |
|----------|--------|
| `$NVIDIA_API_KEY` | For `backend: nat-nim` panelists (NVIDIA Nemotron via langchain) |
| `$ANTHROPIC_API_KEY` | For `backend: nat-anthropic` panelists |
| `$OPENAI_API_KEY` | For `backend: nat-openai` panelists |

The configuration lives in `~/.claude/panel/config.yml`. Each enabled
panelist specifies its backend and any required auth credentials. Missing
credentials → that panelist emits ERROR verdict; severity.decide() handles
it per your configured failure mode.

### Optional environment variables

| Variable | Default | Effect |
|----------|---------|--------|
| `CLAUDE_PANEL` | `on` | Controls panel behavior. `on` (default) auto-takes the recommendation on HOLD. `advise` runs the panel but re-asks every question with the panel's commentary appended — preserves user agency at the cost of one extra click per question. `off` bypasses the panel entirely (hook exits without dispatching). |
| `CLAUDE_PANEL_TIMEOUT` | `90` | Per-panelist timeout (seconds). |
| `CLAUDE_PANEL_TRACE_LOG` | `~/.claude/debug/panel-trace.log` | Path the hook and aggregator append verdict telemetry to. The trace log is **always written** (one line per trigger, one line per verdict) so the operator can detect silent decay. Override path for tests or alternative routing. |
| `CLAUDE_PANEL_DEBUG` | unset | If set, the hook writes extra verbose lines to the trace log on top of the always-on telemetry. |

### One-off bypass

To disable the panel for a single session:

```bash
CLAUDE_PANEL=off claude
```

The hook exits immediately without dispatching panelists.

To preserve user agency while keeping the panel's audit value:

```bash
CLAUDE_PANEL=advise claude
```

Panel still runs and writes telemetry. On HOLD verdicts, the question
is re-issued with a `**Panel validated:**` note appended — the user
picks every answer but gets the panel commentary alongside.

## Cost

Panel cost depends on your configuration. If all panelists use
`backend: claude-subagent`, the cost is the subagent context. If you
configure `nat-*` panelists:

- **NAT backends** (NVIDIA, Anthropic, OpenAI): token costs per the
  configured model. Typical inference call: 100-200 prompt tokens (question
  + options + persona) + up to 1024 completion tokens.
- **Claude subagent panelists**: full subagent context. Per the persona
  prompt, the subagent uses tools (Read, Grep, Glob) to consult
  `~/.claude/CLAUDE.md` and `~/.claude/rules/*.md` before rendering a
  verdict. Realistically 5-15k tokens per invocation including the
  rule-file reads.

Monitor actual usage via the trace log:
```bash
grep -c 'event=trigger' ~/.claude/debug/panel-trace.log
grep -c 'outcome=HOLD' ~/.claude/debug/panel-trace.log
```

To reduce cost: `CLAUDE_PANEL=off` bypasses the panel entirely.

## Files

```
.claude/
├── hooks/
│   ├── validate-recommendation.sh       (hook; deploys to ~/.claude/hooks/)
│   └── validate-recommendation_test.sh  (hook tests; 8 cases)
└── skills/validate-recommendation/
    ├── SKILL.md                  (orchestration instructions Claude follows)
    ├── panel/
    │   ├── severity.py           (N-panelist decision tree; pure)
    │   ├── aggregate.py          (reads config, verdicts; emits JSON)
    │   ├── config.py             (config.yml parser)
    │   ├── dispatch.py           (nat-* backend router)
    │   ├── cli.py                (CLI for manual debugging)
    │   └── tests/                (pytest suite; 113 cases)
    ├── personas/                 (per-role persona files for config-driven dispatch)
    │   ├── da.md
    │   ├── pe.md
    │   └── qa.md
    ├── fixtures/                 (verdict + config fixtures for tests)
    └── README.md                 (this file)
```

## Running the test suites

From this skill's directory:

```bash
cd ~/.claude/skills/validate-recommendation
~/.local/pipx/venvs/pytest/bin/pytest panel/tests/ -q
```

Expected: `113 passed`. The test suite covers severity decision tree,
JSON aggregator, config parsing, dispatch routing, and CLI wiring.

## E2E smoke test (post-install)

After syncing this skill to `~/.claude/`:

1. Verify the config is present:
   ```bash
   ~/.local/pipx/venvs/pytest/bin/python3.12 -m panel lint-config 2>&1 | head -5
   ```
   Should print `Config valid`.

2. Confirm `CLAUDE_PANEL` is unset (default = on):
   ```bash
   echo "${CLAUDE_PANEL:-on}"
   ```
   Should print `on`.

3. Open a fresh Claude Code session.

4. Prompt the assistant for a recommendation that triggers
   `AskUserQuestion`, e.g.:
   > "Recommend an HTTP client for a Go service that needs retries.
   > Show 3 options."

5. Verify behavior:
   - The assistant should announce that it's running the panel before
     surfacing any user-facing question.
   - On HOLD: the assistant prints the panel rationales and proceeds
     without showing the question. You never see the `AskUserQuestion`
     UI for that decision.
   - On DISSENT: the question shows up with a `**Panel review:**` line
     appended.

6. Inspect the trace log:
   ```bash
   tail -n 20 ~/.claude/debug/panel-trace.log
   ```
   Should contain `event=trigger` and `outcome=HOLD/SOFT-DISSENT/HARD-DISSENT` lines.

7. Run with bypass to verify the off-switch:
   ```bash
   CLAUDE_PANEL=off claude
   ```
   Same prompt as step 4 — the panel should NOT fire; the question
   appears immediately with the original options.

## Troubleshooting

**Is the panel actually working?** Check the trace log:

```bash
tail -n 20 ~/.claude/debug/panel-trace.log
grep -c 'outcome=HOLD' ~/.claude/debug/panel-trace.log
grep -c 'outcome=SOFT-DISSENT' ~/.claude/debug/panel-trace.log
grep -c 'outcome=HARD-DISSENT' ~/.claude/debug/panel-trace.log
grep -c 'outcome=ERROR' ~/.claude/debug/panel-trace.log
```

If trigger count is 0 the panel is not firing (see "panel never fires"
below). If ERROR count is high while other outcomes are 0, the panel is
firing but every dispatch is failing — most likely missing credentials
for your configured backends.

**The panel never fires.** Check that the hook is registered in
`~/.claude/settings.json` under `hooks.PreToolUse` with matcher
`AskUserQuestion`. Run `jq '.hooks.PreToolUse[] | select(.matcher == "AskUserQuestion")' ~/.claude/settings.json` to verify.

**Every recommendation hits the ERROR path.** Check which backends are
enabled in `~/.claude/panel/config.yml`. For each `nat-*` backend,
confirm the required env var is set (NVIDIA_API_KEY, ANTHROPIC_API_KEY,
or OPENAI_API_KEY). For `claude-subagent` backends, ensure the subagent
type exists (check `~/.claude/agents/` or parent repo).

## Uninstall

1. Remove the matcher block from `.claude/settings.json` under
   `hooks.PreToolUse` (the entry pointing at
   `validate-recommendation.sh`).
2. Delete the skill and hook files:
   ```bash
   rm -rf .claude/skills/validate-recommendation/
   rm -f .claude/hooks/validate-recommendation.sh \
         .claude/hooks/validate-recommendation_test.sh
   ```
3. Re-run `./scripts/deploy.sh` (or hand-delete from `~/.claude/`).

## Security notes

- Verdict files live at `~/.claude/panel/work/<session-id>/<panelist-id>.verdict`
  and are created with `umask 077` so they are mode 0600 (user-only readable).
- Per-session workdir is cleaned up after the skill finishes aggregating.
- For `nat-*` panelists: API credentials are passed through langchain
  providers. They are never written to files or logged in trace output
  (trace logs only record outcome, not prompts or responses).
- For `claude-subagent` panelists: the Agent tool's response is written
  verbatim to a verdict file; SKILL.md parses it for VERDICT/RATIONALE/ALTERNATIVE.
- The hook fails open: any error in hook bash logic results in `exit 0`
  (approve). This prevents broken hooks from blocking `AskUserQuestion` entirely.

## Phase 3b: `panel dispatch` (backend abstraction)

You can invoke one panelist end-to-end from the CLI for debugging:

```bash
/opt/homebrew/bin/python3.12 -m panel dispatch \
    --panelist <id-from-config.yml> \
    --prompt-file /path/to/templated-user-body.txt \
    --output /tmp/panelist.verdict
cat /tmp/panelist.verdict
```

Exit codes:
- `0` — verdict file written (HOLD, OVERTURN, or ERROR — any structured outcome)
- `1` — caller-supplied path/id invalid (no verdict file written)

The `panel dispatch` command reads the panelist config (backend, model,
auth credentials) and routes to the appropriate langchain provider
(ChatNVIDIA, ChatAnthropic, ChatOpenAI). It is invoked automatically by
SKILL.md per `nat-*` panelist; the CLI usage above is for manual debugging only.

Backend implementation routes through langchain providers directly
(`ChatNVIDIA`, `ChatAnthropic`, `ChatOpenAI`). The single mockable test
seam is `panel.dispatch._invoke_nat`; tests mock at that boundary only.

Required env vars per backend (only needed for `nat-*` panelists in config):
- `nat-nim`: `$NVIDIA_API_KEY` (langchain-nvidia-ai-endpoints reads it natively)
- `nat-anthropic`: `$ANTHROPIC_API_KEY`
- `nat-openai`: `$OPENAI_API_KEY`

Missing env vars → dispatch still exits 0; verdict file contains
`VERDICT: ERROR` with the auth failure in the rationale. Same applies
to network errors and malformed model responses.

## Phase 3c: N-panelist JSON aggregator

`panel aggregate` is now N-panelist and emits a single-line JSON
directive on stdout. SKILL.md parses it via `jq`.

### CLI

```bash
/opt/homebrew/bin/python3.12 -m panel aggregate \
    --config ~/.claude/panel/config.yml \
    --verdicts-dir ~/.claude/panel/work/<session-id>/ \
    --recommended-label "Option A (Recommended)"
```

### JSON directive shape

```json
{
  "verdict": "HOLD | SOFT-DISSENT | HARD-DISSENT | ERROR",
  "summary": "<user-facing one-line, already sanitized>",
  "rationale_gate_passed": true | false | null,
  "panelists": [
    {"id": "<panelist-id>", "role": "DA|PE|QA|...",
     "verdict": "HOLD|OVERTURN|ERROR",
     "rationale": "<verbatim, sanitized>",
     "alternative": "<verbatim option label or 'n/a'>"}
  ],
  "escalate_to_user": true  // present and true on Phase 3c HARD-DISSENT
}
```

Phase 5+ will add a `re_brainstorm` payload on HARD-DISSENT when
`cycle < max_cycles`. Phase 3c always emits `escalate_to_user: true`
on HARD-DISSENT (no cycle machinery yet).

### Verdict file convention

Per-session subdir: `~/.claude/panel/work/<session-id>/<id>.verdict`
where `<id>` matches the panelist's `id` in `~/.claude/panel/config.yml`.
SKILL.md creates the subdir; `panel dispatch` writes verdict files for
`nat-*` panelists; SKILL.md writes verdict files for `claude-subagent`
panelists from the Agent tool's response. Missing verdict files coerce
to ERROR-status panelist rows.
