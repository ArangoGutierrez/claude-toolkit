#!/usr/bin/env bash
# Tests for graphify-graph-hint.sh — the SessionStart graph-hint hook.
# Plain bash (no bats), matching the repo's *_test.sh convention.
#
# Contract under test:
#   - a project WITH graphify-out/graph.json  -> plain-text hint on stdout
#   - a project WITHOUT one                   -> silent, rc 0
#   - project dir resolves env -> payload .cwd -> PWD, in that order
#   - the hint re-fires on every SessionStart (startup/resume/clear/compact),
#     because each is a context boundary where the earlier hint is gone
#   - stdout is plain text, and never claims the PreToolUse event
set -uo pipefail
HOOK="$(cd "$(dirname "$0")" && pwd)/graphify-graph-hint.sh"
fails=0
# Anchor at $TMPDIR: macOS mktemp with no template resolves through
# _CS_DARWIN_USER_TEMP_DIR instead, which an agent sandbox denies.
tmproot="$(mktemp -d "${TMPDIR:-/tmp}/graphify-graph-hint-test.XXXXXX")"
trap 'rm -rf "$tmproot"' EXIT

# A project WITH a graph, and one WITHOUT. Every case runs from a controlled cwd
# so a stray graph in the tester's own directory can never make a case pass.
repo="$tmproot/repo"; mkdir -p "$repo/graphify-out"; echo '{}' > "$repo/graphify-out/graph.json"
norepo="$tmproot/norepo"; mkdir -p "$norepo"

rc=0
run() { # $1=CLAUDE_PROJECT_DIR ("" unsets it) $2=cwd $3=payload -> stdout; sets $rc
  local out
  out="$(
    cd "$2" || exit 99
    if [ -n "$1" ]; then export CLAUDE_PROJECT_DIR="$1"; else unset CLAUDE_PROJECT_DIR; fi
    TMPDIR="$tmproot" bash "$HOOK" <<<"$3"
  )"; rc=$?
  printf '%s' "$out"
}

ok()   { echo "ok: $1"; }
bad()  { echo "FAIL: $1"; fails=$((fails+1)); }
empty()       { if [ -n "$2" ]; then bad "$1 (expected silent, got: $2)"; else ok "$1"; fi; }
contains()    { if printf '%s' "$2" | grep -qF "$3"; then ok "$1"; else bad "$1 (missing '$3' in: $2)"; fi; }
notcontains() { if printf '%s' "$2" | grep -qF "$3"; then bad "$1 (forbidden '$3' present in: $2)"; else ok "$1"; fi; }
startswith()  { case "$2" in "$3"*) ok "$1" ;; *) bad "$1 (expected prefix '$3', got: $2)" ;; esac; }
rc_is()       { if [ "$rc" -eq "$2" ]; then ok "$1"; else bad "$1 (rc=$rc, want $2)"; fi; }

# Realistic SessionStart payloads — note there is no tool_name and no tool_input.
SS_START='{"session_id":"s-a","transcript_path":"/tmp/t.jsonl","hook_event_name":"SessionStart","source":"startup"}'
SS_COMPACT='{"session_id":"s-a","transcript_path":"/tmp/t.jsonl","hook_event_name":"SessionStart","source":"compact"}'
SS_CWD_GRAPH="{\"session_id\":\"s-b\",\"hook_event_name\":\"SessionStart\",\"source\":\"startup\",\"cwd\":\"$repo\"}"
SS_CWD_NONE="{\"session_id\":\"s-c\",\"hook_event_name\":\"SessionStart\",\"source\":\"startup\",\"cwd\":\"$norepo\"}"

# 1) No graph -> silent no-op, and never blocks session start.
out="$(run "$norepo" "$norepo" "$SS_START")"
empty "no graph -> silent" "$out"
rc_is "no graph -> rc 0" 0

# 2) Graph present -> the hint fires on a plain SessionStart payload.
out="$(run "$repo" "$norepo" "$SS_START")"
contains "graph -> emits hint" "$out" "graphify query"
rc_is "graph -> rc 0" 0
# Output contract: plain text on stdout (like inject-date.sh), not a JSON envelope.
startswith "graph -> plain text, not JSON" "$out" "graphify:"
# A SessionStart hook must never announce itself as PreToolUse.
notcontains "graph -> does not claim PreToolUse" "$out" "PreToolUse"

# 3) Same session, a second SessionStart (compact) -> emits AGAIN. A compact drops the
#    earlier hint from context, so suppressing the repeat would silently lose the nudge.
out="$(run "$repo" "$norepo" "$SS_COMPACT")"
contains "same session, compact -> emits again" "$out" "graphify query"

# 4) No CLAUDE_PROJECT_DIR: the project dir comes from the payload's .cwd.
out="$(run "" "$norepo" "$SS_CWD_GRAPH")"
contains "payload .cwd with graph -> emits" "$out" "graphify query"
out="$(run "" "$norepo" "$SS_CWD_NONE")"
empty "payload .cwd without graph -> silent" "$out"

# 5) No env, no payload at all: fall back to PWD. Both directions, so the silent
#    case above cannot be passing merely because the hook is inert.
out="$(run "" "$norepo" "")"
empty "empty payload, PWD without graph -> silent" "$out"
rc_is "empty payload -> rc 0" 0
out="$(run "" "$repo" "")"
contains "empty payload, PWD with graph -> emits" "$out" "graphify query"

echo "---"; if [ "$fails" -eq 0 ]; then echo "ALL PASS"; else echo "$fails FAILED"; exit 1; fi
