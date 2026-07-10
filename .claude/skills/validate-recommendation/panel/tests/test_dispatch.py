"""Tests for panel.dispatch — langchain-backed panelist dispatch.

The single mock seam is `panel.dispatch._invoke_nat`. Tests never mock
requests/httpx/langchain.* directly — that couples to upstream internals
and breaks on version bumps.

Test surface:
- Happy path: well-formed response → verdict file with HOLD/OVERTURN
- Error paths (all write VERDICT: ERROR; all exit 0):
  - _invoke_nat raises (network, timeout)
  - Response missing VERDICT/RATIONALE/ALTERNATIVE lines
  - Response has OVERTURN + ALTERNATIVE: n/a (Phase 1 bug #3 preservation)
  - Unsupported backend (ValueError from _invoke_nat)
- Caller-bug paths (exit non-zero, no verdict written):
  - Missing config file
  - Missing persona file
  - Missing prompt file
  - panelist_id not in config
- File mode 0600 (umask 077)
- Response shape variations: object with .content / dict / plain string
"""
import os
import stat
import textwrap
from pathlib import Path
from unittest.mock import patch

import pytest


def _fixture_files(tmp_path, *, panelist_id="da", backend="nat-nim",
                   model="test-model"):
    cfg_path = tmp_path / "config.yml"
    cfg_path.write_text(textwrap.dedent(f"""
        version: 1
        panelists:
          - id: {panelist_id}
            role: DA
            enabled: true
            backend: {backend}
            model: {model}
    """).strip() + "\n")

    persona_path = tmp_path / "persona.md"
    persona_path.write_text(textwrap.dedent("""
        ---
        role: DA
        description: test persona
        intended_backends: [nat-nim]
        ---

        # System prompt

        You are a test reviewer. Output VERDICT: ... etc.

        # One-shot example

        Example output:
        VERDICT: HOLD
        RATIONALE: nothing to add
        ALTERNATIVE: n/a

        # User prompt template

        Question: <q>
    """).strip() + "\n")

    prompt_path = tmp_path / "prompt.txt"
    prompt_path.write_text("Question: Should we pick option A?\n")

    output_path = tmp_path / "verdict.txt"
    return cfg_path, persona_path, prompt_path, output_path


class _FakeAIMessage:
    """Shape mirrors langchain.schema.AIMessage (has .content)."""
    def __init__(self, content: str):
        self.content = content


def test_dispatch_writes_well_formed_hold_verdict_on_happy_path(tmp_path):
    from panel.dispatch import dispatch
    cfg, persona, prompt, out = _fixture_files(tmp_path)
    fake_response = _FakeAIMessage(
        "VERDICT: HOLD\n"
        "RATIONALE: The recommendation aligns with stated goals.\n"
        "ALTERNATIVE: n/a\n"
    )
    with patch("panel.dispatch._invoke_nat", return_value=fake_response):
        rc = dispatch(panelist_id="da", config_path=cfg, persona_path=persona,
                      prompt_file=prompt, output=out)
    assert rc == 0
    written = out.read_text(encoding="utf-8")
    assert "VERDICT: HOLD" in written
    assert "RATIONALE: " in written
    assert "ALTERNATIVE: n/a" in written


def test_dispatch_writes_overturn_verdict_with_alternative(tmp_path):
    from panel.dispatch import dispatch
    cfg, persona, prompt, out = _fixture_files(tmp_path)
    fake_response = _FakeAIMessage(
        "VERDICT: OVERTURN\n"
        "RATIONALE: Option B better matches stated constraints.\n"
        "ALTERNATIVE: Option B\n"
    )
    with patch("panel.dispatch._invoke_nat", return_value=fake_response):
        rc = dispatch(panelist_id="da", config_path=cfg, persona_path=persona,
                      prompt_file=prompt, output=out)
    assert rc == 0
    written = out.read_text(encoding="utf-8")
    assert "VERDICT: OVERTURN" in written
    assert "ALTERNATIVE: Option B" in written


def test_dispatch_writes_error_verdict_on_network_exception(tmp_path):
    from panel.dispatch import dispatch
    cfg, persona, prompt, out = _fixture_files(tmp_path)
    with patch("panel.dispatch._invoke_nat",
               side_effect=ConnectionError("backend unreachable")):
        rc = dispatch(panelist_id="da", config_path=cfg, persona_path=persona,
                      prompt_file=prompt, output=out)
    assert rc == 0
    written = out.read_text(encoding="utf-8")
    assert "VERDICT: ERROR" in written
    assert "backend unreachable" in written


def test_dispatch_writes_error_verdict_on_malformed_response(tmp_path):
    from panel.dispatch import dispatch
    cfg, persona, prompt, out = _fixture_files(tmp_path)
    fake_response = _FakeAIMessage("This is not a verdict; the model rambled.")
    with patch("panel.dispatch._invoke_nat", return_value=fake_response):
        rc = dispatch(panelist_id="da", config_path=cfg, persona_path=persona,
                      prompt_file=prompt, output=out)
    assert rc == 0
    assert "VERDICT: ERROR" in out.read_text(encoding="utf-8")


