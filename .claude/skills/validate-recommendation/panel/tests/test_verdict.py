"""Tests for panel.verdict — verdict file parsing and validation."""
import pytest
from pathlib import Path


def test_parse_hold_verdict(fixtures_dir, tmp_path):
    from panel.verdict import parse_verdict_file
    v = parse_verdict_file(fixtures_dir / "da_hold.txt")
    assert v.verdict == "HOLD"
    assert v.rationale != ""
    assert v.alternative == "n/a"


def test_parse_overturn_verdict(fixtures_dir, tmp_path):
    from panel.verdict import parse_verdict_file
    v = parse_verdict_file(fixtures_dir / "da_overturn_b.txt")
    assert v.verdict == "OVERTURN"
    assert v.rationale != ""
    assert v.alternative == "Option B"


def test_parse_malformed_returns_unknown_verdict(fixtures_dir, tmp_path):
    """A file without VERDICT/RATIONALE/ALTERNATIVE lines is unparseable.

    The parser returns an empty-verdict object; validation happens at the
    aggregator level. This mirrors aggregate.sh's behavior (parse_field
    returns empty, then the case statement classifies as ERROR).
    """
    from panel.verdict import parse_verdict_file
    v = parse_verdict_file(fixtures_dir / "malformed.txt")
    assert v.verdict == ""  # not one of HOLD/OVERTURN; caller treats as ERROR
    assert v.rationale == ""


def test_parse_strips_field_prefix(tmp_path):
    """parse_verdict_file strips 'FIELD: ' from each line, preserving the rest."""
    from panel.verdict import parse_verdict_file
    p = tmp_path / "v.txt"
    p.write_text("VERDICT: HOLD\nRATIONALE: A short reason here.\nALTERNATIVE: n/a\n")
    v = parse_verdict_file(p)
    assert v.verdict == "HOLD"
    assert v.rationale == "A short reason here."
    assert v.alternative == "n/a"
