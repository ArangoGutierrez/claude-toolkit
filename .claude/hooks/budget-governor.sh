#!/bin/bash
# budget-governor.sh — advisory token-spend surfacing on Stop (per session +
# per dispatch). A `Stop` hook that ALWAYS exits 0; it only writes an advisory
# line to stderr when spend crosses a budget threshold.
#
# GOAL-FILE CONTRACT (this is the only external dependency; it degrades
# SILENTLY when unmet, so the hook is safe to wire even if nothing writes goal
# files yet):
#   - Reads a per-session goal file at
#       $HOME/.claude/audit/session-goals/<session_id>.md
#   - Within that file it takes the LAST line matching
#       Budget: <N|N.Nk|N.Nm>
#     (e.g. `Budget: 200k`, `Budget: 1.5m`, `Budget: 40000`) as the session's
#     OUTPUT-token budget. Later `Budget:` lines override earlier ones, so the
#     budget survives goal amendments that don't restate it.
#   - No goal file, or a goal file with no `Budget:` line -> the hook stays
#     SILENT and exits 0 (nothing to govern).
# On Stop it sums output tokens across the session transcript and any subagent
# transcripts, then emits a one-time advisory as spend crosses 80% / 100% of
# the budget (bucketed so it fires once per threshold, not every Stop).
#
# Env overrides:
#   BUDGET_GOVERNOR_GOAL_DIR   goal-file dir   (default $HOME/.claude/audit/session-goals)
#   BUDGET_GOVERNOR_STATE_DIR  bucket state    (default $HOME/.claude/audit/budget)
#   BUDGET_GOVERNOR_VERBOSE=1  always emit a spend line (even under budget, or
#                              with no budget at all)
set -o pipefail

INPUT=$(cat)
TRANSCRIPT=$(echo "$INPUT" | jq -r '.transcript_path // empty' 2>/dev/null)
SESSION=$(echo "$INPUT" | jq -r '.session_id // empty' 2>/dev/null)
[ -z "$TRANSCRIPT" ] && exit 0
[ ! -f "$TRANSCRIPT" ] && exit 0
[ -z "$SESSION" ] && exit 0

GOAL_DIR="${BUDGET_GOVERNOR_GOAL_DIR:-$HOME/.claude/audit/session-goals}"
STATE_DIR="${BUDGET_GOVERNOR_STATE_DIR:-$HOME/.claude/audit/budget}"
VERBOSE="${BUDGET_GOVERNOR_VERBOSE:-0}"
GOAL_FILE="$GOAL_DIR/$SESSION.md"