def test_dispatch_writes_error_on_overturn_with_alternative_na(tmp_path):
    """Phase 1 bug #3: OVERTURN + ALTERNATIVE: n/a must be rejected."""
    from panel.dispatch import dispatch
    cfg, persona, prompt, out = _fixture_files(tmp_path)
    fake_response = _FakeAIMessage(
        "VERDICT: OVERTURN\n"
        "RATIONALE: I disagree but have no concrete suggestion.\n"
        "ALTERNATIVE: n/a\n"
    )
    with patch("panel.dispatch._invoke_nat", return_value=fake_response):
        rc = dispatch(panelist_id="da", config_path=cfg, persona_path=persona,
                      prompt_file=prompt, output=out)
    assert rc == 0
    written = out.read_text(encoding="utf-8")
    assert "VERDICT: ERROR" in written


def test_dispatch_writes_verdict_file_mode_0600(tmp_path):
    from panel.dispatch import dispatch
    cfg, persona, prompt, out = _fixture_files(tmp_path)
    fake_response = _FakeAIMessage(
        "VERDICT: HOLD\nRATIONALE: ok\nALTERNATIVE: n/a\n"
    )
    with patch("panel.dispatch._invoke_nat", return_value=fake_response):
        dispatch(panelist_id="da", config_path=cfg, persona_path=persona,
                 prompt_file=prompt, output=out)
    mode = stat.S_IMODE(os.stat(out).st_mode)
    assert mode == 0o600, f"expected 0o600, got 0o{mode:o}"


def test_dispatch_returns_nonzero_on_missing_config(tmp_path):
    from panel.dispatch import dispatch
    _, persona, prompt, out = _fixture_files(tmp_path)
    rc = dispatch(panelist_id="da",
                  config_path=tmp_path / "no-config.yml",
                  persona_path=persona, prompt_file=prompt, output=out)
    assert rc != 0
    assert not out.exists()


def test_dispatch_returns_nonzero_on_missing_persona(tmp_path):
    from panel.dispatch import dispatch
    cfg, _, prompt, out = _fixture_files(tmp_path)
    rc = dispatch(panelist_id="da", config_path=cfg,
                  persona_path=tmp_path / "no-persona.md",
                  prompt_file=prompt, output=out)
    assert rc != 0
    assert not out.exists()


def test_dispatch_returns_nonzero_on_missing_prompt(tmp_path):
    from panel.dispatch import dispatch
    cfg, persona, _, out = _fixture_files(tmp_path)
    rc = dispatch(panelist_id="da", config_path=cfg, persona_path=persona,
                  prompt_file=tmp_path / "no-prompt.txt", output=out)
    assert rc != 0
    assert not out.exists()


def test_dispatch_returns_nonzero_on_panelist_id_not_in_config(tmp_path):
    from panel.dispatch import dispatch
    cfg, persona, prompt, out = _fixture_files(tmp_path)
    rc = dispatch(panelist_id="not-a-real-id", config_path=cfg,
                  persona_path=persona, prompt_file=prompt, output=out)
    assert rc != 0
    assert not out.exists()


def test_dispatch_threads_system_prompt_and_user_to_invoke_nat(tmp_path):
    from panel.dispatch import dispatch
    cfg, persona, prompt, out = _fixture_files(tmp_path)
    captured = {}
    def fake_invoke(panelist, system, user):
        captured["system"] = system
        captured["user"] = user
        captured["panelist_id"] = panelist.id
        return _FakeAIMessage("VERDICT: HOLD\nRATIONALE: ok\nALTERNATIVE: n/a\n")
    with patch("panel.dispatch._invoke_nat", side_effect=fake_invoke):
        dispatch(panelist_id="da", config_path=cfg, persona_path=persona,
                 prompt_file=prompt, output=out)
    assert "test reviewer" in captured["system"]
    assert "Example output" in captured["system"]
    assert "Should we pick option A?" in captured["user"]
    assert captured["panelist_id"] == "da"


def test_dispatch_response_with_content_attribute_extracted(tmp_path):
    from panel.dispatch import dispatch
    cfg, persona, prompt, out = _fixture_files(tmp_path)
    with patch("panel.dispatch._invoke_nat",
               return_value=_FakeAIMessage(
                   "VERDICT: HOLD\nRATIONALE: ok\nALTERNATIVE: n/a\n")):
        rc = dispatch(panelist_id="da", config_path=cfg, persona_path=persona,
                      prompt_file=prompt, output=out)
    assert rc == 0
    assert "VERDICT: HOLD" in out.read_text(encoding="utf-8")


def test_dispatch_response_as_dict_extracted(tmp_path):
    from panel.dispatch import dispatch
    cfg, persona, prompt, out = _fixture_files(tmp_path)
    with patch("panel.dispatch._invoke_nat",
               return_value={"content": "VERDICT: HOLD\nRATIONALE: ok\nALTERNATIVE: n/a\n"}):
        rc = dispatch(panelist_id="da", config_path=cfg, persona_path=persona,
                      prompt_file=prompt, output=out)
    assert rc == 0
    assert "VERDICT: HOLD" in out.read_text(encoding="utf-8")


