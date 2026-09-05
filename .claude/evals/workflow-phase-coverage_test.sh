#!/bin/bash
# workflow-phase-coverage_test.sh — discrimination test for
# workflow-phase-coverage.sh. The runner excludes *_test.sh, so this harness
# never runs as a real eval.
#
# A guard that stays green when its regression returns is theater
# (rules/constitution.md). This harness feeds the eval fixtures that CONTAIN the
# regression, in BOTH directions it claims to catch (a used phase nobody
# declared, and a declared phase nobody uses), and demands a red verdict.
#
# It asserts the EXACT verdict line, never a prefix or a return code alone: the
# SKIP path and the vacuous-scan path already occupy rc 2 and rc 1, so rc does
# not discriminate between "caught the mutant" and "fell over for an unrelated
# reason".
#
# The clean case is a copy of the REAL workflows, which is what proves the eval
# is not simply red on everything.
set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EVAL_SRC="$SCRIPT_DIR/workflow-phase-coverage.sh"
WORKFLOWS_SRC="$SCRIPT_DIR/../workflows"
NAME="workflow-phase-coverage_test"

[ -f "$EVAL_SRC" ] || { echo "$NAME: FAIL — missing input: $EVAL_SRC"; exit 1; }
[ -d "$WORKFLOWS_SRC" ] || { echo "$NAME: FAIL — missing input: $WORKFLOWS_SRC"; exit 1; }

