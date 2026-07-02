#!/bin/bash
# goal.sh — write or amend the session-goal file.
# Backs the /goal skill; resolves the session UUID and writes the goal stanza.
set -o pipefail

INPUT="${1:-}"

# Resolve session UUID — prefer $CLAUDE_SESSION_ID, fall back to ~/.claude/sessions/$$.json
UUID="${CLAUDE_SESSION_ID:-}"
if [ -z "$UUID" ] || [ "$UUID" = "unknown" ]; then
  if [ -f "$HOME/.claude/sessions/$$.json" ]; then
    UUID=$(jq -r '.sessionId // empty' "$HOME/.claude/sessions/$$.json" 2>/dev/null)
  fi
fi
if [ -z "$UUID" ]; then
  # last-resort: newest session file
  # shellcheck disable=SC2012  # paths are internal/controlled; ls preserves plan pattern
  SESS_FILE=$(ls -t "$HOME/.claude/sessions/"*.json 2>/dev/null | head -1)
  [ -n "$SESS_FILE" ] && UUID=$(jq -r '.sessionId // empty' "$SESS_FILE" 2>/dev/null)
fi
if [ -z "$UUID" ]; then
  echo "[goal] ERROR: could not resolve session UUID" >&2
  exit 1
fi

GOAL_DIR="$HOME/.claude/audit/session-goals"
mkdir -p "$GOAL_DIR"
GOAL_FILE="$GOAL_DIR/$UUID.md"
TS=$(date -u +%Y-%m-%dT%H:%M:%SZ)

# Determine stanza type by file presence (NOT by 'amend' keyword)
if [ -f "$GOAL_FILE" ]; then
  HEADER="## Amendment $TS"
else
  HEADER="## Initial $TS"
fi

# Strip leading "amend " keyword if present (user signal, not behavior change)
INPUT="${INPUT#amend }"

# Project anchor: git remote.origin.url of the cwd at write time.
# Empty when cwd is not a git repo OR the repo has no 'origin' remote.
# Recorded in the stanza so the statusline can warn on cwd-vs-goal mismatch.

# Normalize a git origin URL to '<host>/<owner>/<repo>' identity.
# Strips protocol, user@, colon delimiter of SSH URLs, and .git suffix.
# Empty input → empty output. Examples (all → 'github.com/foo/bar'):
#   git@github.com:foo/bar.git, https://github.com/foo/bar.git,
#   https://user:pass@github.com/foo/bar
normalize_origin() {
  local url="$1"
  [ -z "$url" ] && return
  url="${url#https://}"
  url="${url#http://}"
  url="${url#git://}"
  url="${url#*@}"
  url="${url/://}"
  url="${url%.git}"
  url="${url%/}"
  echo "$url"
}

ORIGIN=$(normalize_origin "$(git config --get remote.origin.url 2>/dev/null || true)")

# Format check — warn but write
if ! echo "$INPUT" | grep -q '^Goal: '; then
  echo "[goal] WARNING: input missing 'Goal: ' line" >&2
fi
if ! echo "$INPUT" | grep -q '^Acceptance:'; then
  echo "[goal] WARNING: input missing 'Acceptance:' section" >&2
fi

# Check existence BEFORE the append-group to avoid SC2094 (read+write in same pipeline).
PREPEND_NL=0
[ -f "$GOAL_FILE" ] && PREPEND_NL=1
{
  [ "$PREPEND_NL" -eq 1 ] && echo ""
  echo "$HEADER"
  # Inject 'Origin: <url>' immediately after the 'Goal:' line if origin known.
  # $INPUT format is: "Goal: ...\nAcceptance:\n- ..."  →  split at first newline.
  if [ -n "$ORIGIN" ]; then
    GOAL_LINE="${INPUT%%$'\n'*}"
    REST="${INPUT#*$'\n'}"
    if [ "$GOAL_LINE" = "$INPUT" ]; then
      # No newline in $INPUT — single-line goal body.
      echo "$INPUT"
      echo "Origin: $ORIGIN"
    else
      echo "$GOAL_LINE"
      echo "Origin: $ORIGIN"
      echo "$REST"
    fi
  else
    echo "$INPUT"
  fi
} >> "$GOAL_FILE"

echo "[goal] wrote $HEADER to $GOAL_FILE" >&2
