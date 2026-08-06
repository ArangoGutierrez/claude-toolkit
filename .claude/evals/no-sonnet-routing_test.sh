#!/bin/bash
# no-sonnet-routing_test.sh — discrimination test for no-sonnet-routing.sh.
# The runner excludes *_test.sh, so this harness never runs as a real eval.
#
# A guard that stays green when its regression returns is theater
# (rules/constitution.md). This harness therefore feeds the eval a fixture that
# CONTAINS the regression and demands a red verdict, in every form the eval
# claims to catch: the 3 quote characters (single, double, backtick), a
# capitalised alias, and a .mjs file beside the .js ones.
#
# It asserts the EXACT verdict line, never a prefix. A return code alone does
# not discriminate: the SKIP path and the vacuous-scan path also exit 2 and 1,
# and an eval with the wrong name or an ASCII hyphen instead of the contract's
# em dash still returns the right codes.
#
# The clean fixture is a copy of the REAL workflows, which carry a routing
# comment naming Sonnet on purpose. That case is the false-alarm guard: a
# word-level grep turns those comments red. The harness asserts that precondition
# before it trusts the case.
set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EVAL_SRC="$SCRIPT_DIR/no-sonnet-routing.sh"
WORKFLOWS_SRC="$SCRIPT_DIR/../workflows"
NAME="no-sonnet-routing_test"

[ -f "$EVAL_SRC" ] || { echo "$NAME: FAIL — missing input: $EVAL_SRC"; exit 1; }
[ -d "$WORKFLOWS_SRC" ] || { echo "$NAME: FAIL — missing input: $WORKFLOWS_SRC"; exit 1; }

