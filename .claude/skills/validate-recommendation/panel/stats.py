"""Per-panelist dissent-rate health metric over decisions.jsonl.

A panelist that never dissents is as broken as one that always does: the
first is a rubber stamp, the second is noise. Both mean the panel is not
deliberating. The data already exists - _record_decision writes a per
panelist verdict on every decision - so this module only reads.

decisions.jsonl is shared by every concurrent Claude session, so rates are
aggregated across sessions and no single-writer ordering is assumed.
"""
from __future__ import annotations

import json
from pathlib import Path

UNHEALTHY_LOW = 0.0
UNHEALTHY_HIGH = 1.0


def load_rows(path: str | Path) -> list[dict]:
    """Read decisions.jsonl, skipping blank and malformed lines."""
    rows: list[dict] = []
    p = Path(path).expanduser()
    if not p.is_file():
        return rows
    for line in p.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line:
            continue
        try:
            rows.append(json.loads(line))
        except json.JSONDecodeError:
            continue
    return rows


def panelist_dissent_rates(rows: list[dict]) -> dict[str, dict]:
    """Aggregate per-panelist vote counts and dissent rate."""
    acc: dict[str, dict] = {}
    for row in rows:
        for p in row.get("panelists") or []:
            pid = p.get("id")
            if not pid:
                continue
            slot = acc.setdefault(pid, {"n": 0, "overturns": 0, "dissent_rate": 0.0})
            slot["n"] += 1
            if p.get("verdict") == "OVERTURN":
                slot["overturns"] += 1
    for slot in acc.values():
        slot["dissent_rate"] = slot["overturns"] / slot["n"] if slot["n"] else 0.0
    return acc


def health_flags(rates: dict[str, dict], min_n: int = 20) -> dict[str, str]:
    """Flag each panelist OK / UNHEALTHY / SKIP.

    SKIP below min_n rather than OK: a vacuous pass on a tiny sample is
    exactly how a rubber-stamping panelist stays green.
    """
    out: dict[str, str] = {}
    for pid, slot in rates.items():
        if slot["n"] < min_n:
            out[pid] = "SKIP"
        elif slot["dissent_rate"] <= UNHEALTHY_LOW or slot["dissent_rate"] >= UNHEALTHY_HIGH:
            out[pid] = "UNHEALTHY"
        else:
            out[pid] = "OK"
    return out
