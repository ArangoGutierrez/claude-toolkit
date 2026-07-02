#!/usr/bin/env bash
set -euo pipefail

# capture.sh — refresh this repo's tracked config FROM the live ~/.claude and
# ~/.cursor environment.
#
# ALLOWLIST model: only files that are ALREADY TRACKED in this repo get
# refreshed. Nothing new is ever pulled in from the live environment, so local
# or private material cannot leak into the repo just by running capture — even
# if you add new local skills, hooks, or MCP servers. To publish a brand-new
# file, add it to the repo by hand (and `git add` it) first; subsequent
# captures will then keep it in sync.
#
# CURATED files diverge from the live copies on purpose — they are written for
# this repo's audience, or ship as neutral templates. Capture never overwrites
# them; maintain them by hand.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="${REPO_DIR:-$(cd "$SCRIPT_DIR/.." && pwd)}"

# Hand-maintained files; capture leaves these untouched.
CURATED=(
  ".claude/CLAUDE.md"
  ".claude/settings.json"
  ".claude/remote-settings.json"
  ".claude/statusline.sh"
  ".claude/hooks/session-goal-init.sh"
  ".claude/rules/learned-anti-patterns.md"
  ".claude/skills/goal/SKILL.md"
  ".claude/skills/goal/goal.sh"
  ".cursor/mcp.json"
  ".cursor/hooks.json"
)

CLAUDE_ONLY=false
CURSOR_ONLY=false

usage() {
  cat <<'EOF'
Usage: capture.sh [OPTIONS]

Refresh this repo's tracked .claude/ and .cursor/ files from the live
~/.claude and ~/.cursor environment. Allowlist = files already tracked in this
repo; nothing new is ever pulled in. Curated files are left untouched.

Options:
  --claude-only    Capture only .claude/
  --cursor-only    Capture only .cursor/
  -h, --help       Show this help message
EOF
  exit 0
}

parse_flags() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --claude-only) CLAUDE_ONLY=true; shift ;;
      --cursor-only) CURSOR_ONLY=true; shift ;;
      -h|--help)     usage ;;
      *)             echo "Unknown option: $1" >&2; exit 1 ;;
    esac
  done
  if $CLAUDE_ONLY && $CURSOR_ONLY; then
    echo "Error: --claude-only and --cursor-only are mutually exclusive." >&2
    exit 1
  fi
}

is_curated() {
  local rel="$1" c
  for c in "${CURATED[@]}"; do
    [[ "$rel" == "$c" ]] && return 0
  done
  return 1
}

capture_tree() {
  local top="$1"                 # .claude | .cursor
  local live="$HOME/$top"
  if [[ ! -d "$live" ]]; then
    echo ">> Skipping $top/ (not found at $live)"
    return
  fi

  echo ">> Capturing $top/ (allowlist = tracked files)"
  local refreshed=0 curated=0 absent=0

  while IFS= read -r rel; do
    [[ -z "$rel" ]] && continue
    if is_curated "$rel"; then
      curated=$((curated + 1))
      continue
    fi
    local src="$HOME/$rel" dst="$REPO_DIR/$rel"
    if [[ ! -e "$src" ]]; then
      absent=$((absent + 1))     # live no longer has it; keep the repo copy
      continue
    fi
    /bin/mkdir -p "$(dirname "$dst")"
    /bin/cp -L "$src" "$dst"      # resolve symlinks to real file content
    refreshed=$((refreshed + 1))
  done < <(git -C "$REPO_DIR" ls-files -- "$top")

  echo "   refreshed $refreshed file(s); left $curated curated, $absent live-absent untouched"
}

main() {
  parse_flags "$@"
  # Guard: REPO_DIR must be a git work tree with a .claude/ tree. Prevents an
  # accidental REPO_DIR override (e.g. pointing at the wrong repo) from
  # capturing live content into an unintended place. Printed prominently so the
  # capture target is always visible.
  if ! git -C "$REPO_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "Error: REPO_DIR ($REPO_DIR) is not a git work tree." >&2; exit 1
  fi
  [[ -d "$REPO_DIR/.claude" ]] || { echo "Error: no .claude/ under REPO_DIR ($REPO_DIR)." >&2; exit 1; }
  echo "=== dotfiles capture (allowlist) ==="
  echo ">> capturing INTO: $REPO_DIR"
  echo ""
  if ! $CURSOR_ONLY; then capture_tree ".claude"; fi
  if ! $CLAUDE_ONLY;  then capture_tree ".cursor"; fi
  echo ""
  echo "Review changes:"
  echo "  git -C \"$REPO_DIR\" diff --stat"
  echo "  git -C \"$REPO_DIR\" status"
  echo ""
}

# Only run main when executed directly; allow sourcing for tests.
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
