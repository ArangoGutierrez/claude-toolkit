import pytest
from pydantic import BaseModel
from langchain_core.messages import ToolMessage
from tool.agentic import agentic_run, UNTRUSTED_OPEN
from tool.tools import Tool
from tool.errors import LoopBudgetError


class Result(BaseModel):
    answer: str


def _ai(tool_calls=None, content=""):
    # mimic langchain AIMessage: .tool_calls list of {name,args,id}, .content str
    return type("AI", (), {"tool_calls": tool_calls or [], "content": content})()


class _ScriptedModel:
    """Fake bindable chat model: yields a scripted AIMessage per invoke()."""
    def __init__(self, script):
        self._script = list(script)
        self.seen_messages = []
        self.bound_tools = None

    def bind_tools(self, tools):
        self.bound_tools = tools
        return self

    def invoke(self, messages):
        self.seen_messages = messages
        return self._script.pop(0)


@pytest.fixture
def patch_model(monkeypatch):
    def _install(script):
        model = _ScriptedModel(script)
        monkeypatch.setattr("tool.agentic.build_chat_model", lambda **kw: model)
        return model
    return _install


def test_submit_result_returns_validated_dict(patch_model):
    patch_model([_ai(tool_calls=[{"name": "submit_result", "args": {"answer": "done"}, "id": "1"}])])
    out = agentic_run(backend="nat-nim", model="m", system="s", user="u",
                      tools=[], result_schema=Result)
    assert out == {"answer": "done"}


def test_submit_result_invalid_args_retried_once_then_raises(patch_model):
    from tool.errors import SchemaError
    # Two consecutive malformed submits: the first gets ONE retry with the
    # validation error fed back; the second raises SchemaError.
    model = patch_model([
        _ai(tool_calls=[{"name": "submit_result", "args": {}, "id": "s1"}]),
        _ai(tool_calls=[{"name": "submit_result", "args": {}, "id": "s2"}]),
    ])
    with pytest.raises(SchemaError):
        agentic_run(backend="nat-nim", model="m", system="s", user="u",
                    tools=[], result_schema=Result)
    assert any("failed validation" in getattr(m, "content", "")
               for m in model.seen_messages)   # the retry feedback was sent


def test_submit_result_invalid_args_then_valid_succeeds(patch_model):
    model = patch_model([
        _ai(tool_calls=[{"name": "submit_result", "args": {}, "id": "s1"}]),
        _ai(tool_calls=[{"name": "submit_result", "args": {"answer": "ok"}, "id": "s2"}]),
    ])
    out = agentic_run(backend="nat-nim", model="m", system="s", user="u",
                      tools=[], result_schema=Result)
    assert out == {"answer": "ok"}


def test_schema_failure_lands_in_transcript(patch_model, tmp_path):
    from tool.errors import SchemaError
    path = tmp_path / "transcript.jsonl"
    patch_model([
        _ai(tool_calls=[{"name": "submit_result", "args": {}, "id": "s1"}]),
        _ai(tool_calls=[{"name": "submit_result", "args": {}, "id": "s2"}]),
    ])
    with pytest.raises(SchemaError):
        agentic_run(backend="nat-nim", model="m", system="s", user="u",
                    tools=[], result_schema=Result, transcript_path=str(path))
    assert '"submit_result"' in path.read_text()   # the malformed attempt is visible post-mortem


def test_read_tool_then_submit(patch_model):
    calls = {"n": 0}

    def reader(path):
        calls["n"] += 1
        return "FILE CONTENTS"

    from pydantic import BaseModel as BM

    class P(BM):
        path: str

    tool = Tool("read_file", "d", P, reader)
    model = patch_model([
        _ai(tool_calls=[{"name": "read_file", "args": {"path": "go.mod"}, "id": "a"}]),
        _ai(tool_calls=[{"name": "submit_result", "args": {"answer": "ok"}, "id": "b"}]),
    ])
    out = agentic_run(backend="nat-nim", model="m", system="s", user="u",
                      tools=[tool], result_schema=Result)
    assert out == {"answer": "ok"}
    assert calls["n"] == 1
    # tool result was fed back wrapped as untrusted in a ToolMessage
    assert any(isinstance(msg, ToolMessage) and UNTRUSTED_OPEN in msg.content
               for msg in model.seen_messages)


