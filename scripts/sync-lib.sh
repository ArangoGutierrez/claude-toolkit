#!/usr/bin/env bash
# sync-lib.sh — shared source of truth for capture.sh and diff.sh.
#
# Sourced by both (SCRIPT_DIR-relative). Defines the CURATED allowlist,
# is_curated(), and the leak-sweep helpers used to gate copies out of the
# live ~/.claude / ~/.cursor environment before they land in this PUBLIC repo.
#
# macOS bash 3.2 compatible: plain arrays only, no associative arrays,
# no ${var,,}.

# Hand-maintained files; capture/diff leave these untouched. Entries may be
# GLOBS (e.g. ".claude/team/*"); is_curated() matches with an unquoted RHS
# bash pattern, which lets `*` cross `/` and cover a whole subtree.
CURATED=(
  ".claude/CLAUDE.md"
  ".claude/settings.json"
  ".claude/remote-settings.json"
  ".claude/statusline.sh"
  ".claude/hooks/session-goal-init.sh"
  ".claude/rules/learned-anti-patterns.md"
  ".claude/skills/goal/SKILL.md"
  ".claude/skills/goal/goal.sh"
  ".claude/plugins/installed_plugins.json"
  ".claude/policy-limits.json"
  ".claude/team/*"
  ".cursor/mcp.json"
  ".cursor/hooks.json"
)

is_curated() {
  local rel="$1" c
  for c in "${CURATED[@]}"; do
    # RHS deliberately unquoted: it's a bash glob pattern, not a literal string.
    [[ "$rel" == $c ]] && return 0
  done
  return 1
}

# Generic, identity-agnostic leak patterns (ERE). Always active regardless of
# the local pattern file below — these are safe to ship in the public repo.
GENERIC_LEAK_PATTERNS=(
  '/Users/[A-Za-z0-9._-]+'
  '/home/[A-Za-z0-9._-]+'
)

# Local, identity-bearing patterns (real names, machine usernames, private
# project paths) never enter tracked content. Override with LEAK_PATTERNS_FILE;
# default is SCRIPT_DIR-relative and .gitignore'd — see scripts/leak-patterns.local
# in .gitignore. One ERE per line; blank lines and lines starting with # are
# skipped.
LEAK_PATTERNS_FILE="${LEAK_PATTERNS_FILE:-$SCRIPT_DIR/leak-patterns.local}"

LOCAL_LEAK_PATTERNS=()
if [[ -f "$LEAK_PATTERNS_FILE" ]]; then
  while IFS= read -r _pat || [[ -n "$_pat" ]]; do
    [[ -z "$_pat" || "$_pat" == \#* ]] && continue
    LOCAL_LEAK_PATTERNS+=("$_pat")
  done < "$LEAK_PATTERNS_FILE"
else
  echo "WARNING: scripts/leak-patterns.local not found — leak sweep running with generic patterns only" >&2
fi
unset _pat

# leak_scan_file <abs-path> <rel-path>
# Greps <abs-path> against the generic + local patterns; prints one
# "LEAK?  <rel-path>:<lineno>: <line>" per hit. Returns 0 if clean, 1 if any
# hit (caller must invoke this in an `if`/`||` context under set -e).
leak_scan_file() {
  local abs="$1" rel="$2" pat lineno content hit=0
  [[ -f "$abs" ]] || return 0

  local -a patterns=("${GENERIC_LEAK_PATTERNS[@]}")
  if [[ ${#LOCAL_LEAK_PATTERNS[@]} -gt 0 ]]; then
    patterns+=("${LOCAL_LEAK_PATTERNS[@]}")
  fi

  for pat in "${patterns[@]}"; do
    while IFS=: read -r lineno content; do
      [[ -z "$lineno" ]] && continue
      echo "LEAK?  $rel:$lineno: $content"
      hit=1
    done < <(grep -nE "$pat" "$abs" 2>/dev/null)
  done
  return $hit
}
