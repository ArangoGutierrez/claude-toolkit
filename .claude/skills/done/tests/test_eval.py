"""Tests for done/eval.py — mocks _invoke_nat only."""
from __future__ import annotations

import io
import json
import os
from unittest.mock import patch

import pytest

# Add the parent dir to sys.path so `import eval` works.
import pathlib, sys
sys.path.insert(0, str(pathlib.Path(__file__).parent.parent))
import eval as done_eval  # noqa: E402


def _make_goal() -> str:
    return (
        "## Initial 2026-05-18T10:00:00Z\n"
        "Goal: ship done-hook v1\n"
        "Acceptance:\n"
        "- ./done-hook_test.sh passes\n"
        "- shellcheck clean\n"
        "- spec committed\n"
    )


def _make_evidence(complete: bool) -> list[dict]:
    base = [
        {"cmd": "./done-hook_test.sh", "exit": 0, "ts": "2026-05-18T14:32Z"},
        {"cmd": "shellcheck ~/.claude/hooks/done-hook.sh", "exit": 0, "ts": "2026-05-18T14:33Z"},
    ]
    if complete:
        base.append({"cmd": "git commit", "subject": "docs(specs): add design", "sha": "f3a4b5c", "ts": "2026-05-18T14:15Z"})
    return base


def test_agree_path_returns_met():
    """When NAT returns AGREE, evaluate() yields verdict=AGREE + non-empty rationale."""
    fake_response = (
        "VERDICT: AGREE\n"
        "RATIONALE: All three bullets have supporting evidence.\n"
        "GAPS: n/a"
    )
    with patch.object(done_eval, "_invoke_nat", return_value=fake_response):
        result = done_eval.evaluate(_make_goal(), _make_evidence(complete=True), "MET")
    assert result["verdict"] == "AGREE"
    assert "All three bullets" in result["rationale"]
    assert result["gaps"] == []


def test_disagree_path_returns_disagree_with_gaps():
    """When NAT returns DISAGREE, evaluate() yields verdict=DISAGREE + GAPS list."""
    fake_response = (
        "VERDICT: DISAGREE\n"
        "RATIONALE: Spec committed but no evidence for shellcheck run.\n"
        "GAPS: shellcheck clean"
    )
    with patch.object(done_eval, "_invoke_nat", return_value=fake_response):
        result = done_eval.evaluate(_make_goal(), _make_evidence(complete=False), "MET")
    assert result["verdict"] == "DISAGREE"
    assert "shellcheck clean" in result["gaps"]


def test_insufficient_path_returns_insufficient():
    """When NAT returns INSUFFICIENT_EVIDENCE, evaluate() preserves that label."""
    fake_response = (
        "VERDICT: INSUFFICIENT_EVIDENCE\n"
        "RATIONALE: Bullets are vague; cannot judge.\n"
        "GAPS: n/a"
    )
    with patch.object(done_eval, "_invoke_nat", return_value=fake_response):
        result = done_eval.evaluate(_make_goal(), [], "MET")
    assert result["verdict"] == "INSUFFICIENT_EVIDENCE"


def test_error_fallback_when_nat_raises():
    """When _invoke_nat raises any exception, evaluate() returns verdict=ERROR."""
    def boom(*args, **kwargs):
        raise RuntimeError("NIM endpoint unreachable")
    with patch.object(done_eval, "_invoke_nat", side_effect=boom):
        result = done_eval.evaluate(_make_goal(), _make_evidence(complete=True), "MET")
    assert result["verdict"] == "ERROR"
    assert "NIM endpoint unreachable" in result["rationale"]


def test_error_fallback_when_response_lacks_verdict_line():
    """Malformed NAT response (no VERDICT line) → verdict=ERROR with parse-failed reason."""
    fake_response = "I think the goal might be met but I'm not sure."  # no strict format
    with patch.object(done_eval, "_invoke_nat", return_value=fake_response):
        result = done_eval.evaluate(_make_goal(), _make_evidence(complete=True), "MET")
    assert result["verdict"] == "ERROR"
    assert "parse failed" in result["rationale"]


