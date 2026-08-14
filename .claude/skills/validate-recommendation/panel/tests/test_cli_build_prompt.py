"""CLI tests for `panel build-prompt`.

The leak assertions in test_prompt.py cover build_prompt_body itself. They
say nothing about the WIRING: if this CLI branch passed the wrong blind=
argument — hardcoded, or read off the wrong panelist — every blinded
panelist's prompt would carry the recommendation and test_prompt.py would
stay green. These tests cover that seam, so they run the real branch with
no mocking: a real config, a real question file, a real output file.

The blinded and unblinded cases share one config and one invocation style.
Only the --panelist id differs, so a CLI that blinds unconditionally (or
never blinds) fails one of the two.
"""
import json
import textwrap

QUESTION = "Which HTTP client should we use?"
RECOMMENDED = "Use net/http (Recommended)"
# Per SKILL.md "Reasoning extraction", the reasoning IS the recommended
# option's description. The payload mirrors that, so these tests exercise the
# shape the real caller writes.
REASONING = "stdlib is sufficient and avoids dependency cost"


def _write_config(tmp_path):
    """Three enabled panelists (the odd-N invariant); only 'pe' is blinded."""
    p = tmp_path / "config.yml"
    p.write_text(textwrap.dedent("""
        version: 1
        panelists:
          - id: pe
            role: principal-engineer
            enabled: true
            backend: claude-subagent
            subagent_type: principal-engineer
            blind: true
          - id: qa
            role: qa-engineer
            enabled: true
            backend: claude-subagent
            subagent_type: qa-engineer
          - id: da
            role: DA
            enabled: true
            backend: nat-nim
            model: test-model
    """).strip() + "\n")
    return p


def _write_question(tmp_path):
    p = tmp_path / "q.json"
    p.write_text(json.dumps({
        "question": QUESTION,
        "options": [
            {"label": RECOMMENDED, "description": REASONING},
            {"label": "Use resty", "description": "third-party with retries"},
            {"label": "Use fasthttp", "description": "faster, incompatible interface"},
        ],
        "recommended_label": RECOMMENDED,
        "reasoning": REASONING,
    }), encoding="utf-8")
    return p


def _run(tmp_path, panelist, out_name="body.txt"):
    from panel.cli import main
    out = tmp_path / out_name
    rc = main([
        "build-prompt",
        "--panelist", panelist,
        "--config", str(_write_config(tmp_path)),
        "--question-file", str(_write_question(tmp_path)),
        "--output", str(out),
    ])
    return rc, out


def test_cli_build_prompt_blinds_a_blinded_panelist(tmp_path):
    """The payload CARRIES a reasoning field; the CLI must drop it.

    build_prompt_body raises ValueError on a blinded build with a non-empty
    reasoning, so rc == 0 here is itself proof that the CLI dropped it rather
    than forwarding it.
    """
    rc, out = _run(tmp_path, "pe")
    # guard the premise: if the payload ever stops carrying a reasoning, this
    # test silently stops proving anything.
    payload = json.loads((tmp_path / "q.json").read_text(encoding="utf-8"))
    assert payload["reasoning"] == REASONING

    assert rc == 0
    body = out.read_text(encoding="utf-8")
    assert "(Recommended)" not in body
    assert "Assistant's" not in body
    # the options themselves survive, marker-stripped
    assert "Use net/http" in body
    assert "Use resty" in body
    assert "Use fasthttp" in body


def test_cli_build_prompt_does_not_blind_an_unblinded_panelist(tmp_path):
    """The discriminating half: same config, same invocation, other id.

    Without this a CLI that blinded every panelist unconditionally would
    pass the blinded test and ship.
    """
    rc, out = _run(tmp_path, "qa")
    assert rc == 0
    body = out.read_text(encoding="utf-8")
    assert "Assistant's recommended option: Use net/http (Recommended)" in body
    assert f"Assistant's stated reasoning: {REASONING}" in body
    assert "(Recommended)" in body


def test_cli_build_prompt_unknown_panelist_returns_1(tmp_path):
    rc, out = _run(tmp_path, "nope")
    assert rc == 1
    assert not out.exists()
