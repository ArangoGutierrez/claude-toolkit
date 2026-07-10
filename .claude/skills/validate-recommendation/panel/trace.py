"""Append-only verdict trace log.

Parity with aggregate.sh's log_verdict(). Default-on telemetry: a
silently-broken panel is invisible to the operator without it (every
recommendation hits ERROR and the user sees no behavioral change).
Override path via $CLAUDE_PANEL_TRACE_LOG for tests and alternative
log routing.
"""
import os
from datetime import datetime, timezone
from pathlib import Path

DEFAULT_TRACE_LOG = Path.home() / ".claude" / "debug" / "panel-trace.log"


def _resolve_log_path() -> Path:
    env_value = os.environ.get("CLAUDE_PANEL_TRACE_LOG")
    if env_value:
        return Path(env_value).expanduser()
    return DEFAULT_TRACE_LOG


def log_verdict(outcome: str, detail: str) -> None:
    """Append one verdict line to the trace log.

    Failures are silently swallowed — telemetry must never block the
    panel decision path. The user-visible question always survives.
    """
    log_path = _resolve_log_path()
    try:
        log_path.parent.mkdir(parents=True, exist_ok=True)
    except OSError:
        return

    ts = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    sid = os.environ.get("CLAUDE_SESSION_ID", "unknown")
    # Sanitize detail to a single line, cap length so logs stay greppable.
    safe_detail = detail.replace("\n", " ").replace("\r", " ")[:160]
    line = f'[{ts}] event=verdict session={sid} outcome={outcome} detail="{safe_detail}"\n'
    try:
        with open(log_path, "a", encoding="utf-8") as f:
            f.write(line)
        try:
            os.chmod(log_path, 0o600)
        except OSError:
            pass
    except OSError:
        return
