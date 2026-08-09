#!/usr/bin/env bash
# graphify-graph-hint.sh — global SessionStart hook (no matcher; fires on startup, resume,
# clear and compact).
#
# When the current project has a Graphify code graph (graphify-out/graph.json), print a
# reminder to orient via `graphify query` before grepping or reading raw source. A silent
# no-op in any repo without a graph. Fully generic and shareable — no project specifics.
#
# Why SessionStart and not PreToolUse: this was registered on the "Bash" and "Read|Glob|Grep"
# matchers, so it forked on nearly every tool call — about 23 ms each even after its
# once-per-session marker was set, since it still had to re-read that marker. A 300-call
# session paid roughly 7 seconds to deliver one message. SessionStart pays that cost once,
# and the hint lands BEFORE the first search rather than racing it.
#
# The once-per-session marker file is deliberately GONE, not kept as a guard. It existed only
# to suppress the per-call spam. SessionStart fires a handful of times per session, and each
# fire is a context boundary: a compact or a clear drops the earlier hint, so a marker keyed
# on the session id would swallow the repeat exactly when the hint is needed again.
#
# Reads the SessionStart JSON payload on stdin. Writes the hint to stdout, which Claude Code
# adds to the session context — the same contract inject-date.sh and session-goal-init.sh use.
# Exits 0 always; never blocks session start.
set -uo pipefail

payload="$(cat 2>/dev/null || true)"

# Resolve project dir: env first, then payload .cwd, then PWD.
proj="${CLAUDE_PROJECT_DIR:-}"
if [ -z "$proj" ] && [ -n "$payload" ]; then
  proj="$(printf '%s' "$payload" | jq -r '.cwd // empty' 2>/dev/null || true)"
fi
proj="${proj:-$PWD}"

# Guard: no graph -> silent no-op.
[ -f "$proj/graphify-out/graph.json" ] || exit 0

cat <<'EOF'
graphify: a code knowledge graph exists (graphify-out/graph.json). Before grepping/reading raw source to understand this codebase, orient first with `graphify query "<question>"` (scoped subgraph), `graphify explain "<concept>"`, or `graphify path "<A>" "<B>"`. Read graphify-out/GRAPH_REPORT.md only for broad architecture review. Then search/read raw files for specifics. Applies to subagents too.
EOF

exit 0
