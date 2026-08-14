"""Tests for panel.aggregate — N-panelist JSON-emitting aggregator.

The aggregator's responsibility is wiring: read config, read verdict files,
hand off to severity.decide(), serialize directive to JSON. The decision
logic itself is tested in test_severity.py.

Mock discipline: no mocks. We construct config.yml and verdict files in
tmp_path and run the real aggregator against them.
"""
from __future__ import annotations
import json
import textwrap

import pytest

from panel.aggregate import aggregate


@pytest.fixture
def cfg_path_n1(tmp_path):
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


@pytest.fixture
def cfg_path_n3(tmp_path):
    cfg = tmp_path / "config.yml"
    cfg.write_text(textwrap.dedent("""
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
            backend: claude-subagent
            subagent_type: principal-engineer
          - id: qa-test
            role: QA
            enabled: true
            backend: claude-subagent
            subagent_type: qa-engineer
    """).strip() + "\n")
    return cfg


def _write_verdict(verdicts_dir, panelist_id, verdict, rationale, alternative):
    verdicts_dir.mkdir(parents=True, exist_ok=True)
    p = verdicts_dir / f"{panelist_id}.verdict"
    p.write_text(
        f"VERDICT: {verdict}\n"
        f"RATIONALE: {rationale}\n"
        f"ALTERNATIVE: {alternative}\n"
    )


def _write_blind_config(tmp_path):
    """N=1 blinded PE, plus a DA seat, for mapping tests. Only the panelist
    under test gets a verdict file; the other becomes ERROR, which is fine
    because these tests assert on the per-panelist row, not the directive."""
    cfg_file = tmp_path / "config.yml"
    cfg_file.write_text(
        "version: 1\n"
        "panelists:\n"
        "  - id: da\n"
        "    role: DA\n"
        "    enabled: true\n"
        "    backend: nat-nim\n"
        "    model: m\n"
        "  - id: pe\n"
        "    role: PE\n"
        "    enabled: true\n"
        "    backend: claude-subagent\n"
        "    subagent_type: principal-engineer\n"
        "    blind: true\n"
        "  - id: qa\n"
        "    role: QA\n"
        "    enabled: true\n"
        "    backend: claude-subagent\n"
        "    subagent_type: qa-engineer\n"
        "    blind: true\n",
        encoding="utf-8",
    )
    return cfg_file


def test_n1_hold_emits_hold_json(tmp_path, cfg_path_n1):
    from panel.aggregate import aggregate
    verdicts = tmp_path / "work"
    _write_verdict(verdicts, "da-test", "HOLD",
                   "Looks acceptable as recommended.", "n/a")

    out = aggregate(str(cfg_path_n1), str(verdicts), "Option A (Recommended)")
    data = json.loads(out)
    assert data["verdict"] == "HOLD"
    assert data["rationale_gate_passed"] is True
    assert len(data["panelists"]) == 1
    assert data["panelists"][0]["id"] == "da-test"
    assert data["panelists"][0]["role"] == "DA"
    assert data["panelists"][0]["verdict"] == "HOLD"


def test_n3_majority_two_overturns_emits_hard_dissent_json(tmp_path, cfg_path_n3):
    from panel.aggregate import aggregate
    verdicts = tmp_path / "work"
    _write_verdict(verdicts, "da-test", "OVERTURN",
                   "Option B better matches goals.", "Option B")
    _write_verdict(verdicts, "pe-test", "OVERTURN",
                   "violates YAGNI principle.", "Option B")
    _write_verdict(verdicts, "qa-test", "HOLD",
                   "Testable as written.", "n/a")

    out = aggregate(str(cfg_path_n3), str(verdicts), "Option A (Recommended)")
    data = json.loads(out)
    assert data["verdict"] == "HARD-DISSENT"
    assert data["escalate_to_user"] is True
    assert "re_brainstorm" not in data or data.get("re_brainstorm") is None


def test_one_overturn_below_threshold_emits_soft_dissent(tmp_path, cfg_path_n3):
    from panel.aggregate import aggregate
    verdicts = tmp_path / "work"
    _write_verdict(verdicts, "da-test", "OVERTURN",
                   "concern about cost", "Option B")
    _write_verdict(verdicts, "pe-test", "HOLD", "ok", "n/a")
    _write_verdict(verdicts, "qa-test", "HOLD", "ok", "n/a")

    out = aggregate(str(cfg_path_n3), str(verdicts), "Option A (Recommended)")
    data = json.loads(out)
    assert data["verdict"] == "SOFT-DISSENT"


