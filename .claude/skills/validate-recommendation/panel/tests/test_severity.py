"""Tests for panel.severity — pure N-panelist decision tree.

Constitution compliance: each test must fail when the implementation
mutates. Tests cover the decision tree exhaustively (no theater).

Mock discipline: severity.py is pure — no mocks used. Tests construct
Config and ParsedVerdict objects directly.
"""
from __future__ import annotations


from panel.severity import (
    decide,
    Directive,
    ParsedVerdict,
    ReBrainstormPayload,
)
from panel.config import (
    Config,
    Severity,
    RationaleGate,
    FailureMode,
    ReBrainstorm,
    Telemetry,
    Panelist,
)


def _config(
    panelist_count=1,
    *,
    hard_threshold="majority",
    on_panelist_error="auto",
    max_cycles=2,
):
    panelists = [
        Panelist(
            id=f"p{i}",
            role=("DA" if i == 0 else "PE" if i == 1 else "QA" if i == 2 else f"R{i}"),
            enabled=True,
            backend="nat-nim",
            model="test-model",
            max_tokens=1024,
            temperature=0.0,
            timeout_seconds=10,
        )
        for i in range(panelist_count)
    ]
    return Config(
        version="1",
        panelists=panelists,
        severity=Severity(
            hard_threshold=hard_threshold,
            rationale_gate=RationaleGate(),
        ),
        failure_mode=FailureMode(on_panelist_error=on_panelist_error),
        re_brainstorm=ReBrainstorm(enabled=True, max_cycles=max_cycles),
        telemetry=Telemetry(),
    )


def _v(verdict, *, alt="n/a", rationale="some rationale text here.",
       id="p0", role="DA"):
    return ParsedVerdict(
        id=id, role=role, verdict=verdict,
        rationale=rationale, alternative=alt,
    )


# ---- N=1 (default config) ----

def test_n1_hold_emits_hold():
    cfg = _config(1)
    d = decide(cfg, [_v("HOLD")])
    assert d.verdict == "HOLD"
    assert d.rationale_gate_passed is True
    assert len(d.panelists) == 1


def test_n1_overturn_with_concrete_alternative_is_hard_dissent():
    cfg = _config(1)
    d = decide(cfg, [_v("OVERTURN", alt="Option B")])
    assert d.verdict == "HARD-DISSENT"
    assert d.escalate_to_user is True
    assert d.re_brainstorm is None
    assert d.rationale_gate_passed is True


def test_n1_overturn_with_na_alternative_is_coerced_to_error():
    """Phase 1 bug #3 preservation: OVERTURN + n/a → ERROR (not SOFT)."""
    cfg = _config(1)
    d = decide(cfg, [_v("OVERTURN", alt="n/a")])
    assert d.verdict == "ERROR"


def test_n1_error_panelist_with_strict_mode_emits_error():
    cfg = _config(1, on_panelist_error="strict")
    d = decide(cfg, [_v("ERROR", rationale="backend timeout")])
    assert d.verdict == "ERROR"
    assert "tolerance" in d.summary.lower()


def test_n1_with_auto_failure_mode_is_strict_at_n_equals_1():
    """auto mode resolves to strict for N=1 (no room to degrade)."""
    cfg = _config(1, on_panelist_error="auto")
    d = decide(cfg, [_v("ERROR")])
    assert d.verdict == "ERROR"


# ---- N=3 majority ----

def test_n3_all_hold_emits_hold():
    cfg = _config(3)
    d = decide(cfg, [_v("HOLD", id="p0"), _v("HOLD", id="p1", role="PE"),
                     _v("HOLD", id="p2", role="QA")])
    assert d.verdict == "HOLD"


def test_n3_one_overturn_below_threshold_is_soft_dissent():
    """1 OVERTURN of 3 < ceil(3/2)=2 → SOFT."""
    cfg = _config(3)
    d = decide(cfg, [
        _v("OVERTURN", alt="Option B", id="p0"),
        _v("HOLD", id="p1", role="PE"),
        _v("HOLD", id="p2", role="QA"),
    ])
    assert d.verdict == "SOFT-DISSENT"
    assert d.rationale_gate_passed is False


def test_n3_two_overturns_meets_majority_threshold_is_hard_dissent():
    """2 OVERTURN of 3 ≥ ceil(3/2)=2 + alt naming → gate passes → HARD."""
    cfg = _config(3)
    d = decide(cfg, [
        _v("OVERTURN", alt="Option B", id="p0"),
        _v("OVERTURN", alt="Option B", id="p1", role="PE"),
        _v("HOLD", id="p2", role="QA"),
    ])
    assert d.verdict == "HARD-DISSENT"
    assert d.escalate_to_user is True
    assert d.rationale_gate_passed is True


def test_n3_three_overturns_is_hard_dissent():
    cfg = _config(3)
    d = decide(cfg, [
        _v("OVERTURN", alt="Option B", id="p0"),
        _v("OVERTURN", alt="Option B", id="p1", role="PE"),
        _v("OVERTURN", alt="Option B", id="p2", role="QA"),
    ])
    assert d.verdict == "HARD-DISSENT"


