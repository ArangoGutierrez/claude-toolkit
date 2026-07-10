"""Pure severity decision tree for the N-panelist validate-recommendation panel.

No I/O, no logging from this module (logging is the aggregator's job). Inputs:
config + parsed verdicts. Output: a Directive dataclass instance.

Phase 3c contract:
- HARD-DISSENT escalates to user immediately when cycle is None (no state
  machine). The re_brainstorm payload is reserved for Phase 5+.
- Phase 1 bug #3 preservation: OVERTURN + alternative='n/a' → coerced to ERROR.
- ERROR cascade via failure_mode (strict/graceful/auto).
"""
from __future__ import annotations

import math
import re
from dataclasses import dataclass

from panel.config import Config
from panel.sanitize import strip_markdown


@dataclass
class ParsedVerdict:
    id: str
    role: str
    verdict: str        # "HOLD" | "OVERTURN" | "ERROR"
    rationale: str
    alternative: str    # option label or "n/a"


@dataclass
class PanelistRow:
    id: str
    role: str
    verdict: str
    rationale: str
    alternative: str


@dataclass
class ReBrainstormPayload:
    cycle: int
    max_cycles: int
    suggested_alternatives: list[str]
    feedback_for_claude: str


@dataclass
class Directive:
    verdict: str                                       # HOLD | SOFT-DISSENT | HARD-DISSENT | ERROR
    summary: str
    rationale_gate_passed: bool | None
    panelists: list[PanelistRow]
    re_brainstorm: ReBrainstormPayload | None = None
    escalate_to_user: bool | None = None


def decide(
    config: Config,
    panelists: list[ParsedVerdict],
    cycle: int | None = None,
) -> Directive:
    """Decide the panel directive from N parsed verdicts.

    cycle=None  → Phase 3c semantics; HARD-DISSENT always escalates.
    cycle=int   → Phase 5+ semantics; HARD-DISSENT emits re-think payload
                  while cycle < max_cycles; escalates at cap.
    """
    normalized = [_validate(p) for p in panelists]

    n_error = sum(1 for p in normalized if p.verdict == "ERROR")
    n_total = len(normalized)

    if n_error > 0:
        mode = _resolve_failure_mode(config, n_total)
        if mode == "strict" or (n_total - 2 * n_error) < 1:
            return _error_directive(
                normalized,
                _failure_summary(n_total, n_error, mode),
            )
        normalized = _degrade_keeping_odd(normalized)

    overturns = [p for p in normalized if p.verdict == "OVERTURN"]
    n = len(normalized)
    threshold = (
        math.ceil(n / 2)
        if config.severity.hard_threshold == "majority"
        else math.ceil(2 * n / 3)
    )

    if not overturns:
        return _hold_directive(normalized)

    if len(overturns) < threshold:
        return _soft_dissent_directive(normalized, gate_passed=False)

    gate_passed = _gate_passed(
        overturns,
        config.severity.rationale_gate.principle_patterns,
    )
    if not gate_passed:
        return _soft_dissent_directive(normalized, gate_passed=False)

    if cycle is None or cycle >= config.re_brainstorm.max_cycles:
        return _hard_dissent_directive(
            normalized, gate_passed=True, escalate_to_user=True,
        )
    return _hard_dissent_directive(
        normalized, gate_passed=True,
        re_brainstorm=_build_payload(overturns, cycle, config),
    )


# ---- private helpers ----

def _validate(p: ParsedVerdict) -> ParsedVerdict:
    """Normalize a panelist verdict; coerce malformed → ERROR."""
    if p.verdict not in ("HOLD", "OVERTURN", "ERROR"):
        return ParsedVerdict(
            id=p.id, role=p.role, verdict="ERROR",
            rationale=(p.rationale or "verdict field unparseable"),
            alternative="n/a",
        )
    if p.verdict == "OVERTURN":
        alt = (p.alternative or "").strip().lower()
        if alt in ("n/a", ""):
            return ParsedVerdict(
                id=p.id, role=p.role, verdict="ERROR",
                rationale="OVERTURN without concrete ALTERNATIVE (Phase 1 bug #3)",
                alternative="n/a",
            )
    if not (p.rationale or "").strip():
        return ParsedVerdict(
            id=p.id, role=p.role, verdict="ERROR",
            rationale="rationale field empty",
            alternative="n/a",
        )
    return p


def _resolve_failure_mode(config: Config, n_total: int) -> str:
    mode = config.failure_mode.on_panelist_error
    if mode in ("strict", "graceful"):
        return mode
    return "strict" if n_total in (1, 3) else "graceful"


def _degrade_keeping_odd(panelists: list[ParsedVerdict]) -> list[ParsedVerdict]:
    """Drop ERROR panelists; if surviving count is even, drop one more."""
    surviving = [p for p in panelists if p.verdict != "ERROR"]
    if surviving and (len(surviving) % 2 == 0):
        surviving = surviving[:-1]
    return surviving