def test_lazy_import_langchain_not_required_when_mocked():
    """If a test mocks _invoke_nat, the langchain packages need not be installed.

    Protects against accidental top-level imports of langchain_nvidia_ai_endpoints
    or langchain_openai (both reachable via tool.backends) that would make tests
    fragile or slow.
    """
    fake_response = "VERDICT: AGREE\nRATIONALE: ok\nGAPS: n/a"
    # Save and clear any cached langchain imports
    saved_nvidia = sys.modules.pop("langchain_nvidia_ai_endpoints", None)
    saved_openai = sys.modules.pop("langchain_openai", None)
    try:
        with patch.object(done_eval, "_invoke_nat", return_value=fake_response):
            result = done_eval.evaluate(_make_goal(), _make_evidence(complete=True), "MET")
        assert result["verdict"] == "AGREE"
        assert "langchain_nvidia_ai_endpoints" not in sys.modules, (
            "evaluate() pulled in langchain_nvidia_ai_endpoints even though _invoke_nat was mocked"
        )
        assert "langchain_openai" not in sys.modules, (
            "evaluate() pulled in langchain_openai even though _invoke_nat was mocked"
        )
    finally:
        if saved_nvidia is not None:
            sys.modules["langchain_nvidia_ai_endpoints"] = saved_nvidia
        if saved_openai is not None:
            sys.modules["langchain_openai"] = saved_openai


def test_default_model_env_first(monkeypatch):
    """Bug caught: hub-form literal returning to source (leak-gate class) or
    DONE_NAT_MODEL override silently ignored (wrong model at the endpoint)."""
    fake_response = "VERDICT: AGREE\nRATIONALE: ok\nGAPS: n/a"
    monkeypatch.setenv("DONE_NAT_MODEL", "org/custom-model")
    with patch.object(done_eval, "_invoke_nat", return_value=fake_response) as mock_nat:
        done_eval.evaluate(_make_goal(), _make_evidence(complete=True), "MET")
    assert mock_nat.call_args.kwargs["model"] == "org/custom-model"


def test_default_model_public_catalog_fallback(monkeypatch):
    """Without DONE_NAT_MODEL the default must be the public OpenRouter catalog
    ID (single nvidia/ namespace) — never a double-namespace hub form."""
    fake_response = "VERDICT: AGREE\nRATIONALE: ok\nGAPS: n/a"
    monkeypatch.delenv("DONE_NAT_MODEL", raising=False)
    with patch.object(done_eval, "_invoke_nat", return_value=fake_response) as mock_nat:
        done_eval.evaluate(_make_goal(), _make_evidence(complete=True), "MET")
    model = mock_nat.call_args.kwargs["model"]
    assert model == "nvidia/nemotron-3-ultra-550b-a55b:free"
    # single (public) namespace — a hub-form ID would count 2. Constructed
    # check instead of the literal so this file passes the T13 leak gate.
    assert model.count("nvidia/") == 1


def test_resolve_api_key_non_nim_backend_skips_nim_chain(monkeypatch):
    """Bug caught: an ambient nvapi- key being sent to OpenRouter (401)."""
    monkeypatch.setenv("DONE_BACKEND", "nat-openai")
    monkeypatch.delenv("DONE_NAT_API_KEY", raising=False)
    monkeypatch.setenv("PANEL_DA_API_KEY", "sk-panel-key")
    monkeypatch.setenv("NVIDIA_API_KEY", "nvapi-public-key")
    assert done_eval._resolve_api_key() is None


def test_resolve_base_url_non_nim_backend_skips_panel_endpoint(monkeypatch):
    """Bug caught: the panel's hub endpoint leaking into an OpenRouter dispatch."""
    monkeypatch.setenv("DONE_BACKEND", "nat-openai")
    monkeypatch.delenv("DONE_NAT_ENDPOINT", raising=False)
    monkeypatch.setenv("CLAUDE_PANEL_DA_ENDPOINT", "https://hub.example/v1")
    assert done_eval._resolve_base_url() is None


