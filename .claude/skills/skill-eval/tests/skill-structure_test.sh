#!/usr/bin/env bash
# skill-structure_test.sh — required files present + SKILL.md frontmatter well-formed.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
for f in SKILL.md README.md scripts/skill-eval.sh scripts/probe.sh scripts/score.jq scripts/report.sh scripts/extract.jq; do
  [ -e "$root/$f" ] || { echo "FAIL missing $f"; exit 1; }
done
fm=$(awk '/^---[[:space:]]*$/{c++; if(c==2)exit} c>=1{print}' "$root/SKILL.md")
for k in "name:" "description:" "user-invocable:" "argument-hint:"; do
  grep -q "$k" <<<"$fm" || { echo "FAIL frontmatter missing $k"; exit 1; }
done
grep -q "name: skill-eval" <<<"$fm" || { echo "FAIL name not skill-eval"; exit 1; }
echo "PASS skill-structure_test"
