# Pattern: Panel Config

## What

The validate-recommendation panel reviews every `AskUserQuestion` whose option
labels carry `(Recommended)`. A `PreToolUse` hook fires the panel skill, which
dispatches N configured panelists and produces one verdict: **HOLD**
(auto-proceed with the recommended option), **DISSENT** (re-ask the question,
augmented with panelist reasoning), or **ERROR** (re-ask the original
question — a panelist failed to respond usefully). The panel's behavior is
entirely driven by one file, `config.yml`.

## How

Copy the template into place and adjust it:

```bash
cp .claude/panel/config.yml.template ~/.claude/panel/config.yml
```

Each entry under `panelists:` is independent:

| Field | Meaning |
|---|---|
| `id` | short identifier used in trace/telemetry output |
| `role` | `DA` (default advocate), `PE` (principal engineer), `QA`, or a custom role |
| `enabled` | panelists can be toggled off without deleting their config |
| `backend` | `nat-openai`, `nat-anthropic`, `nat-nim`, or `claude-subagent` |
| `model` | catalog ID (only for the three `nat-*` backends) |
| `subagent_type` | which agent definition to spawn (only for `claude-subagent`) |
| `max_tokens`, `temperature`, `timeout_seconds` | per-panelist request tuning |

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

- **Cost note for `claude-subagent` panelists.** A `claude-subagent` panelist
  is a full agent dispatch (its own context window, tool calls, reasoning
  turns), not a single completion request. Enabling `PE`/`QA` panelists
  (disabled by default in the template) multiplies the cost of every paneled
  question by roughly an agent invocation each — reserve them for genuinely
  high-stakes design forks, not routine `(Recommended)` options.
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