# --- Budget from goal file: the LAST `Budget: <N|N.Nk|N.Nm>` line anywhere in
# the file wins — later declarations override, and the budget survives
# amendments that don't restate it (goal.sh appends budget-less stanzas).
BUDGET=0
if [ -f "$GOAL_FILE" ]; then
  RAW=$(grep '^Budget: ' "$GOAL_FILE" 2>/dev/null | tail -1 | sed 's/^Budget: //; s/[[:space:]]*$//')
  if [ -n "$RAW" ]; then
    BUDGET=$(printf '%s' "$RAW" | awk '
      /^[0-9]+([.][0-9]+)?[kK]$/ { printf "%.0f", $0 * 1000; exit }
      /^[0-9]+([.][0-9]+)?[mM]$/ { printf "%.0f", $0 * 1000000; exit }
      /^[0-9]+$/                 { printf "%d",   $0;          exit }')
    [ -z "$BUDGET" ] && BUDGET=0
  fi
fi
# No budget and not verbose: nothing to do.
[ "$BUDGET" -eq 0 ] && [ "$VERBOSE" != "1" ] && exit 0

# --- Spend summing: dedup by message id (last occurrence wins) ---
JQ_SUM='split("\n") | map(select(length > 0) | fromjson? // empty)
  | map(select(.message.usage? != null) | {k: (.message.id // "?"), u: .message.usage})
  | group_by(.k) | map(.[-1].u)
  | [([.[].output_tokens // 0] | add // 0),
     ([.[].input_tokens // 0] | add // 0),
     ([.[].cache_creation_input_tokens // 0] | add // 0),
     ([.[].cache_read_input_tokens // 0] | add // 0)] | @tsv'
sum_file() { jq -Rs -r "$JQ_SUM" "$1" 2>/dev/null || printf '0\t0\t0\t0'; }

read -r OUT INP CW CR <<< "$(sum_file "$TRANSCRIPT" | tr '\t' ' ')"
: "${OUT:=0}" "${INP:=0}" "${CW:=0}" "${CR:=0}"

# --- Per-dispatch attribution ---
BASE=$(basename "$TRANSCRIPT" .jsonl)
SUB_DIR="$(dirname "$TRANSCRIPT")/$BASE/subagents"
N_DISP=0
TOP=""
if [ -d "$SUB_DIR" ]; then
  ROWS=""
  for f in "$SUB_DIR"/agent-*.jsonl; do
    [ -f "$f" ] || continue
    N_DISP=$((N_DISP + 1))
    read -r SO SI SW SR <<< "$(sum_file "$f" | tr '\t' ' ')"
    : "${SO:=0}" "${SI:=0}" "${SW:=0}" "${SR:=0}"
    OUT=$((OUT + SO)); INP=$((INP + SI)); CW=$((CW + SW)); CR=$((CR + SR))
    META="${f%.jsonl}.meta.json"
    LABEL="agent"
    [ -f "$META" ] && LABEL=$(jq -r '.description // .agentType // "agent"' "$META" 2>/dev/null | head -c 40)
    ROWS="$ROWS$SO $LABEL\n"
  done
  TOP=$(printf '%b' "$ROWS" | sort -rn | head -3 | awk '{ $1=$1; lbl=""; for(i=2;i<=NF;i++) lbl=lbl (i>2?" ":"") $i; printf "%s%s %s", (NR>1?", ":""), lbl, $1 }')
fi

DISP_PART=""
[ "$N_DISP" -gt 0 ] && DISP_PART=" | dispatches: $N_DISP (top: $TOP)"

# --- Threshold buckets + state ---
emit() { echo "$1" >&2; }
LINE_TAIL="| in=$INP cache_w=$CW cache_r=$CR$DISP_PART"

if [ "$BUDGET" -gt 0 ]; then
  PCT=$((OUT * 100 / BUDGET))
  if   [ "$PCT" -ge 100 ]; then BUCKET=$((100 + (PCT - 100) / 25 * 25))
  elif [ "$PCT" -ge 80 ];  then BUCKET=80
  else                          BUCKET=0
  fi
  LAST=0
  STATE_FILE="$STATE_DIR/$SESSION.state"
  [ -f "$STATE_FILE" ] && LAST=$(cat "$STATE_FILE" 2>/dev/null | tr -cd '0-9')
  : "${LAST:=0}"
  if [ "$BUCKET" -gt "$LAST" ] 2>/dev/null; then
    mkdir -p "$STATE_DIR" 2>/dev/null && echo "$BUCKET" > "$STATE_FILE" 2>/dev/null
    if [ "$BUCKET" -ge 100 ]; then
      emit "BUDGET GOVERNOR: OVER BUDGET — out=$OUT of $BUDGET tokens ($PCT%) $LINE_TAIL"
    else
      emit "BUDGET GOVERNOR: approaching budget — out=$OUT of $BUDGET tokens ($PCT%) $LINE_TAIL"
    fi
  elif [ "$VERBOSE" = "1" ]; then
    emit "BUDGET GOVERNOR: out=$OUT of $BUDGET tokens ($PCT%) $LINE_TAIL"
  fi
else
  # VERBOSE without budget: spend line, no percentage.
  emit "BUDGET GOVERNOR: out=$OUT $LINE_TAIL"
fi

exit 0
