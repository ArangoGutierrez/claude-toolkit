#!/usr/bin/env bash
set -euo pipefail
# graphify-install.sh — install the Graphify Claude Code integration (hook + rule +
# settings.json PreToolUse entries) into a Claude config dir. IDEMPOTENT: re-running
# inserts nothing new and exits 0. NEVER clobbers existing hooks.
#
# Usage: graphify-install.sh [--target DIR] [--source DIR] [--dry-run]
#   --target  Claude config dir to install into       (default: $HOME/.claude)
#   --source  repo .claude dir to copy artifacts from (default: <repo>/.claude)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCE="$(cd "$SCRIPT_DIR/.." && pwd)/.claude"
TARGET="$HOME/.claude"
DRY_RUN=false

while [ $# -gt 0 ]; do
  case "$1" in
    --target) TARGET="$2"; shift 2 ;;
    --source) SOURCE="$2"; shift 2 ;;
    --dry-run) DRY_RUN=true; shift ;;
    -h|--help) grep '^#' "$0"; exit 0 ;;
    *) echo "graphify-install: unknown arg: $1" >&2; exit 2 ;;
  esac
done

HOOK_SRC="$SOURCE/hooks/graphify-graph-hint.sh"
RULE_SRC="$SOURCE/rules/graphify.md"
SETTINGS="$TARGET/settings.json"
# Literal $HOME is intentional: settings.json stores the unexpanded path (matching
# the existing hook entries); Claude Code expands it at hook-run time.
# shellcheck disable=SC2016
HOOK_CMD='$HOME/.claude/hooks/graphify-graph-hint.sh'

command -v jq >/dev/null || { echo "graphify-install: jq is required" >&2; exit 1; }
for f in "$HOOK_SRC" "$RULE_SRC" "$SETTINGS"; do
  [ -f "$f" ] || { echo "graphify-install: missing required file: $f" >&2; exit 1; }
done

# 1) Copy hook + rule (force; bypass any cp -i alias).
if $DRY_RUN; then
  echo "[dry-run] would copy hook -> $TARGET/hooks/ and rule -> $TARGET/rules/"
else
  mkdir -p "$TARGET/hooks" "$TARGET/rules"
  command cp -f "$HOOK_SRC" "$TARGET/hooks/graphify-graph-hint.sh"
  chmod +x "$TARGET/hooks/graphify-graph-hint.sh"
  command cp -f "$RULE_SRC" "$TARGET/rules/graphify.md"
fi

# 2) Idempotency: already registered? -> done.
if jq -e '[.hooks.PreToolUse[]?.hooks[]?.command // ""] | any(test("graphify-graph-hint"))' "$SETTINGS" >/dev/null; then
  echo "graphify-install: settings.json already registers graphify-graph-hint; no settings change."
  exit 0
fi

if $DRY_RUN; then
  echo "[dry-run] would back up $SETTINGS and add Bash + Glob|Grep PreToolUse blocks"
  exit 0
fi

# 3) Backup, then insert the two PreToolUse blocks.
backup="$SETTINGS.bak-graphify-$(date +%Y%m%d-%H%M%S)"
command cp -f "$SETTINGS" "$backup"

tmpf="$(mktemp)"
jq --arg cmd "$HOOK_CMD" '
  .hooks.PreToolUse += [
    {matcher:"Bash",      hooks:[{type:"command", command:$cmd}]},
    {matcher:"Glob|Grep", hooks:[{type:"command", command:$cmd}]}
  ]
' "$SETTINGS" > "$tmpf"

# 4) Validate generated JSON before replacing the live file.
if ! jq -e . "$tmpf" >/dev/null 2>&1; then
  echo "graphify-install: generated invalid JSON; aborting (live file untouched, backup $backup)" >&2
  rm -f "$tmpf"; exit 1
fi
command mv -f "$tmpf" "$SETTINGS"

echo "graphify-install: installed hook+rule and Bash + Glob|Grep PreToolUse blocks into $TARGET"
echo "  backup: $backup"
