"""aggregate() adds the stakes policy to the directive, the telemetry row and the trace.

No mocks: a real config.yml with three seats, real verdict files, a real
question file, and the real decisions.jsonl row (redirected by the autouse
conftest fixture).
"""
from __future__ import annotations

import json
import textwrap

import pytest

from panel.aggregate import aggregate

PANEL = """
version: 1
panelists:
  - id: da-test
    role: DA
    enabled: true
    backend: nat-nim
    model: test-model
  - id: pe-test
    role: PE
    enabled: true
    backend: nat-nim
    model: test-model
  - id: qa-test
    role: QA
    enabled: true
    backend: nat-nim
    model: test-model
"""

HOLD = "VERDICT: HOLD\nRATIONALE: Fits the constraints.\nALTERNATIVE: n/a\n"
OVERTURN = "VERDICT: OVERTURN\nRATIONALE: Option B avoids shared state.\nALTERNATIVE: Option B\n"
LABEL_A = "Option A (Recommended)"


@pytest.fixture(autouse=True)
def _panel_mode_on(monkeypatch):
    monkeypatch.delenv("CLAUDE_PANEL", raising=False)


def _panel(tmp_path, overturns):
    cfg = tmp_path / "config.yml"
    cfg.write_text(textwrap.dedent(PANEL).strip() + "\n")
    work = tmp_path / "work"
    work.mkdir()
    for i, seat in enumerate(("da-test", "pe-test", "qa-test")):
        (work / f"{seat}.verdict").write_text(OVERTURN if i < overturns else HOLD)
    return str(cfg), str(work)


def _question(tmp_path, text, label_a=LABEL_A, raw=None):
    path = tmp_path / "question.json"
    if raw is not None:
        path.write_text(raw)
    else:
        path.write_text(json.dumps({
            "question": text,
            "options": [{"label": label_a, "description": "Keep the cache local"},
                        {"label": "Option B", "description": "Use a shared cache"}],
            "recommended_label": label_a,
            "reasoning": "Keep the cache local",
        }))
    return str(path)


def _run(tmp_path, overturns, text, label_a=LABEL_A):
    cfg, work = _panel(tmp_path, overturns)
    qfile = _question(tmp_path, text, label_a)
    return json.loads(aggregate(cfg, work, label_a, question_file=qfile))


def _last_row(path):
    return json.loads(path.read_text().splitlines()[-1])


def test_reversible_soft_dissent_proceeds_with_the_objection_noted(tmp_path, decisions_log):
    out = _run(tmp_path, 1, "[reversible] Which cache layout?")
    assert out["verdict"] == "SOFT-DISSENT"
    assert (out["stakes"], out["stakes_reason"], out["action"]) == (
        "reversible", "tagged", "proceed_noted")
    row = _last_row(decisions_log)
    assert (row["stakes"], row["stakes_reason"], row["action"]) == (
        "reversible", "tagged", "proceed_noted")


def test_a_keyword_in_a_label_keeps_a_tagged_fork_with_the_user(tmp_path):
    out = _run(tmp_path, 1, "[reversible] Which cache layout?",
               label_a="Merge the cache now (Recommended)")
    assert out["verdict"] == "SOFT-DISSENT"
    assert (out["stakes"], out["stakes_reason"], out["action"]) == (
        "high", "keyword:merge", "ask_with_review")


def test_reversible_hard_dissent_still_asks(tmp_path):
    out = _run(tmp_path, 2, "[reversible] Which cache layout?")
    assert (out["verdict"], out["action"]) == ("HARD-DISSENT", "ask_with_review")


def test_reversible_hold_proceeds(tmp_path):
    out = _run(tmp_path, 0, "[reversible] Which cache layout?")
    assert (out["verdict"], out["action"]) == ("HOLD", "proceed")


def test_untagged_hold_asks_with_review(tmp_path):
    out = _run(tmp_path, 0, "Which cache layout?")
    assert (out["verdict"], out["stakes"], out["action"]) == ("HOLD", "high", "ask_with_review")


def test_without_a_question_file_the_fork_is_high_stakes(tmp_path, decisions_log):
    cfg, work = _panel(tmp_path, 1)
    out = json.loads(aggregate(cfg, work, LABEL_A))
    assert (out["stakes"], out["stakes_reason"], out["action"]) == (
        "high", "no_question", "ask_with_review")
    assert _last_row(decisions_log)["action"] == "ask_with_review"


@pytest.mark.parametrize("raw", ["{not json", "[1, 2]", ""])
def test_an_unusable_question_file_is_high_stakes(tmp_path, raw):
    cfg, work = _panel(tmp_path, 1)
    qfile = _question(tmp_path, None, raw=raw)
    out = json.loads(aggregate(cfg, work, LABEL_A, question_file=qfile))
    assert (out["stakes"], out["stakes_reason"], out["action"]) == (
        "high", "no_question", "ask_with_review")


def test_a_question_file_that_does_not_exist_is_high_stakes(tmp_path):
    # The path SKILL.md passes can drift away from the file step 1 wrote.
    cfg, work = _panel(tmp_path, 0)
    out = json.loads(aggregate(cfg, work, LABEL_A, question_file=str(tmp_path / "missing.json")))
    assert (out["stakes"], out["stakes_reason"], out["action"]) == (
        "high", "no_question", "ask_with_review")


def test_advise_mode_asks_even_when_reversible(tmp_path, monkeypatch):
    monkeypatch.setenv("CLAUDE_PANEL", "advise")
    out = _run(tmp_path, 0, "[reversible] Which cache layout?")
    assert (out["verdict"], out["action"]) == ("HOLD", "ask_with_review")


def test_the_directive_json_shape_is_pinned(tmp_path):
    # SKILL.md parses the directive with jq; the stakes policy adds exactly
    # three keys to it: stakes, stakes_reason and action.
    out = _run(tmp_path, 1, "[reversible] Which cache layout?")
    assert set(out) == {"verdict", "summary", "rationale_gate_passed", "panelists",
                        "stakes", "stakes_reason", "action"}


def test_trace_line_names_the_action_and_stakes(tmp_path, monkeypatch):
    log = tmp_path / "trace.log"
    monkeypatch.setenv("CLAUDE_PANEL_TRACE_LOG", str(log))
    _run(tmp_path, 1, "[reversible] Which cache layout?")
    assert "action=proceed_noted stakes=reversible" in log.read_text()


LONG_ID = "seat-with-a-deliberately-long-identifier-for-the-trace-cap"


def test_action_and_stakes_survive_the_trace_length_cap(tmp_path, monkeypatch):
    # log_verdict keeps the first 160 characters of the detail; three long
    # panelist ids alone exceed that, so action and stakes must come first.
    log = tmp_path / "trace.log"
    monkeypatch.setenv("CLAUDE_PANEL_TRACE_LOG", str(log))
    cfg = tmp_path / "config.yml"
    seats = [f"{role}-{LONG_ID}" for role in ("da", "pe", "qa")]
    cfg.write_text("version: 1\npanelists:\n" + "".join(
        f"  - id: {seat}\n    role: {seat[:2].upper()}\n    enabled: true\n"
        f"    backend: nat-nim\n    model: test-model\n" for seat in seats))
    work = tmp_path / "work"
    work.mkdir()
    for i, seat in enumerate(seats):
        (work / f"{seat}.verdict").write_text(OVERTURN if i == 0 else HOLD)
    qfile = _question(tmp_path, "[reversible] Which cache layout?")
    aggregate(str(cfg), str(work), LABEL_A, question_file=qfile)
    assert "action=proceed_noted stakes=reversible" in log.read_text()
