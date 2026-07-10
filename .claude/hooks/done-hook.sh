#!/bin/bash
# done-hook.sh — Surface evidence against the captured session goal.
# Hook: Stop  (peer with context-watch.sh)
# Exit 0 always — coordinates with context-watch.sh, never blocks.
# Spec: docs/superpowers/specs/2026-05-18-done-hook-design.md §Component 3
set -o pipefail

# --- Helpers ---

# Extract the LAST stanza (## ...) body from the goal file.
extract_last_stanza() {
  local file="$1"
  awk '/^## /{buf=""} {buf=buf $0 "\n"} END{printf "%s", buf}' "$file"
}

# Extract the Goal: line (one-line summary).
extract_goal_name() {
  local stanza="$1"
  local raw
  raw=$(echo "$stanza" | grep -m1 '^Goal: ' | sed 's/^Goal: //; s/[[:space:]]*$//')
  [ -z "$raw" ] && raw="<unnamed>"
  if [ "${#raw}" -gt 60 ]; then
    raw="${raw:0:60}…"
  fi
  echo "$raw"
}

# Extract acceptance bullets (lines starting with "- " under "Acceptance:").
extract_bullets() {
  local stanza="$1"
  echo "$stanza" | awk '
    /^Acceptance:/ { in_acc=1; next }
    /^## / { in_acc=0 }
    in_acc && /^- / { sub(/^- /, ""); print }
  '
}

# Given a bullet and path to the cached bash log tail, return the matching line (or empty).
# Collects all anchors into a single `grep -F -e ...` invocation to keep subprocess
# count down per spec §15 perf budget.
match_bullet_evidence() {
  local bullet="$1" tail_file="$2"
  [ ! -f "$tail_file" ] && return 1
  # Anchors: paths, test-script names, command-like tokens.
  local grep_args=()
  local anchor
  while read -r anchor; do
    [ -z "$anchor" ] && continue
    # Skip noise words shorter than 3 chars (defensive backstop; the bare-generic regex alternative floors at 5)
    [ "${#anchor}" -lt 3 ] && continue
    grep_args+=(-e "$anchor")
  done < <(echo "$bullet" | grep -oE '(\.?\.?/[a-zA-Z0-9_/.-]+|[a-z][a-z0-9_-]{2,}_test\.sh|[a-z][a-z0-9_-]{2,}\.sh|docs/[a-zA-Z0-9_/.-]+|[a-z][a-z0-9_-]{4,})' | sort -u)
  [ "${#grep_args[@]}" -eq 0 ] && return 1
  # Two-tier match. Prefer a genuine command EXECUTION over a data-carrier line
  # (heredoc/ledger appends whose command text can quote a bullet's anchor and
  # shadow the real execution under `tail -1` — the observed false-DISAGREE bug).
  # Run the single multi-anchor grep once (perf budget, spec §15), then split its
  # output with one `grep -Ev` denylist pass rather than a per-anchor loop:
  #   Tier 1: last NON-data-carrier match wins (later re-runs still supersede).
  #   Tier 2: if no tier-1 match, fall back to the last match of any kind, so
  #           evidence never regresses below the prior single-grep behavior.
  # Denylist targets the write-append command forms seen in the audit log: heredoc
  # (`<<`, a heredoc in every logged command shape observed), `cat >>`, `tee -a`,
  # goal-tooling (`goal.sh`, already dropped upstream but kept defensively), and
  # echo/printf appends (EM-F, task 99507d70): `(cmd: |; ?)(echo|printf) [^|]*>>`
  # matches echo/printf as a command start either at `cmd: ` or right after a
  # `;` boundary (real compound-command shape, e.g. `W=...; printf '...' >>
  # $W/.../progress.md; ...`), not just at the very start of the logged
  # command -- a denylist anchored ONLY on `cmd: ` misses that live shape.
  # Validated against the live log (~/.claude/audit/bash-commands-2026-07-09.log,
  # sessions 265be882/75b1e5a9): matches all cited append lines, does not match
  # a non-append `printf ... > file` (single `>`) line from the same log.
  local matches line
  # Body-blindness (EP-F): truncate every candidate line at the FIRST `<<`,
  # keeping the `<<` marker but dropping the heredoc BODY, BEFORE anchor-matching.
  # bash-audit-log.sh folds a compound/heredoc call's real newlines to literal
  # `\n`, so a heredoc body lands inline on the same physical (marker-bearing)
  # line. Without this strip, an anchor present ONLY in that body would satisfy a
  # match and, as the sole match, be recorded as evidence via the tier-2 fallback
  # below — a false-POSITIVE the pre-fold hook never had (regression the fold
  # introduced). Stripping (not skipping the whole `<<` line) keeps a MIXED line's
  # command part evidence-visible, e.g. `bash widget_test.sh && cat > note.md
  # <<EOF…` still matches `widget_test.sh`; whole-line skipping would drop it and
  # regress below base. The retained `<<` marker keeps such lines demoted by the
  # tier-1 denylist, so a heredoc-carried write never shadows a genuine execution.
  # Both anchor-matching AND the recorded `raw` see only this stripped view.
  # Accepted edges (documented, not over-engineered): a `<<` inside a quoted
  # argument truncates there too (rare; conservative — only ever UNDER-counts,
  # never fabricates); echo/printf append PAYLOADS (no `<<` marker) stay demoted by
  # the denylist but can still surface via tier-2 as a sole match — a pre-existing,
  # non-fold-induced residual, see EP-F report (e).
  matches=$(sed 's/<<.*/<</' "$tail_file" 2>/dev/null | grep -F "${grep_args[@]}" 2>/dev/null)
  [ -z "$matches" ] && return 1
  line=$(printf '%s\n' "$matches" | grep -Ev '<<|cat >>|tee -a|goal\.sh|(cmd: |; ?)(echo|printf) [^|]*>>' | tail -1)
  [ -z "$line" ] && line=$(printf '%s\n' "$matches" | tail -1)
  printf '%s' "$line"
  return 0
}

