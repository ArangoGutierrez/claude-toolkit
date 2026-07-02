#!/usr/bin/env bash
set -euo pipefail

# graphify-bootstrap.sh — build (or refresh) a Graphify code knowledge graph
# for a repo so Claude can orient by structure instead of blind grep.
#
# Runs `graphify update <path>` — AST-only extraction, no LLM and no API key.
# Once the graph exists at <path>/graphify-out/graph.json, the bundled
# graphify-graph-hint PreToolUse hook points Claude at it before raw-source
# searches (Grep/Glob/grep), and the .claude/rules/graphify.md directive
# reminds the agent to query it first.
#
# Usage: graphify-bootstrap.sh [PATH]   (PATH defaults to the current directory)

usage() {
  cat <<'EOF'
Usage: graphify-bootstrap.sh [PATH]

Build or refresh a Graphify code graph for the repo at PATH (default: .).
Runs `graphify update PATH` (AST-only, no LLM).

Requires graphify on PATH:
  pipx install graphify     # recommended
  # or: pip install graphify
EOF
}

main() {
  case "${1:-}" in
    -h|--help) usage; exit 0 ;;
  esac

  local target="${1:-.}"

  if ! command -v graphify >/dev/null 2>&1; then
    echo "graphify-bootstrap: 'graphify' not found on PATH." >&2
    echo "  Install it first:  pipx install graphify" >&2
    exit 1
  fi

  if [ ! -d "$target" ]; then
    echo "graphify-bootstrap: '$target' is not a directory." >&2
    exit 1
  fi

  # Seed a minimal default .graphifyignore if the repo has none. graphify does not
  # hard-skip vendor/, and it honors only in-tree ignore files — so vendored deps and
  # generated site output otherwise pollute the graph. Never overwrite a user's file.
  if [ ! -f "$target/.graphifyignore" ]; then
    cat > "$target/.graphifyignore" <<'IGNORE'
# graphify scan excludes (auto-seeded by graphify-bootstrap; edit freely).
# Vendored third-party deps and generated site output are not first-party code.
vendor/
**/vendor/
_site/
**/_site/
IGNORE
    echo ">> Seeded default .graphifyignore (vendored/generated excludes)"
  fi

  echo ">> Building Graphify graph (AST-only, no LLM) for: $target"
  graphify update "$target"

  local graph="$target/graphify-out/graph.json"
  if [ -f "$graph" ]; then
    echo ">> Graph ready: $graph"
    echo "   Claude will now be pointed here before raw-source searches in this repo."
    echo "   Re-run after large refactors to refresh (add --force via: GRAPHIFY_FORCE=1)."

    # Keep git unaware of the graph + the scan-ignore file via .git/info/exclude
    # (LOCAL — never staged, committed, or pushed), NOT .gitignore, so the repo's
    # tracked tree is never polluted. Idempotent; worktree-safe via --git-path.
    if git -C "$target" rev-parse --git-dir >/dev/null 2>&1; then
      local excl
      excl="$(cd "$target" && git rev-parse --git-path info/exclude 2>/dev/null || true)"
      case "$excl" in /*) : ;; *) excl="$target/$excl" ;; esac
      if [ -n "$excl" ]; then
        mkdir -p "$(dirname "$excl")"; [ -f "$excl" ] || : > "$excl"
        for pat in 'graphify-out/' '.graphifyignore'; do
          grep -qxF "$pat" "$excl" 2>/dev/null || printf '%s\n' "$pat" >> "$excl"
        done
        echo ">> Excluded graphify-out/ + .graphifyignore via .git/info/exclude (local, not committed)"
      fi
    fi

    # Ensure the GLOBAL graphify-refresh hooks exist (core.hooksPath-aware).
    # Per-repo .git/hooks/* are bypassed when core.hooksPath is set, so we
    # install into the effective global hooks dir instead.
    installer="$(cd "$(dirname "$0")" && pwd)/graphify-hooks-install.sh"
    if [ -f "$installer" ]; then
      # Invoke via `bash` so a dropped exec bit (re-clone/file-copy) does not
      # silently skip global-hook install. A missing installer WARNs, never no-ops.
      bash "$installer" || echo ">> WARNING: graphify-hooks-install failed" >&2
    else
      echo ">> WARNING: graphify-hooks-install.sh not found at $installer (skipping global hooks)" >&2
    fi

    # Warn if vendored/dependency paths still leaked into the graph (excludes missed them).
    if command -v jq >/dev/null 2>&1; then
      local leaked
      leaked=$(jq '[.nodes[]? | select((.source_file // "") | test("(^|/)(vendor|node_modules)/"))] | length' "$graph" 2>/dev/null || echo 0)
      if [ "${leaked:-0}" -gt 0 ]; then
        echo ">> WARNING: $leaked graph nodes come from vendored paths (vendor/ or node_modules/)." >&2
        echo ">>          Add the offending dir to $target/.graphifyignore and rebuild (GRAPHIFY_FORCE=1)." >&2
      fi
    fi
  else
    echo "graphify-bootstrap: expected a graph at $graph but none was created." >&2
    exit 1
  fi
}

main "$@"
