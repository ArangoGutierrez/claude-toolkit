"""Per-panelist dissent-rate health metric."""
import json

from panel.stats import load_rows, panelist_dissent_rates, health_flags


def _row(votes):
    return {"event": "decision", "verdict": "HOLD",
            "panelists": [{"id": i, "role": "R", "verdict": v} for i, v in votes]}


def test_dissent_rate_counts_overturns_over_total_votes():
    rows = [
        _row([("da", "OVERTURN"), ("pe", "HOLD")]),
        _row([("da", "OVERTURN"), ("pe", "HOLD")]),
        _row([("da", "HOLD"), ("pe", "OVERTURN")]),
    ]
    out = panelist_dissent_rates(rows)
    assert out["da"]["n"] == 3
    assert out["da"]["overturns"] == 2
    assert abs(out["da"]["dissent_rate"] - 2 / 3) < 1e-9
    assert out["pe"]["overturns"] == 1


def test_error_votes_count_toward_n_but_not_dissent():
    rows = [_row([("da", "ERROR")]), _row([("da", "OVERTURN")])]
    out = panelist_dissent_rates(rows)
    assert out["da"]["n"] == 2
    assert out["da"]["overturns"] == 1


def test_rows_without_panelists_are_ignored():
    out = panelist_dissent_rates([{"event": "decision"}, _row([("da", "HOLD")])])
    assert out["da"]["n"] == 1


def test_health_flags_red_on_never_dissents():
    rows = [_row([("qa", "HOLD")]) for _ in range(30)]
    flags = health_flags(panelist_dissent_rates(rows), min_n=20)
    assert flags["qa"] == "UNHEALTHY"


def test_health_flags_red_on_always_dissents():
    rows = [_row([("da", "OVERTURN")]) for _ in range(30)]
    flags = health_flags(panelist_dissent_rates(rows), min_n=20)
    assert flags["da"] == "UNHEALTHY"


def test_health_flags_skip_below_min_n_never_pass_vacuously():
    """Small samples must SKIP, not PASS. A vacuous pass is how a broken
    panelist stays green."""
    rows = [_row([("qa", "HOLD")]) for _ in range(5)]
    flags = health_flags(panelist_dissent_rates(rows), min_n=20)
    assert flags["qa"] == "SKIP"


def test_health_flags_ok_inside_the_band():
    rows = [_row([("pe", "HOLD")]) for _ in range(15)]
    rows += [_row([("pe", "OVERTURN")]) for _ in range(15)]
    flags = health_flags(panelist_dissent_rates(rows), min_n=20)
    assert flags["pe"] == "OK"


def test_health_flags_score_at_exactly_min_n():
    """n == min_n is scored, not skipped.

    The threshold is `n < min_n`. Off-by-one to `<=` would silently stop
    grading a panelist that has just become measurable, and every other
    fixture sits far from the boundary, so nothing else catches it.
    """
    rows = [_row([("pe", "HOLD")]) for _ in range(10)]
    rows += [_row([("pe", "OVERTURN")]) for _ in range(10)]
    flags = health_flags(panelist_dissent_rates(rows), min_n=20)
    assert flags["pe"] == "OK"


# --- load_rows: the input path for the whole metric ---------------------
#
# A broken reader makes every downstream number 0, which reads as "healthy"
# unless something pins the reader itself.


def _write(path, lines):
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")
    return path


def test_load_rows_parses_well_formed_rows(tmp_path):
    log = _write(tmp_path / "d.jsonl", [
        json.dumps(_row([("da", "OVERTURN")])),
        json.dumps(_row([("qa", "HOLD")])),
    ])
    rows = load_rows(log)
    assert len(rows) == 2
    assert rows[0]["panelists"][0]["id"] == "da"
    assert rows[1]["panelists"][0]["verdict"] == "HOLD"


def test_load_rows_skips_blank_lines(tmp_path):
    log = _write(tmp_path / "d.jsonl", [
        json.dumps(_row([("da", "HOLD")])),
        "",
        "   ",
        json.dumps(_row([("da", "OVERTURN")])),
    ])
    assert len(load_rows(log)) == 2


def test_load_rows_skips_malformed_line_without_crashing(tmp_path):
    """One truncated line must not cost the other 337.

    decisions.jsonl has many concurrent writers, so a half-written line is a
    real possibility. Raising here would take the whole metric down.
    """
    log = _write(tmp_path / "d.jsonl", [
        json.dumps(_row([("da", "HOLD")])),
        '{"event":"decision","panelists":[{"id":"da"',
        "not json at all",
        json.dumps(_row([("da", "OVERTURN")])),
    ])
    rows = load_rows(log)
    assert len(rows) == 2
    assert panelist_dissent_rates(rows)["da"]["overturns"] == 1


def test_load_rows_returns_empty_for_missing_file(tmp_path):
    assert load_rows(tmp_path / "does-not-exist.jsonl") == []