# JSON-escape a string. Delegates to python3 for full RFC 7159 compliance
# (all control chars 0x00-0x1F, UTF-8 surrogates). A pure-bash version was
# tried for perf but only covered a subset of escapes — see Task 10 review.
# shellcheck disable=SC2016
json_escape() {
  python3 -c 'import json,sys; print(json.dumps(sys.stdin.read().rstrip("\n"))[1:-1])' <<< "$1"
}

INPUT=$(cat)
TRANSCRIPT=$(echo "$INPUT" | jq -r '.transcript_path // empty' 2>/dev/null)
[ -z "$TRANSCRIPT" ] && exit 0

UUID=$(basename "$TRANSCRIPT" .jsonl)
GOAL_FILE="${HOME}/.claude/audit/session-goals/${UUID}.md"
OUTCOMES_LOG="${HOME}/.claude/audit/session-outcomes-$(date -u +%Y-%m-%d).log"
mkdir -p "$(dirname "$OUTCOMES_LOG")"

# NO_GOAL path: emit ONCE per session, then silent.
if [ ! -f "$GOAL_FILE" ]; then
  if [ -f "$OUTCOMES_LOG" ] && grep -q "\"session\":\"${UUID}\".*\"verdict\":\"NO_GOAL\"" "$OUTCOMES_LOG"; then
    exit 0  # already emitted; debounce
  fi
  TS=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  printf '{"schema":1,"session":"%s","seq":1,"ts":"%s","goal_file":null,"heuristic":{"verdict":"NO_GOAL","matched":0,"total":0},"evidence":[],"state_hash":"","user":null}\n' \
    "$UUID" "$TS" >> "$OUTCOMES_LOG"
  exit 0
fi

# --- Main GOAL_PRESENT path ---
# (replaces the previous `exit 0` stub)

STANZA=$(extract_last_stanza "$GOAL_FILE")
GOAL_NAME=$(extract_goal_name "$STANZA")
BULLETS=$(extract_bullets "$STANZA")
TOTAL=$(echo "$BULLETS" | sed '/^$/d' | wc -l | tr -d ' ')

BASH_LOG="${HOME}/.claude/audit/bash-commands-$(date -u +%Y-%m-%d).log"
MATCHED=0
EVIDENCE_RECORDS="["
FIRST_REC=1

# Pre-compute the tail chunk once to a tempfile. Both the matching loop and the
# stderr loop reuse it via match_bullet_evidence (which runs one multi-pattern
# grep per bullet, not one per anchor).
#
# Evidence is scoped to THIS session only (no fallback to unscoped/other-session
# lines — bash-audit-log.sh tags every line `session:<uuid>`), and goal-tooling
# noise (goal.sh invocations, session-goals/ paths) is dropped so a bullet can
# never "match" the echo of its own goal text in a kickoff/goal command.
BASH_TAIL_FILE=$(mktemp)
trap 'rm -f "$BASH_TAIL_FILE"' EXIT
tail -c 200000 "$BASH_LOG" 2>/dev/null \
  | grep -F "session:${UUID} " \
  | grep -Ev 'goal\.sh|session-goals/' \
  > "$BASH_TAIL_FILE"

