#!/bin/bash
# skill-frontmatter_test.sh - drives skill-frontmatter.sh through fake trees.
#
# The eval resolves the checker and its scan roots from its own location, so
# each case copies the eval and the checker into $TMP/<case>/.claude/ and plants
# skills there. There is no env override, so the cases exercise the real path
# resolution. Every case asserts the exit code AND the exact verdict line; the
# em dash in the verdict is built at runtime, like in the eval.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EVAL_SRC="$SCRIPT_DIR/skill-frontmatter.sh"
CHECKER_SRC="$SCRIPT_DIR/../scripts/check_skill_frontmatter.py"
NAME="skill-frontmatter_test"
DASH="$(printf '\xe2\x80\x94')"
V="EVAL skill-frontmatter:"

for f in "$EVAL_SRC" "$CHECKER_SRC"; do
  [ -f "$f" ] || { echo "$NAME: FAIL $DASH missing input: $f"; exit 1; }
done
python3 -c 'import yaml' >/dev/null 2>&1 || { echo "$NAME: FAIL $DASH PyYAML missing; the cases need it"; exit 1; }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/skill-frontmatter-test.XXXXXX")" || { echo "$NAME: FAIL $DASH mktemp -d failed"; exit 1; }
case "$TMP" in
  /*) [ -d "$TMP" ] || { echo "$NAME: FAIL $DASH mktemp -d gave no directory"; exit 1; } ;;
   *) echo "$NAME: FAIL $DASH mktemp -d gave a non-absolute path: '$TMP'"; exit 1 ;;
esac
trap 'rm -rf "$TMP"' EXIT
# The eval prints paths it resolved with cd and pwd, which collapse the "//" that
# a TMPDIR ending in "/" (the macOS default outside the agent sandbox) leaves in
# the mktemp result. Resolve TMP the same way so expected and actual paths match.
TMP="$(cd "$TMP" && pwd)" || { echo "$NAME: FAIL $DASH cannot resolve the temp dir"; exit 1; }

fails=0
cases=0

# new_tree <case>: a fake repo holding copies of the eval and the checker.
new_tree() {
  local tree="$TMP/$1"
  mkdir -p "$tree/.claude/evals" "$tree/.claude/scripts"
  cp "$EVAL_SRC" "$tree/.claude/evals/skill-frontmatter.sh"
  cp "$CHECKER_SRC" "$tree/.claude/scripts/check_skill_frontmatter.py"
  printf '%s' "$tree"
}

# skill <tree> <root> <dir> <frontmatter line>...
skill() {
  local tree="$1" root="$2" dir="$3"
  shift 3
  mkdir -p "$tree/$root/$dir"
  { printf '%s\n' '---'; printf '%s\n' "$@"; printf '%s\n' '---' 'Body.'; } > "$tree/$root/$dir/SKILL.md"
}

# expect <case> <tree> <rc> <exact last line> [PATH prefix]
expect() {
  local name="$1" tree="$2" want_rc="$3" want_line="$4" prefix="${5:-}" out rc last
  cases=$((cases + 1))
  if [ -n "$prefix" ]; then
    out="$(PATH="$prefix:$PATH" bash "$tree/.claude/evals/skill-frontmatter.sh" 2>&1)"
  else
    out="$(bash "$tree/.claude/evals/skill-frontmatter.sh" 2>&1)"
  fi
  rc=$?
  last="$(printf '%s\n' "$out" | tail -1)"
  if [ "$rc" -ne "$want_rc" ] || [ "$last" != "$want_line" ]; then
    echo "  FAIL $name: want rc=$want_rc '$want_line'"
    echo "       got  rc=$rc '$last'"
    fails=$((fails + 1))
  else
    echo "  ok   $name"
  fi
}

t="$(new_tree clean)"
skill "$t" .claude/skills good-skill 'name: good-skill' 'description: Use when asked.'
expect clean "$t" 0 "$V PASS $DASH 0 errors, 0 warnings, 1 files checked"

t="$(new_tree tools-key)"
skill "$t" .claude/skills bad-skill 'name: bad-skill' 'description: Use when asked.' 'tools:' '  - Read'
expect tools-key "$t" 1 "$V FAIL $DASH 1 errors, 0 warnings, 1 files checked"

t="$(new_tree scheduled-hash)"
skill "$t" .claude/skills good-skill 'name: good-skill' 'description: Use when asked.'
skill "$t" .claude/scheduled-tasks watch 'name: watch' 'description: Watch the #ops thread. Use when asked.'
expect scheduled-hash "$t" 1 "$V FAIL $DASH 1 errors, 1 warnings, 2 files checked"

t="$(new_tree codex-root)"
skill "$t" codex/plugins/agent-workbench/skills cx 'name: cx' 'description: Use when asked.' 'when_to_use: later'
expect codex-root "$t" 1 "$V FAIL $DASH 1 errors, 0 warnings, 1 files checked"

t="$(new_tree fixtures-excluded)"
skill "$t" .claude/skills good-skill 'name: good-skill' 'description: Use when asked.'
skill "$t" .claude/skills/kickoff/scripts/fixtures/skills single 'name: single-skill'
expect fixtures-excluded "$t" 0 "$V PASS $DASH 0 errors, 0 warnings, 1 files checked"

t="$(new_tree no-roots)"
expect no-roots "$t" 1 "$V FAIL $DASH no skill roots under $t"

t="$(new_tree no-checker)"
skill "$t" .claude/skills good-skill 'name: good-skill' 'description: Use when asked.'
rm "$t/.claude/scripts/check_skill_frontmatter.py"
expect no-checker "$t" 1 "$V FAIL $DASH checker missing: $t/.claude/scripts/check_skill_frontmatter.py"

# PyYAML missing: a PATH shim makes `python3 -c 'import yaml'` fail, which
# fails the same way outside the agent sandbox as inside it.
t="$(new_tree no-pyyaml)"
skill "$t" .claude/skills good-skill 'name: good-skill' 'description: Use when asked.'
mkdir -p "$TMP/shim"
printf '%s\n' '#!/bin/sh' 'exit 1' > "$TMP/shim/python3"
chmod +x "$TMP/shim/python3"
expect no-pyyaml "$t" 2 "$V SKIP $DASH PyYAML is not installed for python3" "$TMP/shim"

if [ "$fails" -ne 0 ]; then
  echo "$NAME: FAIL $DASH $fails of $cases cases"
  exit 1
fi
echo "$NAME: PASS $DASH $cases cases"
exit 0