def test_main_threads_payload_model(monkeypatch):
    """main() forwards payload["model"] to the dispatch — the eval-side half
    of the DONE_NAT_MODEL wire (done.sh supplies the key; see integration test)."""
    payload = {
        "goal_stanza": _make_goal(),
        "evidence": [],
        "user_claim": "MET",
        "model": "custom/model-x",
    }
    fake_response = "VERDICT: AGREE\nRATIONALE: ok\nGAPS: n/a"
    monkeypatch.setattr(sys, "stdin", io.StringIO(json.dumps(payload)))
    with patch.object(done_eval, "_invoke_nat", return_value=fake_response) as mock_nat:
        rc = done_eval.main([])
    assert rc == 0
    assert mock_nat.call_args.kwargs["model"] == "custom/model-x"


def test_resolve_base_url_prefers_done_nat_endpoint(monkeypatch):
    """Explicit DONE_NAT_ENDPOINT beats the panel hub fallback."""
    monkeypatch.setenv("DONE_NAT_ENDPOINT", "https://done.example/v1")
    monkeypatch.setenv("CLAUDE_PANEL_DA_ENDPOINT", "https://hub.example/v1")
    assert done_eval._resolve_base_url() == "https://done.example/v1"


def test_resolve_base_url_falls_back_to_hub_and_strips_suffix(monkeypatch):
    """Without DONE_NAT_ENDPOINT, /done uses the panel's hub endpoint —
    the defect that sent hub-form model IDs to the public API. ChatNVIDIA
    appends /chat/completions itself, so a suffixed value must be stripped."""
    monkeypatch.delenv("DONE_NAT_ENDPOINT", raising=False)
    monkeypatch.setenv("CLAUDE_PANEL_DA_ENDPOINT", "https://hub.example/v1/chat/completions")
    assert done_eval._resolve_base_url() == "https://hub.example/v1"


def test_resolve_base_url_none_when_unset(monkeypatch):
    """Neither env set → None → ChatNVIDIA public default (graceful ERROR path)."""
    monkeypatch.delenv("DONE_NAT_ENDPOINT", raising=False)
    monkeypatch.delenv("CLAUDE_PANEL_DA_ENDPOINT", raising=False)
    assert done_eval._resolve_base_url() is None


def test_resolve_api_key_prefers_done_nat_api_key(monkeypatch):
    """Explicit DONE_NAT_API_KEY beats both panel and public NVIDIA keys."""
    monkeypatch.setenv("DONE_NAT_API_KEY", "done-key")
    monkeypatch.setenv("PANEL_DA_API_KEY", "sk-panel-key")
    monkeypatch.setenv("NVIDIA_API_KEY", "nvapi-public-key")
    assert done_eval._resolve_api_key() == "done-key"


def test_resolve_api_key_prefers_panel_da_over_nvidia(monkeypatch):
    """PANEL_DA_API_KEY must win over NVIDIA_API_KEY — this is the auth-alignment
    regression: the hub endpoint (CLAUDE_PANEL_DA_ENDPOINT/DONE_NAT_ENDPOINT) is
    LiteLLM-fronted and expects the sk- virtual key, not an nvapi- key. Reversing
    this order sent an nvapi- key to the hub and produced the 401 "LiteLLM Virtual
    Key expected... expected to start with 'sk-'" failure (2026-07-06)."""
    monkeypatch.delenv("DONE_NAT_API_KEY", raising=False)
    monkeypatch.setenv("PANEL_DA_API_KEY", "sk-panel-key")
    monkeypatch.setenv("NVIDIA_API_KEY", "nvapi-public-key")
    assert done_eval._resolve_api_key() == "sk-panel-key"


def test_resolve_api_key_falls_back_to_nvidia_when_no_panel_key(monkeypatch):
    """With no DONE_NAT_API_KEY or PANEL_DA_API_KEY, NVIDIA_API_KEY is still used
    (the public-endpoint case, per SKILL.md's documented fallback chain)."""
    monkeypatch.delenv("DONE_NAT_API_KEY", raising=False)
    monkeypatch.delenv("PANEL_DA_API_KEY", raising=False)
    monkeypatch.setenv("NVIDIA_API_KEY", "nvapi-public-key")
    assert done_eval._resolve_api_key() == "nvapi-public-key"


