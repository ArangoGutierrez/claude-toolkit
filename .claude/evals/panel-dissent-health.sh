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

if [ "$rows" -eq 0 ]; then
  echo "EVAL $NAME: SKIP — no panelist votes recorded in $JSONL"
  exit 2
fi

# An output-format change would leave the flag column unparsed, and every
# count below would silently read 0 -> SKIP forever against a real log. The
# row count is derived independently (the n= column), so a mismatch means
# the eval has stopped grading anything.
if [ "$parsed" -ne "$rows" ]; then
  echo "$OUT"
  echo "EVAL $NAME: FAIL — parsed $parsed flag(s) from $rows panelist row(s); \`panel stats\` output format changed and this eval no longer grades it"
  exit 1
fi

scored=$(printf '%s\n' "$OUT" | grep -cE '(OK|UNHEALTHY)$' || true)
unhealthy=$(printf '%s\n' "$OUT" | grep -cE 'UNHEALTHY$' || true)

if [ "$scored" -eq 0 ]; then
  echo "EVAL $NAME: SKIP — no panelist has reached ${MIN_N} votes (${rows} panelist(s) below the threshold)"
  exit 2
fi

if [ "$unhealthy" -gt 0 ]; then
  echo "$OUT"
  echo "EVAL $NAME: FAIL — ${unhealthy} of ${scored} scored panelist(s) at exactly 0% or 100% dissent; the panel is not deliberating"
  exit 1
fi

echo "EVAL $NAME: PASS — all ${scored} scored panelist(s) dissent inside the band (min-n=${MIN_N})"
exit 0
