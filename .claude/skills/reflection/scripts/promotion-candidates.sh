#!/bin/bash
# promotion-candidates.sh — list anti-patterns eligible for promotion.
# Usage: promotion-candidates.sh [FILE...]  (default: ~/.claude + repo learned-anti-patterns.md)
# Output: one line per entry with Count>=PROMOTION_THRESHOLD not marked Promoted:
#   <file>\t[behavioral?|mechanical?]\tcount=N\t<pattern text>
# Read-only. Exit 0 always.
set -uo pipefail

THRESHOLD="${PROMOTION_THRESHOLD:-3}"

if [ "$#" -eq 0 ]; then
  REPO_RULES="$(cd "$(dirname "$0")/../../.." 2>/dev/null && pwd)/rules/learned-anti-patterns.md"
  set -- "$HOME/.claude/rules/learned-anti-patterns.md" "$REPO_RULES"
fi

found=0
for f in "$@"; do
  [ -f "$f" ] || continue
  while IFS= read -r line; do
    case "$line" in *'**Count**'*) : ;; *) continue ;; esac
    case "$line" in *'**Promoted**'*) continue ;; esac
    count=$(printf '%s\n' "$line" | sed -n 's/.*\*\*Count\*\*:[[:space:]]*\([0-9][0-9]*\).*/\1/p')
    [ -n "$count" ] || continue
    if [ "$count" -ge "$THRESHOLD" ]; then
      pattern=$(printf '%s\n' "$line" | sed -n 's/.*\*\*Pattern\*\*:[[:space:]]*\([^|]*\).*/\1/p' | sed 's/[[:space:]]*$//')
      hint="behavioral?"
      case "$pattern" in *regex*|*test*|*Test*|*format*|*lint*|*AST*|*ordering*|*index*) hint="mechanical?" ;; esac
      printf '%s\t[%s]\tcount=%s\t%s\n' "$f" "$hint" "$count" "$pattern"
      found=$((found+1))
    fi
  done < "$f"
done

[ "$found" -eq 0 ] && echo "(no promotion candidates with Count>=$THRESHOLD)" >&2
exit 0
