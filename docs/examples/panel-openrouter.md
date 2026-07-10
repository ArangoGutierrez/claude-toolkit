# Example: validate-recommendation panel on OpenRouter

## What this shows

The validate-recommendation panel reviews every `(Recommended)` option in an
`AskUserQuestion` by dispatching one or more configured panelists. This page
dispatches a single devil's-advocate (`DA`) panelist against a sample question
and captures its verdict, running the panelist's `nat-openai` backend against
a `:free` OpenRouter model.

## Setup

Engine dependencies installed? See [OpenRouter free tier](../patterns/openrouter-free-tier.md) — one pip install.

Copy the panel config template into place (see
[Panel Config](../patterns/panel-config.md)):

```bash
cp .claude/panel/config.yml.template ~/.claude/panel/config.yml
```

The template's `da` panelist already targets the `nat-openai` backend with a
`:free` catalog model:

```yaml
panelists:
  - id: da
    role: DA
    enabled: true
    backend: nat-openai
    model: nvidia/nemotron-3-ultra-550b-a55b:free   # OpenRouter catalog ID ($0)
```

Point the OpenAI-compatible env vars at OpenRouter:

```bash
export OPENAI_BASE_URL=https://openrouter.ai/api/v1
export OPENAI_API_KEY=sk-or-...                       # your OpenRouter key
```

## Run

Write a sample question to a prompt file in the DA persona's template shape,
then dispatch the panelist:

```bash
cat > /tmp/panel-prompt.txt <<'EOF'
Question: Which HTTP client should a small Go service use?
Options (verbatim labels and descriptions):
  Option A (Recommended) — net/http; standard library, zero dependencies
  Option B — resty; third-party client with built-in retries
  Option C — fasthttp; faster but an incompatible interface
Assistant's recommended option: Option A (Recommended)
Assistant's stated reasoning: The standard library covers the service's needs and avoids dependency and maintenance cost.
EOF

PYTHONPATH="$PWD/.claude:$PWD/.claude/skills/validate-recommendation" \
  python3.12 -m panel dispatch --panelist da \
  --config ~/.claude/panel/config.yml \
  --persona .claude/skills/validate-recommendation/personas/da.md \
  --prompt-file /tmp/panel-prompt.txt --output /tmp/da.verdict
cat /tmp/da.verdict
```

The DA persona emits a strict `VERDICT: HOLD | OVERTURN` line with a rationale
and, on `OVERTURN`, the verbatim option label it prefers instead.

## Output (captured live via an OpenAI-compatible endpoint, 2026-07-10 — the structure is identical on OpenRouter):

```text
VERDICT: OVERTURN
RATIONALE: The recommendation assumes the standard library "covers the service's needs" without knowing what those needs are. For any service making outbound HTTP calls, automatic retry with backoff is a near-universal resilience requirement; net/http provides none, forcing the team to write and maintain custom retry logic — a subtle, error-prone task that resty solves out of the box. Dismissing a mature, well-maintained dependency like resty on principle ignores the hidden maintenance cost of reimplementing its core features poorly.
ALTERNATIVE: Option B — resty; third-party client with built-in retries
```

The panelist overturned the recommendation and named a concrete alternative
(`Option B`) — exactly the adversarial second opinion the panel exists to
surface before a `(Recommended)` option is auto-accepted.

## Privacy

This example sends the sample question through OpenRouter's free tier.
OpenRouter free routes may log prompts for provider training; use a paid route
or a self-hosted endpoint for panelists reviewing sensitive design decisions.
