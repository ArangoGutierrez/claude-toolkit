#!/bin/bash
# kickoff-timeout-contract.sh — cross-artifact contract eval:
# the kickoff SKILL.md must instruct a Bash-tool timeout (ms) that covers the
# engine's wall-clock ceiling (KICKOFF_TIMEOUT default + KICKOFF_DEADLINE_MARGIN
# default, seconds). Regression guarded: 2026-07-07 "engine stall" was the Bash
# tool's default 120s timeout killing a legitimate 300s+ engine run (2x).
# Contract: exit 0 PASS / 1 FAIL / 2 SKIP; last stdout line:
#   EVAL kickoff-timeout-contract: PASS|FAIL|SKIP — <detail>
set -o pipefail

NAME="kickoff-timeout-contract"
ENGINE="${EVAL_KICKOFF_ENGINE:-$HOME/.claude/tool/kickoff.py}"
SKILLMD="${EVAL_KICKOFF_SKILLMD:-$HOME/.claude/skills/kickoff/SKILL.md}"

[ -f "$ENGINE" ] || { echo "EVAL $NAME: SKIP — engine not found: $ENGINE"; exit 2; }
[ -f "$SKILLMD" ] || { echo "EVAL $NAME: SKIP — SKILL.md not found: $SKILLMD"; exit 2; }

T=$(grep -o 'KICKOFF_TIMEOUT", "[0-9]*"' "$ENGINE" | grep -o '[0-9]*' | head -1)
M=$(grep -o 'KICKOFF_DEADLINE_MARGIN", "[0-9]*"' "$ENGINE" | grep -o '[0-9]*' | head -1)
if [ -z "$T" ] || [ -z "$M" ]; then
  echo "EVAL $NAME: FAIL — cannot extract KICKOFF_TIMEOUT/MARGIN defaults from $ENGINE"
  exit 1
fi
CEILING_MS=$(( (T + M) * 1000 ))

# SKILL.md must carry an explicit ms timeout instruction: `timeout: <N>` or `timeout <N>`
DOC_MS=$(grep -oE 'timeout[: ]+[0-9]{6,}' "$SKILLMD" | grep -oE '[0-9]+' | sort -rn | head -1)
if [ -z "$DOC_MS" ]; then
  echo "EVAL $NAME: FAIL — SKILL.md has no explicit ms timeout instruction; Bash default (120s) kills legitimate ${T}s engine runs"
  exit 1
fi
if [ "$DOC_MS" -lt "$CEILING_MS" ]; then
  echo "EVAL $NAME: FAIL — SKILL.md instructs ${DOC_MS}ms < engine ceiling ${CEILING_MS}ms (${T}s+${M}s margin)"
  exit 1
fi
echo "EVAL $NAME: PASS — SKILL.md instructs ${DOC_MS}ms >= engine ceiling ${CEILING_MS}ms"
exit 0
