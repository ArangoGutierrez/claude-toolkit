import socket
import threading

import pytest
import requests

import tool.backends as backends


class _FakeChat:
    last_kwargs = None
    invoke_call_count = 0  # per-subclass counter

    def __init__(self, **kwargs):
        type(self).last_kwargs = kwargs

    def invoke(self, messages):
        type(self).invoke_call_count += 1
        return ("RESPONSE", type(self).__name__, messages)


@pytest.fixture
def fake_providers(monkeypatch):
    import langchain_anthropic as an
    import langchain_nvidia_ai_endpoints as nv
    import langchain_openai as oa
    nim = type("NIM", (_FakeChat,), {})
    anth = type("ANTH", (_FakeChat,), {})
    oai = type("OAI", (_FakeChat,), {})
    monkeypatch.setattr(nv, "ChatNVIDIA", nim)
    monkeypatch.setattr(an, "ChatAnthropic", anth)
    monkeypatch.setattr(oa, "ChatOpenAI", oai)
    return {"nim": nim, "anth": anth, "oai": oai}


def test_nim_prefers_panel_da_api_key_then_nvidia_key(fake_providers, monkeypatch):
    monkeypatch.setenv("PANEL_DA_API_KEY", "da-key")
    monkeypatch.setenv("NVIDIA_API_KEY", "nv-key")
    monkeypatch.delenv("CLAUDE_PANEL_DA_ENDPOINT", raising=False)
    resp = backends.invoke_llm(backend="nat-nim", model="m", system="s", user="u",
                               temperature=0.3, max_tokens=2048)
    assert resp[1] == "NIM"
    kw = fake_providers["nim"].last_kwargs
    assert kw["max_completion_tokens"] == 2048
    assert kw["nvidia_api_key"] == "da-key"


def test_nim_endpoint_env_strips_chat_completions_suffix(fake_providers, monkeypatch):
    monkeypatch.delenv("PANEL_DA_API_KEY", raising=False)
    monkeypatch.delenv("NVIDIA_API_KEY", raising=False)
    monkeypatch.setenv("CLAUDE_PANEL_DA_ENDPOINT", "https://h/v1/chat/completions")
    backends.invoke_llm(backend="nat-nim", model="m", system="s", user="u",
                        temperature=0.3, max_tokens=8)
    assert fake_providers["nim"].last_kwargs["base_url"] == "https://h/v1"


def test_anthropic_routes_to_chatanthropic(fake_providers):
    resp = backends.invoke_llm(backend="nat-anthropic", model="claude-opus-4-8", system="s",
                               user="u", temperature=0.2, max_tokens=64)
    assert resp[1] == "ANTH"
    assert fake_providers["anth"].last_kwargs["max_tokens"] == 64


def test_openai_routes_to_chatopenai(fake_providers):
    resp = backends.invoke_llm(backend="nat-openai", model="gpt-5.5", system="s",
                               user="u", temperature=0.2, max_tokens=64)
    assert resp[1] == "OAI"
    assert fake_providers["oai"].last_kwargs["max_completion_tokens"] == 64


def test_unsupported_backend_raises(fake_providers):
    with pytest.raises(ValueError, match="unsupported NAT backend: nat-bogus"):
        backends.invoke_llm(backend="nat-bogus", model="m", system="s", user="u",
                            temperature=0.1, max_tokens=8)


def test_build_chat_model_returns_bindable_without_invoking(fake_providers, monkeypatch):
    monkeypatch.setenv("PANEL_DA_API_KEY", "k")
    llm = backends.build_chat_model(backend="nat-nim", model="m", temperature=0.2, max_tokens=16)
    # construction happened (last_kwargs set) but .invoke was NOT called by build_chat_model
    assert fake_providers["nim"].last_kwargs["max_completion_tokens"] == 16
    assert isinstance(llm, fake_providers["nim"])
    assert fake_providers["nim"].invoke_call_count == 0


def test_nim_falls_back_to_nvidia_api_key(fake_providers, monkeypatch):
    monkeypatch.delenv("PANEL_DA_API_KEY", raising=False)
    monkeypatch.setenv("NVIDIA_API_KEY", "nv-key")
    backends.invoke_llm(backend="nat-nim", model="m", system="s", user="u",
                        temperature=0.1, max_tokens=8)
    assert fake_providers["nim"].last_kwargs["nvidia_api_key"] == "nv-key"


# --- HTTP timeout injection (2026-07-03 /kickoff hang) ------------------------
# The NVIDIA client posts via requests.Session with NO timeout kwarg, so a
# stalled endpoint connection blocks forever. These tests use the REAL
# ChatNVIDIA (no fake_providers) because the contract under test is the
# session factory of the constructed model.


@pytest.fixture
def stalled_server():
    """TCP server that accepts connections and never responds — the observed
    failure mode: connection established, response never arrives."""
    srv = socket.socket()
    srv.bind(("127.0.0.1", 0))
    srv.listen(5)
    port = srv.getsockname()[1]
    conns = []

    def accept_loop():
        while True:
            try:
                conn, _ = srv.accept()
                conns.append(conn)  # hold open, never write
            except OSError:
                return

    threading.Thread(target=accept_loop, daemon=True).start()
    yield port
    for conn in conns:
        conn.close()
    srv.close()