def test_dispatch_response_as_plain_string_extracted(tmp_path):
    from panel.dispatch import dispatch
    cfg, persona, prompt, out = _fixture_files(tmp_path)
    with patch("panel.dispatch._invoke_nat",
               return_value="VERDICT: HOLD\nRATIONALE: ok\nALTERNATIVE: n/a\n"):
        rc = dispatch(panelist_id="da", config_path=cfg, persona_path=persona,
                      prompt_file=prompt, output=out)
    assert rc == 0
    assert "VERDICT: HOLD" in out.read_text(encoding="utf-8")


def test_dispatch_unsupported_backend_returns_error_verdict(tmp_path):
    """Unsupported backend → _invoke_nat raises ValueError → ERROR verdict, exit 0."""
    from panel.dispatch import dispatch
    cfg, persona, prompt, out = _fixture_files(tmp_path)
    cfg.write_text(textwrap.dedent("""
        version: 1
        panelists:
          - id: da
            role: DA
            enabled: true
            backend: claude-subagent
            subagent_type: principal-engineer
    """).strip() + "\n")
    rc = dispatch(panelist_id="da", config_path=cfg, persona_path=persona,
                  prompt_file=prompt, output=out)
    assert rc == 0
    written = out.read_text(encoding="utf-8")
    assert "VERDICT: ERROR" in written
    assert "claude-subagent" in written or "unsupported" in written.lower()


def test_invoke_nat_nim_threads_api_key_from_panel_da_env(monkeypatch):
    """_invoke_nat (nat-nim branch) reads $PANEL_DA_API_KEY and passes it
    to ChatNVIDIA. We mock ChatNVIDIA at the import site so we don't actually
    instantiate it; we just verify the kwargs are right.
    """
    from panel import dispatch as dispatch_mod
    from panel.config import Panelist

    monkeypatch.setenv("PANEL_DA_API_KEY", "k-from-panel-da-env")
    monkeypatch.delenv("NVIDIA_API_KEY", raising=False)
    monkeypatch.delenv("CLAUDE_PANEL_DA_ENDPOINT", raising=False)

    captured = {}

    class FakeChatNVIDIA:
        def __init__(self, **kwargs):
            captured.update(kwargs)
        def invoke(self, messages):
            return _FakeAIMessage(
                "VERDICT: HOLD\nRATIONALE: ok.\nALTERNATIVE: n/a\n"
            )

    import sys, types
    fake_mod = types.ModuleType("langchain_nvidia_ai_endpoints")
    fake_mod.ChatNVIDIA = FakeChatNVIDIA
    monkeypatch.setitem(sys.modules, "langchain_nvidia_ai_endpoints", fake_mod)

    panelist = Panelist(
        id="da-test", role="DA", enabled=True, backend="nat-nim",
        model="nvidia/test-model", max_tokens=8, temperature=0.0,
    )
    dispatch_mod._invoke_nat(panelist, "system prompt", "user prompt")

    assert captured["nvidia_api_key"] == "k-from-panel-da-env"
    assert captured["model"] == "nvidia/test-model"
    assert captured["temperature"] == 0.0
    assert captured["max_completion_tokens"] == 8
    assert "base_url" not in captured  # endpoint env var was unset


def test_invoke_nat_nim_strips_chat_completions_from_base_url(monkeypatch):
    """If $CLAUDE_PANEL_DA_ENDPOINT has the full chat-completions URL,
    _invoke_nat strips the suffix so ChatNVIDIA's base_url is the v1 base.
    """
    from panel import dispatch as dispatch_mod
    from panel.config import Panelist

    monkeypatch.setenv("PANEL_DA_API_KEY", "k")
    monkeypatch.setenv(
        "CLAUDE_PANEL_DA_ENDPOINT",
        "https://nim.example.com/v1/chat/completions",
    )

    captured = {}

    class FakeChatNVIDIA:
        def __init__(self, **kwargs):
            captured.update(kwargs)
        def invoke(self, messages):
            return _FakeAIMessage("VERDICT: HOLD\nRATIONALE: ok.\nALTERNATIVE: n/a\n")

    import sys, types
    fake_mod = types.ModuleType("langchain_nvidia_ai_endpoints")
    fake_mod.ChatNVIDIA = FakeChatNVIDIA
    monkeypatch.setitem(sys.modules, "langchain_nvidia_ai_endpoints", fake_mod)

    panelist = Panelist(
        id="da-test", role="DA", enabled=True, backend="nat-nim",
        model="nvidia/test", max_tokens=8, temperature=0.0,
    )
    dispatch_mod._invoke_nat(panelist, "system prompt", "user prompt")

    assert captured["base_url"] == "https://nim.example.com/v1"
    assert "/chat/completions" not in captured["base_url"]
