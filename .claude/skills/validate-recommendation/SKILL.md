---
name: validate-recommendation
description: Validate (Recommended) options in AskUserQuestion via N configurable panelists (~/.claude/panel/config.yml). Triggered by the validate-recommendation hook; do not invoke manually.
---

# Validate Recommendation

You were invoked because the `validate-recommendation` hook fired on an
`AskUserQuestion` call that contained a `(Recommended)` option marker.
Your job: dispatch an N-panelist review (where N comes from
`~/.claude/panel/config.yml`), aggregate the verdicts into a JSON
directive, and act on it.

The panel composition is **configurable** — defaults to one Devil's
Advocate via Nemotron (`nat-nim` backend), and any number of additional
panelists (PE, QA, etc.) can be opted in by setting `enabled: true` in
`config.yml`. This skill is config-driven; it does NOT assume two
fixed panelists.

## Inputs

The hook wrote tool input to a session state file:

```
STATE_FILE="${TMPDIR:-/tmp}/claude-panel-${CLAUDE_SESSION_ID:-$PPID}.json"
```

When `CLAUDE_SESSION_ID` is unset, both hook and skill resolve `$PPID`
to the same value (the Claude Code parent process), so the skill reads
exactly the file the hook wrote. Two concurrent CC sessions get
different `$PPID`s and therefore different state-file paths — the old
`-unknown` sentinel collided across sessions.

Read it via the `Read` tool. If the file is missing, emit the
user-visible message "Panel state file missing; asking the original
question." and fall back to issuing the original `AskUserQuestion`
unmodified. Stop here.

The panel config:

```
CONFIG="${HOME}/.claude/panel/config.yml"
```

State file keys you'll use:
- `tool_input.questions` — array of question objects (1-4 per the
  AskUserQuestion schema)
- `timeout_seconds` — per-panelist budget (default 90)

## Setup

```bash
export PYTHONPATH="$HOME/.claude${PYTHONPATH:+:$PYTHONPATH}"
```

This ensures `import tool` (the shared engine) resolves at runtime.
All subsequent `python3.12 -m panel …` calls inherit this setting.

### 1. Validate the config

Run via the `Bash` tool:

```bash
cd "${HOME}/.claude/skills/validate-recommendation" && \
    "${CLAUDE_PANEL_PYTHON:-python3.12}" -m panel lint-config --config "$CONFIG"
```

If exit code is non-zero, fall back: print "Panel disabled: config
invalid (see lint-config output)." and re-issue the original
`AskUserQuestion` unmodified. Stop.

### 2. Read enabled panelists from config

Use `jq` via Bash to enumerate enabled panelists:

```bash
jq -r '.panelists[] | select(.enabled) | "\(.id)|\(.role)|\(.backend)|\(.subagent_type // "")"' \
    <("${CLAUDE_PANEL_PYTHON:-python3.12}" -c "
import yaml, json, sys
print(json.dumps(yaml.safe_load(open('$CONFIG'))))
")
```

The yaml→json conversion runs once at skill startup. Capture the output
into a variable; each line is `<id>|<role>|<backend>|<subagent_type>`
for one enabled panelist.

(If `python3.12 -c` for yaml→json is awkward in your sandbox, the
equivalent: `python3.12 -m panel lint-config --config "$CONFIG"` prints
the same data in human-readable form; you can grep its output for the
`- <id>` lines and extract role/backend from them.)

### 2a. Resolve the panel profile (team auto-detect)

PE and QA are `enabled: false` in `config.yml` (the solo default). Enable them
for THIS dispatch only when a team context is detected, in priority order:

1. **Override:** if `CLAUDE_PANEL_PROFILE` is set — `team` forces PE+QA on,
   `solo` forces config defaults (skip steps 2–3). Read it via Bash:
   `echo "${CLAUDE_PANEL_PROFILE:-}"`.
2. **Live team:** else, call the `TeamList` tool. If it returns ≥1 active agent,
   the profile is `team`.
