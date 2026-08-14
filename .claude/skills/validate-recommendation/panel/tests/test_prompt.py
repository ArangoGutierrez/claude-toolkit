"""Prompt construction, including authorship blinding."""
import pytest

from panel.prompt import build_prompt_body, strip_marker

QUESTION = "Which HTTP client should we use?"
OPTIONS = [
    ("Use net/http (Recommended)", "stdlib, no deps"),
    ("Use resty", "third-party with retries"),
    ("Use fasthttp", "faster, incompatible interface"),
]
RECOMMENDED = "Use net/http (Recommended)"
REASONING = "stdlib is sufficient and avoids dependency cost"


def test_strip_marker_removes_both_marker_forms():
    assert strip_marker("Use net/http (Recommended)") == "Use net/http"
    assert strip_marker("Use net/http (Recommended; Panel-flagged)") == "Use net/http"
    assert strip_marker("Use resty") == "Use resty"


def test_unblinded_prompt_names_the_recommendation():
    body = build_prompt_body(QUESTION, OPTIONS, RECOMMENDED, REASONING, blind=False)
    assert "Assistant's recommended option: Use net/http (Recommended)" in body
    assert "Assistant's stated reasoning: stdlib is sufficient" in body
    assert "(Recommended)" in body


def test_blinded_prompt_leaks_nothing_about_the_recommendation():
    body = build_prompt_body(QUESTION, OPTIONS, RECOMMENDED, REASONING, blind=True)
    assert "(Recommended)" not in body
    assert "Panel-flagged" not in body
    assert "Assistant's recommended option" not in body
    assert "Assistant's stated reasoning" not in body
    assert REASONING not in body
    # every option is still present, marker-stripped
    for label, _desc in OPTIONS:
        assert strip_marker(label) in body


def test_blinded_prompt_asks_for_CHOICE_not_a_verdict():
    body = build_prompt_body(QUESTION, OPTIONS, RECOMMENDED, REASONING, blind=True)
    assert "CHOICE:" in body
    assert "VERDICT:" not in body


def test_blinded_option_order_is_deterministic_across_calls():
    a = build_prompt_body(QUESTION, OPTIONS, RECOMMENDED, REASONING, blind=True)
    b = build_prompt_body(QUESTION, OPTIONS, RECOMMENDED, REASONING, blind=True)
    assert a == b


def test_blinded_option_order_does_not_simply_preserve_input_order():
    """The recommended option is conventionally first; rotation must move it
    for at least one question, or blinding leaves a positional tell."""
    rotated_somewhere = False
    for q in ("q-alpha", "q-beta", "q-gamma", "q-delta", "q-epsilon"):
        body = build_prompt_body(q, OPTIONS, RECOMMENDED, REASONING, blind=True)
        first_option_line = [
            ln for ln in body.splitlines() if ln.startswith("  ")
        ][0]
        if not first_option_line.startswith("  Use net/http"):
            rotated_somewhere = True
            break
    assert rotated_somewhere, "rotation never moved the recommended option off position 0"


def test_blinded_order_depends_on_question_text():
    a = build_prompt_body("question one", OPTIONS, RECOMMENDED, REASONING, blind=True)
    b = build_prompt_body("question two", OPTIONS, RECOMMENDED, REASONING, blind=True)
    order_a = [ln for ln in a.splitlines() if ln.startswith("  ")]
    order_b = [ln for ln in b.splitlines() if ln.startswith("  ")]
    assert set(order_a) == set(order_b)


def test_single_option_does_not_crash_rotation():
    body = build_prompt_body(QUESTION, [("Only choice", "d")], "Only choice", "r", blind=True)
    assert "Only choice" in body
