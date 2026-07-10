"""N-panelist aggregator emitting JSON directives.

Reads ~/.claude/panel/config.yml, finds enabled panelists, reads
<verdicts-dir>/<id>.verdict for each, calls severity.decide(), serializes
the Directive to single-line JSON, prints to stdout.

The text-output 2-panelist Phase 2 version is gone — SKILL.md is being
rewritten in Phase 3c Task 4 to parse JSON via jq.
"""
from __future__ import annotations
import json
import os
import sys
from dataclasses import asdict
from pathlib import Path

from panel.config import load_config
from panel.severity import decide, ParsedVerdict
from panel.verdict import parse_verdict_file
from panel.trace import log_verdict
from panel.telemetry import append_decision


def aggregate(
    config_path: str,
    verdicts_dir: str,
    recommended_label: str,
    question_id: str | None = None,
) -> str:
    """Build the JSON directive from per-panelist verdict files.

    Returns a single-line JSON string (no trailing newline). Caller is
    responsible for printing it.

    Missing verdict files for enabled panelists are not fatal — the
    aggregator synthesizes an ERROR panelist row and lets severity.decide()
    handle it via the failure mode.

    `question_id` is an optional canonical identifier threaded into the
    decisions.jsonl telemetry row so a future user_pick/label event can
    join to it; it is null when the caller does not supply one.
    """
    cfg = load_config(config_path)
    enabled = [p for p in cfg.panelists if p.enabled]

    verdicts_path = Path(verdicts_dir).expanduser()
    parsed: list[ParsedVerdict] = []
    for p in enabled:
        f = verdicts_path / f"{p.id}.verdict"
        if not f.is_file():
            parsed.append(ParsedVerdict(
                id=p.id, role=p.role,
                verdict="ERROR",
                rationale=f"verdict file missing: {f}",
                alternative="n/a",
            ))
            continue
        v = parse_verdict_file(f)
        parsed.append(ParsedVerdict(
            id=p.id, role=p.role,
            verdict=v.verdict,
            rationale=v.rationale,
            alternative=v.alternative,
        ))

    directive = decide(cfg, parsed, cycle=None)
    log_verdict(directive.verdict, _trace_line(directive))
    _record_decision(cfg, directive, recommended_label, question_id)

    payload = _to_serializable_dict(directive)
    return json.dumps(payload, ensure_ascii=False, separators=(",", ":"))


def _record_decision(cfg, directive, recommended_label: str, question_id: str | None) -> None:
    """Append one decision row to decisions.jsonl. Best-effort.

    Wrapped so ANY failure (serialization, an unexpected directive shape,
    a bad telemetry path) is swallowed: telemetry must never break the
    stdout directive the skill parses. append_decision already swallows
    OSError internally; this guard covers everything above it.
    """
    try:
        record = {
            "event": "decision",
            "session": os.environ.get("CLAUDE_SESSION_ID", "unknown"),
            "question_id": question_id,
            "recommended_label": recommended_label,
            "verdict": directive.verdict,
            "rationale_gate_passed": directive.rationale_gate_passed,
            "panelists": [
                {"id": p.id, "role": p.role, "verdict": p.verdict}
                for p in directive.panelists
            ],
        }
        append_decision(record, cfg.telemetry.jsonl)
    except Exception as exc:  # noqa: BLE001 — telemetry is best-effort; never break the directive
        print(f"panel: telemetry write skipped ({exc})", file=sys.stderr)


def _to_serializable_dict(directive) -> dict:
    """Convert Directive to a dict with None-valued optional keys dropped."""
    raw = asdict(directive)
    # Drop optional fields when None — keeps the JSON shape clean per spec.
    if raw.get("re_brainstorm") is None:
        raw.pop("re_brainstorm", None)
    if raw.get("escalate_to_user") is None:
        raw.pop("escalate_to_user", None)
    return raw


def _trace_line(directive) -> str:
    """Format the trace log message for this aggregate call."""
    parts = []
    for p in directive.panelists:
        parts.append(f"{p.id}={p.verdict}")
    return " ".join(parts) if parts else "no-panelists"
