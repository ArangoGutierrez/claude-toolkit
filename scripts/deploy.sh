#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# --- Exclude lists (runtime data, not config) ---

CLAUDE_EXCLUDES=(
  .git/
  .DS_Store
  debug/
  projects/
  teams/
  tasks/
  todos/
  cache/
  file-history/
  session-env/
  shell-snapshots/
  paste-cache/
  telemetry/
  backups/
  ide/
  plans/
  history.jsonl
  stats-cache.json
  plugins/cache/
  plugins/known_marketplaces.json
  plugins/marketplaces/
  settings.local.json
)

CURSOR_EXCLUDES=(
  .git/
  .DS_Store
  extensions/
  projects/
  ai-tracking/
  snapshots/
  ide_state.json
  argv.json
  unified_repo_list.json
  worktrees/
  blocklist
  .deploy-version
  docs/
  skills/
)

# --- Defaults ---
DRY_RUN=false
FORCE=false
CLAUDE_ONLY=false
CURSOR_ONLY=false
NO_PLUGINS=false
DELETE=false

usage() {
  cat <<'EOF'
Usage: deploy.sh [OPTIONS]

Deploy .claude/ and .cursor/ from the repo to ~/.

Options:
  --dry-run        Show what would be done without making changes
  --force          Skip backup step
  --claude-only    Deploy only .claude/
  --cursor-only    Deploy only .cursor/
  --no-plugins     Exclude plugins/ from .claude deployment
  --delete         Pass --delete to rsync (remove files not in repo)
  -h, --help       Show this help message
EOF
  exit 0
}

# --- Parse flags ---
while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run)     DRY_RUN=true; shift ;;
    --force)       FORCE=true; shift ;;
    --claude-only) CLAUDE_ONLY=true; shift ;;
    --cursor-only) CURSOR_ONLY=true; shift ;;
    --no-plugins)  NO_PLUGINS=true; shift ;;
    --delete)      DELETE=true; shift ;;
    -h|--help)     usage ;;
    *)             echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done

if $CLAUDE_ONLY && $CURSOR_ONLY; then
  echo "Error: --claude-only and --cursor-only are mutually exclusive." >&2
  exit 1
fi

# --- Helpers ---

build_rsync_excludes() {
  local -n excludes_ref=$1
  local args=()
  for pattern in "${excludes_ref[@]}"; do
    args+=(--exclude "$pattern")
  done
  printf '%s\n' "${args[@]}"
}

run_rsync() {
  local src="$1" dest="$2"
  shift 2
  local extra_args=("$@")

  local rsync_args=(-av --itemize-changes)
  if $DRY_RUN; then
    rsync_args+=(--dry-run)
  fi
  if $DELETE; then
    rsync_args+=(--delete)
  fi
  rsync_args+=("${extra_args[@]}")
  rsync_args+=("$src" "$dest")

  /usr/bin/rsync "${rsync_args[@]}"
}

# --- Backup ---