3. **Filesystem signal:** else, run the helper:
   ```bash
   bash "${HOME}/.claude/skills/validate-recommendation/detect-team-context.sh"
   ```
   If it prints `team`, the profile is `team`.
4. Otherwise the profile is `solo`.

If the resolved profile is `team`, enable PE+QA for this dispatch. The stock
`config.yml` keeps them `enabled: false`, and **`panel aggregate` re-derives its
panelist set from its `--config`** — so dispatching PE+QA is not enough on its own;
the aggregator would silently drop their verdicts. Write a profile-resolved config
and use it as the effective config for the REST of this run (the section-2
enumeration AND the §5 aggregator):

```bash
CONFIG_RESOLVED="${TMPDIR:-/tmp}/panel-config-resolved-${CLAUDE_SESSION_ID:-$PPID}.yml"
"${CLAUDE_PANEL_PYTHON:-python3.12}" - "$CONFIG" "$CONFIG_RESOLVED" <<'PY'
import sys, yaml
cfg = yaml.safe_load(open(sys.argv[1]))
for p in cfg.get("panelists", []):
    if p.get("id") in ("pe", "qa"):
        p["enabled"] = True
yaml.safe_dump(cfg, open(sys.argv[2], "w"))
PY
```

Re-run the section-2 enumeration against `$CONFIG_RESOLVED` (it now lists three
panelists — the two added rows are `pe|PE|claude-subagent|principal-engineer` and
`qa|QA|claude-subagent|qa-engineer`) and pass `$CONFIG_RESOLVED` to the §5
aggregator. Solo profile: skip this; keep the stock `$CONFIG` (DA-only).

Cost note: PE+QA each spawn a Claude subagent — only enable in team context, and
only for genuine scope-guard forks (architecture / security / API / irreversible;
see `rules/panel.md`). Solo sessions stay DA-only.

### 3. Create the per-session workdir

```bash
WORKDIR="${HOME}/.claude/panel/work/${CLAUDE_SESSION_ID:-$PPID}"
mkdir -p "$WORKDIR" && chmod 0700 "$WORKDIR"
```

This is the directory where per-panelist verdict files land.
`panel aggregate` will read `${WORKDIR}/<id>.verdict` for each enabled
panelist after fan-out completes.

## Per-question dispatch

For EACH question in `tool_input.questions` that has an option labeled
with `(Recommended)` AND NOT `(Recommended; Panel-flagged)`:

### 1. Build the user prompt body

Construct from state file data:

```
Question: <question text>
Options (verbatim labels and descriptions):
  <option 1 label> — <option 1 description>
  <option 2 label> — <option 2 description>
  ...
Assistant's recommended option: <recommended label>
Assistant's stated reasoning: <see "Reasoning extraction" below>
```

Write to a per-question prompt file:

```
PROMPT_FILE="${TMPDIR:-/tmp}/panel-prompt-${CLAUDE_SESSION_ID}-q<N>.txt"
```

Where `<N>` is the question index (0-based).

### 2. Reasoning extraction

The "stated reasoning" passed to panelists comes from:

1. The recommended option's `description` field (primary source).
2. The question's lead text, if it contains rationale phrases.

If neither is informative, pass `(no reasoning supplied)`. Panelists
are told this is acceptable input. NEVER attempt to read or fabricate
hidden chain-of-thought.

### 3. Fan out N panelists in ONE message

**This is the parallelism point. All panelist dispatches MUST be in a
single message so they run concurrently.**

For EACH enabled panelist from the config enumeration above:

