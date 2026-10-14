#!/bin/bash
# check_skill_frontmatter_mutants.sh - every rule condition in
# check_skill_frontmatter.py must have a test that fails when that one
# condition is switched off.
#
# Works on copies in a temp dir, never on the repo files. Each line tagged
# "# rule:<code>" is its own mutant: the script rewrites that line alone to
# "if False and (...)" (or "elif ..."), prints the diff to prove the mutant
# applied, runs that rule's tests (-k rule_<code>), and requires pytest to
# report failures (rc 1). Any other rc counts as a survivor: rc 0 means nothing
# failed, rc 5 means -k selected nothing. One mutant per tagged line, not per
# rule, so a rule with one tested branch cannot hide an untested one.
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

# mutate.py SRC DST RULE N: write SRC to DST with the Nth line tagged
# "# rule:RULE" switched off, and print that line's number. Exit 4 when there
# is no Nth tagged line, 3 when it is not an if/elif condition.
cat > "$WORK/mutate.py" <<'PY'
import sys
src, dst, rule, nth = sys.argv[1], sys.argv[2], sys.argv[3], int(sys.argv[4])
lines = open(src).read().split("\n")
tag = "# rule:" + rule
tagged = [i for i, line in enumerate(lines) if line.rstrip().endswith(tag)]
if nth > len(tagged):
    sys.exit(4)
index = tagged[nth - 1]
print(index + 1)
code = lines[index][: lines[index].rindex(tag)].rstrip()
body = code.lstrip()
indent = code[: len(code) - len(body)]
for keyword in ("if ", "elif "):
    if body.startswith(keyword) and body.endswith(":"):
        # Parenthesize the whole condition: "False and a or b" still runs b.
        lines[index] = "%s%sFalse and (%s):  %s" % (indent, keyword, body[len(keyword):-1], tag)
        open(dst, "w").write("\n".join(lines))
        sys.exit(0)
sys.exit(3)
PY

RULES="E1 E2 E3 E4 E5 E6 E7 W1"
total=0
survived=0
for rule in $RULES; do
  n=1
  while :; do
    lineno="$(python3 "$WORK/mutate.py" "$SRC" "$WORK/check_skill_frontmatter.py" "$rule" "$n")"
    prc=$?
    if [ "$prc" -eq 4 ]; then
      if [ "$n" -eq 1 ]; then
        echo "MUTANT $rule: SURVIVED (no condition tagged '# rule:$rule')"
        total=$((total + 1))
        survived=$((survived + 1))
      fi
      break
    fi
    total=$((total + 1))
    label="$rule.$n (line $lineno)"
    n=$((n + 1))
    if [ "$prc" -ne 0 ]; then
      echo "MUTANT $label: SURVIVED (the tagged line is not an if/elif condition)"
      survived=$((survived + 1))
      continue
    fi
    echo "--- mutant $label"
    diff "$SRC" "$WORK/check_skill_frontmatter.py"
    key="rule_$(printf '%s' "$rule" | tr 'A-Z' 'a-z')"
    python3 -m pytest -q -p no:cacheprovider "$WORK/check_skill_frontmatter_test.py" -k "$key" > "$WORK/out.txt" 2>&1
    rc=$?
    if [ "$rc" -eq 1 ]; then
      echo "MUTANT $label: killed ($(tail -1 "$WORK/out.txt"))"
    else
      echo "MUTANT $label: SURVIVED (pytest rc=$rc)"
      tail -5 "$WORK/out.txt"
      survived=$((survived + 1))
    fi
  done
done

if [ "$survived" -ne 0 ]; then
  echo "FAIL: $survived of $total mutants survived"
  exit 1
fi
echo "PASS: all $total mutants killed"
exit 0