def test_missing_verdict_file_coerces_panelist_to_error(tmp_path, cfg_path_n3):
    from panel.aggregate import aggregate
    verdicts = tmp_path / "work"
    verdicts.mkdir()
    # Only write 2 of 3 verdict files
    _write_verdict(verdicts, "da-test", "HOLD", "ok", "n/a")
    _write_verdict(verdicts, "qa-test", "HOLD", "ok", "n/a")
    # pe-test verdict file missing

    out = aggregate(str(cfg_path_n3), str(verdicts), "Option A (Recommended)")
    data = json.loads(out)
    pe = next(p for p in data["panelists"] if p["id"] == "pe-test")
    assert pe["verdict"] == "ERROR"
    assert "missing" in pe["rationale"].lower()


def test_all_error_emits_error_directive(tmp_path, cfg_path_n1):
    from panel.aggregate import aggregate
    verdicts = tmp_path / "work"
    _write_verdict(verdicts, "da-test", "ERROR",
                   "backend timeout", "n/a")

    out = aggregate(str(cfg_path_n1), str(verdicts), "Option A (Recommended)")
    data = json.loads(out)
    assert data["verdict"] == "ERROR"
    assert data["rationale_gate_passed"] is None


def test_disabled_panelists_excluded_from_panelists_list(tmp_path):
    from panel.aggregate import aggregate
    cfg = tmp_path / "config.yml"
    cfg.write_text(textwrap.dedent("""
        version: 1
        panelists:
          - id: da-test
            role: DA
            enabled: true
            backend: nat-nim
            model: test-model
          - id: pe-test
            role: PE
            enabled: false
            backend: claude-subagent
            subagent_type: principal-engineer
    """).strip() + "\n")
    verdicts = tmp_path / "work"
    _write_verdict(verdicts, "da-test", "HOLD", "ok", "n/a")
    # No pe-test verdict — but pe-test is disabled.

    out = aggregate(str(cfg), str(verdicts), "Option A (Recommended)")
    data = json.loads(out)
    assert len(data["panelists"]) == 1
    assert data["panelists"][0]["id"] == "da-test"


def test_dissent_summary_starts_with_panel_review_sentinel(tmp_path, cfg_path_n1):
    """SKILL.md parses this exact sentinel."""
    from panel.aggregate import aggregate
    verdicts = tmp_path / "work"
    _write_verdict(verdicts, "da-test", "OVERTURN",
                   "cost concerns matter", "Option B")

    out = aggregate(str(cfg_path_n1), str(verdicts), "Option A (Recommended)")
    data = json.loads(out)
    assert data["summary"].startswith("**Panel review:** ")


def test_output_is_single_line_json(tmp_path, cfg_path_n1):
    from panel.aggregate import aggregate
    verdicts = tmp_path / "work"
    _write_verdict(verdicts, "da-test", "HOLD", "ok", "n/a")

    out = aggregate(str(cfg_path_n1), str(verdicts), "Option A (Recommended)")
    assert "\n" not in out.rstrip("\n")  # at most one trailing newline


def test_markdown_injection_stripped_from_summary(tmp_path, cfg_path_n1):
    from panel.aggregate import aggregate
    verdicts = tmp_path / "work"
    _write_verdict(verdicts, "da-test", "OVERTURN",
                   "See [link](http://evil.example.com) and `rm -rf /`.",
                   "Option B")

    out = aggregate(str(cfg_path_n1), str(verdicts), "Option A (Recommended)")
    data = json.loads(out)
    assert "evil.example.com" not in data["summary"]
    assert "`" not in data["summary"]


def test_trace_log_records_outcome(tmp_path, monkeypatch, cfg_path_n1):
    log_path = tmp_path / "trace.log"
    monkeypatch.setenv("CLAUDE_PANEL_TRACE_LOG", str(log_path))
    from panel.aggregate import aggregate
    verdicts = tmp_path / "work"
    _write_verdict(verdicts, "da-test", "HOLD", "ok", "n/a")

    aggregate(str(cfg_path_n1), str(verdicts), "Option A (Recommended)")
    content = log_path.read_text()
    assert "outcome=HOLD" in content


def test_overturn_with_na_alternative_emits_error_for_panelist(tmp_path, cfg_path_n1):
    """Phase 1 bug #3 preservation via severity._validate()."""
    from panel.aggregate import aggregate
    verdicts = tmp_path / "work"
    _write_verdict(verdicts, "da-test", "OVERTURN",
                   "I disagree but have no concrete alt.", "n/a")

    out = aggregate(str(cfg_path_n1), str(verdicts), "Option A (Recommended)")
    data = json.loads(out)
    # The panelist gets coerced to ERROR; the panel emits ERROR at N=1 strict.
    assert data["verdict"] == "ERROR"


