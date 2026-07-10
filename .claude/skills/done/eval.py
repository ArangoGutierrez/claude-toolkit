"""done/eval.py — NAT-backed goal evidence evaluator.

Mirrors the validate-recommendation v3 panel/dispatch.py pattern:
one mockable _invoke_nat seam + ERROR-fallback wrapping.
"""
from __future__ import annotations

import json
import os
import pathlib
import sys
from typing import Any, Literal

Verdict = Literal["AGREE", "DISAGREE", "INSUFFICIENT_EVIDENCE", "ERROR"]

PERSONA_PATH = pathlib.Path(__file__).parent / "personas" / "goal-evaluator.md"

# eval.py runs standalone (done.sh pipes JSON to it), so put the .claude root
# on sys.path before importing the shared engine seam.
_CLAUDE_ROOT = pathlib.Path(__file__).resolve().parents[2]
if str(_CLAUDE_ROOT) not in sys.path:
    sys.path.insert(0, str(_CLAUDE_ROOT))
from tool.backends import invoke_llm  # noqa: E402 — path bootstrap above

# Public catalog form (single nvidia/ namespace — OpenRouter ID). Private
# deploys override via the DONE_NAT_MODEL env (settings.json env block).
DEFAULT_MODEL = "nvidia/nemotron-3-ultra-550b-a55b:free"


def _resolve_base_url() -> str | None:
    """DONE_NAT_ENDPOINT wins. The panel's endpoint is a nat-nim-only fallback;
    for any other backend, return None and let tool.backends resolve its own
    env (e.g. OPENAI_BASE_URL). Strips a /chat/completions suffix."""
    url = os.environ.get("DONE_NAT_ENDPOINT")
    if not url and os.environ.get("DONE_BACKEND", "nat-nim") == "nat-nim":
        url = os.environ.get("CLAUDE_PANEL_DA_ENDPOINT")
    if not url:
        return None
    suffix = "/chat/completions"
    return url[: -len(suffix)] if url.endswith(suffix) else url


def _resolve_api_key() -> str | None:
    """DONE_NAT_API_KEY wins (done-specific override). The PANEL_DA/NVIDIA
    chain applies only to nat-nim — sending an nvapi- key to a non-NVIDIA
    endpoint 401s (LiteLLM virtual-key class, 2026-07-06)."""
    key = os.environ.get("DONE_NAT_API_KEY")
    if key:
        return key
    if os.environ.get("DONE_BACKEND", "nat-nim") != "nat-nim":
        return None
    return os.environ.get("PANEL_DA_API_KEY") or os.environ.get("NVIDIA_API_KEY")


def _invoke_nat(prompt: str, model: str, max_tokens: int = 32768) -> str:
    """Single mockable seam. Raises on any failure — caller wraps in ERROR-fallback.

    Dispatches through tool.backends.invoke_llm (the shared engine seam);
    DONE_BACKEND selects the provider (default nat-nim), DONE_NAT_* env
    overrides thread through as explicit args.
    """
    backend = os.environ.get("DONE_BACKEND", "nat-nim")
    response = invoke_llm(
        backend=backend, model=model, system="", user=prompt,
        temperature=0.1, max_tokens=max_tokens,
        base_url=_resolve_base_url(), api_key=_resolve_api_key(),
    )
    content = getattr(response, "content", None)
    if isinstance(content, str):
        return content
    if isinstance(content, list):
        # Flatten list-of-dicts to text
        parts = []
        for item in content:
            if isinstance(item, dict) and "text" in item:
                parts.append(item["text"])
            else:
                parts.append(str(item))
        return "".join(parts)
    return str(content) if content is not None else ""


def _parse_verdict(raw: str) -> dict[str, Any]:
    """Parse the strict 'VERDICT: ... / RATIONALE: ... / GAPS: ...' format."""
    lines = raw.strip().splitlines()
    out: dict[str, Any] = {"verdict": "ERROR", "rationale": "", "gaps": []}
    for line in lines:
        if line.startswith("VERDICT:"):
            v = line.split(":", 1)[1].strip()
            if v in ("AGREE", "DISAGREE", "INSUFFICIENT_EVIDENCE"):
                out["verdict"] = v
        elif line.startswith("RATIONALE:"):
            out["rationale"] = line.split(":", 1)[1].strip()
        elif line.startswith("GAPS:"):
            g = line.split(":", 1)[1].strip()
            out["gaps"] = [] if g == "n/a" else [x.strip() for x in g.split(",")]
    return out


def collect_evidence(log_lines: str) -> list[dict[str, Any]]:
    """Merge evidence across ALL outcomes entries (one JSON object per line).

    Union keyed by bullet text: a later entry's item refreshes its bullet in
    place; an entry missing the bullet (or with empty evidence — e.g. done.sh
    user entries) never removes it. Malformed lines are skipped. Replaces the
    old grep|tail -1 single-entry window that dropped accrued evidence.
    """
    merged: dict[str, dict[str, Any]] = {}
    for line in log_lines.splitlines():
        line = line.strip()
        if not line:
            continue
        try:
            entry = json.loads(line)
        except ValueError:
            continue
        if not isinstance(entry, dict):  # a corrupt `null`/`42`/list line is malformed too
            continue
        items = entry.get("evidence")
        if not isinstance(items, list):
            continue
        for item in items:
            if not isinstance(item, dict):
                continue
            bullet = item.get("bullet")
            if not isinstance(bullet, str) or not bullet:
                continue
            merged[bullet] = item
    return list(merged.values())


def evaluate(
    goal_stanza: str,
    evidence: list[dict[str, Any]],
    user_claim: str,
    model: str | None = None,
) -> dict[str, Any]:
    """Evaluate evidence against goal; return {verdict, rationale, gaps}.

    On any internal failure (NAT unavailable, parse error, model error),
    returns {verdict: "ERROR", rationale: "<reason>", gaps: []}. The caller
    falls through to user_only.
    """
    model = model or os.environ.get("DONE_NAT_MODEL") or DEFAULT_MODEL
    try:
        persona = PERSONA_PATH.read_text()
    except OSError as exc:
        return {"verdict": "ERROR", "rationale": f"persona load failed: {exc}", "gaps": []}

    prompt = (
        f"{persona}\n\n"
        f"## Goal stanza\n{goal_stanza}\n\n"
        f"## Evidence collected\n{json.dumps(evidence, indent=2)}\n\n"
        f"## User claims\n{user_claim}\n"
    )
    try:
        raw = _invoke_nat(prompt, model=model)
        result = _parse_verdict(raw)
        if result["verdict"] == "ERROR":
            result["rationale"] = "parse failed: no VERDICT line"
        return result
    except Exception as exc:  # noqa: BLE001 — ERROR fallback per spec
        return {"verdict": "ERROR", "rationale": f"NAT dispatch failed: {exc}", "gaps": []}


def main(argv: list[str]) -> int:
    """CLI entry. Reads JSON from stdin, prints JSON to stdout."""
    payload = json.load(sys.stdin)
    result = evaluate(
        goal_stanza=payload["goal_stanza"],
        evidence=payload["evidence"],
        user_claim=payload.get("user_claim", "MET"),
        model=payload.get("model"),
    )
    json.dump(result, sys.stdout)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