# ---- N=3 supermajority ----

def test_n3_supermajority_two_overturns_meets_threshold():
    """ceil(2*3/3)=2; 2 OVERTURN crosses supermajority."""
    cfg = _config(3, hard_threshold="supermajority")
    d = decide(cfg, [
        _v("OVERTURN", alt="Option B", id="p0"),
        _v("OVERTURN", alt="Option B", id="p1", role="PE"),
        _v("HOLD", id="p2", role="QA"),
    ])
    assert d.verdict == "HARD-DISSENT"


def test_n3_supermajority_one_overturn_below_threshold_is_soft():
    cfg = _config(3, hard_threshold="supermajority")
    d = decide(cfg, [
        _v("OVERTURN", alt="Option B", id="p0"),
        _v("HOLD", id="p1", role="PE"),
        _v("HOLD", id="p2", role="QA"),
    ])
    assert d.verdict == "SOFT-DISSENT"


# ---- N=5 ----

def test_n5_majority_three_overturns_meets_threshold():
    """ceil(5/2)=3; 3 OVERTURN crosses majority at N=5."""
    cfg = _config(5)
    d = decide(cfg, [
        _v("OVERTURN", alt="Option B", id=f"p{i}", role=f"R{i}")
        for i in range(3)
    ] + [_v("HOLD", id="p3", role="R3"), _v("HOLD", id="p4", role="R4")])
    assert d.verdict == "HARD-DISSENT"


def test_n5_supermajority_three_overturns_below_threshold():
    """ceil(2*5/3)=4; 3 OVERTURN does NOT cross supermajority at N=5."""
    cfg = _config(5, hard_threshold="supermajority")
    d = decide(cfg, [
        _v("OVERTURN", alt="Option B", id=f"p{i}", role=f"R{i}")
        for i in range(3)
    ] + [_v("HOLD", id="p3", role="R3"), _v("HOLD", id="p4", role="R4")])
    assert d.verdict == "SOFT-DISSENT"


# ---- ERROR cascade + degradation ----

def test_n3_strict_one_error_emits_error_directive():
    cfg = _config(3, on_panelist_error="strict")
    d = decide(cfg, [
        _v("ERROR", rationale="backend down", id="p0"),
        _v("OVERTURN", alt="Option B", id="p1", role="PE"),
        _v("HOLD", id="p2", role="QA"),
    ])
    assert d.verdict == "ERROR"


def test_n3_auto_one_error_resolves_to_strict_emits_error():
    """auto mode at N=3 → strict → ERROR."""
    cfg = _config(3, on_panelist_error="auto")
    d = decide(cfg, [
        _v("ERROR", id="p0"),
        _v("HOLD", id="p1", role="PE"),
        _v("HOLD", id="p2", role="QA"),
    ])
    assert d.verdict == "ERROR"


def test_n5_graceful_one_error_degrades_to_three():
    """graceful drops the ERROR panelist; surviving N=4 is even, drop 1 more to 3."""
    cfg = _config(5, on_panelist_error="graceful")
    d = decide(cfg, [
        _v("ERROR", id="p0"),
        _v("HOLD", id="p1", role="PE"),
        _v("HOLD", id="p2", role="QA"),
        _v("HOLD", id="p3", role="R3"),
        _v("HOLD", id="p4", role="R4"),
    ])
    assert d.verdict == "HOLD"
    assert len(d.panelists) == 3


def test_n5_auto_one_error_resolves_to_graceful_degrades_to_three():
    """auto mode at N=5 → graceful → degrade ERROR + keep odd."""
    cfg = _config(5, on_panelist_error="auto")
    d = decide(cfg, [
        _v("ERROR", id="p0"),
        _v("OVERTURN", alt="Option B", id="p1", role="PE"),
        _v("OVERTURN", alt="Option B", id="p2", role="QA"),
        _v("HOLD", id="p3", role="R3"),
        _v("HOLD", id="p4", role="R4"),
    ])
    # After dropping ERROR and 1 more, 3 remain. 2 OVERTURN of 3 → HARD.
    assert d.verdict == "HARD-DISSENT"


def test_n3_two_errors_cannot_degrade_emits_error():
    """N=3, 2 ERROR → surviving < 1, mandatory ERROR even in graceful."""
    cfg = _config(3, on_panelist_error="graceful")
    d = decide(cfg, [
        _v("ERROR", id="p0"),
        _v("ERROR", id="p1", role="PE"),
        _v("HOLD", id="p2", role="QA"),
    ])
    assert d.verdict == "ERROR"


# ---- Rationale gate ----

def test_gate_passes_on_concrete_alternative():
    """Any OVERTURN with a concrete alt makes gate pass."""
    cfg = _config(3)
    d = decide(cfg, [
        _v("OVERTURN", alt="Option B", rationale="cost concern", id="p0"),
        _v("OVERTURN", alt="Option B", rationale="cost concern", id="p1", role="PE"),
        _v("HOLD", id="p2", role="QA"),
    ])
    assert d.verdict == "HARD-DISSENT"
    assert d.rationale_gate_passed is True