def test_nat_nim_session_post_times_out_on_stalled_server(monkeypatch, stalled_server):
    monkeypatch.setenv("NVIDIA_API_KEY", "nvapi-test-dummy")
    monkeypatch.delenv("CLAUDE_PANEL_DA_ENDPOINT", raising=False)
    monkeypatch.setenv("CLAUDE_NAT_HTTP_TIMEOUT", "1")
    llm = backends.build_chat_model(backend="nat-nim", model="m",
                                    temperature=0.0, max_tokens=8)
    session = llm._client.get_session_fn()
    outcome = {}

    def post():
        try:
            session.post(f"http://127.0.0.1:{stalled_server}/v1/chat/completions",
                         json={})
            outcome["response"] = "unexpected success"
        except requests.exceptions.Timeout:
            outcome["timeout"] = True
        except Exception as e:  # noqa: BLE001 — recorded for the assertion message
            outcome["error"] = repr(e)

    worker = threading.Thread(target=post, daemon=True)
    worker.start()
    worker.join(10)
    assert outcome.get("timeout") is True, \
        f"POST did not time out: {outcome or 'still blocked after 10s'}"


def test_nat_nim_session_applies_default_timeout_when_env_unset(monkeypatch):
    monkeypatch.setenv("NVIDIA_API_KEY", "nvapi-test-dummy")
    monkeypatch.delenv("CLAUDE_NAT_HTTP_TIMEOUT", raising=False)
    llm = backends.build_chat_model(backend="nat-nim", model="m",
                                    temperature=0.0, max_tokens=8)
    session = llm._client.get_session_fn()
    assert getattr(session, "_default_timeout", None) == (10.0, 120.0)


import sys
import types

from tool import backends


def _fake_openai_module(captured: dict):
    class FakeChatOpenAI:
        def __init__(self, **kwargs):
            captured.update(kwargs)

        def invoke(self, messages):
            captured["messages"] = messages
            return types.SimpleNamespace(content="ok")

    mod = types.ModuleType("langchain_openai")
    mod.ChatOpenAI = FakeChatOpenAI
    return mod


def test_nat_openai_wires_base_url_and_key_from_env(monkeypatch):
    """Bug caught: OpenRouter env ignored → every public example dead on arrival."""
    captured: dict = {}
    monkeypatch.setitem(sys.modules, "langchain_openai", _fake_openai_module(captured))
    monkeypatch.setenv("OPENAI_BASE_URL", "https://openrouter.ai/api/v1/chat/completions")
    monkeypatch.setenv("OPENAI_API_KEY", "sk-or-test")
    backends.build_chat_model(backend="nat-openai", model="m", temperature=0.1, max_tokens=64)
    assert captured["base_url"] == "https://openrouter.ai/api/v1"  # suffix stripped
    assert captured["api_key"] == "sk-or-test"
    assert captured["timeout"] == backends._http_timeout()[1]


def test_nat_openai_explicit_args_beat_env(monkeypatch):
    """Bug caught: done's DONE_NAT_* overrides silently losing to ambient env."""
    captured: dict = {}
    monkeypatch.setitem(sys.modules, "langchain_openai", _fake_openai_module(captured))
    monkeypatch.setenv("OPENAI_BASE_URL", "https://env.example/v1")
    monkeypatch.setenv("OPENAI_API_KEY", "sk-env")
    backends.build_chat_model(
        backend="nat-openai", model="m", temperature=0.1, max_tokens=64,
        base_url="https://arg.example/v1", api_key="sk-arg")
    assert captured["base_url"] == "https://arg.example/v1"
    assert captured["api_key"] == "sk-arg"


def test_nat_openai_without_env_omits_kwargs(monkeypatch):
    """Bug caught: passing base_url=None/api_key=None overrides SDK defaults with None."""
    captured: dict = {}
    monkeypatch.setitem(sys.modules, "langchain_openai", _fake_openai_module(captured))
    monkeypatch.delenv("OPENAI_BASE_URL", raising=False)
    monkeypatch.delenv("OPENAI_API_KEY", raising=False)
    backends.build_chat_model(backend="nat-openai", model="m", temperature=0.1, max_tokens=64)
    assert "base_url" not in captured
    assert "api_key" not in captured


def test_invoke_llm_omits_empty_system_message(monkeypatch):
    """Bug caught: endpoints that reject empty-content system messages (400s)."""
    captured: dict = {}
    monkeypatch.setitem(sys.modules, "langchain_openai", _fake_openai_module(captured))
    backends.invoke_llm(backend="nat-openai", model="m", system="", user="hello",
                        temperature=0.1, max_tokens=64)
    assert captured["messages"] == [{"role": "user", "content": "hello"}]


def test_invoke_llm_keeps_nonempty_system_message(monkeypatch):
    """Guard for the panel/kickoff path: real system prompts must still be sent."""
    captured: dict = {}
    monkeypatch.setitem(sys.modules, "langchain_openai", _fake_openai_module(captured))
    backends.invoke_llm(backend="nat-openai", model="m", system="persona", user="hello",
                        temperature=0.1, max_tokens=64)
    assert captured["messages"][0] == {"role": "system", "content": "persona"}
    assert captured["messages"][1] == {"role": "user", "content": "hello"}
