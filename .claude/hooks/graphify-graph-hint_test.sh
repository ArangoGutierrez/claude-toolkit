#!/usr/bin/env bash
# Tests for graphify-graph-hint.sh — global once-per-session graph-hint PreToolUse hook.
# Plain bash (no bats), matching the repo's *_test.sh convention.
set -uo pipefail
HOOK="$(cd "$(dirname "$0")" && pwd)/graphify-graph-hint.sh"
fails=0
tmproot="$(mktemp -d)"; trap 'rm -rf "$tmproot"' EXIT

# A project WITH a graph, and one WITHOUT.
repo="$tmproot/repo"; mkdir -p "$repo/graphify-out"; echo '{}' > "$repo/graphify-out/graph.json"
norepo="$tmproot/norepo"; mkdir -p "$norepo"

run() { # $1=projectdir $2=sessionid $3=json-payload -> hook stdout
  CLAUDE_PROJECT_DIR="$1" CLAUDE_SESSION_ID="$2" TMPDIR="$tmproot" bash "$HOOK" <<<"$3"
}
empty()    { if [ -n "$2" ]; then echo "FAIL: $1 (expected silent, got: $2)"; fails=$((fails+1)); else echo "ok: $1"; fi; }
contains() { if printf '%s' "$2" | grep -q "$3"; then echo "ok: $1"; else echo "FAIL: $1 (missing '$3' in: $2)"; fails=$((fails+1)); fi; }

BASH_GREP='{"tool_name":"Bash","tool_input":{"command":"grep -r foo src/"}}'
BASH_LS='{"tool_name":"Bash","tool_input":{"command":"ls -la"}}'
READ_TSX='{"tool_name":"Read","tool_input":{"file_path":"apps/web/Login.tsx"}}'
READ_PNG='{"tool_name":"Read","tool_input":{"file_path":"docs/diagram.png"}}'
READ_GRAPH='{"tool_name":"Read","tool_input":{"file_path":"graphify-out/GRAPH_REPORT.md"}}'
GREP_TOOL='{"tool_name":"Grep","tool_input":{"pattern":"useEffect","path":"src"}}'

# 1) No graph in the project -> silent no-op (the guard).
empty "no graph -> silent" "$(run "$norepo" s1 "$BASH_GREP")"
# 2) Graph + a search command, first call this session -> emits the hint.
contains "graph + grep (first call) -> emits" "$(run "$repo" s2 "$BASH_GREP")" "graphify query"
# 3) Graph + search, SAME session, second call -> silent (once-per-session dedup).
empty "graph + grep (same session 2nd) -> silent" "$(run "$repo" s2 "$BASH_GREP")"
# 4) Graph + Read of a source file in a NEW session -> emits again.
contains "graph + Read .tsx (new session) -> emits" "$(run "$repo" s3 "$READ_TSX")" "graphify query"
# 5) Graph + Read of a NON-source file -> silent (relevance gate).
empty "graph + Read .png -> silent" "$(run "$repo" s4 "$READ_PNG")"
# 6) Graph + a non-search Bash command -> silent (relevance gate).
empty "graph + Bash ls -> silent" "$(run "$repo" s5 "$BASH_LS")"
# 7) Graph + Read of the graph artifact itself -> silent (don't nag about reading graphify-out/).
empty "graph + Read graphify-out/ -> silent" "$(run "$repo" s6 "$READ_GRAPH")"
# 8) Graph + the dedicated Grep tool (raw-source search), new session -> emits.
contains "graph + Grep tool (new session) -> emits" "$(run "$repo" s7 "$GREP_TOOL")" "graphify query"

echo "---"; if [ "$fails" -eq 0 ]; then echo "ALL PASS"; else echo "$fails FAILED"; exit 1; fi
