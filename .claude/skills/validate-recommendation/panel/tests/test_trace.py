"""Tests for panel.trace — append-only verdict trace log.

Parity with aggregate.sh's log_verdict(): writes a single-line entry
with timestamp, session id, outcome, and detail. Default path is
~/.claude/debug/panel-trace.log; override via $CLAUDE_PANEL_TRACE_LOG
(used by tests and ops to redirect).
"""
import os
from pathlib import Path


def test_log_verdict_appends_line(tmp_path, monkeypatch):
    from panel.trace import log_verdict
    log_path = tmp_path / "trace.log"
    monkeypatch.setenv("CLAUDE_PANEL_TRACE_LOG", str(log_path))
    monkeypatch.setenv("CLAUDE_SESSION_ID", "test-session")
    log_verdict("HOLD", "DA: foo | PE: bar")
    content = log_path.read_text()
    assert "outcome=HOLD" in content
    assert 'detail="DA: foo | PE: bar"' in content
    assert "session=test-session" in content


def test_log_verdict_creates_parent_dir(tmp_path, monkeypatch):
    from panel.trace import log_verdict
    log_path = tmp_path / "nested" / "deeper" / "trace.log"
    monkeypatch.setenv("CLAUDE_PANEL_TRACE_LOG", str(log_path))
    log_verdict("DISSENT", "test")
    assert log_path.exists()


def test_log_verdict_sanitizes_newlines_in_detail(tmp_path, monkeypatch):
    """log entry must remain single-line — newlines in detail get replaced."""
    from panel.trace import log_verdict
    log_path = tmp_path / "trace.log"
    monkeypatch.setenv("CLAUDE_PANEL_TRACE_LOG", str(log_path))
    log_verdict("ERROR", "multi\nline\ndetail")
    lines = log_path.read_text().rstrip("\n").split("\n")
    assert len(lines) == 1
    assert "multi line line detail" in lines[0] or "multi line detail" in lines[0]


def test_log_verdict_appends_not_overwrites(tmp_path, monkeypatch):
    from panel.trace import log_verdict
    log_path = tmp_path / "trace.log"
    monkeypatch.setenv("CLAUDE_PANEL_TRACE_LOG", str(log_path))
    log_verdict("HOLD", "first")
    log_verdict("DISSENT", "second")
    content = log_path.read_text()
    assert "first" in content
    assert "second" in content
    assert content.count("outcome=") == 2
