from __future__ import annotations


class EngineError(Exception):
    """Base for every engine failure. Consumers catch this and apply their own fail policy."""


class BackendError(EngineError):
    """Provider construction / invocation failed."""


class ToolError(EngineError):
    """A tool rejected its arguments or could not run safely."""


class LoopBudgetError(EngineError):
    """The agentic loop exceeded max_rounds, wall-clock timeout, or read budget."""


class SchemaError(EngineError):
    """The model's submit_result args failed result-schema validation."""