do_backup() {
  if $FORCE; then
    echo ">> Skipping backup (--force)"
    return
  fi

  local backup_dir="$HOME/.config/dotfiles-backup"
  /bin/mkdir -p "$backup_dir"
  local timestamp
  timestamp="$(date +%Y%m%d-%H%M%S)"
  local tarball="$backup_dir/dotfiles-backup-${timestamp}.tar.gz"

  local tar_args=()
  if ! $CURSOR_ONLY && [[ -d "$HOME/.claude" ]]; then
    tar_args+=(".claude")
  fi
  if ! $CLAUDE_ONLY && [[ -d "$HOME/.cursor" ]]; then
    tar_args+=(".cursor")
  fi

  if [[ ${#tar_args[@]} -eq 0 ]]; then
    echo ">> Nothing to back up (target directories do not exist yet)"
    return
  fi

  echo ">> Backing up to $tarball"
  if $DRY_RUN; then
    echo "   [dry-run] Would create tarball of: ${tar_args[*]}"
  else
    (cd "$HOME" && /usr/bin/tar czf "$tarball" "${tar_args[@]}")
    echo "   Backup created: $tarball"
  fi
}

# --- Deploy ---

deploy_claude() {
  local src="$REPO_DIR/.claude/"
  local dest="$HOME/.claude/"

  if [[ ! -d "$src" ]]; then
    echo ">> Skipping .claude/ (not found in repo)"
    return
  fi

  echo ">> Deploying .claude/"
  local exclude_args=()
  for pattern in "${CLAUDE_EXCLUDES[@]}"; do
    exclude_args+=(--exclude "$pattern")
  done
  if $NO_PLUGINS; then
    exclude_args+=(--exclude "plugins/")
  fi

  run_rsync "$src" "$dest" "${exclude_args[@]}"
}

deploy_cursor() {
  local src="$REPO_DIR/.cursor/"
  local dest="$HOME/.cursor/"

  if [[ ! -d "$src" ]]; then
    echo ">> Skipping .cursor/ (not found in repo)"
    return
  fi

  echo ">> Deploying .cursor/"
  local exclude_args=()
  for pattern in "${CURSOR_EXCLUDES[@]}"; do
    exclude_args+=(--exclude "$pattern")
  done

  run_rsync "$src" "$dest" "${exclude_args[@]}"
}

# --- Verification ---

verify() {
  echo ""
  echo ">> Verification"
  local errors=0

  # Check key files exist
  local key_files=()
  if ! $CURSOR_ONLY; then
    key_files+=("$HOME/.claude/settings.json" "$HOME/.claude/CLAUDE.md")
  fi
  if ! $CLAUDE_ONLY; then
    key_files+=("$HOME/.cursor/mcp.json" "$HOME/.cursor/rules")
  fi

  for f in "${key_files[@]}"; do
    if [[ -e "$f" ]]; then
      echo "   OK   $f"
    else
      echo "   MISS $f"
      errors=$((errors + 1))
    fi
  done

  # Check hooks are executable
  local hook_dirs=()
  if ! $CURSOR_ONLY && [[ -d "$HOME/.claude/hooks" ]]; then
    hook_dirs+=("$HOME/.claude/hooks")
  fi
  if ! $CLAUDE_ONLY && [[ -d "$HOME/.cursor/hooks" ]]; then
    hook_dirs+=("$HOME/.cursor/hooks")
  fi

  for hdir in "${hook_dirs[@]}"; do
    while IFS= read -r -d '' hook; do
      if [[ -x "$hook" ]]; then
        echo "   OK   $hook (executable)"
      else
        echo "   WARN $hook (not executable)"
        errors=$((errors + 1))
      fi
    done < <(/usr/bin/find "$hdir" -type f -print0 2>/dev/null)
  done

  # Validate JSON files
  local json_files=()
  if ! $CURSOR_ONLY; then
    for jf in "$HOME/.claude/settings.json" "$HOME/.claude/policy-limits.json" "$HOME/.claude/remote-settings.json"; do
      [[ -f "$jf" ]] && json_files+=("$jf")
    done
  fi
  if ! $CLAUDE_ONLY; then
    for jf in "$HOME/.cursor/mcp.json" "$HOME/.cursor/hooks.json"; do
      [[ -f "$jf" ]] && json_files+=("$jf")
    done
  fi

  for jf in "${json_files[@]}"; do
    if python3 -c "import json,sys; json.load(open(sys.argv[1]))" "$jf" 2>/dev/null; then
      echo "   OK   $jf (valid JSON)"
    else
      echo "   FAIL $jf (invalid JSON)"
      errors=$((errors + 1))
    fi
  done

  if [[ $errors -eq 0 ]]; then
    echo "   All checks passed."
  else
    echo "   $errors issue(s) found."
  fi
}

# --- Main ---

echo "=== dotfiles deploy ==="
if $DRY_RUN; then
  echo "    (dry-run mode)"
fi
echo ""

do_backup

if ! $CURSOR_ONLY; then
  deploy_claude
fi
if ! $CLAUDE_ONLY; then
  deploy_cursor
fi

if ! $DRY_RUN; then
  verify
fi

echo ""
echo "Done."
