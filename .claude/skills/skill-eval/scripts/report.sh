#!/usr/bin/env bash
# report.sh <scores.json> — print scorecard.md to stdout; exit 1 if any FAIL/ERROR.
# Input is a JSON array of per-skill scores objects (score.jq output).
set -euo pipefail
scores="${1:?usage: report.sh <scores.json>}"
jq -r '
  "# skill-eval scorecard", "",
  "| skill | case | expect | rate | verdict |",
  "|---|---|---|---:|---|",
  ( .[] as $s | $s.cases[]
    | "| \($s.skill) | \(.id) | \(.expect) | "
      + (if .rate == null then "n/a" else "\(.rate*100|floor)%" end)
      + " | \(.verdict) |" ),
  "",
  "**Totals:** \([.[].summary.pass]|add // 0) pass, \([.[].summary.fail]|add // 0) fail, \([.[].summary.error]|add // 0) error"
' "$scores"
bad=$(jq '([.[].summary.fail]|add // 0) + ([.[].summary.error]|add // 0)' "$scores")
[ "$bad" -eq 0 ]
