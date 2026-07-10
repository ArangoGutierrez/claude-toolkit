"""Append-only JSONL telemetry for panel decisions.

One `decision` record per aggregate run, appended to the path from
config (`telemetry.jsonl`). This is what makes the panel auditable:
`decisions.jsonl` has never been written since the config field was
added, so panel effectiveness has been unmeasurable.

Best-effort, modeled on trace.py: every write failure is swallowed so
telemetry can NEVER break the panel's stdout directive (the skill parses
that stdout via jq). The user-visible question always survives.

Record schema (v=1):
    v                     : schema version (1)
    event                 : "decision"
    ts                    : UTC ISO-8601, e.g. "2026-07-09T12:34:56Z"
    session               : $CLAUDE_SESSION_ID or "unknown"
    question_id           : optional canonical id; null until a caller threads one
    recommended_label     : the option the panel reviewed
    verdict               : HOLD | SOFT-DISSENT | HARD-DISSENT | ERROR
    rationale_gate_passed : true | false | null
    panelists             : [{id, role, verdict}, ...]

Panelist rationale/alternative text is intentionally NOT recorded — it
is free-form and derived from question context; telemetry stays to
non-sensitive structured signal.
"""
from __future__ import annotations
import json
import os
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

SCHEMA_VERSION = 1
DEFAULT_JSONL = "~/.claude/panel/decisions.jsonl"
ENV_OVERRIDE = "CLAUDE_PANEL_DECISIONS_JSONL"


def resolve_jsonl_path(configured: str | None = None) -> Path:
    """Resolve the decisions.jsonl path, expanding a leading '~' via $HOME.

    Precedence: $CLAUDE_PANEL_DECISIONS_JSONL (a redirect knob, mirroring
    trace.py's $CLAUDE_PANEL_TRACE_LOG — used by tests to stay hermetic and
    for alternative routing) > the configured path > the built-in default.
    """
    override = os.environ.get(ENV_OVERRIDE)
    return Path(override or configured or DEFAULT_JSONL).expanduser()


def append_decision(record: dict[str, Any], jsonl_path: str | None = None) -> bool:
    """Append one decision record as a single JSONL line. Best-effort.

    Stamps `v` (schema version) and `ts` (UTC ISO) when absent. Uses
    O_APPEND semantics (open mode "a") with one write() per record so
    concurrent appends do not interleave. Returns True when the row was
    written, False when the write was swallowed. Callers on the panel
    path ignore the return; tests assert on it.
    """
    record.setdefault("v", SCHEMA_VERSION)
    record.setdefault("ts", datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"))

    try:
        line = json.dumps(record, ensure_ascii=False, separators=(",", ":"))
    except (TypeError, ValueError):
        return False

    path = resolve_jsonl_path(jsonl_path)
    try:
        path.parent.mkdir(parents=True, exist_ok=True)
        os.chmod(path.parent, 0o700)
    except OSError:
        return False

    try:
        with open(path, "a", encoding="utf-8") as f:
            f.write(line + "\n")
    except OSError:
        return False

    try:
        os.chmod(path, 0o600)
    except OSError:
        pass
    return True
