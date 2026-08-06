#!/usr/bin/env bash
# skill-eval.sh [skill ...] — discover skills with evals.json, probe+score+report.
# Zero args → every skill under .claude/skills/*/evals.json. Exit code from report.sh.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
ROOT="${SKILL_EVAL_ROOT:-$(cd "$here/../.." && pwd)}"      # .claude/skills/
STAGE="${SKILL_EVAL_STAGE:-$(cd "$ROOT/../.." && pwd)}"    # repo root: .claude/ discoverable
N="${SKILL_EVAL_N:-5}"; PASS="${SKILL_EVAL_PASS:-0.6}"; DECOY="${SKILL_EVAL_DECOY:-0.2}"
outdir="${SKILL_EVAL_OUT:-$here/../.out}"; mkdir -p "$outdir"
targets=("$@")
if [ "${#targets[@]}" -eq 0 ]; then
  while IFS= read -r f; do targets+=("$(basename "$(dirname "$f")")"); done \
    < <(find "$ROOT" -maxdepth 2 -name evals.json | sort)
fi
scores='[]'
for skill in "${targets[@]}"; do
  evals="$ROOT/$skill/evals.json"
  [ -f "$evals" ] || { echo "skip $skill (no evals.json)" >&2; continue; }
  norm=$("$here/probe.sh" "$skill" "$evals" "$N" "$STAGE")
  sc=$(printf '%s' "$norm" | jq --argjson pass "$PASS" --argjson decoy "$DECOY" -f "$here/score.jq")
  scores=$(jq --argjson s "$sc" '. + [$s]' <<<"$scores")
done
printf '%s' "$scores" > "$outdir/scores.json"
# guard the gate: report.sh exits 1 on FAILs; set -e would abort before we print/cat
set +e; "$here/report.sh" "$outdir/scores.json" > "$outdir/scorecard.md"; rc=$?; set -e
cat "$outdir/scorecard.md"

# Persist to evidence/, which is where evals/scorecard-staleness.sh looks.
# Until 2026-08-06 the scorecard only ever reached the scratch .out/ dir, so
# running this tool could never satisfy the guard that demands a fresh one —
# the staleness eval had been red since 2026-07-26 with no way to clear it.
# Written even on rc=1: a run that found failures is still evidence of a run.
evidence="${SKILL_EVAL_EVIDENCE:-$ROOT/skill-eval/evidence}"
if mkdir -p "$evidence" 2>/dev/null; then
  card="$evidence/$(date +%F)-scorecard.md"
  if cp -f "$outdir/scorecard.md" "$card" 2>/dev/null; then
    echo "wrote $card" >&2
  else
    echo "WARN: could not write $card" >&2
  fi
else
  echo "WARN: could not create $evidence" >&2
fi
exit "$rc"
