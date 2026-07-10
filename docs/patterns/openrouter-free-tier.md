# Pattern: OpenRouter Free-Tier Backend

## What

The toolkit's [agentic engine](../architecture.md#the-agentic-engine) can run its
LLM calls — kickoff enrichment, the validate-recommendation panel, the done
evaluator — against a zero-cost model instead of a paid API key. OpenRouter
publishes `:free` variants of several catalog models; pointed through the
`nat-openai` backend, they work as a drop-in for local development, CI dry
runs, or trying the toolkit before committing to a paid provider.

## How

Install the engine's Python dependencies first (Python 3.12+):

    pip install langchain-openai pyyaml requests

(`langchain-openai` pulls the OpenAI-compatible client; the panel's config
loader needs `pyyaml`; the engine's HTTP timeout shim needs `requests`.
Backends other than nat-openai need their own langchain provider package.)

`nat-openai` is one of three backends `tool.backends` knows how to build a
chat client for (the others are `nat-nim` and `nat-anthropic`). It targets
any OpenAI-compatible `/chat/completions` endpoint, OpenRouter included.

1. Create a free OpenRouter account and API key.
2. Point the generic OpenAI-compatible env vars at OpenRouter:

   ```bash
   export OPENAI_BASE_URL=https://openrouter.ai/api/v1
   export OPENAI_API_KEY=<your-openrouter-key>
   ```

3. Select a `:free` catalog model. The toolkit's own default is
   `nvidia/nemotron-3-ultra-550b-a55b:free` — a 1M-context model at $0 on
   OpenRouter's free tier. It is used as the fallback default in `tool/kickoff.py`
   and `skills/done/eval.py`.
4. Route the component you're using to the `nat-openai` backend, e.g.
   `KICKOFF_BACKEND=nat-openai` or `DONE_BACKEND=nat-openai`, or set
   `backend: nat-openai` for a panelist in `~/.claude/panel/config.yml`.

## Env

| Var | Purpose |
|---|---|
| `OPENAI_BASE_URL` | `https://openrouter.ai/api/v1` for OpenRouter |
| `OPENAI_API_KEY` | your OpenRouter API key |
| `KICKOFF_BACKEND` / `DONE_BACKEND` / panel `backend:` | set to `nat-openai` to route through this pattern |
| `KICKOFF_MODEL` / `DONE_NAT_MODEL` / panel `model:` | a `:free`-suffixed catalog ID, e.g. `nvidia/nemotron-3-ultra-550b-a55b:free` |

## Pitfalls

- **Privacy.** OpenRouter :free routes may log prompts for provider training;
  use a paid route or a self-hosted endpoint for sensitive work.
- **Rate limits.** Free-tier routes are throttled more aggressively than paid
  routes; expect occasional 429s under sustained use (e.g. a long kickoff
  enrichment loop).
- **Model availability.** OpenRouter can retire or rename `:free` variants
  without notice — pin the exact ID you tested against and re-verify it
  resolves (`curl` the OpenRouter models endpoint) before relying on it in CI.
- **Never use a hub-form ID here.** OpenRouter (and every public catalog)
  expects single-namespace IDs like `nvidia/nemotron-3-ultra-550b-a55b:free`.
  Double-namespace ("hub-form") IDs are an internal-catalog artifact and will
  simply 404 against a public endpoint — see
  [Model ID Hygiene](model-id-hygiene.md).
