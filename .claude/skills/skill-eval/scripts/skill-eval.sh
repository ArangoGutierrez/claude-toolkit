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
exit "$rc"
