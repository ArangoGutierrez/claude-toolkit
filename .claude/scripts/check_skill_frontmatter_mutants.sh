#!/bin/bash
# check_skill_frontmatter_mutants.sh - every rule in check_skill_frontmatter.py
# must have a test that fails when the rule is switched off.
#
# Works on copies in a temp dir, never on the repo files. For each rule code it
# rewrites the condition lines tagged "# rule:<code>" to "if False and (...)",
# prints the diff to prove the mutant applied, runs that rule's tests
# (-k rule_<code>), and requires pytest to report failures (rc 1). Any other rc
# counts as a survivor: rc 0 means nothing failed, rc 5 means -k selected nothing.
# PYTHONDONTWRITEBYTECODE=1 keeps a cached .pyc from running the unmutated code.
set -uo pipefail
export PYTHONDONTWRITEBYTECODE=1

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="$SCRIPT_DIR/check_skill_frontmatter.py"
TEST="$SCRIPT_DIR/check_skill_frontmatter_test.py"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/csf-mutants.XXXXXX")" || { echo "FAIL: mktemp -d failed"; exit 1; }
case "$WORK" in
  /*) [ -d "$WORK" ] || { echo "FAIL: mktemp -d gave no directory"; exit 1; } ;;
   *) echo "FAIL: mktemp -d gave a non-absolute path: '$WORK'"; exit 1 ;;
esac
trap 'rm -rf "$WORK"' EXIT
cp "$TEST" "$WORK/check_skill_frontmatter_test.py"

RULES="E1 E2 E3 E4 E5 E6 E7 W1"
survived=0
for rule in $RULES; do
  python3 - "$SRC" "$WORK/check_skill_frontmatter.py" "$rule" <<'PY'
import sys
src, dst, rule = sys.argv[1], sys.argv[2], sys.argv[3]
lines = open(src).read().split("\n")
tag = "# rule:" + rule
hits = 0
for index, line in enumerate(lines):
    if line.rstrip().endswith(tag):
        code = line[: line.rindex(tag)].rstrip()
        body = code.lstrip()
        indent = code[: len(code) - len(body)]
        for keyword in ("if ", "elif "):
            if body.startswith(keyword) and body.endswith(":"):
                # Parenthesize the whole condition: "False and a or b" still runs b.
                condition = body[len(keyword):-1]
                lines[index] = "%s%sFalse and (%s):  %s" % (indent, keyword, condition, tag)
                hits += 1
                break
open(dst, "w").write("\n".join(lines))
sys.exit(0 if hits else 3)
PY
  if [ $? -ne 0 ]; then
    echo "MUTANT $rule: SURVIVED (no condition tagged '# rule:$rule')"
    survived=$((survived + 1))
    continue
  fi
  echo "--- mutant $rule"
  diff "$SRC" "$WORK/check_skill_frontmatter.py"
  key="rule_$(printf '%s' "$rule" | tr 'A-Z' 'a-z')"
  python3 -m pytest -q -p no:cacheprovider "$WORK/check_skill_frontmatter_test.py" -k "$key" > "$WORK/out.txt" 2>&1
  rc=$?
  if [ "$rc" -eq 1 ]; then
    echo "MUTANT $rule: killed ($(tail -1 "$WORK/out.txt"))"
  else
    echo "MUTANT $rule: SURVIVED (pytest rc=$rc)"
    tail -5 "$WORK/out.txt"
    survived=$((survived + 1))
  fi
done

if [ "$survived" -ne 0 ]; then
  echo "FAIL: $survived of 8 mutants survived"
  exit 1
fi
echo "PASS: all 8 mutants killed"
exit 0
