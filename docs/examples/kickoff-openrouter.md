# Example: kickoff enrichment on OpenRouter

## What this shows

The `/kickoff` skill turns a one-line idea into a scoped prompt, a routed
skill list, and a runnable verification checklist. Under the hood its
`enrich.sh` shim calls the shared agentic engine (`tool.kickoff`), which runs
a tool-calling LLM loop that inspects the repo before answering. This page
runs that engine end to end against a `:free` OpenRouter model — no paid key,
no mock.

## Setup

Engine dependencies installed? See [OpenRouter free tier](../patterns/openrouter-free-tier.md) — one pip install.

Point the generic OpenAI-compatible env vars at OpenRouter and route the
kickoff engine through the `nat-openai` backend (see
[OpenRouter Free-Tier Backend](../patterns/openrouter-free-tier.md)):

```bash
export OPENAI_BASE_URL=https://openrouter.ai/api/v1
export OPENAI_API_KEY=sk-or-...                       # your OpenRouter key
export KICKOFF_BACKEND=nat-openai
export KICKOFF_MODEL=nvidia/nemotron-3-ultra-550b-a55b:free
```

## Run

From a repo checkout, feed the engine a rough idea:

```bash
PYTHONPATH="$PWD/.claude" \
  bash .claude/skills/kickoff/scripts/enrich.sh --mode interactive \
  'add a --json flag to my CLI tool'
```

`enrich.sh` is fail-open: on any engine or model error it prints a
`KICKOFF_PASSTHROUGH:` marker and exits 0, so a missing key never blocks your
session. A successful run starts with a `## Kickoff` block.

## Output (captured live via an OpenAI-compatible endpoint, 2026-07-10 — the structure is identical on OpenRouter):

```text
## Kickoff
**Scoped prompt:** Add a `--json` flag to the `deploy.sh` CLI script that outputs deployment results in structured JSON format. When `--json` is provided, the script should emit a single JSON object to stdout containing: deployment status (success/failure), dry-run mode flag, backup info (path or skipped), deployed components (.claude, .cursor), verification results (key files, hooks, JSON validation), and any errors. The existing human-readable output should remain on stderr when `--json` is used. Apply the same pattern to `capture.sh` and `diff.sh` for consistency.
**Intent:** The deploy/capture/diff scripts are the primary CLI interface for this toolkit. Adding `--json` enables programmatic consumption by CI/CD pipelines, automation scripts, and other tools that need structured deployment/capture/diff results without parsing human-readable output.
**Out of scope:**
- Do not modify the public API of any Python modules (none exist in this repo)
- Do not change existing flag behavior or default output format
- Do not add external dependencies (jq, python) for JSON generation — use bash built-ins
- Do not modify sync-lib.sh or other shared libraries
- Only modify scripts/deploy.sh, scripts/capture.sh, scripts/diff.sh
**Skills:** none
**Execution:** solo
**Budget:** 300k
**Grounded in:** README.md, scripts/capture.sh, scripts/deploy.sh, scripts/diff.sh, scripts/graphify-bootstrap_test.sh
**Verification checklist:**
- [REJECTED: shell metacharacter '>'] deploy.sh --json outputs valid JSON with expected fields — `bash scripts/deploy.sh --dry-run --json 2>/dev/null | python3 -c "import json,sys; json.load(sys.stdin); print('OK')"`
- [REJECTED: shell metacharacter '>'] deploy.sh --json includes deployment status, backup info, verification results — `bash scripts/deploy.sh --dry-run --json 2>/dev/null | python3 -c "import json,sys; d=json.load(sys.stdin); assert 'status' in d and 'backup' in d and 'verification' in d; print('OK')"`
- [REJECTED: shell metacharacter '>&'] deploy.sh without --json still works normally — `bash scripts/deploy.sh --dry-run --help 2>&1 | head -20`
- [REJECTED: shell metacharacter '>&'] capture.sh --json outputs valid JSON — `bash scripts/capture.sh --help 2>&1 | head -10`
- [REJECTED: shell metacharacter '>&'] diff.sh --json outputs valid JSON — `bash scripts/diff.sh --help 2>&1 | head -10`

Acceptance (runnable):
(none proven runnable)
```

The engine grounded its answer in the repo's actual files (`deploy.sh`,
`capture.sh`, `diff.sh`) — it read them during the tool-calling loop before
scoping the prompt. The `[REJECTED: ...]` markers are the validator rejecting
checklist commands that contain shell metacharacters, a guardrail against
suggesting unsafe verification commands.

## Privacy

This example sends your prompt through OpenRouter's free tier. OpenRouter
free routes may log prompts for provider training; use a paid route or a
self-hosted endpoint for anything sensitive.
