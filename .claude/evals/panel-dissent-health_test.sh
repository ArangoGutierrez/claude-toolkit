#!/bin/bash
# panel-dissent-health_test.sh — discrimination test for panel-dissent-health.sh.
# The runner excludes *_test.sh, so this harness never runs as a real eval.
#
# The eval it guards grades a log that lives under $HOME, so on a CI runner it
# SKIPs forever and CI proves nothing about it. This harness is therefore the
# only place its logic is exercised automatically: it feeds the eval a fixture
# log for every verdict the eval can reach and demands the exact verdict line.
#
# It asserts the EXACT last stdout line, never a prefix. A return code alone
# does not discriminate: FAIL is reached three different ways (unhealthy
# panelist, broken reader, unparsable output) and SKIP two more, and an eval
# with the wrong name or an ASCII hyphen instead of the contract's em dash
# still returns the right codes.
#
# Two cases matter more than the rest:
#
#   * "reader returns nothing on a populated log -> FAIL". The eval FAILED OPEN
#     here: rows=0 read as "nothing to grade" and it reported healthy forever.
#     The mutant guts load_rows in a COPY of the skill, so the case exercises
#     the real failure rather than a hand-built fixture. Its control case runs
#     the same copy unmutated and demands PASS, so a FAIL cannot come from the
#     copy itself.
#   * Both fake-tree cases run with EVAL_SUBJECT UNSET. The eval must resolve
#     its subject from its OWN directory; a $HOME/.claude default would grade
#     the deployed copy and stay green against a repo regression.
#
# The operator's real log at $HOME/.claude/panel/decisions.jsonl is never read:
# every case passes PANEL_DECISIONS_JSONL, and run_case refuses a path outside
# the fixture directory.
set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EVAL_SRC="$SCRIPT_DIR/panel-dissent-health.sh"
REPO_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
SUBJECT="$REPO_DIR/.claude/skills/validate-recommendation"
NAME="panel-dissent-health_test"
PYBIN="${PANEL_HEALTH_PYTHON:-python3.12}"

[ -f "$EVAL_SRC" ] || { echo "$NAME: FAIL — missing input: $EVAL_SRC"; exit 1; }
[ -d "$SUBJECT" ] || { echo "$NAME: FAIL — missing input: $SUBJECT"; exit 1; }

# Without the interpreter the eval SKIPs on every case and each one fails as a
# bare rc mismatch. Say so instead: a harness that cannot grade must not be
# mistaken for a harness that graded and was happy.
command -v "$PYBIN" >/dev/null 2>&1 || {
  echo "$NAME: FAIL — interpreter not found ($PYBIN); set PANEL_HEALTH_PYTHON"
  exit 1
}

