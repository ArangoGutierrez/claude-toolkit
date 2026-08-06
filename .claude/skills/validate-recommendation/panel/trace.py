"""Append-only verdict trace log.

Parity with aggregate.sh's log_verdict(). Default-on telemetry: a
silently-broken panel is invisible to the operator without it (every
recommendation hits ERROR and the user sees no behavioral change).
Override path via $CLAUDE_PANEL_TRACE_LOG for tests and alternative
log routing.
"""
import os
import sys
from datetime import datetime, timezone
from pathlib import Path

DEFAULT_TRACE_LOG = Path.home() / ".claude" / "debug" / "panel-trace.log"

# Process-global: trace is high-frequency, so a dropped write warns at most
# once per process — a broken path must never flood the operator's stderr.
_warned = False


def _warn_trace_drop(reason: str, path) -> None:
    """Emit ONE stderr line the first time a trace write drops in this process.

    Best-effort: the warning must never raise, and never fires more than once
    (unlike telemetry, which warns every drop — trace is far more frequent).
    """
    global _warned
    if _warned:
        return
    _warned = True
    try:
        # sys.stderr.write, not print(file=sys.stderr): when sys.stderr is
        # None, print silently falls back to STDOUT; .write raises into the
        # swallow instead (stdout must stay clean for the jq-parsed directive).
        sys.stderr.write(
            f"[panel-trace] WARNING: trace line dropped ({reason}: {path}) "
            f"— run sandbox-disabled or widen the sandbox allowlist\n"
        )
    except Exception:
        pass


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
        _warn_trace_drop("mkdir", log_path)
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
        _warn_trace_drop("write", log_path)
        return
