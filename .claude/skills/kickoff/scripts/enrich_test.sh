#!/bin/bash
# enrich_test.sh — TDD harness for enrich.sh (thin shim over python -m tool.kickoff).
# Run: bash enrich_test.sh < /dev/null
# The shim delegates all logic to the Python engine; these tests cover shim behavior only:
#   - fail-open when the engine module cannot be imported
#   - fail-open when the python interpreter is absent
#   - exit 0 and KICKOFF_PASSTHROUGH: prefix in all failure modes
# Internal curl/jq engine cases (redact, build_manifest, build_payload, call_llm,
# parse_response) have been removed: those functions no longer exist in enrich.sh.
# shellcheck disable=SC1090
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENRICH="$ROOT/enrich.sh"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
FAIL=0
ok(){  echo "PASS: $1"; }
bad(){ echo "FAIL: $1"; FAIL=$((FAIL+1)); }

assert_eq() { local want="$1" got="$2" label="$3"; if [ "$got" = "$want" ]; then ok "$label"; else bad "$label (got=$got want=$want)"; fi; }

# ── Test: passthrough when engine module is missing ────────────────────────────
# Uses a fake python binary that exits 1 on the importability check.
# Discriminates: if enrich.sh doesn't guard the python invocation, a missing engine
# module would cause a nonzero exit, breaking fail-open. The test catches
# the bug introduced by removing the `|| passthrough` guard.
test_passthrough_when_engine_missing() {
  local bin; bin="$WORK/fake-py-$$"; mkdir -p "$bin"
  # Fake python: exit 1 (module not found) on any invocation — simulates engine unavailable.
  printf '#!/usr/bin/env bash\nexit 1\n' > "$bin/fake-python"
  chmod +x "$bin/fake-python"
  out="$(CLAUDE_TOOL_PYTHON="$bin/fake-python" \
        bash "$ENRICH" --mode interactive "do a thing" 2>/dev/null)"; rc=$?
  assert_eq "0" "$rc" "enrich.sh exits 0 when engine missing"
  case "$out" in
    KICKOFF_PASSTHROUGH:*) ok "passthrough marker emitted when engine missing" ;;
    *) bad "expected KICKOFF_PASSTHROUGH, got: $out" ;;
  esac
}
test_passthrough_when_engine_missing

# ── Test: passthrough when python interpreter is absent ───────────────────────
# Discriminates: if enrich.sh doesn't guard the python invocation, a missing
# interpreter would cause a nonzero exit, breaking fail-open.
test_passthrough_when_python_absent() {
  out="$(CLAUDE_TOOL_PYTHON="python-nonexistent-interpreter-xyz" \
        bash "$ENRICH" --mode interactive "do a thing" 2>/dev/null)"; rc=$?
  assert_eq "0" "$rc" "enrich.sh exits 0 when python absent"
  case "$out" in
    KICKOFF_PASSTHROUGH:*) ok "passthrough marker emitted when python absent" ;;
    *) bad "expected KICKOFF_PASSTHROUGH when python absent, got: $out" ;;
  esac
}
test_passthrough_when_python_absent

# ── Test: passthrough when python module run exits nonzero ──────────────────
# Discriminates: if enrich.sh doesn't guard the rc of the module invocation,
# a nonzero exit from the engine would cause a nonzero exit, breaking fail-open.
# This fake python succeeds on the import check but fails on the module run,
# so ONLY the rc-guard branch fires.
test_passthrough_when_engine_exits_nonzero() {
  local bin; bin="$WORK/fake-py-rc-$$"; mkdir -p "$bin"
  # Fake python: exit 0 on import check (-c), exit 1 on module run (-m).
  printf '#!/bin/sh\nfor a in "$@"; do\n  case "$a" in\n    -c) exit 0 ;;\n    -m) exit 1 ;;\n  esac\ndone\nexit 0\n' > "$bin/fake-python"
  chmod +x "$bin/fake-python"
  out="$(CLAUDE_TOOL_PYTHON="$bin/fake-python" \
        bash "$ENRICH" --mode interactive "do a thing" 2>/dev/null)"; rc=$?
  assert_eq "0" "$rc" "enrich.sh exits 0 when engine module run fails"
  case "$out" in
    KICKOFF_PASSTHROUGH:*) ok "passthrough marker emitted when engine rc guard fires" ;;
    *) bad "expected KICKOFF_PASSTHROUGH when engine fails, got: $out" ;;
  esac
}
test_passthrough_when_engine_exits_nonzero

echo ""
if [ "$FAIL" -eq 0 ]; then echo "All tests PASS"; exit 0; else echo "$FAIL FAILED"; exit 1; fi
