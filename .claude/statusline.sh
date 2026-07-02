#!/bin/bash
# Claude Code status line script
# Displays: model name, git branch (worktree-aware), worktree name, rate limits
# Fields per https://code.claude.com/docs/en/statusline
set -uo pipefail

input=$(cat)

MODEL=$(echo "$input" | jq -r '.model.display_name // "?"')

# git branch: prefer worktree.branch (--worktree sessions), fall back to live git
WORKTREE_BRANCH=$(echo "$input" | jq -r '.worktree.branch // empty')
if [ -n "$WORKTREE_BRANCH" ]; then
    BRANCH="$WORKTREE_BRANCH"
else
    BRANCH=$(git branch --show-current 2>/dev/null)
fi

# git worktree name (present only inside a linked worktree)
GIT_WORKTREE=$(echo "$input" | jq -r '.workspace.git_worktree // empty')

# Session goal (~/.claude/audit/session-goals/<id>.md)
GOAL="(no goal)"
GOAL_ORIGIN=""
SESSION_ID=$(echo "$input" | jq -r '.session_id // empty')
if [ -n "$SESSION_ID" ]; then
    GOAL_FILE="${HOME}/.claude/audit/session-goals/${SESSION_ID}.md"
    if [ -f "$GOAL_FILE" ]; then
        # Extract last stanza body once, then pull Goal: and Origin: from it.
        STANZA=$(awk '/^## /{buf=""} {buf=buf $0 "\n"} END{printf "%s", buf}' "$GOAL_FILE")
        RAW=$(echo "$STANZA" | grep -m1 '^Goal: ' | sed 's/^Goal: //; s/[[:space:]]*$//')
        GOAL_ORIGIN=$(echo "$STANZA" | grep -m1 '^Origin: ' | sed 's/^Origin: //; s/[[:space:]]*$//')
        if [ -n "$RAW" ]; then
            if [ "${#RAW}" -gt 40 ]; then RAW="${RAW:0:38}…"; fi
            GOAL="$RAW"
        fi
    fi
fi

# Project-anchor mismatch detection. Append " ⚠ wrong-repo" when both the
# goal-file Origin and the current cwd's git remote are known AND differ.
# Empty on either side → no check, no warning (preserves backward compat
# with pre-spec goal files and non-git cwds).

# Normalize a git origin URL to '<host>/<owner>/<repo>' identity.
# Must match goal.sh's normalize_origin() — kept in sync intentionally
# (deliberate duplication for v1; shared lib is a follow-up).
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

CUR_ORIGIN=$(normalize_origin "$(git config --get remote.origin.url 2>/dev/null || true)")
GOAL_WARN=""
if [ -n "$GOAL_ORIGIN" ] && [ -n "$CUR_ORIGIN" ] && [ "$GOAL_ORIGIN" != "$CUR_ORIGIN" ]; then
    GOAL_WARN=" ⚠ wrong-repo"
fi

# Context-window token consumption (post-v2.1.132 these are current-context tokens)
IN_TOKENS=$(echo "$input" | jq -r '.context_window.total_input_tokens // 0')
OUT_TOKENS=$(echo "$input" | jq -r '.context_window.total_output_tokens // 0')
TOTAL_TOKENS=$((IN_TOKENS + OUT_TOKENS))
PCT=$(echo "$input" | jq -r '.context_window.used_percentage // 0' | cut -d. -f1)
if [ "$TOTAL_TOKENS" -ge 1000 ]; then
    TOKENS=$(awk -v n="$TOTAL_TOKENS" 'BEGIN{ printf "%.1fk", n/1000 }')
else
    TOKENS="$TOTAL_TOKENS"
fi
# Color the context-usage segment by band: green <50, yellow [50,75),
# amber [75,90), red >=90. Themed ANSI + 256-color amber (Palette A).
pct_color() {
    local p="$1"
    if   [ "$p" -ge 90 ]; then printf '\033[31m'        # red
    elif [ "$p" -ge 75 ]; then printf '\033[38;5;208m'  # amber (256-color orange)
    elif [ "$p" -ge 50 ]; then printf '\033[33m'        # yellow
    else                       printf '\033[32m'        # green
    fi
}
PCT=${PCT:-0}
TOK_SEG="$(pct_color "$PCT")${TOKENS} tok (${PCT}%)"$'\033[0m'

# rate limits (Pro/Max only; absent otherwise)
FIVE_H=$(echo "$input" | jq -r '.rate_limits.five_hour.used_percentage // empty')
SEVEN_D=$(echo "$input" | jq -r '.rate_limits.seven_day.used_percentage // empty')

# Build output
PARTS="[$MODEL]"

[ -n "$BRANCH" ] && PARTS="$PARTS  $BRANCH"
[ -n "$GIT_WORKTREE" ] && PARTS="$PARTS (wt:$GIT_WORKTREE)"

PARTS="$PARTS | 🎯 ${GOAL}${GOAL_WARN}"
PARTS="$PARTS | $TOK_SEG"

LIMITS=""
[ -n "$FIVE_H" ] && LIMITS="5h:$(printf '%.0f' "$FIVE_H")%"
[ -n "$SEVEN_D" ] && LIMITS="${LIMITS:+$LIMITS }7d:$(printf '%.0f' "$SEVEN_D")%"
[ -n "$LIMITS" ] && PARTS="$PARTS | $LIMITS"

echo "$PARTS"