def _gate_passed(overturns: list[ParsedVerdict], patterns: list[str]) -> bool:
    """Rationale gate: any OVERTURN names a principle or has concrete alt.

    Note (Phase 3c invariants): _validate() coerces every OVERTURN with
    alt='n/a' or empty alt to ERROR before this function is reached, so
    every surviving OVERTURN here has a concrete alternative and the
    alt-check arm always returns True. The principle-patterns loop is
    therefore unreachable in Phase 3c. It is kept for forward
    compatibility — Phase 5+ may relax _validate() to let principled
    OVERTURNs with alt='n/a' survive, at which point this loop becomes
    live. Do not remove without revisiting _validate()'s OVERTURN+n/a
    coercion.
    """
    compiled = [re.compile(pat, re.IGNORECASE) for pat in patterns]
    for p in overturns:
        if (p.alternative or "").strip().lower() not in ("n/a", ""):
            return True
        for rx in compiled:
            if rx.search(p.rationale or ""):
                return True
    return False


# ---- directive builders ----

def _hold_directive(panelists: list[ParsedVerdict]) -> Directive:
    parts = []
    for p in panelists:
        first = _abbreviate_first_sentence(p.rationale)
        parts.append(f"{p.role}: {strip_markdown(first)}.")
    return Directive(
        verdict="HOLD",
        summary=" ".join(parts),
        rationale_gate_passed=True,
        panelists=[_row(p) for p in panelists],
    )


def _soft_dissent_directive(
    panelists: list[ParsedVerdict], *, gate_passed: bool,
) -> Directive:
    return Directive(
        verdict="SOFT-DISSENT",
        summary=_panel_review_summary(panelists),
        rationale_gate_passed=gate_passed,
        panelists=[_row(p) for p in panelists],
    )


def _hard_dissent_directive(
    panelists: list[ParsedVerdict],
    *,
    gate_passed: bool,
    escalate_to_user: bool = False,
    re_brainstorm: ReBrainstormPayload | None = None,
) -> Directive:
    return Directive(
        verdict="HARD-DISSENT",
        summary=_panel_review_summary(panelists),
        rationale_gate_passed=gate_passed,
        panelists=[_row(p) for p in panelists],
        escalate_to_user=(True if escalate_to_user else None),
        re_brainstorm=re_brainstorm,
    )


def _error_directive(
    panelists: list[ParsedVerdict], reason: str,
) -> Directive:
    return Directive(
        verdict="ERROR",
        summary=reason,
        rationale_gate_passed=None,
        panelists=[_row(p) for p in panelists],
    )


def _row(p: ParsedVerdict) -> PanelistRow:
    return PanelistRow(
        id=p.id, role=p.role, verdict=p.verdict,
        rationale=strip_markdown(p.rationale or ""),
        alternative=strip_markdown(p.alternative or "n/a"),
    )


def _panel_review_summary(panelists: list[ParsedVerdict]) -> str:
    """Compose the dissent summary text.

    Note: the spec's example summaries name the recommended option in the
    flagged text (e.g., 'DA flagged Option A → suggests Option B: ...').
    This function does NOT currently interpolate the recommended_label
    because decide() does not receive it (cycle is the only optional
    arg). The current output reads 'DA flagged → suggests Option B: ...'
    — grammatically incomplete but information-preserving. Re-threading
    recommended_label through decide() to enable the antecedent is
    deferred to a later phase.
    """
    parts = []
    for p in panelists:
        rat = strip_markdown(p.rationale or "")
        if p.verdict == "OVERTURN":
            alt = strip_markdown(p.alternative or "n/a")
            parts.append(f"{p.role} flagged → suggests {alt}: {rat}")
        elif p.verdict == "HOLD":
            parts.append(f"{p.role} held: {rat}")
        else:  # ERROR
            parts.append(f"{p.role} errored: {rat}")
    return "**Panel review:** " + " ".join(parts)


def _failure_summary(n_total: int, n_error: int, mode: str) -> str:
    return (
        f"panelist errors exceed failure-mode tolerance "
        f"({mode}@N={n_total}: {n_error} of {n_total} panelists returned ERROR)"
    )


def _build_payload(
    overturns: list[ParsedVerdict], cycle: int, config: Config,
) -> ReBrainstormPayload:
    """Phase 5+ only; never called when cycle is None."""
    alts = sorted({
        strip_markdown(p.alternative)
        for p in overturns
        if (p.alternative or "").strip().lower() not in ("n/a", "")
    })
    feedback = " ".join(
        f"{p.role}: {strip_markdown(p.rationale or '')}"
        for p in overturns
    )
    return ReBrainstormPayload(
        cycle=cycle,
        max_cycles=config.re_brainstorm.max_cycles,
        suggested_alternatives=alts,
        feedback_for_claude=feedback,
    )


def _abbreviate_first_sentence(text: str) -> str:
    """Trim text after first sentence boundary (punct + ws + uppercase)."""
    match = re.search(r"^(.*?[.!?])\s+[A-Z]", text or "")
    if match:
        return match.group(1)
    return (text or "").strip()