# An unchecked mktemp leaves TMP empty and targets fixtures at /.
TMP="$(mktemp -d "${TMPDIR:-/tmp}/eval.XXXXXX")" || { echo "$NAME: FAIL — mktemp -d failed"; exit 1; }
case "$TMP" in
  /*) [ -d "$TMP" ] || { echo "$NAME: FAIL — mktemp -d gave no directory"; exit 1; } ;;
   *) echo "$NAME: FAIL — mktemp -d gave a non-absolute path: '$TMP'"; exit 1 ;;
esac
# Explicit path only, never a glob: an unmatched glob aborts the whole rm.
trap 'rm -rf "$TMP"' EXIT

fails=0
cases=0

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

# Builds a fixture dir: the real workflows plus one planted mutant. Proves both
# the copy and the write landed before the case is trusted, because cp returns 0
# while doing nothing useful often enough to matter.
plant() {
  local dir="$1" body="$2" probe="$3" n
  mkdir -p "$dir"
  cp "$WORKFLOWS_SRC"/*.js "$dir/" || { echo "$NAME: FAIL — could not copy the real workflows into $dir"; exit 1; }
  printf '%s\n' "$body" > "$dir/mutant.js"
  n="$(grep -cF -- "$probe" "$dir/mutant.js")"
  [ "${n:-0}" -ge 1 ] || { echo "$NAME: FAIL — mutant fixture did not take: $dir/mutant.js"; exit 1; }
}

UNDECLARED_BODY="export const meta = {
  name: 'mutant',
  description: 'fixture: an agent carries a phase meta never declared',
  phases: [
    { title: 'A' },
  ],
}
await agent('x', { phase: 'B' })"

UNUSED_BODY="export const meta = {
  name: 'mutant',
  description: 'fixture: meta declares a phase no agent ever uses',
  phases: [
    { title: 'A' },
    { title: 'Z' },
  ],
}
await agent('x', { phase: 'A' })"

# ------------------------------------------------------- case 1: clean copy ---
CLEAN="$TMP/clean"
mkdir -p "$CLEAN"
cp "$WORKFLOWS_SRC"/*.js "$CLEAN/" || { echo "$NAME: FAIL — could not copy the real workflows"; exit 1; }
shopt -s nullglob
clean_js=( "$CLEAN"/*.js )
shopt -u nullglob
n_clean=${#clean_js[@]}
[ "$n_clean" -ge 1 ] || { echo "$NAME: FAIL — the clean fixture holds no .js file"; exit 1; }

# Precondition: without a phased workflow in the copy the clean case is vacuous.
n_phased="$(grep -l "phases:" "$CLEAN"/*.js | grep -c .)"
[ "${n_phased:-0}" -ge 1 ] || {
  echo "$NAME: FAIL — the clean fixture holds no workflow declaring phases, so case 1 proves nothing"
  exit 1
}

run_case "clean copy of the real workflows -> PASS" 0 \
  "EVAL workflow-phase-coverage: PASS — scanned $n_clean .js/.mjs files; declared and used phase names agree in every one" \
  "$CLEAN"

# ------------------------------------------- cases 2-3: both drift directions ---
MUT_U="$TMP/mut-undeclared"
plant "$MUT_U" "$UNDECLARED_BODY" "phase: 'B'"
run_case "agent uses an undeclared phase -> FAIL" 1 \
  "EVAL workflow-phase-coverage: FAIL — mutant.js uses phase 'B' but meta.phases does not declare it; that agent renders in its own unlabelled group" \
  "$MUT_U"

MUT_N="$TMP/mut-unused"
plant "$MUT_N" "$UNUSED_BODY" "title: 'Z'"
run_case "meta declares a phase nobody uses -> FAIL" 1 \
  "EVAL workflow-phase-coverage: FAIL — mutant.js declares phase 'Z' but no agent call uses it; that stage renders as a box that never fills" \
  "$MUT_N"

# --------------------------------------------------- case 4: missing subject ---
MISSING="$TMP/does-not-exist"
run_case "missing directory -> SKIP" 2 \
  "EVAL workflow-phase-coverage: SKIP — subject not found ($MISSING)" \
  "$MISSING"

# ----------------------------------------------------- case 5: vacuous scan ---
EMPTY="$TMP/empty"
mkdir -p "$EMPTY"
run_case "subject with no .js or .mjs file -> FAIL" 1 \
  "EVAL workflow-phase-coverage: FAIL — no .js or .mjs file under $EMPTY; the scan would pass vacuously" \
  "$EMPTY"

# ----------------------------- case 6: the default subject, no env override ---
# The eval must resolve its default subject from its OWN directory. A
# $HOME/.claude/... default grades the deployed copy, so a repo regression stays
# green. Only script-relative resolution turns this fake tree red.
TREE="$TMP/tree"
mkdir -p "$TREE/.claude/evals" "$TREE/.claude/workflows"
cp "$EVAL_SRC" "$TREE/.claude/evals/workflow-phase-coverage.sh"
cmp -s "$EVAL_SRC" "$TREE/.claude/evals/workflow-phase-coverage.sh" || {
  echo "$NAME: FAIL — the eval copy in the fake tree differs from the source"; exit 1; }
plant "$TREE/.claude/workflows" "$UNDECLARED_BODY" "phase: 'B'"

cases=$((cases + 1))
out="$(env -u EVAL_SUBJECT bash "$TREE/.claude/evals/workflow-phase-coverage.sh" 2>&1)"
rc=$?
last="$(printf '%s\n' "$out" | tail -1)"
want="EVAL workflow-phase-coverage: FAIL — mutant.js uses phase 'B' but meta.phases does not declare it; that agent renders in its own unlabelled group"
if [ "$rc" -eq 1 ] && [ "$last" = "$want" ]; then
  echo "  ok   default subject resolves from the script directory (rc=$rc)"
else
  echo "  FAIL default subject resolves from the script directory — want rc=1"
  echo "         want: $want"
  echo "         got:  rc=$rc | $last"
  fails=$((fails + 1))
fi

# ----------------------------------------------------------------- verdict ---
if [ "$cases" -ne 6 ]; then
  echo "$NAME: FAIL — expected 6 cases, ran $cases"
  exit 1
fi
if [ "$fails" -eq 0 ]; then
  echo "$NAME: PASS — $cases/$cases cases; the eval flips in both drift directions, stays green on the real workflows, refuses a vacuous scan, and resolves its subject from the script directory"
  exit 0
fi
echo "$NAME: FAIL — $fails of $cases cases wrong"
exit 1
