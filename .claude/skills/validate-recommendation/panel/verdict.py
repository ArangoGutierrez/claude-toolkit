"""Verdict file parsing.

A verdict file is a plain text file with three known fields:

    VERDICT: HOLD|OVERTURN
    RATIONALE: <one paragraph>
    ALTERNATIVE: <option label or n/a>

`parse_verdict_file` returns a `Verdict` object. It does NOT validate the
values — that's the aggregator's job. Unknown or missing fields come back
as empty strings; the aggregator treats them as ERROR.

Matches the field-extraction behavior of aggregate.sh's `parse_field` (uses
`grep -m1` semantics — first matching line, strip the field prefix).
"""
from __future__ import annotations
from dataclasses import dataclass
from pathlib import Path


@dataclass
class Verdict:
    verdict: str  # "HOLD" | "OVERTURN" | "" (empty means unparseable)
    rationale: str
    alternative: str


def _first_field(lines: list[str], field: str) -> str:
    prefix = f"{field}: "
    for line in lines:
        if line.startswith(prefix):
            return line[len(prefix):].rstrip("\n")
    return ""


def parse_verdict(text: str) -> Verdict:
    """Extract VERDICT/RATIONALE/ALTERNATIVE from a plain text string.

    Missing fields come back as empty strings. Used by dispatch.py to
    parse in-memory model responses; parse_verdict_file wraps this for
    callers that hold a path.
    """
    lines = text.splitlines()
    return Verdict(
        verdict=_first_field(lines, "VERDICT"),
        rationale=_first_field(lines, "RATIONALE"),
        alternative=_first_field(lines, "ALTERNATIVE"),
    )


def parse_verdict_file(path: str | Path) -> Verdict:
    """Read a verdict file and extract VERDICT/RATIONALE/ALTERNATIVE."""
    return parse_verdict(Path(path).read_text(encoding="utf-8"))
