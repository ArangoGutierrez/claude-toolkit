#!/usr/bin/env bash
# panel-dissent-health.sh — per-panelist dissent-rate health.
#
# Why: a panelist that NEVER dissents is as broken as one that ALWAYS does.
# The first is a rubber stamp, the second is noise; either way the panel has
# stopped deliberating and its HOLD verdicts mean nothing. decisions.jsonl
# already records a per-panelist verdict on every decision, so this check
# needs no new instrumentation — it only reads.
#
# FAIL when any panelist with >= MIN_N votes sits at exactly 0% or 100%
# dissent. SKIP when no panelist has reached MIN_N, or the log is absent.
#
# Contract (.claude/evals/README.md):
#   exit 0 PASS / 1 FAIL / 2 SKIP
#   last stdout line: `EVAL panel-dissent-health: PASS|FAIL|SKIP — <detail>`
#
# --- Two design points worth keeping ---
#
# 1. The subject is resolved from THIS script's directory, never from $HOME.
#    A $HOME/.claude/... default grades the DEPLOYED copy, so a regression in
#    the repo stays hidden. scripts/run-evals.sh runs this file in CI, where
#    $HOME/.claude does not exist at all: pointed at $HOME it would SKIP
#    forever while looking healthy. Same shape as no-sonnet-routing.sh.
#    EVAL_SUBJECT overrides it for a fixture run.
#
# 2. Below MIN_N the verdict is SKIP, never PASS. A vacuous pass on a tiny
#    sample is exactly how a rubber-stamping panelist stays green, which is
#    the failure this metric exists to catch — the eval must not commit it.
#
# The decisions log itself legitimately lives under $HOME: it is real
# operator data, not a repo artifact. In CI it is simply absent -> SKIP.
set -uo pipefail

NAME="panel-dissent-health"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
SUBJECT="${EVAL_SUBJECT:-$REPO_DIR/.claude/skills/validate-recommendation}"
SUBJECT="${SUBJECT%/}"

JSONL="${PANEL_DECISIONS_JSONL:-$HOME/.claude/panel/decisions.jsonl}"
MIN_N="${PANEL_HEALTH_MIN_N:-20}"
PYBIN="${PANEL_HEALTH_PYTHON:-python3.12}"

# --- Environmental preconditions. Absent -> SKIP, never FAIL. ---

if [ ! -f "$JSONL" ]; then
  echo "EVAL $NAME: SKIP — decisions log not found ($JSONL)"
  exit 2
fi

if [ ! -d "$SUBJECT" ]; then
  echo "EVAL $NAME: SKIP — subject not found ($SUBJECT)"
  exit 2
fi

if ! command -v "$PYBIN" >/dev/null 2>&1; then
  echo "EVAL $NAME: SKIP — interpreter not found ($PYBIN)"
  exit 2
fi

# The package root that holds panel/ — derived from the SUBJECT so an
# EVAL_SUBJECT override carries its own imports with it, rather than
# silently falling back to the deployed tree.
PKG_ROOT="$(cd "$SUBJECT/../.." && pwd)"

OUT=$(cd "$SUBJECT" && PYTHONPATH="$PKG_ROOT" "$PYBIN" -m panel stats \
  --jsonl "$JSONL" --min-n "$MIN_N" 2>&1)
rc=$?

# Every environmental cause of a non-zero rc is ruled out above, so what is
# left is a broken metric. That is a FAIL, not a SKIP: a `panel stats` that
# raises on every real log would otherwise report "skipping" forever — the
# same vacuous-green failure this eval exists to prevent, one level up.
if [ $rc -ne 0 ]; then
  echo "$OUT"
  echo "EVAL $NAME: FAIL — panel stats exited rc=$rc; the health metric is broken"
  exit 1
fi

# --- Parse the flag column (last field of each panelist row). ---

rows=$(printf '%s\n' "$OUT" | grep -cE 'n=[0-9]+' || true)
parsed=$(printf '%s\n' "$OUT" | grep -cE '(OK|UNHEALTHY|SKIP)$' || true)

# Count the vote-carrying lines in the RAW log, independently of the reader.
# This is the whole point: if load_rows breaks, `panel stats` reports nothing
# and every count above reads 0, so the eval would SKIP — green — against a
# log full of rubber stamps. Deriving the expected row count straight from the
# file is the only way the eval can tell "nothing to grade" apart from "I have
# stopped grading". A trailing `{` is required so a decision recorded with an
# empty panelists array is not mistaken for a vote.
#
# -a, and `${x:-0}` at every use below: an empty capture would make `[` throw
# and fall through to SKIP, quietly restoring the fail-open this guard closes.
log_voters=$(grep -acE '"panelists"[[:space:]]*:[[:space:]]*\[[[:space:]]*\{' "$JSONL" || true)

