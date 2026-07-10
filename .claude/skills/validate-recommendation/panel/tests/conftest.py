"""Shared pytest fixtures for panel tests."""
from pathlib import Path
import pytest

SKILL_DIR = Path(__file__).resolve().parent.parent.parent  # .../validate-recommendation/
FIXTURES_DIR = SKILL_DIR / "fixtures"


@pytest.fixture(autouse=True)
def decisions_log(tmp_path_factory, monkeypatch):
    """Redirect panel decision telemetry to a throwaway file for every test.

    aggregate() appends a decisions.jsonl row using the config's telemetry
    path, which DEFAULTS to the operator's real
    '~/.claude/panel/decisions.jsonl'. Tests that build a config without an
    explicit telemetry block (test_aggregate, test_cli_aggregate) would
    otherwise write that real file. Pointing $CLAUDE_PANEL_DECISIONS_JSONL
    at a tmp file keeps every test hermetic without touching HOME (which
    would break the subprocess tests' user-site imports). Returns the path
    so tests can assert on the written row.
    """
    path = tmp_path_factory.mktemp("panel-telemetry") / "decisions.jsonl"
    monkeypatch.setenv("CLAUDE_PANEL_DECISIONS_JSONL", str(path))
    return path


@pytest.fixture
def fixtures_dir() -> Path:
    """Path to the validate-recommendation skill's fixtures directory.

    Used by aggregate-parity tests that reuse the same fixtures as
    aggregate_test.sh (da_hold.txt, da_overturn_b.txt, etc).
    """
    return FIXTURES_DIR


# Appended in Phase 3a — points at the real personas/ directory shipped with the skill.


@pytest.fixture
def personas_dir() -> Path:
    """Path to the real personas/ directory shipped next to panel/."""
    return Path(__file__).resolve().parent.parent.parent / "personas"
