#!/usr/bin/env bash
# enrich.sh — thin shim over the shared agentic engine (python -m tool.kickoff).
# FAIL-OPEN: always exits 0; prints a passthrough marker on any failure.
set -uo pipefail

PASSTHROUGH_PREFIX="KICKOFF_PASSTHROUGH:"
PY="${CLAUDE_TOOL_PYTHON:-${CLAUDE_PANEL_PYTHON:-python3.12}}"
# Resolve the engine from THIS script's own .claude tree (works identically
# deployed at ~/.claude and inside a repo checkout); PYTHONPATH still wins.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
export PYTHONPATH="${PYTHONPATH:-$CLAUDE_ROOT}"

passthrough() { printf '%s enrichment unavailable (%s)\n' "$PASSTHROUGH_PREFIX" "$1"; exit 0; }

# Verify the engine is importable; otherwise fail-open immediately.
"$PY" -c "import tool.kickoff" >/dev/null 2>&1 || passthrough "engine unavailable"

out="$("$PY" -m tool.kickoff "$@" 2>/dev/null)"; rc=$?
[ "$rc" -eq 0 ] || passthrough "engine error (rc=$rc)"
printf '%s\n' "$out"