def test_panelists_listed_in_config_order(tmp_path, cfg_path_n3):
    from panel.aggregate import aggregate
    verdicts = tmp_path / "work"
    _write_verdict(verdicts, "da-test", "HOLD", "ok", "n/a")
    _write_verdict(verdicts, "pe-test", "HOLD", "ok", "n/a")
    _write_verdict(verdicts, "qa-test", "HOLD", "ok", "n/a")

    out = aggregate(str(cfg_path_n3), str(verdicts), "Option A (Recommended)")
    data = json.loads(out)
    ids = [p["id"] for p in data["panelists"]]
    assert ids == ["da-test", "pe-test", "qa-test"]


def test_recommended_label_is_not_interpolated_into_summary(tmp_path, cfg_path_n1):
    """Contract lock: until a later phase threads recommended_label into the
    severity layer, it must NOT appear in the directive summary. If this test
    starts failing, decide whether interpolation is intentional — and update
    both the docstring of severity._panel_review_summary() and the CLI help
    text for --recommended-label to match the new behavior.
    """
    from panel.aggregate import aggregate
    verdicts = tmp_path / "work"
    _write_verdict(verdicts, "da-test", "OVERTURN",
                   "concerns about dependency cost", "Option B")

    label = "Option A (Recommended) — net/http; stdlib, no deps"
    out = aggregate(str(cfg_path_n1), str(verdicts), label)
    data = json.loads(out)
    # The substring before the em-dash is short; the long label tokens
    # ("(Recommended)", "net/http", "stdlib") are the most likely
    # accidental-interpolation tokens. Assert none appear.
    assert "(Recommended)" not in data["summary"]
    assert "net/http" not in data["summary"]
    assert "stdlib" not in data["summary"]


def test_blinded_choice_matching_recommendation_maps_to_hold(tmp_path):
    cfg_path = _write_blind_config(tmp_path)
    vdir = tmp_path / "v"
    vdir.mkdir()
    (vdir / "pe.verdict").write_text(
        "CHOICE: Use net/http\nRATIONALE: stdlib is enough\n", encoding="utf-8"
    )
    out = json.loads(aggregate(str(cfg_path), str(vdir), "Use net/http (Recommended)"))
    row = [p for p in out["panelists"] if p["id"] == "pe"][0]
    assert row["verdict"] == "HOLD"
    assert row["alternative"] == "n/a"


def test_blinded_choice_differing_maps_to_overturn_with_alternative(tmp_path):
    cfg_path = _write_blind_config(tmp_path)
    vdir = tmp_path / "v"
    vdir.mkdir()
    (vdir / "pe.verdict").write_text(
        "CHOICE: Use resty\nRATIONALE: retries matter\n", encoding="utf-8"
    )
    out = json.loads(aggregate(str(cfg_path), str(vdir), "Use net/http (Recommended)"))
    row = [p for p in out["panelists"] if p["id"] == "pe"][0]
    assert row["verdict"] == "OVERTURN"
    assert row["alternative"] == "Use resty"


def test_blinded_choice_is_marker_insensitive(tmp_path):
    """The panelist saw a marker-stripped label; the recommendation carries
    the marker. Matching must ignore it or every blinded HOLD becomes an
    OVERTURN against itself."""
    cfg_path = _write_blind_config(tmp_path)
    vdir = tmp_path / "v"
    vdir.mkdir()
    (vdir / "pe.verdict").write_text(
        "CHOICE:   use NET/HTTP  \nRATIONALE: stdlib is enough\n", encoding="utf-8"
    )
    out = json.loads(aggregate(str(cfg_path), str(vdir), "Use net/http (Recommended)"))
    row = [p for p in out["panelists"] if p["id"] == "pe"][0]
    assert row["verdict"] == "HOLD"


def test_blinded_panelist_with_no_choice_line_becomes_error(tmp_path):
    cfg_path = _write_blind_config(tmp_path)
    vdir = tmp_path / "v"
    vdir.mkdir()
    (vdir / "pe.verdict").write_text("I refuse to answer\n", encoding="utf-8")
    out = json.loads(aggregate(str(cfg_path), str(vdir), "Use net/http (Recommended)"))
    row = [p for p in out["panelists"] if p["id"] == "pe"][0]
    assert row["verdict"] == "ERROR"