# Cache bullet→evidence in parallel arrays so the stderr loop below can reuse
# results without a second pass through match_bullet_evidence (halves grep spawns).
BULLET_LIST=()
EVIDENCE_LIST=()
while IFS= read -r bullet; do
  [ -z "$bullet" ] && continue
  evidence=$(match_bullet_evidence "$bullet" "$BASH_TAIL_FILE")
  BULLET_LIST+=("$bullet")
  EVIDENCE_LIST+=("$evidence")
  if [ -n "$evidence" ]; then
    MATCHED=$((MATCHED + 1))
    bullet_esc=$(json_escape "$bullet")
    evidence_esc=$(json_escape "$evidence")
    if [ "$FIRST_REC" -eq 1 ]; then
      FIRST_REC=0
    else
      EVIDENCE_RECORDS+=","
    fi
    EVIDENCE_RECORDS+="{\"bullet\":\"${bullet_esc}\",\"raw\":\"${evidence_esc}\"}"
  fi
done <<< "$BULLETS"
EVIDENCE_RECORDS+="]"

if [ "$TOTAL" -gt 0 ] && [ "$MATCHED" -gt 0 ] && [ "$MATCHED" -ge "$((TOTAL - 1))" ]; then
  HEURISTIC="LIKELY_MET"
elif [ "$MATCHED" -gt 0 ]; then
  HEURISTIC="PARTIAL"
else
  HEURISTIC="NO_EVIDENCE"
fi

# Compute next seq for this session
SEQ=1
if [ -f "$OUTCOMES_LOG" ]; then
  PREV_SEQ=$(grep "\"session\":\"$UUID\"" "$OUTCOMES_LOG" 2>/dev/null | \
             grep -oE '"seq":[0-9]+' | grep -oE '[0-9]+' | sort -n | tail -1)
  [ -n "$PREV_SEQ" ] && SEQ=$((PREV_SEQ + 1))
fi

# State-change-hash debounce: hash of (goal-mtime, sorted evidence raws).
GOAL_MTIME=$(stat -f %m "$GOAL_FILE" 2>/dev/null || stat -c %Y "$GOAL_FILE" 2>/dev/null || echo 0)
STATE_HASH=$(printf '%s|%s' "$GOAL_MTIME" "$EVIDENCE_RECORDS" | shasum | cut -c1-12)

# Compare to last entry's state_hash for this session
LAST_HASH=""
if [ -f "$OUTCOMES_LOG" ]; then
  LAST_HASH=$(grep "\"session\":\"$UUID\"" "$OUTCOMES_LOG" | tail -1 | \
              grep -oE '"state_hash":"[^"]*"' | sed 's/"state_hash":"\(.*\)"/\1/')
fi
if [ -n "$LAST_HASH" ] && [ "$STATE_HASH" = "$LAST_HASH" ]; then
  exit 0  # no state change since last entry
fi

TS=$(date -u +%Y-%m-%dT%H:%M:%SZ)
GOAL_REL_PATH="session-goals/${UUID}.md"
printf '{"schema":1,"session":"%s","seq":%d,"ts":"%s","goal_file":"%s","heuristic":{"verdict":"%s","matched":%d,"total":%d},"evidence":%s,"state_hash":"%s","user":null}\n' \
  "$UUID" "$SEQ" "$TS" "$GOAL_REL_PATH" "$HEURISTIC" "$MATCHED" "$TOTAL" "$EVIDENCE_RECORDS" "$STATE_HASH" \
  >> "$OUTCOMES_LOG"

# Stderr evidence block (informational; never claims completion).
# Reuses the BULLET_LIST/EVIDENCE_LIST cache populated above — no re-grep.
echo "" >&2
echo "[done-hook] Session ${UUID:0:8} vs goal '${GOAL_NAME}':" >&2
echo "  Acceptance bullets: ${MATCHED}/${TOTAL} matched" >&2
for i in "${!BULLET_LIST[@]}"; do
  bullet="${BULLET_LIST[$i]}"
  ev="${EVIDENCE_LIST[$i]}"
  if [ -n "$ev" ]; then
    short_ev="${ev:0:80}"
    echo "    [✓] ${bullet:0:50}: ${short_ev}" >&2
  else
    echo "    [ ] ${bullet:0:50}: no matching evidence" >&2
  fi
done
echo "  Heuristic: ${HEURISTIC} (${MATCHED}/${TOTAL}). Run /done to confirm or amend." >&2

exit 0
