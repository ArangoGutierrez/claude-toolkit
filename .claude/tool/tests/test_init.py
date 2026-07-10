import pytest


def test_error_hierarchy():
    from tool.errors import EngineError, BackendError, ToolError, LoopBudgetError, SchemaError
    for sub in (BackendError, ToolError, LoopBudgetError, SchemaError):
        assert issubclass(sub, EngineError)
    # catching EngineError catches every engine failure
    with pytest.raises(EngineError):
        raise ToolError("x")


def test_public_api_reexports():
    import tool
    for name in ("invoke_llm", "build_chat_model", "agentic_run", "Tool",
                 "readonly_tools", "EngineError", "ToolError",
                 "LoopBudgetError", "SchemaError", "BackendError"):
        assert hasattr(tool, name), f"tool.{name} missing from public API"
