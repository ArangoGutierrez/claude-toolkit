#!/usr/bin/env bash
set -euo pipefail

# diff.sh — show how this repo's tracked config differs from the live
# ~/.claude and ~/.cursor environment.
#
# ALLOWLIST model (mirrors capture.sh): only files tracked in this repo are
# compared. Curated files are skipped (they diverge from live on purpose).

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="${REPO_DIR:-$(cd "$SCRIPT_DIR/.." && pwd)}"

# Hand-maintained files; diff skips these (kept in sync with capture.sh).
CURATED=(
  ".claude/CLAUDE.md"
  ".claude/settings.json"
  ".claude/remote-settings.json"
  ".claude/statusline.sh"
  ".claude/hooks/session-goal-init.sh"
  ".claude/skills/goal/SKILL.md"
  ".claude/skills/goal/goal.sh"
  ".cursor/mcp.json"
  ".cursor/hooks.json"
)

CLAUDE_ONLY=false
CURSOR_ONLY=false

usage() {
  cat <<'EOF'
Usage: diff.sh [OPTIONS]

Show differences between this repo's tracked config and the live environment
(allowlist = files tracked here; curated files skipped).

Options:
  --claude-only    Compare only .claude/
  --cursor-only    Compare only .cursor/
  -h, --help       Show this help message
EOF
  exit 0
}

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

DIFF_FOUND=false

is_curated() {
  local rel="$1" c
  for c in "${CURATED[@]}"; do
    [[ "$rel" == "$c" ]] && return 0
  done
  return 1
}

# Resolve a symlink to its target file for content comparison.
resolve_file() {
  local f="$1"
  if [[ -L "$f" ]]; then
    local t
    t="$(/usr/bin/readlink "$f")"
    [[ "$t" != /* ]] && t="$(dirname "$f")/$t"
    [[ -f "$t" ]] && { echo "$t"; return; }
  fi
  echo "$f"
}

compare_tree() {
  local top="$1"                 # .claude | .cursor
  local live="$HOME/$top"
  echo "--- $top ---"
  echo ""
  if [[ ! -d "$live" ]]; then
    echo "  Live directory not found: $live"
    DIFF_FOUND=true
    echo ""
    return
  fi

  local changed=0 absent=0 curated=0
  while IFS= read -r rel; do
    [[ -z "$rel" ]] && continue
    if is_curated "$rel"; then
      curated=$((curated + 1))
      continue
    fi
    local repo_file="$REPO_DIR/$rel" live_file="$HOME/$rel"
    if [[ ! -e "$live_file" ]]; then
      echo "  LIVE MISSING  $rel"
      absent=$((absent + 1))
      DIFF_FOUND=true
      continue
    fi
    if ! diff -q "$(resolve_file "$repo_file")" "$(resolve_file "$live_file")" >/dev/null 2>&1; then
      echo "  CHANGED       $rel"
      changed=$((changed + 1))
      DIFF_FOUND=true
    fi
  done < <(git -C "$REPO_DIR" ls-files -- "$top")

  local total=$((changed + absent))
  if [[ $total -eq 0 ]]; then
    echo "  (in sync; $curated curated skipped)"
  else
    echo ""
    echo "  Summary: $changed changed, $absent live-missing, $curated curated-skipped"
  fi
  echo ""
}

echo "=== dotfiles diff (allowlist) ==="
echo ""

if ! $CURSOR_ONLY; then compare_tree ".claude"; fi
if ! $CLAUDE_ONLY;  then compare_tree ".cursor"; fi

if $DIFF_FOUND; then
  echo "=> Differences found."
  exit 1
else
  echo "=> Everything in sync."
  exit 0
fi