def test_unblinded_panelist_still_parses_verdict_lines(tmp_path):
    """Regression guard: the mapping must not touch unblinded panelists."""
    cfg_path = _write_blind_config(tmp_path)
    vdir = tmp_path / "v"
    vdir.mkdir()
    (vdir / "da.verdict").write_text(
        "VERDICT: OVERTURN\nRATIONALE: flawed\nALTERNATIVE: Use resty\n",
        encoding="utf-8",
    )
    out = json.loads(aggregate(str(cfg_path), str(vdir), "Use net/http (Recommended)"))
    row = [p for p in out["panelists"] if p["id"] == "da"][0]
    assert row["verdict"] == "OVERTURN"
    assert row["alternative"] == "Use resty"


def test_blinded_choice_echoing_the_marker_maps_to_hold(tmp_path):
    """A panelist that copies the label INCLUDING the marker still means HOLD.

    strip_marker runs on BOTH sides of the comparison. Dropping it from the
    panelist's own choice leaves every other blinded test green, because none
    of them feed a marker-bearing CHOICE. Without this case, that mutation
    survives and a panelist that agreed verbatim is recorded as dissenting.
    """
    cfg_path = _write_blind_config(tmp_path)
    vdir = tmp_path / "v"
    vdir.mkdir()
    (vdir / "pe.verdict").write_text(
        "CHOICE: Use net/http (Recommended)\nRATIONALE: stdlib is enough\n",
        encoding="utf-8",
    )
    out = json.loads(aggregate(str(cfg_path), str(vdir), "Use net/http (Recommended)"))
    row = [p for p in out["panelists"] if p["id"] == "pe"][0]
    assert row["verdict"] == "HOLD"
    assert row["alternative"] == "n/a"


def test_blinded_and_unblinded_rows_coexist_in_one_directive(tmp_path):
    """The blind flag is honoured per panelist, not per directive.

    Every other blinded test leaves the unblinded seat as a missing-file
    ERROR, so nothing pins that both contracts are parsed in the same run.
    Treating all seats as unblinded turns pe/qa into ERROR (no VERDICT line);
    treating all seats as blinded turns da into ERROR (no CHOICE line).
    """
    cfg_path = _write_blind_config(tmp_path)
    vdir = tmp_path / "v"
    vdir.mkdir()
    # da is NOT blinded: it speaks the VERDICT contract.
    (vdir / "da.verdict").write_text(
        "VERDICT: OVERTURN\nRATIONALE: retries matter\nALTERNATIVE: Use resty\n",
        encoding="utf-8",
    )
    # pe and qa ARE blinded: they speak the CHOICE contract.
    (vdir / "pe.verdict").write_text(
        "CHOICE: Use net/http\nRATIONALE: stdlib is enough\n", encoding="utf-8"
    )
    (vdir / "qa.verdict").write_text(
        "CHOICE: Use resty\nRATIONALE: retries matter\n", encoding="utf-8"
    )
    out = json.loads(aggregate(str(cfg_path), str(vdir), "Use net/http (Recommended)"))
    rows = {p["id"]: p for p in out["panelists"]}
    assert rows["da"]["verdict"] == "OVERTURN"
    assert rows["da"]["alternative"] == "Use resty"
    assert rows["pe"]["verdict"] == "HOLD"
    assert rows["pe"]["alternative"] == "n/a"
    assert rows["qa"]["verdict"] == "OVERTURN"
    assert rows["qa"]["alternative"] == "Use resty"


def test_blinded_choice_matching_no_option_becomes_a_free_text_overturn(tmp_path):
    """Pins TODAY'S behaviour: an off-list CHOICE is an OVERTURN, verbatim.

    aggregate() never receives the option list - only the recommended label -
    so it cannot tell an invented option from a real one. Exact matching makes
    any non-matching CHOICE an OVERTURN carrying that raw text as the
    alternative, with no validation or sanitization applied. This is a
    deliberate consequence of exact matching, not an oversight; a future
    change here should be a conscious decision, so it is pinned rather than
    left implicit.
    """
    cfg_path = _write_blind_config(tmp_path)
    vdir = tmp_path / "v"
    vdir.mkdir()
    (vdir / "pe.verdict").write_text(
        "CHOICE: Use grpc-gateway\nRATIONALE: transcoding is free\n",
        encoding="utf-8",
    )
    out = json.loads(aggregate(str(cfg_path), str(vdir), "Use net/http (Recommended)"))
    row = [p for p in out["panelists"] if p["id"] == "pe"][0]
    assert row["verdict"] == "OVERTURN"
    assert row["alternative"] == "Use grpc-gateway"