- **If `backend` starts with `nat-` (e.g., `nat-nim`):** include a
  `Bash` tool call in your fan-out message. Export `CLAUDE_SESSION_ID`
  from the state file's `session_id` field in the SAME command —
  `panel/trace.py` reads it from the environment for verdict-line
  telemetry, and it is otherwise never a real exported variable (only
  ever referenced with a `${CLAUDE_SESSION_ID:-$PPID}` fallback), which
  is why trace lines were showing `session=unknown`:

  ```bash
  export CLAUDE_SESSION_ID="$(jq -r '.session_id' "${TMPDIR:-/tmp}/claude-panel-${CLAUDE_SESSION_ID:-$PPID}.json")" && \
  cd "${HOME}/.claude/skills/validate-recommendation" && \
      "${CLAUDE_PANEL_PYTHON:-python3.12}" -m panel dispatch \
      --panelist "<id>" \
      --config "$CONFIG" \
      --persona "${HOME}/.claude/skills/validate-recommendation/personas/<role-lowercase>.md" \
      --prompt-file "$PROMPT_FILE" \
      --output "${WORKDIR}/<id>.verdict"
  ```

  `dispatch.py` writes the verdict file directly (mode 0600). Auth
  comes from per-backend env vars (`nat-nim`: `$PANEL_DA_API_KEY`,
  falling back to `$NVIDIA_API_KEY`; `nat-anthropic`:
  `$ANTHROPIC_API_KEY`; `nat-openai`: `$OPENAI_API_KEY`).

- **If `backend` is `claude-subagent`:** include an `Agent` tool call
  in your fan-out message:
  - `subagent_type`: the panelist's `subagent_type` from config (e.g.,
    `principal-engineer`, `qa-engineer`)
  - `description`: short, e.g., `"Panel <role> review"`
  - `prompt`: the concatenation of the persona file's `# System prompt`
    section, the `# One-shot example` section (if present), and the
    user prompt body from step 1.

  Read the persona file via the `Read` tool BEFORE composing the
  fan-out message:
  `${HOME}/.claude/skills/validate-recommendation/personas/<role-lowercase>.md`.

All `Bash` + `Agent` calls go in ONE message. The framework executes
them concurrently.

### 4. Collect verdict files after fan-out returns

When the fan-out message's tool results come back:

- **`nat-*` panelists:** `dispatch.py` already wrote the verdict file.
  Nothing to do.
- **`claude-subagent` panelists:** the `Agent` tool returned a string.
  Write the ENTIRE response verbatim to the verdict file via the
  `Write` tool:

  ```
  ${WORKDIR}/<id>.verdict
  ```

  Do NOT alter, summarize, or extract from the Agent response. The
  aggregator parses `VERDICT:`/`RATIONALE:`/`ALTERNATIVE:` lines from
  the verbatim text; surrounding prose is ignored.

### 5. Run the aggregator

Same rule as dispatch: export `CLAUDE_SESSION_ID` from the state file's
`session_id` inside this SAME command, so the aggregator's trace lines
carry the real session instead of `session=unknown`.

```bash
DIRECTIVE_JSON=$(export CLAUDE_SESSION_ID="$(jq -r '.session_id' "${TMPDIR:-/tmp}/claude-panel-${CLAUDE_SESSION_ID:-$PPID}.json")" && \
    cd "${HOME}/.claude/skills/validate-recommendation" && \
    "${CLAUDE_PANEL_PYTHON:-python3.12}" -m panel aggregate \
    --config "${CONFIG_RESOLVED:-$CONFIG}" \
    --verdicts-dir "$WORKDIR" \
    --recommended-label "<recommended_label from state for THIS question>")
```

Capture stdout into `$DIRECTIVE_JSON`. It's a single-line JSON object.

### 6. Parse the directive

Extract fields via `jq`:

```bash
VERDICT=$(jq -r '.verdict' <<< "$DIRECTIVE_JSON")
SUMMARY=$(jq -r '.summary' <<< "$DIRECTIVE_JSON")
ESCALATE=$(jq -r '.escalate_to_user // false' <<< "$DIRECTIVE_JSON")
GATE=$(jq -r '.rationale_gate_passed' <<< "$DIRECTIVE_JSON")
```

Values:
- `VERDICT` ∈ `{HOLD, SOFT-DISSENT, HARD-DISSENT, ERROR}`
- `SUMMARY` — one-line user-facing text, already sanitized
- `ESCALATE` — `true` for HARD-DISSENT in Phase 3c, `false` otherwise
- `GATE` — `true`/`false`/`null` per the rationale gate semantics

## Acting on the directive

Behavior matrix:

