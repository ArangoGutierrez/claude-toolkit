"""Per-panelist dissent-rate health metric."""
from panel.stats import panelist_dissent_rates, health_flags


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