def test_resolve_api_key_none_when_all_unset(monkeypatch):
    """No key env set → None → ChatNVIDIA constructed without nvidia_api_key kwarg."""
    monkeypatch.delenv("DONE_NAT_API_KEY", raising=False)
    monkeypatch.delenv("PANEL_DA_API_KEY", raising=False)
    monkeypatch.delenv("NVIDIA_API_KEY", raising=False)
    assert done_eval._resolve_api_key() is None


@pytest.mark.skipif(
    not os.environ.get("DONE_LIVE_E2E"),
    reason="live hub call — set DONE_LIVE_E2E=1 to run",
)
def test_live_hub_grade_returns_real_verdict():
    """One real dispatch through the default model+endpoint. Green unit tests
    mock the seam and cannot catch a nonexistent model ID or wrong endpoint;
    this can — it is the exact failure class that shipped silently."""
    result = done_eval.evaluate(_make_goal(), _make_evidence(complete=True), "MET")
    assert result["verdict"] in ("AGREE", "DISAGREE", "INSUFFICIENT_EVIDENCE"), result


def _entry(seq: int, evidence: list[dict]) -> str:
    return json.dumps({"schema": 1, "session": "s1", "seq": seq,
                       "ts": f"2026-07-10T0{seq}:00:00Z", "goal_file": "g.md",
                       "heuristic": None, "evidence": evidence, "state_hash": "",
                       "user": None})


def test_evidence_window_merges_across_entries():
    """THE mandated regression (2 observations): grep|tail -1 kept only the last
    entry, so evidence accrued in earlier Stop-hook entries was dropped and NAT
    mispaired commands to bullets."""
    lines = "\n".join([
        _entry(1, [{"bullet": "tests pass", "raw": "pytest ok"}]),
        _entry(2, [{"bullet": "lint clean", "raw": "ruff ok"}]),
    ])
    merged = done_eval.collect_evidence(lines)
    assert [m["bullet"] for m in merged] == ["tests pass", "lint clean"]
    assert merged[0]["raw"] == "pytest ok"


def test_evidence_window_later_entry_refreshes_raw():
    """Freshest match wins per bullet, in first-seen position."""
    lines = "\n".join([
        _entry(1, [{"bullet": "tests pass", "raw": "old run"}]),
        _entry(2, [{"bullet": "tests pass", "raw": "new run"}]),
    ])
    merged = done_eval.collect_evidence(lines)
    assert merged == [{"bullet": "tests pass", "raw": "new run"}]


def test_evidence_window_empty_entry_does_not_clobber():
    """done.sh user entries hardcode evidence:[] — they must never erase the
    hook-collected window (the exact tail -1 failure shape)."""
    lines = "\n".join([
        _entry(1, [{"bullet": "tests pass", "raw": "pytest ok"}]),
        _entry(2, []),
    ])
    merged = done_eval.collect_evidence(lines)
    assert merged == [{"bullet": "tests pass", "raw": "pytest ok"}]


def test_evidence_window_skips_malformed_lines():
    """A corrupt log line must not take down /done confirm."""
    lines = "not json at all\n" + _entry(1, [{"bullet": "b", "raw": "r"}]) + "\n{half"
    merged = done_eval.collect_evidence(lines)
    assert merged == [{"bullet": "b", "raw": "r"}]


def test_evidence_window_skips_non_dict_json_lines():
    """Valid-JSON-but-non-dict lines (null, numbers, arrays) are malformed for
    our schema and must be skipped, not crash the collector."""
    lines = "null\n42\n[1, 2]\n" + _entry(1, [{"bullet": "b", "raw": "r"}])
    merged = done_eval.collect_evidence(lines)
    assert merged == [{"bullet": "b", "raw": "r"}]


def test_evidence_window_multi_bullet_refresh_preserves_position():
    """A refresh must keep the bullet's first-seen slot among OTHER bullets —
    guards against move-to-end merge implementations (del + reinsert)."""
    lines = "\n".join([
        _entry(1, [{"bullet": "A", "raw": "a1"}, {"bullet": "B", "raw": "b1"}]),
        _entry(2, [{"bullet": "A", "raw": "a2"}]),
    ])
    merged = done_eval.collect_evidence(lines)
    assert [m["bullet"] for m in merged] == ["A", "B"]
    assert merged[0]["raw"] == "a2"