def test_max_rounds_exhausted_raises(patch_model):
    # model loops forever on a read tool, never submits
    from pydantic import BaseModel as BM

    class P(BM):
        path: str

    tool = Tool("read_file", "d", P, lambda path: "x")
    patch_model([_ai(tool_calls=[{"name": "read_file", "args": {"path": "a"}, "id": str(i)}])
                 for i in range(20)])
    with pytest.raises(LoopBudgetError, match="max_rounds"):
        agentic_run(backend="nat-nim", model="m", system="s", user="u",
                    tools=[tool], result_schema=Result, max_rounds=3)


def test_no_tool_call_nudges_once_then_raises(patch_model):
    model = patch_model([_ai(content="here is prose, no tool call"),
                         _ai(content="still prose")])
    with pytest.raises(LoopBudgetError, match="did not call submit_result"):
        agentic_run(backend="nat-nim", model="m", system="s", user="u",
                    tools=[], result_schema=Result, max_rounds=8)
    assert any("submit_result" in getattr(m, "content", "")
               for m in model.seen_messages)   # the one-time nudge was appended


def test_timeout_raises(patch_model):
    ticks = iter([0.0, 100.0])
    patch_model([_ai(tool_calls=[{"name": "submit_result", "args": {"answer": "x"}, "id": "1"}])])
    with pytest.raises(LoopBudgetError, match=r"timeout \(45\.0s\)"):
        agentic_run(backend="nat-nim", model="m", system="s", user="u",
                    tools=[], result_schema=Result, timeout=45.0, clock=lambda: next(ticks))


def test_tool_exception_is_fed_back_not_fatal(patch_model):
    # A read tool raising a NON-ToolError (e.g. FileNotFoundError) must be caught and
    # fed back as wrapped error text, not crash the loop. Narrowing the dispatch catch
    # back to `except ToolError` lets the exception propagate -> agentic_run raises
    # instead of returning -> this test goes red.
    from pydantic import BaseModel as BM

    class P(BM):
        path: str

    def boom(path):
        raise FileNotFoundError("nope")

    tool = Tool("read_file", "d", P, boom)
    model = patch_model([
        _ai(tool_calls=[{"name": "read_file", "args": {"path": "x"}, "id": "a"}]),
        _ai(tool_calls=[{"name": "submit_result", "args": {"answer": "ok"}, "id": "b"}]),
    ])
    out = agentic_run(backend="nat-nim", model="m", system="s", user="u",
                      tools=[tool], result_schema=Result)
    assert out == {"answer": "ok"}  # loop survived the tool exception and converged
    assert any("ERROR: FileNotFoundError" in getattr(m, "content", "") for m in model.seen_messages)


def test_deadline_nudge_injected_in_final_rounds(patch_model):
    # In the final rounds the loop must inject a forceful "submit now" nudge so a
    # model that keeps exploring converges before the hard cap. Removing the
    # deadline-nudge block leaves no such message -> this test goes red.
    from pydantic import BaseModel as BM

    class P(BM):
        path: str

    tool = Tool("read_file", "d", P, lambda path: "x")
    model = patch_model([_ai(tool_calls=[{"name": "read_file", "args": {"path": "a"}, "id": str(i)}])
                         for i in range(10)])
    with pytest.raises(LoopBudgetError, match="max_rounds"):
        agentic_run(backend="nat-nim", model="m", system="s", user="u",
                    tools=[tool], result_schema=Result, max_rounds=4)
    assert any("Inspection budget is nearly spent" in getattr(m, "content", "")
               for m in model.seen_messages)


def test_validator_triggers_one_revision_then_returns(patch_model):
    from tool.agentic import ValidationOutcome
    seen = {"n": 0}

    def validator(result):
        seen["n"] += 1
        if seen["n"] == 1:
            return ValidationOutcome(accept=False, feedback="fix check 1", result=result)
        return ValidationOutcome(accept=True, feedback="", result={**result, "ok": True})

    model = patch_model([
        _ai(tool_calls=[{"name": "submit_result", "args": {"answer": "v1"}, "id": "s1"}]),
        _ai(tool_calls=[{"name": "submit_result", "args": {"answer": "v2"}, "id": "s2"}]),
    ])
    out = agentic_run(backend="nat-nim", model="m", system="s", user="u",
                      tools=[], result_schema=Result, validator=validator)
    assert seen["n"] == 2                       # validated initial + revised submission
    assert out == {"answer": "v2", "ok": True}
    assert any("fix check 1" in getattr(m, "content", "") for m in model.seen_messages)


