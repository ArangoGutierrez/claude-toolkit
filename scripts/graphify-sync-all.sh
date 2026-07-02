#!/usr/bin/env bash
set -uo pipefail
# Fleet driver: discover graphed repos under the scan root, remediate dead
# per-repo hooks, run graphify-sync-repo.sh on each (failures isolated), and
# write the log + LATEST.md summary. bash 3.2 compatible. 2026.

ROOT="${GRAPHIFY_SCAN_ROOT:-$HOME/src}"
SELF_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_SCRIPT="$SELF_DIR/graphify-sync-repo.sh"
LOGDIR="${GRAPHIFY_LOG_DIR:-$HOME/.claude/logs}"; mkdir -p "$LOGDIR"
LOG="$LOGDIR/graphify-sync.log"; LATEST="$LOGDIR/graphify-sync-LATEST.md"
TS="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

count=0; conflict_count=0
: > "$LATEST.tmp"
: > "$LATEST.conflicts"

while IFS= read -r gd; do
  repo="$(dirname "$gd")"
  git -C "$repo" rev-parse --git-dir >/dev/null 2>&1 || continue
  pc="$repo/.git/hooks/post-commit"
  if [ -f "$pc" ] && grep -qF 'graphify-refresh' "$pc" 2>/dev/null; then rm -f "$pc"; fi
  errf="$LOGDIR/.sync-stderr.$$"
  line="$(bash "$REPO_SCRIPT" "$repo" 2>"$errf")"
  printf '%s %s\n' "$TS" "$line" >> "$LOG"
  # Label per-repo stderr so it is correlatable in the log (was unprefixed).
  if [ -s "$errf" ]; then
    while IFS= read -r e; do printf '%s NOTE[%s] %s\n' "$TS" "$repo" "$e" >> "$LOG"; done < "$errf"
  fi
  rm -f "$errf"
  printf '%s\n' "$line" >> "$LATEST.tmp"
  count=$((count+1))
  case "$line" in *rebase:CONFLICT*) printf -- '- %s\n' "$repo" >> "$LATEST.conflicts"; conflict_count=$((conflict_count+1));; esac
done < <(find "$ROOT" -type d -name graphify-out -prune 2>/dev/null)

{
  echo "# Graphify fleet sync — $TS"
  echo
  if [ "$conflict_count" -gt 0 ]; then
    echo "## Conflicts (manual rebase needed)"; cat "$LATEST.conflicts"; echo
  fi
  echo "## Per-repo ($count)"
  echo '```'; cat "$LATEST.tmp"; echo '```'
} > "$LATEST"
rm -f "$LATEST.tmp" "$LATEST.conflicts"

if [ "$conflict_count" -gt 0 ] && command -v osascript >/dev/null 2>&1; then
  osascript -e "display notification \"$conflict_count repo(s) need manual rebase\" with title \"graphify-sync\"" >/dev/null 2>&1 || true
fi
echo "synced $count repo(s); $conflict_count conflict(s). log: $LOG"