# An unchecked mktemp "${TMPDIR:-/tmp}/eval.XXXXXX" leaves TMP empty, targets fixtures at /, and turns every
# case into a misleading rc mismatch instead of an explicit abort.
TMP="$(mktemp -d "${TMPDIR:-/tmp}/eval.XXXXXX")" || { echo "$NAME: FAIL — mktemp -d "${TMPDIR:-/tmp}/eval.XXXXXX" failed"; exit 1; }
case "$TMP" in
  /*) [ -d "$TMP" ] || { echo "$NAME: FAIL — mktemp -d "${TMPDIR:-/tmp}/eval.XXXXXX" gave no directory"; exit 1; } ;;
   *) echo "$NAME: FAIL — mktemp -d "${TMPDIR:-/tmp}/eval.XXXXXX" gave a non-absolute path: '$TMP'"; exit 1 ;;
esac
# Explicit path only — never a glob. A glob that matches nothing aborts the whole
# rm and leaks the directory.
trap 'rm -rf "$TMP"' EXIT

fails=0
cases=0

# The one FAIL line every mutation case expects, parameterised by file name. The
# line number is always 2 because plant_mutant writes the regression there.
fail_line() { echo "EVAL no-sonnet-routing: FAIL — quoted sonnet literal in $1 line 2; the bare alias is rate-limited to 0 rpm, so pin opus or haiku"; }

# $1 case name, $2 expected rc, $3 the EXACT expected last stdout line,
# $4 the path handed to the eval through EVAL_SUBJECT.
run_case() {
  local name="$1" want_rc="$2" want_line="$3" subject="$4" out rc last
  cases=$((cases + 1))
  out="$(EVAL_SUBJECT="$subject" bash "$EVAL_SRC" 2>&1)"
  rc=$?
  last="$(printf '%s\n' "$out" | tail -1)"
  if [ "$rc" -ne "$want_rc" ]; then
    echo "  FAIL $name — want rc=$want_rc, got rc=$rc | $last"
    fails=$((fails + 1))
    return
  fi
  if [ "$last" != "$want_line" ]; then
    echo "  FAIL $name — rc ok but the verdict line is not exact"
    echo "         want: $want_line"
    echo "         got:  $last"
    fails=$((fails + 1))
    return
  fi
  echo "  ok   $name (rc=$rc)"
}

# Builds a fixture directory: a copy of the real workflows plus one planted file
# whose SECOND line carries the regression. $1 dir, $2 file name, $3 the line.
# Proves the copy and the write landed before the case is trusted.
plant_fixture() {
  local dir="$1" file="$2" line="$3" n
  mkdir -p "$dir"
  cp "$WORKFLOWS_SRC"/*.js "$dir/" || { echo "$NAME: FAIL — could not copy the real workflows into $dir"; exit 1; }
  printf '%s\n%s\n' '// fixture: the routing regression this eval guards' "$line" > "$dir/$file"
  n="$(grep -cF -- "$line" "$dir/$file")"
  [ "${n:-0}" -eq 1 ] || { echo "$NAME: FAIL — mutant fixture did not take: $dir/$file"; exit 1; }
}

# ------------------------------------------------------- case 1: clean copy ---
CLEAN="$TMP/clean"
mkdir -p "$CLEAN"
cp "$WORKFLOWS_SRC"/*.js "$CLEAN/" || { echo "$NAME: FAIL — could not copy the real workflows"; exit 1; }

# Verify the after-state of the copy; cp can return 0 and do nothing useful. The
# count comes from a glob, not from the eval's find loop: a count re-derived the
# way the subject derives it asserts nothing.
shopt -s nullglob
clean_js=( "$CLEAN"/*.js )
shopt -u nullglob
n_clean=${#clean_js[@]}
[ "$n_clean" -ge 1 ] || { echo "$NAME: FAIL — the clean fixture holds no .js file"; exit 1; }

# Precondition for the false-alarm property: without a bare 'sonnet' word in the
# copied files, case 1 proves nothing about comment tolerance.
n_word="$(grep -ril 'sonnet' "$CLEAN" | grep -c .)"
[ "${n_word:-0}" -ge 1 ] || {
  echo "$NAME: FAIL — the clean fixture holds no bare 'sonnet' word, so case 1 cannot test the false-alarm property"
  exit 1
}

run_case "clean copy of the real workflows -> PASS" 0 \
  "EVAL no-sonnet-routing: PASS — scanned $n_clean .js/.mjs files; no quoted sonnet literal" \
  "$CLEAN"

# ------------------------------------- cases 2-6: one per bypass form caught ---
# Each fixture holds the real workflows plus one planted regression. The eval
# must name the planted file and its line, and nothing else.
MUT_SQ="$TMP/mut-single"
plant_fixture "$MUT_SQ" "mutant.js" "const opts = { model: t.model || 'sonnet' }"
run_case "single-quoted alias -> FAIL" 1 "$(fail_line mutant.js)" "$MUT_SQ"

MUT_DQ="$TMP/mut-double"
plant_fixture "$MUT_DQ" "mutant.js" 'const opts = { model: t.model || "sonnet" }'
run_case "double-quoted alias -> FAIL" 1 "$(fail_line mutant.js)" "$MUT_DQ"

MUT_BT="$TMP/mut-backtick"
# shellcheck disable=SC2016  # the single quotes are the point: the backticks
# must reach the fixture literally, not open a command substitution.
plant_fixture "$MUT_BT" "mutant.js" 'const opts = { model: `sonnet` }'
run_case "backtick alias -> FAIL" 1 "$(fail_line mutant.js)" "$MUT_BT"

MUT_CAP="$TMP/mut-capital"
plant_fixture "$MUT_CAP" "mutant.js" "const opts = { model: 'Sonnet' }"
run_case "capitalised alias -> FAIL" 1 "$(fail_line mutant.js)" "$MUT_CAP"

MUT_MJS="$TMP/mut-mjs"
plant_fixture "$MUT_MJS" "mutant.mjs" "const opts = { model: 'sonnet' }"
run_case "alias inside a .mjs file -> FAIL" 1 "$(fail_line mutant.mjs)" "$MUT_MJS"

# --------------------------------------------------- case 7: missing subject ---
MISSING="$TMP/does-not-exist"
run_case "missing directory -> SKIP" 2 \
  "EVAL no-sonnet-routing: SKIP — subject not found ($MISSING)" \
  "$MISSING"

# ----------------------------------------------------- case 8: vacuous scan ---
# A subject with no script file must not report PASS: the guard would then be
# green forever after the workflows move or change extension.
EMPTY="$TMP/empty"
mkdir -p "$EMPTY"
run_case "subject with no .js or .mjs file -> FAIL" 1 \
  "EVAL no-sonnet-routing: FAIL — no .js or .mjs file under $EMPTY; the scan would pass vacuously" \
  "$EMPTY"

# ------------------------------- case 9: the default subject, no env override ---
# The eval must resolve its default subject from its OWN directory. A
# $HOME/.claude/... default grades the deployed copy, so a repo regression stays
# green. The fake tree plants the regression next to a copy of the eval and runs
# it with EVAL_SUBJECT unset: only script-relative resolution turns this red.
TREE="$TMP/tree"
mkdir -p "$TREE/.claude/evals" "$TREE/.claude/workflows"
cp "$EVAL_SRC" "$TREE/.claude/evals/no-sonnet-routing.sh"
cmp -s "$EVAL_SRC" "$TREE/.claude/evals/no-sonnet-routing.sh" || {
  echo "$NAME: FAIL — the eval copy in the fake tree differs from the source"; exit 1; }
plant_fixture "$TREE/.claude/workflows" "mutant.js" "const opts = { model: t.model || 'sonnet' }"

cases=$((cases + 1))
out="$(env -u EVAL_SUBJECT bash "$TREE/.claude/evals/no-sonnet-routing.sh" 2>&1)"
rc=$?
last="$(printf '%s\n' "$out" | tail -1)"
want="$(fail_line mutant.js)"
if [ "$rc" -eq 1 ] && [ "$last" = "$want" ]; then
  echo "  ok   default subject resolves from the script directory (rc=$rc)"
else
  echo "  FAIL default subject resolves from the script directory — want rc=1"
  echo "         want: $want"
  echo "         got:  rc=$rc | $last"
  fails=$((fails + 1))
fi

# ----------------------------------------------------------------- verdict ---
if [ "$cases" -ne 9 ]; then
  echo "$NAME: FAIL — expected 9 cases, ran $cases"
  exit 1
fi
if [ "$fails" -eq 0 ]; then
  echo "$NAME: PASS — $cases/$cases cases; the eval flips on all 3 quote styles, on a capitalised alias and on a .mjs file, tolerates the routing comments, and resolves its subject from the script directory"
  exit 0
fi
echo "$NAME: FAIL — $fails of $cases cases wrong"
exit 1
