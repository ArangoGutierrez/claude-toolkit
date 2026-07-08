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

if [[ ! -f "$SCRIPT_DIR/sync-lib.sh" ]]; then
  echo "Error: $SCRIPT_DIR/sync-lib.sh not found (required shared library)." >&2
  exit 1
fi
# shellcheck source=sync-lib.sh
source "$SCRIPT_DIR/sync-lib.sh"

CLAUDE_ONLY=false
CURSOR_ONLY=false
# Files actually refreshed in THIS run; the leak sweep below scans only these
# (delta-scoped), not the whole tree.
REFRESHED_FILES=()

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
    REFRESHED_FILES+=("$rel")
  done < <(git -C "$REPO_DIR" ls-files -- "$top")

  echo "   refreshed $refreshed file(s); left $curated curated, $absent live-absent untouched"
}

# leak_sweep scans every file refreshed in this run (REFRESHED_FILES) against
# sync-lib.sh's leak patterns. Returns 0 if clean, 1 if any file flagged.
leak_sweep() {
  local rel abs rc=0
  # bash 3.2: expanding "${REFRESHED_FILES[@]}" on a zero-element array is an
  # unbound-variable error under set -u, so skip the loop entirely when empty.
  if [[ ${#REFRESHED_FILES[@]} -gt 0 ]]; then
    for rel in "${REFRESHED_FILES[@]}"; do
      abs="$REPO_DIR/$rel"
      if ! leak_scan_file "$abs" "$rel"; then
        rc=1
      fi
    done
  fi
  return $rc
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

  if ! leak_sweep; then
    echo ""
    echo "Leak sweep found possible identity-bearing content in the files above."
    echo "Review and revert before committing (e.g. git diff, git checkout -- <file>)."
    exit 1
  fi

  echo "Review changes:"
  echo "  git -C \"$REPO_DIR\" diff --stat"
  echo "  git -C \"$REPO_DIR\" status"
  echo ""
}

# Only run main when executed directly; allow sourcing for tests.
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
