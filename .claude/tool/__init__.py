"""Reusable agentic engine shared by kickoff, validate-recommendation, and other skills."""

from tool.errors import (
    EngineError, BackendError, ToolError, LoopBudgetError, SchemaError,
)
from tool.backends import build_chat_model, invoke_llm
from tool.tools import Tool, readonly_tools
from tool.agentic import agentic_run

__version__ = "0.1.0"

__all__ = [
    "invoke_llm", "build_chat_model", "agentic_run", "Tool", "readonly_tools",
    "EngineError", "BackendError", "ToolError", "LoopBudgetError", "SchemaError",
]