### `VERDICT == "HOLD"`

Behavior depends on `${CLAUDE_PANEL:-on}`:

**Default (`on`)** — auto-take mode:

The recommendation stands. Take the recommended option without asking
the user. Print a brief message:

> Panel validated `<recommended_label>` for "<question excerpt>".
> <SUMMARY>
> Proceeding.

Then continue the work as if the user had picked the recommended
option. The `AskUserQuestion` for this question is NEVER issued.

**`advise`** — advisory mode (preserves user agency):

Do NOT auto-take. Re-issue `AskUserQuestion` for this question with
the panel's affirmative annotation appended. Augmented payload:

- **Question text**: original question + two newlines +
  `**Panel validated:** <SUMMARY>` (positive phrasing).
- **Options**: identical, EXCEPT the recommended option's label has
  `(Recommended)` swapped for `(Recommended; Panel-flagged)`. The hook
  detects this marker and skips the panel on the re-ask.

### `VERDICT == "SOFT-DISSENT"`

Re-issue `AskUserQuestion` for this question. Augmented payload:

- **Question text**: original + two newlines + `<SUMMARY>` (the
  `**Panel review:**` line). Use it verbatim.
- **Options**: identical, EXCEPT the recommended option's label is
  swapped to `(Recommended; Panel-flagged)`.

### `VERDICT == "HARD-DISSENT"`

In Phase 3c, HARD-DISSENT also escalates to the user (Phase 5 will add
re-think cycles). Same payload as SOFT-DISSENT, but include severity
in the augmented note:

- **Question text**: original + two newlines + `Panel HARD-DISSENT:
  <SUMMARY>` (severity-clear prefix).
- **Options**: identical, EXCEPT marker swap to
  `(Recommended; Panel-flagged)`.

When Phase 5 lands, this branch will check `re_brainstorm` in the
directive and emit a re-think markdown directive (no `AskUserQuestion`)
when present. Until then, every HARD-DISSENT escalates the question to
the user with full panel feedback.

### `VERDICT == "ERROR"`

Something went wrong (panelist backend down, malformed responses,
missing files, aggregator parse error). For this question, re-issue
the original `AskUserQuestion` unmodified — same options, same
`(Recommended)` marker — BUT swap the marker to
`(Recommended; Panel-flagged)` for loop safety.

Print a brief explanation:

> Panel evaluation failed for "<question excerpt>" (see hook trace
> for detail). Asking the question directly.

## Cleanup

After processing ALL questions (HOLD + DISSENT + ERROR paths), remove
every file this run created — **one explicit path per `rm -f` argument,
never a glob (`*`)**. Under zsh, an unmatched glob aborts the ENTIRE
command line, not just that argument — so a single `rm -f a b* c` where
`b*` matches nothing removes NEITHER `a` NOR `c` either. This is the
root cause of the leak this section exists to close: a bare
`panel-prompt-*-q*.txt` glob that matched nothing silently left
`$STATE_FILE` on disk too, and the hook's re-entry guard then bypassed
the NEXT, unrelated paneled question it saw.

```bash
rm -rf "$WORKDIR"
rm -f "$STATE_FILE"
```

Then remove each per-question prompt file you actually wrote, one
`rm -f` per exact path — using the same 0-based indices you dispatched
in the per-question loop above (you know how many questions you
processed; do not glob `-q*.txt`):

```bash
rm -f "${TMPDIR:-/tmp}/panel-prompt-${CLAUDE_SESSION_ID}-q0.txt"
rm -f "${TMPDIR:-/tmp}/panel-prompt-${CLAUDE_SESSION_ID}-q1.txt"
# ... one rm -f per question index you actually dispatched a prompt file
# for. Skip indices that were never a (Recommended) question — there is
# no file for them, and rm -f on a path that doesn't exist is a no-op.
```

If step 2a resolved a team profile, `$CONFIG_RESOLVED` holds the exact
resolved-config path already — remove that path directly (it is a
single concrete path, not a glob):

