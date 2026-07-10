from __future__ import annotations

import os

import requests

# (connect, read) seconds. The NVIDIA client calls session.post with no
# timeout kwarg, so without a session-level default a stalled endpoint
# connection blocks forever (hung /kickoff, 2026-07-03).
_DEFAULT_HTTP_TIMEOUT = (10.0, 120.0)


class _TimeoutSession(requests.Session):
    def __init__(self, timeout: tuple[float, float]):
        super().__init__()
        self._default_timeout = timeout

    def request(self, method, url, **kwargs):
        kwargs.setdefault("timeout", self._default_timeout)
        return super().request(method, url, **kwargs)


def _http_timeout() -> tuple[float, float]:
    raw = os.environ.get("CLAUDE_NAT_HTTP_TIMEOUT")
    if raw:
        try:
            read = float(raw)
            return (min(_DEFAULT_HTTP_TIMEOUT[0], read), read)
        except ValueError:
            pass
    return _DEFAULT_HTTP_TIMEOUT


def _strip_chat_completions(url: str) -> str:
    suffix = "/chat/completions"
    return url[: -len(suffix)] if url.endswith(suffix) else url


def build_chat_model(*, backend, model, temperature, max_tokens, base_url=None, api_key=None):
    """Construct (but do not invoke) the langchain chat model for a backend.

    The single place that knows providers. Lazy imports keep heavy SDKs off the
    import path until the one backend in use is needed. Optional base_url /
    api_key args override the per-backend env resolution (callers with their
    own env namespaces — e.g. done's DONE_NAT_* — thread them through here).
    """
    if backend == "nat-nim":
        from langchain_nvidia_ai_endpoints import ChatNVIDIA  # noqa: PLC0415
        key = api_key or os.environ.get("PANEL_DA_API_KEY") or os.environ.get("NVIDIA_API_KEY")
        kwargs = {"model": model, "temperature": temperature, "max_completion_tokens": max_tokens}
        if key:
            kwargs["nvidia_api_key"] = key
        url = base_url or os.environ.get("CLAUDE_PANEL_DA_ENDPOINT")
        if url:
            kwargs["base_url"] = _strip_chat_completions(url)
        chat = ChatNVIDIA(**kwargs)
        client = getattr(chat, "_client", None)
        if client is not None:  # absent on test fakes
            timeout = _http_timeout()
            client.get_session_fn = lambda: _TimeoutSession(timeout)
        return chat
    if backend == "nat-anthropic":
        from langchain_anthropic import ChatAnthropic  # noqa: PLC0415
        return ChatAnthropic(model=model, temperature=temperature, max_tokens=max_tokens)
    if backend == "nat-openai":
        from langchain_openai import ChatOpenAI  # noqa: PLC0415
        kwargs = {
            "model": model,
            "temperature": temperature,
            "max_completion_tokens": max_tokens,
            # ChatOpenAI takes a request timeout directly; use the read half of
            # the (connect, read) pair — same stall guard as the nat-nim session.
            "timeout": _http_timeout()[1],
        }
        key = api_key or os.environ.get("OPENAI_API_KEY")
        if key:
            kwargs["api_key"] = key
        url = base_url or os.environ.get("OPENAI_BASE_URL")
        if url:
            kwargs["base_url"] = _strip_chat_completions(url)
        return ChatOpenAI(**kwargs)
    raise ValueError(f"unsupported NAT backend: {backend}")


def invoke_llm(*, backend, model, system, user, temperature, max_tokens, base_url=None, api_key=None):
    """Single-shot dispatch. Empty/None system → no system message is sent."""
    messages = []
    if system:
        messages.append({"role": "system", "content": system})
    messages.append({"role": "user", "content": user})
    llm = build_chat_model(backend=backend, model=model, temperature=temperature,
                           max_tokens=max_tokens, base_url=base_url, api_key=api_key)
    return llm.invoke(messages)