def test_validator_returns_after_single_revision_even_if_still_failing(patch_model):
    from tool.agentic import ValidationOutcome

    def validator(result):
        return ValidationOutcome(accept=False, feedback="still broken", result={**result, "final": True})

    patch_model([
        _ai(tool_calls=[{"name": "submit_result", "args": {"answer": "v1"}, "id": "s1"}]),
        _ai(tool_calls=[{"name": "submit_result", "args": {"answer": "v2"}, "id": "s2"}]),
    ])
    out = agentic_run(backend="nat-nim", model="m", system="s", user="u",
                      tools=[], result_schema=Result, validator=validator)
    assert out == {"answer": "v2", "final": True}   # bounded to ONE revision; no infinite loop


def test_no_validator_returns_immediately(patch_model):
    # Regression: the default path (validator=None) must return the validated dict
    # without any extra round.
    model = patch_model([_ai(tool_calls=[{"name": "submit_result", "args": {"answer": "done"}, "id": "1"}])])
    out = agentic_run(backend="nat-nim", model="m", system="s", user="u",
                      tools=[], result_schema=Result)
    assert out == {"answer": "done"}
    assert len(model.seen_messages) == 2  # exactly one model invoke: no validator -> no revision round


def test_transcript_dumped_on_success(patch_model, tmp_path):
    # Deleting the transcript-dump block leaves no file -> both asserts go red.
    path = tmp_path / "transcript.jsonl"
    patch_model([_ai(tool_calls=[{"name": "submit_result", "args": {"answer": "done"}, "id": "1"}])])
    agentic_run(backend="nat-nim", model="m", system="s", user="u",
                tools=[], result_schema=Result, transcript_path=str(path))
    lines = path.read_text().splitlines()
    assert any('"SystemMessage"' in ln for ln in lines)
    assert any('"HumanMessage"' in ln for ln in lines)


def test_transcript_dumped_on_budget_error_includes_tool_calls(patch_model, tmp_path):
    from pydantic import BaseModel as BM

    class P(BM):
        path: str

    path = tmp_path / "transcript.jsonl"
    tool = Tool("read_file", "d", P, lambda path: "x")
    patch_model([_ai(tool_calls=[{"name": "read_file", "args": {"path": "a"}, "id": str(i)}])
                 for i in range(10)])
    with pytest.raises(LoopBudgetError, match="max_rounds"):
        agentic_run(backend="nat-nim", model="m", system="s", user="u",
                    tools=[tool], result_schema=Result, max_rounds=3,
                    transcript_path=str(path))
    text = path.read_text()
    assert '"read_file"' in text          # the stalled exploration is visible post-mortem
    assert '"ToolMessage"' in text


def _read_loop_model(patch_model, rounds):
    from pydantic import BaseModel as BM

    class P(BM):
        path: str

    tool = Tool("read_file", "d", P, lambda path: "x")
    model = patch_model([_ai(tool_calls=[{"name": "read_file", "args": {"path": "a"}, "id": str(i)}])
                         for i in range(rounds + 2)])
    return tool, model


def test_soft_convergence_nudge_fires_exactly_once_at_60_percent(patch_model):
    # max_rounds=10: soft nudge after round index 5 (60% of the budget), only once,
    # and before the final-third hard nudges begin. Deleting the soft-nudge block
    # -> zero matches -> red.
    tool, model = _read_loop_model(patch_model, 10)
    with pytest.raises(LoopBudgetError, match="max_rounds"):
        agentic_run(backend="nat-nim", model="m", system="s", user="u",
                    tools=[tool], result_schema=Result, max_rounds=10)
    softs = [m for m in model.seen_messages if "Start converging" in getattr(m, "content", "")]
    assert len(softs) == 1
    assert "rounds left" in softs[0].content


def test_deadline_nudge_fires_every_round_in_final_third(patch_model):
    # max_rounds=9 -> final third starts at index 6 -> hard nudge after rounds 6,7,8 = 3 times.
    # The old block (last 3 rounds only) also gives 3 here, so ALSO check max_rounds=12:
    # final third starts at index 8 -> 4 nudges; the old code would emit only 3 -> red.
    tool, model = _read_loop_model(patch_model, 12)
    with pytest.raises(LoopBudgetError, match="max_rounds"):
        agentic_run(backend="nat-nim", model="m", system="s", user="u",
                    tools=[tool], result_schema=Result, max_rounds=12)
    hards = [m for m in model.seen_messages
             if "Inspection budget is nearly spent" in getattr(m, "content", "")]
    assert len(hards) == 4
    assert all("rounds left" in h.content for h in hards)
