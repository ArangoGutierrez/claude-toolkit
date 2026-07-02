#!/usr/bin/env bash
# graphify-graph-hint.sh — global PreToolUse hook (register on matchers "Bash" and "Read|Glob").
#
# When the current project has a Graphify code graph (graphify-out/graph.json) and Claude is
# about to do a raw source search/read, inject a one-line reminder to orient via `graphify query`
# FIRST. Fires at most ONCE per session (avoids the stock per-call token spam) and is a silent
# no-op in any repo without a graph. No NVIDIA/project specifics — fully generic & shareable.
#
# Reads the PreToolUse JSON payload on stdin; emits hookSpecificOutput.additionalContext (the
# same envelope Graphify's native hook uses) or nothing.
set -euo pipefail

payload="$(cat 2>/dev/null || true)"

# Resolve project dir: env first, then payload .cwd, then PWD.
proj="${CLAUDE_PROJECT_DIR:-}"
if [ -z "$proj" ] && [ -n "$payload" ]; then
  proj="$(printf '%s' "$payload" | jq -r '.cwd // empty' 2>/dev/null || true)"
fi
proj="${proj:-$PWD}"

# Guard: no graph -> silent no-op. (|| exit is set -e safe.)
[ -f "$proj/graphify-out/graph.json" ] || exit 0

tool="$(printf '%s' "$payload" | jq -r '.tool_name // empty' 2>/dev/null || true)"

# Is this a "search/read raw source to understand the codebase" action?
relevant=0
case "$tool" in
  Bash)
    cmd="$(printf '%s' "$payload" | jq -r '.tool_input.command // empty' 2>/dev/null || true)"
    case "$cmd" in
      *grep*|*"rg "*|*ripgrep*|*"find "*|*"fd "*|*"ack "*|*"ag "*) relevant=1 ;;
    esac
    ;;
  Read|Glob)
    target="$(printf '%s' "$payload" \
      | jq -r '[.tool_input.file_path, .tool_input.pattern, .tool_input.path] | map(select(. != null)) | join(" ")' 2>/dev/null \
      | tr 'A-Z' 'a-z' || true)"
    case "$target" in
      *graphify-out/*) exit 0 ;;  # reading the graph itself is not "raw source"
    esac
    for e in .ts .tsx .js .jsx .go .rs .py .java .rb .c .h .cpp .hpp .cc .cs .kt .swift .php .scala .lua .sh .md .rst .mdx; do
      case "$target" in *"$e"*) relevant=1; break ;; esac
    done
    ;;
  Grep)
    # The dedicated Grep tool is always a raw-source content search.
    gtarget="$(printf '%s' "$payload" \
      | jq -r '[.tool_input.path, .tool_input.glob] | map(select(. != null)) | join(" ")' 2>/dev/null \
      | tr 'A-Z' 'a-z' || true)"
    case "$gtarget" in
      *graphify-out/*) exit 0 ;;  # searching the graph itself is not "raw source"
    esac
    relevant=1
    ;;
esac
[ "$relevant" = 1 ] || exit 0

# Once-per-session: keyed by session id (env first, then payload), in a temp marker.
sid="${CLAUDE_SESSION_ID:-}"
if [ -z "$sid" ] && [ -n "$payload" ]; then
  sid="$(printf '%s' "$payload" | jq -r '.session_id // empty' 2>/dev/null || true)"
fi
sid="${sid:-nosession}"
marker="${TMPDIR:-/tmp}/claude-graphify-surfaced-${sid}"
if [ -f "$marker" ]; then
  exit 0
fi
: > "$marker"

msg="graphify: a code knowledge graph exists (graphify-out/graph.json). Before grepping/reading raw source to understand this codebase, orient first with \`graphify query \"<question>\"\` (scoped subgraph), \`graphify explain \"<concept>\"\`, or \`graphify path \"<A>\" \"<B>\"\`. Read graphify-out/GRAPH_REPORT.md only for broad architecture review. Then search/read raw files for specifics. Applies to subagents too."
jq -n --arg ctx "$msg" '{hookSpecificOutput:{hookEventName:"PreToolUse",additionalContext:$ctx}}'
