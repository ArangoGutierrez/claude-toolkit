"""Tests for panel.telemetry — the decisions.jsonl decision-record writer.

Mock discipline: no mocks. append_decision is exercised against real files;
the aggregate-seam tests run the real aggregator (config.yml + verdict files
in tmp_path) and assert the row it appends.

The autouse `decisions_log` fixture (conftest) points
$CLAUDE_PANEL_DECISIONS_JSONL at a throwaway file, so every write here (and
in the pre-existing aggregate tests) lands there instead of the operator's
real ~/.claude/panel/decisions.jsonl.
"""
from __future__ import annotations
import json
import os
import textwrap

from panel.aggregate import aggregate
from panel.cli import main
from panel.telemetry import ENV_OVERRIDE, append_decision


def _read_records(path):
    return [json.loads(line) for line in path.read_text(encoding="utf-8").splitlines() if line]


# ---- append_decision unit tests ----

def test_append_decision_writes_single_valid_jsonl_line(decisions_log):
    ok = append_decision({"event": "decision", "verdict": "HOLD"})
    assert ok is True
    records = _read_records(decisions_log)
    assert len(records) == 1
    assert records[0]["event"] == "decision"
    assert records[0]["verdict"] == "HOLD"


def test_append_decision_stamps_schema_version_and_ts(decisions_log):
    append_decision({"event": "decision"})
    rec = _read_records(decisions_log)[0]
    assert rec["v"] == 1
    assert rec["ts"].endswith("Z")  # UTC ISO, e.g. 2026-07-09T12:34:56Z
    assert len(rec["ts"]) == 20


def test_append_decision_file_mode_0600(decisions_log):
    append_decision({"event": "decision"})
    assert (os.stat(decisions_log).st_mode & 0o777) == 0o600


def test_append_decision_appends_not_truncates(decisions_log):
    append_decision({"event": "decision", "n": 1})
    append_decision({"event": "decision", "n": 2})
    records = _read_records(decisions_log)
    assert [r["n"] for r in records] == [1, 2]


def test_append_decision_quoted_label_survives_as_valid_jsonl(decisions_log):
    tricky = 'Option "A" (Recommended) — keep \\ as-is'
    append_decision({"event": "decision", "recommended_label": tricky})
    assert _read_records(decisions_log)[0]["recommended_label"] == tricky


def test_append_decision_honors_configured_path_when_env_unset(tmp_path, monkeypatch):
    # Production path: no redirect env → the configured argument is used.
    monkeypatch.delenv(ENV_OVERRIDE, raising=False)
    configured = tmp_path / "configured.jsonl"
    ok = append_decision({"event": "decision", "verdict": "HOLD"}, str(configured))
    assert ok is True
    assert _read_records(configured)[0]["verdict"] == "HOLD"


def test_append_decision_unwritable_path_returns_false_and_does_not_raise(tmp_path, monkeypatch):
    blocker = tmp_path / "blocker"
    blocker.write_text("i am a file, not a directory\n")
    target = blocker / "decisions.jsonl"  # parent is a regular file → mkdir fails
    monkeypatch.setenv(ENV_OVERRIDE, str(target))
    ok = append_decision({"event": "decision"})
    assert ok is False
    assert not target.exists()


# ---- aggregate-seam integration tests ----

def _hold_config(tmp_path):
    """A one-panelist config with NO telemetry block — proves the aggregate
    seam still lands in the redirected log even for the default-path case
    that used to leak the real file."""
    cfg = tmp_path / "config.yml"
    cfg.write_text(textwrap.dedent("""
        version: 1
        panelists:
          - id: da-test
            role: DA
            enabled: true
            backend: nat-nim
            model: test-model
    """).strip() + "\n")
    return cfg


def _write_verdict(verdicts_dir, panelist_id, verdict, rationale, alternative):
    verdicts_dir.mkdir(parents=True, exist_ok=True)
    p = verdicts_dir / f"{panelist_id}.verdict"
    p.write_text(
        f"VERDICT: {verdict}\nRATIONALE: {rationale}\nALTERNATIVE: {alternative}\n",
        encoding="utf-8",
    )


def test_aggregate_appends_exactly_one_decision_record(decisions_log, tmp_path):
    cfg = _hold_config(tmp_path)
    vdir = tmp_path / "verdicts"
    _write_verdict(vdir, "da-test", "HOLD", "A holds; nothing stronger found.", "n/a")

    aggregate(str(cfg), str(vdir), "Option A (Recommended)", question_id="q-123")

    records = _read_records(decisions_log)
    assert len(records) == 1
    rec = records[0]
    assert rec["event"] == "decision"
    assert rec["v"] == 1
    assert rec["verdict"] == "HOLD"
    assert rec["recommended_label"] == "Option A (Recommended)"
    assert rec["question_id"] == "q-123"  # threaded through
    assert rec["panelists"] == [{"id": "da-test", "role": "DA", "verdict": "HOLD"}]


def test_aggregate_question_id_null_when_not_supplied(decisions_log, tmp_path):
    cfg = _hold_config(tmp_path)
    vdir = tmp_path / "verdicts"
    _write_verdict(vdir, "da-test", "HOLD", "A holds; nothing stronger found.", "n/a")

    aggregate(str(cfg), str(vdir), "Option A (Recommended)")

    assert _read_records(decisions_log)[0]["question_id"] is None


def test_aggregate_record_fields_match_directive(decisions_log, tmp_path):
    cfg = _hold_config(tmp_path)
    vdir = tmp_path / "verdicts"
    _write_verdict(vdir, "da-test", "HOLD", "A holds; nothing stronger found.", "n/a")

    directive = json.loads(aggregate(str(cfg), str(vdir), "Option A (Recommended)"))

    rec = _read_records(decisions_log)[0]
    # The telemetry record must not drift from the directive it describes.
    assert rec["verdict"] == directive["verdict"]
    assert rec["rationale_gate_passed"] == directive["rationale_gate_passed"]
    assert [p["verdict"] for p in rec["panelists"]] == [p["verdict"] for p in directive["panelists"]]


def test_aggregate_unwritable_telemetry_still_emits_directive(tmp_path, monkeypatch):
    blocker = tmp_path / "blocker"
    blocker.write_text("not a directory\n")
    target = blocker / "decisions.jsonl"  # unwritable
    monkeypatch.setenv(ENV_OVERRIDE, str(target))
    cfg = _hold_config(tmp_path)
    vdir = tmp_path / "verdicts"
    _write_verdict(vdir, "da-test", "HOLD", "A holds; nothing stronger found.", "n/a")

    directive = json.loads(aggregate(str(cfg), str(vdir), "Option A (Recommended)"))
    assert directive["verdict"] == "HOLD"  # telemetry failure did not break the directive
    assert not target.exists()


def test_cli_aggregate_unwritable_telemetry_exit_code_unchanged(tmp_path, monkeypatch, capsys):
    blocker = tmp_path / "blocker"
    blocker.write_text("not a directory\n")
    target = blocker / "decisions.jsonl"  # unwritable
    monkeypatch.setenv(ENV_OVERRIDE, str(target))
    cfg = _hold_config(tmp_path)
    vdir = tmp_path / "verdicts"
    _write_verdict(vdir, "da-test", "HOLD", "A holds; nothing stronger found.", "n/a")

    rc = main([
        "aggregate",
        "--config", str(cfg),
        "--verdicts-dir", str(vdir),
        "--recommended-label", "Option A (Recommended)",
    ])
    assert rc == 0
    directive = json.loads(capsys.readouterr().out.strip())  # stdout still carries the directive
    assert directive["verdict"] == "HOLD"