```bash
if [ -n "${CONFIG_RESOLVED:-}" ]; then
    rm -f "$CONFIG_RESOLVED"
fi
```

If you crash before cleanup, stale files are harmless PROVIDED
`CLAUDE_SESSION_ID` is unique per session (different session = different
path). The hook's re-entry guard on `$STATE_FILE` is now stale-aware —
age >= 600s discards the leftover and replaces it with a fresh trigger
instead of bypassing indefinitely — so a leftover `$STATE_FILE` from a
crashed run self-heals within 10 minutes even if this cleanup never
runs. `panel gc` will eventually reap stale workdirs (Phase 6).

## Failure modes you must handle gracefully

| What goes wrong | Behavior |
|---|---|
| State file missing | Print fallback message; re-issue original `AskUserQuestion`. |
| `panel lint-config` fails | Print "Panel disabled: config invalid"; re-issue original. |
| `~/.claude/panel/config.yml` missing | Caught by `lint-config`; same fallback. |
| Persona file missing for a configured role | Fall back. Print "Panel personas unavailable for <role>"; re-issue original. |
| `panel dispatch` crashes (caller-bug exit 1) | Verdict file not written. Aggregator coerces to ERROR for that panelist. Severity decides per failure_mode. |
| `panel dispatch` exits 0 but writes ERROR verdict | Normal path. Severity decides per failure_mode. |
| `Agent` tool call errors / returns garbled output | Write verbatim to verdict file; aggregator coerces to ERROR for that panelist if `VERDICT:` line is missing. |
| `panel aggregate` crashes (non-zero exit) | Fall back. Re-issue original with marker swap. |
| `$WORKDIR` unwritable | Fall back. Print "Panel infrastructure unavailable". |
| Missing API keys (e.g., `$PANEL_DA_API_KEY`) | `dispatch.py` writes ERROR verdict; aggregator emits ERROR directive (at N=1) or degrades (at N>=3 with graceful failure_mode). User-facing message ends up as re-ask original. |

The whole panel is best-effort. The user-visible question ALWAYS
survives.

### Loop safety on fallback

When you fall back to re-issuing the original `AskUserQuestion`, the
original payload still has `(Recommended)` — meaning the hook will
fire AGAIN. The hook has a re-entry guard: if a state file for the
current session already exists when the hook runs, and it is fresh
(age < 600s — always true for an immediate fallback re-issue), the
hook removes it and approves (exit 0) without dispatching the skill
again. So your fallback re-issue is mechanically safe.

As a courtesy to future readers, swap the marker to
`(Recommended; Panel-flagged)` in your fallback re-issue (it documents
intent even though the re-entry guard makes it a no-op for safety).

## Multi-question parallelism (optional optimization)

If the `AskUserQuestion` call had multiple questions each with a
`(Recommended)` marker, you MAY dispatch panel calls for ALL
questions in parallel: fan out the N panelists × M questions in one
message. Aggregate runs per question after both panelists return.

For v1, sequential per-question dispatch is fine. Optimize only if
multi-question recommendations become common (they aren't currently).

## What you must NOT do

- Do NOT echo `$PANEL_DA_API_KEY` (or any other API key) in any
  user-facing text or trace output.
- Do NOT write API keys to any file.
- Do NOT modify or summarize the Agent tool's response before writing
  it to the verdict file. Write verbatim; let the aggregator parse.
- Do NOT modify the `AskUserQuestion` call beyond augmenting question
  text (for dissents) or swapping the marker (for ERROR or fallback).
- Do NOT re-invoke this skill after auto-taking a HOLD recommendation.
  The work continues as if the user picked.
- Do NOT introduce a panelist not in `config.yml`. New panelists ship
  via `config.yml` + a persona file under `personas/<role>.md` — never
  ad-hoc in this file.
- Do NOT call `python3.12 -m panel ...` for JSON parsing. Use `jq`.
  Python invocation is reserved for `lint-config`, `dispatch`, and
  `aggregate`.
- Do NOT bypass the hook re-entry guard by clearing the state file
  yourself. The guard exists to break loops on fallback paths.
