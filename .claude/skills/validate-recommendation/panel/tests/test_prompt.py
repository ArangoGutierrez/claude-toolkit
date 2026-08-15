"""Prompt construction, including authorship blinding."""
import pytest

from panel.prompt import build_prompt_body, strip_marker

QUESTION = "Which HTTP client should we use?"
# The real caller derives `reasoning` from the recommended option's OWN
# description -- SKILL.md, "Reasoning extraction": "The recommended option's
# `description` field (primary source)". A fixture whose REASONING matches no
# description tests a payload that never occurs, and makes any
# "reasoning is absent" assertion unfalsifiable.
REASONING = "stdlib is sufficient and avoids dependency cost"
OPTIONS = [
    ("Use net/http (Recommended)", REASONING),
    ("Use resty", "third-party with retries"),
    ("Use fasthttp", "faster, incompatible interface"),
]
RECOMMENDED = "Use net/http (Recommended)"

NO_REASONING = ""  # what a blinded panelist's caller must pass


def test_strip_marker_removes_both_marker_forms():
    assert strip_marker("Use net/http (Recommended)") == "Use net/http"
    assert strip_marker("Use net/http (Recommended; Panel-flagged)") == "Use net/http"
    assert strip_marker("Use resty") == "Use resty"


def test_unblinded_prompt_names_the_recommendation():
    body = build_prompt_body(QUESTION, OPTIONS, RECOMMENDED, REASONING, blind=False)
    assert "Assistant's recommended option: Use net/http (Recommended)" in body
    assert f"Assistant's stated reasoning: {REASONING}" in body
    assert "(Recommended)" in body


def test_blinded_build_refuses_a_nonempty_reasoning():
    """The precondition, not the formatter, is what keeps the reasoning out.

    Omitting the reasoning was previously a side effect of which lines the
    blinded branch happens to append. A caller passing reasoning got silence.
    It must get a loud error instead.
    """
    with pytest.raises(ValueError) as exc:
        build_prompt_body(QUESTION, OPTIONS, RECOMMENDED, REASONING, blind=True)
    assert str(exc.value) == (
        "blinded panelists must not receive the assistant's stated reasoning"
    )


def test_blinded_prompt_leaks_nothing_about_the_recommendation():
    body = build_prompt_body(QUESTION, OPTIONS, RECOMMENDED, NO_REASONING, blind=True)
    assert "(Recommended)" not in body
    assert "Panel-flagged" not in body
    # One substring covers both attributed lines, so a renamed label cannot
    # slip past a pair of narrower checks.
    assert "Assistant's" not in body
    # NOTE: asserting `REASONING not in body` is deliberately absent. Under the
    # documented convention the reasoning IS the recommended option's
    # description, and a blinded panelist must see every description to choose
    # on the merits. The text therefore appears -- identically to every other
    # option's description, so it identifies nothing. The leak that matters is
    # ATTRIBUTION, which the assertion above and the ValueError guard cover.
    for label, _desc in OPTIONS:
        assert strip_marker(label) in body


def test_blinded_prompt_asks_for_CHOICE_not_a_verdict():
    body = build_prompt_body(QUESTION, OPTIONS, RECOMMENDED, NO_REASONING, blind=True)
    assert "CHOICE:" in body
    assert "VERDICT:" not in body


def test_blinded_option_order_is_deterministic_across_calls():
    a = build_prompt_body(QUESTION, OPTIONS, RECOMMENDED, NO_REASONING, blind=True)
    b = build_prompt_body(QUESTION, OPTIONS, RECOMMENDED, NO_REASONING, blind=True)
    assert a == b


def test_blinded_option_order_does_not_simply_preserve_input_order():
    """The recommended option is conventionally first; rotation must move it
    for at least one question, or blinding leaves a positional tell."""
    rotated_somewhere = False
    for q in ("q-alpha", "q-beta", "q-gamma", "q-delta", "q-epsilon"):
        body = build_prompt_body(q, OPTIONS, RECOMMENDED, NO_REASONING, blind=True)
        first_option_line = [
            ln for ln in body.splitlines() if ln.startswith("  ")
        ][0]
        if not first_option_line.startswith("  Use net/http"):
            rotated_somewhere = True
            break
    assert rotated_somewhere, "rotation never moved the recommended option off position 0"


def test_blinded_order_depends_on_question_text():
    """Two questions must produce two DIFFERENT orderings of the same options.

    Asserting only `set(order_a) == set(order_b)` is order-insensitive: it
    stays green with rotation removed entirely.
    """
    a = build_prompt_body("question one", OPTIONS, RECOMMENDED, NO_REASONING, blind=True)
    b = build_prompt_body("question two", OPTIONS, RECOMMENDED, NO_REASONING, blind=True)
    order_a = [ln for ln in a.splitlines() if ln.startswith("  ")]
    order_b = [ln for ln in b.splitlines() if ln.startswith("  ")]
    assert order_a != order_b, "question text did not change the option order"
    assert set(order_a) == set(order_b), "orderings must be permutations of each other"


def test_single_option_does_not_crash_rotation():
    body = build_prompt_body(QUESTION, [("Only choice", "d")], "Only choice", NO_REASONING, blind=True)
    assert "Only choice" in body


def test_zero_options_does_not_crash_rotation():
    """n=0 is the input that actually pins `if n <= 1: return 0`.

    n=1 does not: `% 1` is 0 anyway, so deleting the guard leaves n=1 green.
    n=0 raises ZeroDivisionError without it.
    """
    body = build_prompt_body(QUESTION, [], "", NO_REASONING, blind=True)
    assert "CHOICE:" in body
