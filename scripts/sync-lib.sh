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
    # shellcheck disable=SC2053
    [[ "$rel" == $c ]] && return 0
  done
  return 1
}

# Generic, identity-agnostic leak patterns (ERE). Always active regardless of
# the local pattern file below — these are safe to ship in the public repo.
GENERIC_LEAK_PATTERNS=(
  '/Users/[A-Za-z0-9._-]+'
  '/home/[A-Za-z0-9._-]+'
  # Hub-form (double-namespace) model IDs are internal-catalog references and
  # must never ship publicly; single-namespace public catalog IDs are fine.
  'nvidia/nvidia/'
)

# Documented placeholder paths that legitimately appear in tracked docs and
# fixtures (e.g. skill examples using "/Users/foo/repo", test fixtures using
# "/home/user/project") — exempted from the generic patterns above so they
# don't flag forever. Boundary check avoids `\b` (unsupported in BSD grep/sed
# EREs) via an explicit non-path-char/end alternation, so a real path that
# merely starts with the same letters — "/Users/method", "/home/username2" —
# is NOT exempted by accident. Exemption is applied PER-MATCH (see
# leak_scan_file), never per-line: a line combining an exempt placeholder
# with a real path must still flag.
EXEMPT_PLACEHOLDER_ERE='/(Users/(foo|me|you)|home/user)(/|[^A-Za-z0-9._-]|$)'

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
#
# Generic-pattern hits get the placeholder exemption: strip the documented
# placeholder substrings from a COPY of the matched line, then re-test the
# stripped copy against the generic patterns; report only if it still
# matches. This is per-match, not per-line — a line with both an exempt
# placeholder and a real path still reports, because the real path survives
# the strip. Local-pattern hits (identity-specific, user-supplied) are never
# stripped or exempted.
leak_scan_file() {
  local abs="$1" rel="$2" pat lineno content stripped hit=0
  [[ -f "$abs" ]] || return 0

  for pat in "${GENERIC_LEAK_PATTERNS[@]}"; do
    while IFS=: read -r lineno content; do
      [[ -z "$lineno" ]] && continue
      stripped="$(printf '%s\n' "$content" | sed -E "s#${EXEMPT_PLACEHOLDER_ERE}#\\3#g")"
      if printf '%s\n' "$stripped" | grep -qE "$pat"; then
        echo "LEAK?  $rel:$lineno: $content"
        hit=1
      fi
    done < <(grep -nE "$pat" "$abs" 2>/dev/null)
  done

  if [[ ${#LOCAL_LEAK_PATTERNS[@]} -gt 0 ]]; then
    for pat in "${LOCAL_LEAK_PATTERNS[@]}"; do
      while IFS=: read -r lineno content; do
        [[ -z "$lineno" ]] && continue
        echo "LEAK?  $rel:$lineno: $content"
        hit=1
      done < <(grep -nE "$pat" "$abs" 2>/dev/null)
    done
  fi
  return $hit
}
