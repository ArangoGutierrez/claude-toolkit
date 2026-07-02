# /kickoff — turn a rough idea into a scoped, goal-tracked start

`/kickoff <rough idea>` compiles a vague task opener into a **scoped prompt**, a
list of **applicable skills**, and a **verification checklist** via a cheap
tool-calling LLM that **inspects the repo** (multi-turn, read-only tools), then sets the
session goal and drops you into brainstorming — one command instead of `/goal` +
brainstorming. It is **fail-open**: if the engine is unavailable or the model
cannot be reached, your raw idea flows through untouched and the kickoff is never
blocked.

## When to use it
- You have a half-formed idea ("explore X", "could we build Y?") and want it
  sharpened into a concrete, verifiable task before you start.
- You want the session **goal + acceptance checklist** planted automatically so
  a later Stop/verification hook can check whether verification actually ran.
- You want the right skills **routed** for you instead of remembering which to invoke.
- **Not** for a task you've already scoped — call `/goal` + the implementation
  skill directly; `/kickoff` is the front door, not a required step.

## Examples

    > /kickoff add retry-with-backoff to the S3 upload client
    → The engine inspects the repo, then produces: Scoped prompt (the task,
      sharpened) + routed skills (brainstorming → writing-plans → TDD) + a
      verification checklist (unit tests for the backoff schedule, an integration
      test against a flaky stub). Sets the session goal with that checklist,
      then enters brainstorming.

    > /kickoff Read SakanaAI/fugu and assess whether we could build something similar
    → The enrichment engine was offline, so kickoff printed `KICKOFF_PASSTHROUGH:`
      and fell open — the raw idea proceeded straight into brainstorming with no
      checklist (the work was then scoped interactively). The kickoff is never the
      thing that blocks you.

## Setup

Deploy (`scripts/deploy.sh` rsyncs `.claude/` into `~/.claude/`), then configure
the engine environment:

```sh
export PANEL_DA_API_KEY=<your-api-key>          # secret; never on a command line
export CLAUDE_PANEL_DA_ENDPOINT=https://your-inference-endpoint
# export KICKOFF_MODEL=<your-tool-calling-model>  # any tool-calling model
```

The engine uses the same env as the recommendation panel (`PANEL_DA_API_KEY` +
`CLAUDE_PANEL_DA_ENDPOINT`). `KICKOFF_MODEL` selects the tool-calling model the
engine uses. Note: the enrichment engine itself is **not bundled** with this kit —
without it (or without `PANEL_DA_API_KEY`), `/kickoff` runs in fail-open
passthrough (see below); bring your own OpenAI-compatible tool-calling endpoint.

Without `PANEL_DA_API_KEY` set, or if the engine module (`~/.claude/tool/kickoff`)
is not deployed, `/kickoff` simply passes your idea through (no enrichment).

## Notes
- **Sandbox:** Run with the sandbox **disabled** — the engine reaches your
  inference endpoint and reads repo files via read-only tools (multi-turn agentic
  flow). `enrich.sh` will not block if the sandbox prevents it; it fails open.
- **Conductor integration:** `enrich.sh --mode worker` emits a non-interactive
  opening-prompt block for a fan-out/conductor skill, which falls back to its own
  static template if enrich is absent or returns `KICKOFF_PASSTHROUGH:` — a soft,
  fail-open dependency.
- **Verify:** `bash .claude/skills/kickoff/scripts/enrich_test.sh < /dev/null`
  (the discriminating tests need no network and no engine deployment).
- Related: [`goal`](../goal/), `superpowers:brainstorming`. Index:
  [`docs/skills-and-commands.md`](../../../docs/skills-and-commands.md).
