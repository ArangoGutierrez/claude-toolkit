# Example: done goal-evidence evaluation on OpenRouter

## What this shows

The `/done` skill closes a session by grading the collected evidence against
the session goal. Its `eval.py` reads a JSON payload — the goal stanza, the
evidence bullets accrued during the session, and the user's MET/UNMET claim —
and returns a JSON verdict: `AGREE`, `DISAGREE`, or `INSUFFICIENT_EVIDENCE`.
This page runs that evaluator against a `:free` OpenRouter model.

## Setup

Engine dependencies installed? See [OpenRouter free tier](../patterns/openrouter-free-tier.md) — one pip install.

Route the done evaluator through the `nat-openai` backend and point the
OpenAI-compatible env vars at OpenRouter (see
[OpenRouter Free-Tier Backend](../patterns/openrouter-free-tier.md)):

```bash
export OPENAI_BASE_URL=https://openrouter.ai/api/v1
export OPENAI_API_KEY=sk-or-...                       # your OpenRouter key
export DONE_BACKEND=nat-openai
export DONE_NAT_MODEL=nvidia/nemotron-3-ultra-550b-a55b:free
```

## Run

Feed `eval.py` a payload on stdin:

```bash
printf '%s' '{"goal_stanza":"Goal: demo\nAcceptance:\n- tests pass","evidence":[{"bullet":"tests pass","raw":"pytest: 12 passed"}],"user_claim":"MET"}' \
  | PYTHONPATH="$PWD/.claude" python3.12 .claude/skills/done/eval.py
```

On any internal failure (model unreachable, unparsable response) the
evaluator returns `{"verdict": "ERROR", ...}` and the `/done` skill falls back
to the user's own claim — the evaluation never blocks closing a session.

## Output (captured live via an OpenAI-compatible endpoint, 2026-07-10 — the structure is identical on OpenRouter)

```json
{"verdict": "AGREE", "rationale": "The acceptance criterion \"tests pass\" is directly supported by the evidence record showing \"pytest: 12 passed\", which indicates that the test suite executed successfully with all tests passing. This satisfies the requirement that tests pass, as the evidence demonstrates a successful test run with zero failures. No contradictory information is present.", "gaps": []}
```

The evaluator agreed with the user's `MET` claim because the single evidence
bullet directly satisfies the lone acceptance criterion. A missing or
contradictory bullet would instead yield `DISAGREE` or
`INSUFFICIENT_EVIDENCE`, with the shortfall named in `gaps`.

## Privacy

This example sends the goal stanza and evidence through OpenRouter's free
tier. OpenRouter free routes may log prompts for provider training; use a paid
route or a self-hosted endpoint for anything sensitive.
