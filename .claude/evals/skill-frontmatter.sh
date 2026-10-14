#!/bin/bash
# skill-frontmatter.sh - every SKILL.md in this checkout passes
# check_skill_frontmatter.py: valid YAML, no value cut at ' #', no unknown keys
# such as tools or when_to_use, name and description within the spec's limits.
#
# Guards the regression where a skill ships frontmatter that a harness following
# the agentskills.io spec cannot read, or reads without the guidance the model
# needs to select it.
#
# The checker and the scan roots resolve from this file's own location, so the
# eval checks this checkout, never the deployed copy. The same file serves both
# config repos: a root this repo lacks, or one holding no SKILL.md outside test
# fixtures, is skipped. Fixtures are excluded from the scan.
#
# Contract: exit 0 PASS / 1 FAIL / 2 SKIP; the last stdout line is the verdict,
# "EVAL skill-frontmatter: PASS|FAIL|SKIP", an em dash, then the detail.
set -uo pipefail

NAME="skill-frontmatter"
DASH="$(printf '\xe2\x80\x94')"  # built at runtime; a literal one trips ai-tell-guard
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
CHECKER="$REPO_DIR/.claude/scripts/check_skill_frontmatter.py"

if ! python3 -c 'import yaml' >/dev/null 2>&1; then
  echo "EVAL $NAME: SKIP $DASH PyYAML is not installed for python3"
  exit 2
fi
if [ ! -f "$CHECKER" ]; then
  echo "EVAL $NAME: FAIL $DASH checker missing: $CHECKER"
  exit 1
fi

roots=()
for root in .claude/skills .claude/scheduled-tasks codex/plugins/agent-workbench/skills; do
  dir="$REPO_DIR/$root"
  if [ -d "$dir" ] && [ -n "$(find "$dir" -name SKILL.md -not -path '*/fixtures/*' -print 2>/dev/null | head -1)" ]; then
    roots+=("$dir")
  fi
done
if [ "${#roots[@]}" -eq 0 ]; then
  echo "EVAL $NAME: FAIL $DASH no skill roots under $REPO_DIR"
  exit 1
fi

out="$(python3 "$CHECKER" --exclude '*/fixtures/*' "${roots[@]}" 2>&1)"
rc=$?
summary="$(printf '%s\n' "$out" | tail -1)"
case "$rc" in
  0)
    echo "EVAL $NAME: PASS $DASH $summary"
    exit 0
    ;;
  1)
    printf '%s\n' "$out" | grep -E ': E[0-9] '
    echo "EVAL $NAME: FAIL $DASH $summary"
    exit 1
    ;;
  *)
    printf '%s\n' "$out"
    echo "EVAL $NAME: FAIL $DASH checker exited rc=$rc"
    exit 1
    ;;
esac