if [ "${rows:-0}" -eq 0 ]; then
  if [ "${log_voters:-0}" -gt 0 ]; then
    echo "$OUT"
    echo "EVAL $NAME: FAIL — the reader returned no panelist rows, but $JSONL carries $log_voters line(s) of panelist votes; load_rows is broken (or every such line is malformed) and the metric is measuring nothing"
    exit 1
  fi
  echo "EVAL $NAME: SKIP — no panelist votes recorded in $JSONL"
  exit 2
fi

# An output-format change would leave the flag column unparsed, and every
# count below would silently read 0 -> SKIP forever against a real log. The
# row count is derived independently (the n= column), so a mismatch means
# the eval has stopped grading anything.
if [ "${parsed:-0}" -ne "${rows:-0}" ]; then
  echo "$OUT"
  echo "EVAL $NAME: FAIL — parsed $parsed flag(s) from $rows panelist row(s); \`panel stats\` output format changed and this eval no longer grades it"
  exit 1
fi

# --- The reader must account for every vote in the log, not merely for some. ---
#
# The guard above only compares the log against the reader when the reader
# returned NOTHING. A reader returning PART of the log leaves rows > 0, slips
# past it, and produces an affirmative PASS while a rubber stamp sits in the
# rows that were dropped — green on the exact condition this metric exists to
# catch. Truncate a 50-vote log to its first 25 rows and the unhealthy panelist
# disappears from the report entirely.
#
# The comparison has to be vote-for-vote. log_voters counts vote-carrying
# LINES, and one decision can carry three panelists: the operator's log holds
# 339 such lines but 357 votes, so comparing a vote total against log_voters
# would fail that log every run. So count vote OBJECTS.
#
# The oracle reads the file itself with stdlib json and never imports
# panel.stats, so a broken reader cannot cover for itself. It skips unparsable
# lines exactly as the contract says load_rows may, which keeps one truncated
# line - a real possibility with concurrent writers - from crying wolf; the
# all-lines-malformed case is caught by the empty-read guard above instead.
accounted=$(printf '%s\n' "$OUT" | awk 'match($0, /n=[0-9]+/) { s += substr($0, RSTART + 2, RLENGTH - 2) } END { print s + 0 }')

log_votes=$("$PYBIN" - "$JSONL" <<'PY' 2>/dev/null
import json, sys
n = 0
with open(sys.argv[1], encoding="utf-8", errors="replace") as fh:
    for line in fh:
        line = line.strip()
        if not line:
            continue
        try:
            row = json.loads(line)
        except Exception:
            continue
        if isinstance(row, dict):
            for p in row.get("panelists") or []:
                if isinstance(p, dict) and p.get("id"):
                    n += 1
print(n)
PY
)

# An oracle that cannot count leaves the accounting unverifiable. Unverifiable
# is not healthy: say so rather than passing on a number nobody checked.
case "${log_votes:-}" in
  ''|*[!0-9]*)
    echo "EVAL $NAME: FAIL — could not count votes in $JSONL independently of the reader, so the metric's coverage is unverifiable"
    exit 1 ;;
esac

if [ "${accounted:-0}" -ne "$log_votes" ]; then
  echo "$OUT"
  echo "EVAL $NAME: FAIL — the reader accounted for ${accounted} vote(s) but $JSONL carries ${log_votes}; load_rows is dropping data and the metric is grading a subset"
  exit 1
fi

scored=$(printf '%s\n' "$OUT" | grep -cE '(OK|UNHEALTHY)$' || true)
unhealthy=$(printf '%s\n' "$OUT" | grep -cE 'UNHEALTHY$' || true)

if [ "${scored:-0}" -eq 0 ]; then
  echo "EVAL $NAME: SKIP — no panelist has reached ${MIN_N} votes (${rows} panelist(s) below the threshold)"
  exit 2
fi

if [ "${unhealthy:-0}" -gt 0 ]; then
  echo "$OUT"
  echo "EVAL $NAME: FAIL — ${unhealthy} of ${scored} scored panelist(s) at exactly 0% or 100% dissent; the panel is not deliberating"
  exit 1
fi

echo "EVAL $NAME: PASS — all ${scored} scored panelist(s) dissent inside the band (min-n=${MIN_N})"
exit 0
