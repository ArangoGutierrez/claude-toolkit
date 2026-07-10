---
name: done
description: Confirm or abandon the session goal with NAT-backed evidence evaluation. Triggered by /done, /done confirm, /done abandon <reason>, /done amend <text>, /done override [reason].
user-invocable: true
tools:
  - Bash
  - Read
---

# /done

Surfaces a candidate verdict against the captured session goal using a NAT-backed goal-evaluator panelist, and writes the authoritative `user.verdict` into the daily outcomes log.

## When to use

- End of a session, when the user believes the goal has been met (or not).
- When the user wants to record `ABANDONED <reason>` or amend the goal.

## Subcommands

| Subcommand | Behavior |
|---|---|
| `/done` or `/done confirm` | Read latest outcomes evidence + last goal stanza. Invoke NAT goal-evaluator. AGREE → write `user.verdict=MET`. DISAGREE → surface NAT rationale; ask user to override or amend. INSUFFICIENT → ask user for explicit verdict using NAT's `GAPS`. NAT ERROR → fall through to `user_only`. |
| `/done abandon <reason>` | Skip NAT call. Write `user.verdict=ABANDONED` with `reason=<reason>`. |
| `/done amend <text>` | Forward to `/goal amend <text>`; no outcomes entry written. |
| `/done override [reason]` | Skip NAT call. Write `user.verdict=MET` with `evaluator=user_override`, `nat_verdict=OVERRIDDEN`, and `reason=<reason>` (default `"user override"` if omitted). |

`override` exists because the user is authoritative and NAT is advisory: when NAT's DISAGREE
or INSUFFICIENT_EVIDENCE verdict is wrong (e.g. it misread evidence), the user needs a way to
close the goal without either being stuck in a `confirm` loop or having to lie about NAT's
verdict — `override` records the disagreement honestly via `evaluator=user_override` /
`nat_verdict=OVERRIDDEN`, it does not fake an `AGREE`.

## Implementation

The skill runs `~/.claude/skills/done/done.sh` (and `eval.py`) via Python 3.12. **Run with the
sandbox disabled** — `done.sh` writes the outcomes log under `~/.claude/audit/`, which the Bash
sandbox blocks. UUID resolution matches `goal.sh` (`$CLAUDE_SESSION_ID` → `$CLAUDE_CODE_SESSION_ID`
→ `$$.json` → newest-file-with-warning), so `/done` grades the right session. The Python module mirrors the validate-recommendation v3 `panel/dispatch.py` pattern: a single mockable `_invoke_nat` seam and ERROR-fallback wrapping so all NAT/HTTP/parse failures degrade gracefully to `user_only`.

## NAT model

Default model: `DONE_NAT_MODEL` env if set, else the public catalog ID
`nvidia/nemotron-3-ultra-550b-a55b:free`.

Backend: `DONE_BACKEND` selects the provider — `nat-nim` (default) or
`nat-openai` for any OpenAI-compatible endpoint, including OpenRouter.
Endpoint resolution: `DONE_NAT_ENDPOINT` if set, else (for `nat-openai`)
`OPENAI_BASE_URL`.

**Auth key resolution**: `DONE_NAT_API_KEY` if set, else (for `nat-openai`)
`OPENAI_API_KEY`.

OpenRouter :free routes may log prompts for provider training; use a paid
route or a self-hosted endpoint for sensitive work.

Private hub-specific details — internal model ID forms, the `nat-nim`
panel-fallback endpoint/key chain, and the internal endpoint host — live in
`docs/nat-hub-endpoints.md` and are never extracted to the public toolkit.

## Spec

`docs/superpowers/specs/2026-05-18-done-hook-design.md` §Component 5.
