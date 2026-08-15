"""CLI tests for `panel stats`.

`panel/stats.py` is covered by test_stats.py; this file covers only the CLI
shim — argument wiring, the default log path, and the printed row format.

The row format is a contract, not cosmetics. `.claude/evals/panel-dissent-health.sh`
greps this output for `n=[0-9]+` and for a trailing `OK|UNHEALTHY|SKIP` flag,
and reports SKIP when it counts zero rows. A format change that drops either
token therefore turns the health eval permanently green against a log full of
rubber stamps, with nothing else to notice. The literals below are copied from
a real run, never re-derived from the f-string under test.
"""
from __future__ import annotations

import json
from pathlib import Path


def _row(votes):
    return {
        "event": "decision",
        "verdict": "HOLD",
        "panelists": [{"id": i, "role": "R", "verdict": v} for i, v in votes],
    }


def _write_log(path, rows):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("\n".join(json.dumps(r) for r in rows) + "\n", encoding="utf-8")
    return path


def _fixture_rows():
    """4 decisions: da 2/4 overturns, pe 0/4, qa 2/4.

    Panelists are listed qa-first so an implementation that prints in
    insertion order rather than sorted order produces a different sequence.
    """
    return (
        [_row([("qa", "HOLD"), ("pe", "HOLD"), ("da", "OVERTURN")])] * 2
        + [_row([("qa", "OVERTURN"), ("pe", "HOLD"), ("da", "HOLD")])] * 2
    )


def _rows_of(out: str) -> list[str]:
    return [ln for ln in out.splitlines() if ln.strip()]


def test_stats_prints_one_row_per_panelist_with_the_exact_columns(tmp_path, capsys):
    """Catches column drift — a renamed or reordered field silently blinds
    panel-dissent-health.sh, which parses these exact tokens."""
    from panel.cli import main

    log = _write_log(tmp_path / "d.jsonl", _fixture_rows())
    rc = main(["stats", "--jsonl", str(log), "--min-n", "4"])
    assert rc == 0

    lines = _rows_of(capsys.readouterr().out)
    assert lines == [
        "  da             n=4     overturns=2     dissent-rate= 50.0%  OK",
        "  pe             n=4     overturns=0     dissent-rate=  0.0%  UNHEALTHY",
        "  qa             n=4     overturns=2     dissent-rate= 50.0%  OK",
    ]


def test_stats_rows_are_sorted_by_panelist_id(tmp_path, capsys):
    """Catches insertion-order output. The fixture records qa before da on
    every line, so unsorted printing yields qa, pe, da."""
    from panel.cli import main

    log = _write_log(tmp_path / "d.jsonl", _fixture_rows())
    main(["stats", "--jsonl", str(log), "--min-n", "4"])

    ids = [ln.split()[0] for ln in _rows_of(capsys.readouterr().out)]
    assert ids == ["da", "pe", "qa"]


def test_stats_every_row_ends_with_a_health_flag(tmp_path, capsys):
    """Catches a dropped flag column. The eval counts rows carrying a
    trailing flag and FAILs when that count diverges from the `n=` count;
    a flagless row would make it FAIL on a healthy panel instead."""
    from panel.cli import main

    log = _write_log(tmp_path / "d.jsonl", _fixture_rows())
    main(["stats", "--jsonl", str(log), "--min-n", "4"])

    flags = [ln.split()[-1] for ln in _rows_of(capsys.readouterr().out)]
    assert flags == ["OK", "UNHEALTHY", "OK"]


def test_stats_min_n_flag_is_honoured(tmp_path, capsys):
    """Catches a --min-n parsed but never threaded into health_flags.

    The same 4-vote fixture scores OK/UNHEALTHY at --min-n 4 and SKIP at
    --min-n 20. A hard-coded threshold keeps one of those two wrong.
    """
    from panel.cli import main

    log = _write_log(tmp_path / "d.jsonl", _fixture_rows())

    main(["stats", "--jsonl", str(log), "--min-n", "4"])
    scored = [ln.split()[-1] for ln in _rows_of(capsys.readouterr().out)]

    main(["stats", "--jsonl", str(log), "--min-n", "20"])
    skipped = [ln.split()[-1] for ln in _rows_of(capsys.readouterr().out)]

    assert scored == ["OK", "UNHEALTHY", "OK"]
    assert skipped == ["SKIP", "SKIP", "SKIP"]


def test_stats_min_n_defaults_to_twenty(tmp_path, capsys):
    """Catches default drift. 4 votes must stay unscored when the operator
    passes no threshold — the vacuous-pass guard the metric exists for."""
    from panel.cli import main

    log = _write_log(tmp_path / "d.jsonl", _fixture_rows())
    rc = main(["stats", "--jsonl", str(log)])
    assert rc == 0

    flags = [ln.split()[-1] for ln in _rows_of(capsys.readouterr().out)]
    assert flags == ["SKIP", "SKIP", "SKIP"]


def test_stats_absent_log_reports_no_decisions_and_exits_zero(tmp_path, capsys):
    """Catches a crash on a fresh install. The log does not exist until the
    panel has run once, and `panel stats` is documented as safe to run then."""
    from panel.cli import main

    rc = main(["stats", "--jsonl", str(tmp_path / "does-not-exist.jsonl")])
    assert rc == 0
    assert capsys.readouterr().out.strip() == "no decisions recorded yet"


def test_stats_empty_log_reports_no_decisions_and_exits_zero(tmp_path, capsys):
    """Catches a crash on a zero-byte log — what a truncated or freshly
    created decisions.jsonl looks like."""
    from panel.cli import main

    log = tmp_path / "d.jsonl"
    log.write_text("", encoding="utf-8")

    rc = main(["stats", "--jsonl", str(log)])
    assert rc == 0
    assert capsys.readouterr().out.strip() == "no decisions recorded yet"


def test_stats_log_of_decisions_without_panelists_reports_no_decisions(tmp_path, capsys):
    """Catches an IndexError/KeyError on rows that carry no panelist votes.

    A decision recorded before the panel dispatched has `panelists: []`;
    the row is well-formed JSON, so load_rows returns it and the aggregate
    is empty. The CLI must take the empty branch, not print a header.
    """
    from panel.cli import main

    log = _write_log(tmp_path / "d.jsonl", [{"event": "decision", "panelists": []}] * 3)
    rc = main(["stats", "--jsonl", str(log)])
    assert rc == 0
    assert capsys.readouterr().out.strip() == "no decisions recorded yet"


def test_stats_defaults_to_the_home_decisions_log(tmp_path, capsys, monkeypatch):
    """Catches a wrong default path.

    With --jsonl omitted the CLI must read $HOME/.claude/panel/decisions.jsonl.
    Home is redirected at tmp_path so the operator's real log is never touched;
    a default pointing anywhere else finds no file and prints the empty message.
    """
    from panel.cli import main

    monkeypatch.setattr(Path, "home", staticmethod(lambda: tmp_path))
    _write_log(tmp_path / ".claude" / "panel" / "decisions.jsonl", _fixture_rows())

    rc = main(["stats", "--min-n", "4"])
    assert rc == 0

    lines = _rows_of(capsys.readouterr().out)
    assert [ln.split()[0] for ln in lines] == ["da", "pe", "qa"]
    assert lines[0].endswith("OK")
