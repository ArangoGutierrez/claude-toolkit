# Pattern: Panel Config

## What

The validate-recommendation panel reviews every `AskUserQuestion` whose option
labels carry `(Recommended)`. A `PreToolUse` hook fires the panel skill, which
dispatches N configured panelists and produces one verdict: **HOLD**
(auto-proceed with the recommended option), **DISSENT** (re-ask the question,
augmented with panelist reasoning), or **ERROR** (re-ask the original
question — a panelist failed to respond usefully). The panel's behavior is
entirely driven by one file, `config.yml`.

At the wire level an unblinded panelist emits HOLD or OVERTURN (see the worked
example) and a blinded one emits a CHOICE, which the aggregator maps onto the
same two votes: agreement with the recommended option is HOLD, any other
choice is OVERTURN naming that option. The aggregator then maps OVERTURN votes
into SOFT-DISSENT or HARD-DISSENT by the severity threshold.

## How

Copy the template into place and adjust it:

```bash
cp .claude/panel/config.yml.template ~/.claude/panel/config.yml
```

The template ships three enabled panelists: an adversarial `DA`, which is told
which option was recommended and argues against it, plus a blinded `PE` and
`QA`, which are not told and rank the options on their merits. Three is the
smallest odd N at which a single dissenting panelist produces a SOFT-DISSENT
rather than a hard interrupt. Set `CLAUDE_PANEL_PROFILE=solo` to fall back to
`DA` alone for one dispatch.

Each entry under `panelists:` is independent:

| Field | Meaning |
|---|---|
| `id` | short identifier used in trace/telemetry output |
| `role` | `DA` (devil's advocate), `PE` (principal engineer), `QA`, or a custom role |
| `enabled` | panelists can be toggled off without deleting their config |
| `blind` | withhold the recommendation from this panelist (`claude-subagent` only) |
| `backend` | `nat-openai`, `nat-anthropic`, `nat-nim`, or `claude-subagent` |
| `model` | catalog ID (only for the three `nat-*` backends) |
| `subagent_type` | which agent definition to spawn (only for `claude-subagent`) |
| `max_tokens`, `temperature`, `timeout_seconds` | per-panelist request tuning |

A blinded panelist gets a prompt with the recommendation removed, the
`(Recommended)` marker stripped from every label, and the options
deterministically reordered — it cannot tell which option the assistant
favoured, so its agreement is evidence rather than an echo.

Two other blocks matter beyond the panelist list: `severity.hard_threshold`
(how many panelists must agree to force a re-ask) and `re_brainstorm`
(whether/how many times a DISSENT triggers an augmented re-ask before
surfacing to the user as-is).

## Env

Panel backends resolve credentials the same way as every other
`tool.backends` caller — see the [engine env contract](../architecture.md#the-agentic-engine).
For a `nat-openai` panelist, that means `OPENAI_BASE_URL` / `OPENAI_API_KEY`
in the environment the panel runs in (see
[OpenRouter Free-Tier Backend](openrouter-free-tier.md) for a concrete
zero-cost setup). `claude-subagent` panelists need no extra env — they run
in-process as a spawned agent.

## Pitfalls

- **`blind` must match the panelist's persona.** A blinded panelist never sees
  the recommendation, so its persona asks for `CHOICE: <option label>`; an
  unblinded one judges a named recommendation and answers
  `VERDICT: HOLD|OVERTURN`. `panel lint-config` cross-checks the two and exits
  non-zero on a mismatch, because the runtime failure is silent: a reply
  carrying no `VERDICT:` line is scored ERROR for that panelist on every
  question. Blinding is supported on the `claude-subagent` backend only —
  `blind: true` on a `nat-*` panelist is rejected at config load.
- **Cost note for `claude-subagent` panelists.** A `claude-subagent` panelist
  is a full agent dispatch (its own context window, tool calls, reasoning
  turns), not a single completion request. The template enables two of them,
  so every paneled question costs roughly two agent invocations on top of the
  `DA` request. For a cheaper run, set `CLAUDE_PANEL_PROFILE=solo` for one
  dispatch, or `enabled: false` on `PE`/`QA` permanently — but note that at
  N=1 the majority threshold makes every single OVERTURN a hard interrupt.
- **`enabled: false` is not the same as deleting the entry.** Config stays in
  place so panelists can be toggled back on without re-typing the block; a
  disabled panelist still needs valid `backend`/`model` fields if it's ever
  flipped on.
- **`hard_threshold: majority` needs an odd panelist count (or a documented
  tie-break) to avoid deadlock** — an even number of enabled panelists
  split 50/50 has no majority.
- **Privacy applies here too.** For a `nat-openai` panelist pointed at
  OpenRouter, the same caveat from
  [OpenRouter Free-Tier Backend](openrouter-free-tier.md) applies: free
  routes may log prompts for provider training. Use a paid route or a
  self-hosted endpoint for panelists reviewing sensitive design decisions.