def test_gate_passes_on_principle_naming_in_rationale():
    """Principle keyword in rationale (e.g., YAGNI) makes gate pass."""
    cfg = _config(3)
    d = decide(cfg, [
        _v("OVERTURN", alt="Option B",
           rationale="This violates the YAGNI principle directly.", id="p0"),
        _v("OVERTURN", alt="Option B",
           rationale="violates atomicity by bundling two concerns.",
           id="p1", role="PE"),
        _v("HOLD", id="p2", role="QA"),
    ])
    assert d.verdict == "HARD-DISSENT"
    assert d.rationale_gate_passed is True


# ---- Cycle handling (Phase 3c default + Phase 5+ ready) ----

def test_cycle_none_phase3c_default_escalates_immediately():
    cfg = _config(3)
    d = decide(cfg, [
        _v("OVERTURN", alt="Option B", id="p0"),
        _v("OVERTURN", alt="Option B", id="p1", role="PE"),
        _v("HOLD", id="p2", role="QA"),
    ], cycle=None)
    assert d.verdict == "HARD-DISSENT"
    assert d.escalate_to_user is True
    assert d.re_brainstorm is None


def test_cycle_zero_emits_re_brainstorm_payload():
    """Phase 5+: cycle=0, max=2 → emit re_brainstorm payload, no escalation."""
    cfg = _config(3, max_cycles=2)
    d = decide(cfg, [
        _v("OVERTURN", alt="Option B", id="p0"),
        _v("OVERTURN", alt="Option B", id="p1", role="PE"),
        _v("HOLD", id="p2", role="QA"),
    ], cycle=0)
    assert d.verdict == "HARD-DISSENT"
    assert d.escalate_to_user is None
    assert d.re_brainstorm is not None
    assert d.re_brainstorm.cycle == 0
    assert d.re_brainstorm.max_cycles == 2


def test_cycle_at_cap_escalates():
    """Phase 5+: cycle=max → escalate, no re-brainstorm payload."""
    cfg = _config(3, max_cycles=2)
    d = decide(cfg, [
        _v("OVERTURN", alt="Option B", id="p0"),
        _v("OVERTURN", alt="Option B", id="p1", role="PE"),
        _v("HOLD", id="p2", role="QA"),
    ], cycle=2)
    assert d.verdict == "HARD-DISSENT"
    assert d.escalate_to_user is True
    assert d.re_brainstorm is None


# ---- Summary text + sanitization ----

def test_hold_summary_lists_each_panelist_with_abbreviation():
    cfg = _config(3)
    d = decide(cfg, [
        _v("HOLD", rationale="Option A is fine. Other notes follow.", id="p0"),
        _v("HOLD", rationale="Aligns with stated principles.", id="p1", role="PE"),
        _v("HOLD", rationale="Testable as written.", id="p2", role="QA"),
    ])
    assert "DA:" in d.summary
    assert "PE:" in d.summary
    assert "QA:" in d.summary


def test_dissent_summary_uses_panel_review_sentinel():
    """SKILL.md parses this exact sentinel."""
    cfg = _config(1)
    d = decide(cfg, [_v("OVERTURN", alt="Option B",
                       rationale="cost considerations matter here")])
    assert d.summary.startswith("**Panel review:** ")


def test_summary_strips_markdown_injection():
    """sanitize.strip_markdown integration check."""
    cfg = _config(1)
    d = decide(cfg, [_v(
        "OVERTURN", alt="Option B",
        rationale="See [link](http://evil.example.com) and `rm -rf /`.",
    )])
    assert "evil.example.com" not in d.summary
    assert "`" not in d.summary


# ---- Mutation-resistance probes ----

def test_threshold_uses_ceiling_not_floor():
    """ceil(3/2)=2, not floor(3/2)=1. Off-by-one mutation must fail."""
    cfg = _config(3)
    # 1 OVERTURN: should be SOFT (1 < 2), not HARD (1 < floor(3/2)=1 false).
    d = decide(cfg, [
        _v("OVERTURN", alt="Option B", id="p0"),
        _v("HOLD", id="p1", role="PE"),
        _v("HOLD", id="p2", role="QA"),
    ])
    assert d.verdict == "SOFT-DISSENT"  # If implementation used floor → HARD.


def test_gate_uses_any_not_all():
    """gate passes if ANY overturn names principle or alt."""
    cfg = _config(3)
    # Both overturns have alt → gate passes (any). HARD.
    d = decide(cfg, [
        _v("OVERTURN", alt="Option B", rationale="vague", id="p0"),
        _v("OVERTURN", alt="Option B", rationale="vague", id="p1", role="PE"),
        _v("HOLD", id="p2", role="QA"),
    ])
    assert d.verdict == "HARD-DISSENT"