# An unchecked mktemp leaves TMP empty, targets fixtures at /, and turns every
# case into a misleading rc mismatch instead of an explicit abort.
TMP="$(mktemp -d "${TMPDIR:-/tmp}/eval.XXXXXX")" || { echo "$NAME: FAIL — mktemp -d failed"; exit 1; }
case "$TMP" in
  /*) [ -d "$TMP" ] || { echo "$NAME: FAIL — mktemp -d gave no directory"; exit 1; } ;;
   *) echo "$NAME: FAIL — mktemp -d gave a non-absolute path: '$TMP'"; exit 1 ;;
esac
# Explicit path only — never a glob. A glob that matches nothing aborts the whole
# rm and leaks the directory.
trap 'rm -rf "$TMP"' EXIT

fails=0
cases=0

# One decisions.jsonl line carrying one panelist vote. $1 panelist id, $2 verdict.
vote_row() {
  printf '{"event":"decision","verdict":"HOLD","panelists":[{"id":"%s","role":"PE","verdict":"%s"}]}\n' "$1" "$2"
}

# $1 path, $2 count, $3 panelist id, $4 verdict — appends $2 identical votes.
add_votes() {
  local path="$1" n="$2" pid="$3" verdict="$4" i
  for ((i = 0; i < n; i++)); do vote_row "$pid" "$verdict" >> "$path"; done
}

# $1 case name, $2 expected rc, $3 the EXACT expected last stdout line,
# $4 log path, $5 min-n, $6 EVAL_SUBJECT ("" = unset, default resolution),
# $7 the eval to run (defaults to the repo copy).
run_case() {
  local name="$1" want_rc="$2" want_line="$3" jsonl="$4" min_n="$5" subject="$6"
  local evl="${7:-$EVAL_SRC}" out rc last
  cases=$((cases + 1))

  # The operator's log is read-only to this harness. Anything outside the
  # fixture directory is a bug in the case, not a verdict worth reporting.
  case "$jsonl" in
    "$TMP"/*) ;;
    *) echo "$NAME: FAIL — case '$name' points at a log outside the fixtures: $jsonl"; exit 1 ;;
  esac

  if [ -n "$subject" ]; then
    out="$(EVAL_SUBJECT="$subject" PANEL_DECISIONS_JSONL="$jsonl" \
           PANEL_HEALTH_MIN_N="$min_n" PANEL_HEALTH_PYTHON="$PYBIN" bash "$evl" 2>&1)"
  else
    out="$(env -u EVAL_SUBJECT PANEL_DECISIONS_JSONL="$jsonl" \
           PANEL_HEALTH_MIN_N="$min_n" PANEL_HEALTH_PYTHON="$PYBIN" bash "$evl" 2>&1)"
  fi
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

# ------------------------------------------- cases 1-2: a panelist at a rail ---
# n == min-n is the scoring boundary, so these also pin that the eval grades at
# exactly the threshold rather than one vote later.
ALL_HOLD="$TMP/all-hold.jsonl"
add_votes "$ALL_HOLD" 6 pe HOLD
run_case "rubber stamp: 6 HOLD at min-n=6 -> FAIL" 1 \
  "EVAL panel-dissent-health: FAIL — 1 of 1 scored panelist(s) at exactly 0% or 100% dissent; the panel is not deliberating" \
  "$ALL_HOLD" 6 "$SUBJECT"

ALL_OVERTURN="$TMP/all-overturn.jsonl"
add_votes "$ALL_OVERTURN" 6 pe OVERTURN
run_case "pure noise: 6 OVERTURN at min-n=6 -> FAIL" 1 \
  "EVAL panel-dissent-health: FAIL — 1 of 1 scored panelist(s) at exactly 0% or 100% dissent; the panel is not deliberating" \
  "$ALL_OVERTURN" 6 "$SUBJECT"

# ------------------------------------------------------- case 3: the band ---
MIXED="$TMP/mixed.jsonl"
add_votes "$MIXED" 3 pe HOLD
add_votes "$MIXED" 3 pe OVERTURN
run_case "deliberating: 3 HOLD + 3 OVERTURN -> PASS" 0 \
  "EVAL panel-dissent-health: PASS — all 1 scored panelist(s) dissent inside the band (min-n=6)" \
  "$MIXED" 6 "$SUBJECT"

# --------------------------------------------------- case 4: below min-n ---
# A rubber stamp on a tiny sample must SKIP, not PASS: the same all-HOLD shape
# as case 1, one vote short of the threshold.
FEW="$TMP/few.jsonl"
add_votes "$FEW" 5 pe HOLD
run_case "5 HOLD at min-n=6 -> SKIP, never a vacuous PASS" 2 \
  "EVAL panel-dissent-health: SKIP — no panelist has reached 6 votes (1 panelist(s) below the threshold)" \
  "$FEW" 6 "$SUBJECT"

# ------------------------------------------------------ case 5: no log ---
ABSENT="$TMP/does-not-exist.jsonl"
run_case "decisions log absent -> SKIP" 2 \
  "EVAL panel-dissent-health: SKIP — decisions log not found ($ABSENT)" \
  "$ABSENT" 6 "$SUBJECT"

# ------------------------------------- case 6: a log that carries no votes ---
# The boundary the fail-open guard has to respect: an empty aggregate is only
# benign when the log really holds no votes. Confusing this with case 8 in
# either direction breaks the eval.
NO_VOTES="$TMP/no-votes.jsonl"
printf '{"event":"decision","verdict":"HOLD"}\n' > "$NO_VOTES"
printf '{"event":"decision","verdict":"HOLD","panelists":[]}\n' >> "$NO_VOTES"
run_case "log with no panelist votes -> SKIP" 2 \
  "EVAL panel-dissent-health: SKIP — no panelist votes recorded in $NO_VOTES" \
  "$NO_VOTES" 6 "$SUBJECT"

# ------------------------------- cases 7-8: the fake tree and a gutted reader ---
# The eval derives SUBJECT, and from it PKG_ROOT, from its own directory, so a
# copy of the skill under $TMP/<tree> is what a copy of the eval grades. Every
# fake-tree case runs with EVAL_SUBJECT unset, which is what pins that
# resolution. Echoes the eval path into $2 and the stats.py path into $3.
make_tree() {
  local tree="$1"
  mkdir -p "$tree/.claude/evals" "$tree/.claude/skills/validate-recommendation"
  command cp "$EVAL_SRC" "$tree/.claude/evals/panel-dissent-health.sh"
  cmp -s "$EVAL_SRC" "$tree/.claude/evals/panel-dissent-health.sh" || {
    echo "$NAME: FAIL — the eval copy in $tree differs from the source"; exit 1; }
  command cp -R "$SUBJECT/panel" "$tree/.claude/skills/validate-recommendation/panel" || {
    echo "$NAME: FAIL — could not copy the panel package into $tree"; exit 1; }
  [ -f "$tree/.claude/skills/validate-recommendation/panel/stats.py" ] || {
    echo "$NAME: FAIL — the panel copy in $tree has no stats.py"; exit 1; }
  # Explicit paths, never a glob: a stale __pycache__ would let the ORIGINAL
  # load_rows answer for the mutated source and turn the case vacuously green.
  rm -rf "$tree/.claude/skills/validate-recommendation/panel/__pycache__" \
         "$tree/.claude/skills/validate-recommendation/panel/tests/__pycache__"
}

# Rewrites the first line of load_rows' body. $1 stats.py, $2 the replacement.
# awk index()/substr(), not sed — the literal holds regex metacharacters. The
# substitution proves it applied before the case is trusted; a silent no-op
# would leave the reader working and the case vacuously green.
gut_load_rows() {
  local stats="$1" rep="$2" lit='    p = Path(path).expanduser()' before after
  before="$(grep -cF -- "$lit" "$stats")"
  awk -v lit="$lit" -v rep="$rep" '
    { i = index($0, lit)
      if (i > 0) $0 = substr($0, 1, i-1) rep substr($0, i + length(lit))
      print }
  ' "$stats" > "$stats.mut" && command mv -f "$stats.mut" "$stats"
  after="$(grep -cF -- "$lit" "$stats")"
  if [ "${before:-0}" -ne 1 ] || [ "${after:-1}" -ne 0 ]; then
    echo "$NAME: FAIL — mutating load_rows did not apply (before=$before, after=$after); stats.py changed shape"
    exit 1
  fi
  grep -qF -- "$rep" "$stats" || {
    echo "$NAME: FAIL — the replacement '$rep' is absent from $stats after the rewrite"; exit 1; }
}

# Wraps load_rows so it keeps only the first $2 rows of whatever it read. An
# append, not a rewrite: the module-level rebinding is unambiguous, where a
# substitution on `    return rows` would match two lines at two indents.
truncate_reader() {
  local stats="$1" keep="$2" before after
  before="$(wc -l < "$stats")"
  cat >> "$stats" <<PY

_orig_load_rows = load_rows  # MUTANT


def load_rows(path):  # MUTANT: keeps only the first $keep rows
    return _orig_load_rows(path)[:$keep]
PY
  after="$(wc -l < "$stats")"
  [ "$((after - before))" -eq 6 ] || {
    echo "$NAME: FAIL — the truncating wrapper did not append (before=$before, after=$after)"; exit 1; }
  [ "$(grep -cF 'MUTANT' "$stats")" -eq 2 ] || {
    echo "$NAME: FAIL — expected 2 MUTANT markers in $stats"; exit 1; }
  "$PYBIN" -c "import ast,sys; ast.parse(open(sys.argv[1]).read())" "$stats" || {
    echo "$NAME: FAIL — the truncating wrapper left $stats unparsable"; exit 1; }
}

TREE="$TMP/tree"
make_tree "$TREE"
TREE_EVAL="$TREE/.claude/evals/panel-dissent-health.sh"
TREE_STATS="$TREE/.claude/skills/validate-recommendation/panel/stats.py"

# Control: the untouched copy must reach the same PASS as case 3. Without it a
# FAIL in case 8 could come from the copy rather than from the mutation.
run_case "fake tree, reader intact, EVAL_SUBJECT unset -> PASS" 0 \
  "EVAL panel-dissent-health: PASS — all 1 scored panelist(s) dissent inside the band (min-n=6)" \
  "$MIXED" 6 "" "$TREE_EVAL"

# Gut load_rows: return the empty accumulator before the file is ever opened.
gut_load_rows "$TREE_STATS" '    return rows'

# The gutted reader sees the same 6-vote log as the control case above.
voters="$(grep -cE '"panelists"[[:space:]]*:[[:space:]]*\[[[:space:]]*\{' "$MIXED")"
[ "${voters:-0}" -eq 6 ] || { echo "$NAME: FAIL — expected 6 vote lines in $MIXED, counted $voters"; exit 1; }
run_case "fake tree, load_rows gutted -> FAIL, never a silent SKIP" 1 \
  "EVAL panel-dissent-health: FAIL — the reader returned no panelist rows, but $MIXED carries $voters line(s) of panelist votes; load_rows is broken (or every such line is malformed) and the metric is measuring nothing" \
  "$MIXED" 6 "" "$TREE_EVAL"

# ------------------------------------------ case 9: every vote line malformed ---
# The other route to an empty aggregate on a populated log: a concurrent writer
# truncating every line. The reader is fine and still returns nothing, so the
# eval must reach the same FAIL rather than call the panel healthy.
TRUNCATED="$TMP/truncated.jsonl"
for i in 1 2 3 4 5 6; do
  printf '{"event":"decision","panelists":[{"id":"pe","role":"PE","verdict":"HOLD"\n' >> "$TRUNCATED"
done
bad="$(grep -cE '"panelists"[[:space:]]*:[[:space:]]*\[[[:space:]]*\{' "$TRUNCATED")"
[ "${bad:-0}" -eq 6 ] || { echo "$NAME: FAIL — expected 6 malformed vote lines, counted $bad"; exit 1; }
run_case "every vote line truncated -> FAIL" 1 \
  "EVAL panel-dissent-health: FAIL — the reader returned no panelist rows, but $TRUNCATED carries $bad line(s) of panelist votes; load_rows is broken (or every such line is malformed) and the metric is measuring nothing" \
  "$TRUNCATED" 6 "$SUBJECT"

# --------------------------- cases 10-11: a reader that truncates, not one ---
# --------------------------- that returns nothing.
#
# The nastier half of the same failure. A reader returning SOME of the log
# leaves a non-zero row count, so the empty-read guard never fires, and the
# eval reports an affirmative PASS while a rubber stamp sits in the data it
# dropped. Green on the exact condition the metric exists to catch.
#
# The fixture is ordered: 25 healthy qa votes first, then 25 rubber-stamp da
# votes. A reader keeping only the first 25 rows loses the whole rubber stamp.
TRUNC="$TMP/truncating.jsonl"
add_votes "$TRUNC" 13 qa HOLD
add_votes "$TRUNC" 12 qa OVERTURN
add_votes "$TRUNC" 25 da HOLD
t_lines="$(grep -cE '"panelists"[[:space:]]*:[[:space:]]*\[[[:space:]]*\{' "$TRUNC")"
[ "${t_lines:-0}" -eq 50 ] || { echo "$NAME: FAIL — expected 50 vote lines in $TRUNC, counted $t_lines"; exit 1; }

TREE2="$TMP/tree-truncating"
make_tree "$TREE2"
TREE2_EVAL="$TREE2/.claude/evals/panel-dissent-health.sh"
TREE2_STATS="$TREE2/.claude/skills/validate-recommendation/panel/stats.py"

# Control: with the reader intact the rubber stamp IS visible and the eval
# catches it. Without this the next case cannot tell "the guard fired" from
# "the fixture was never unhealthy in the first place".
run_case "fake tree, reader intact, rubber stamp visible -> FAIL" 1 \
  "EVAL panel-dissent-health: FAIL — 1 of 2 scored panelist(s) at exactly 0% or 100% dissent; the panel is not deliberating" \
  "$TRUNC" 25 "" "$TREE2_EVAL"

# Keep only the first 25 rows: qa survives at 48% dissent and looks healthy,
# da disappears from the report entirely. This one wraps rather than rewrites,
# because the truncation has to happen AFTER a real read - rewriting the first
# line of the body would return an empty list and reproduce case 8 instead.
truncate_reader "$TREE2_STATS" 25

run_case "fake tree, reader truncates the log -> FAIL, never an affirmative PASS" 1 \
  "EVAL panel-dissent-health: FAIL — the reader accounted for 25 vote(s) but $TRUNC carries 50; load_rows is dropping data and the metric is grading a subset" \
  "$TRUNC" 25 "" "$TREE2_EVAL"

# ----------------------------------------------------------------- verdict ---
if [ "$cases" -ne 11 ]; then
  echo "$NAME: FAIL — expected 11 cases, ran $cases"
  exit 1
fi
if [ "$fails" -eq 0 ]; then
  echo "$NAME: PASS — $cases/$cases cases; the eval flips on both rails, passes inside the band, skips below min-n and on an absent or voteless log, resolves its subject from the script directory, and refuses to stay green when the reader returns nothing"
  exit 0
fi
echo "$NAME: FAIL — $fails of $cases cases wrong"
exit 1
