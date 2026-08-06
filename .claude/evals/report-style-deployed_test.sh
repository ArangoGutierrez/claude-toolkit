#!/bin/bash
# report-style-deployed_test.sh — mutation test for report-style-deployed.sh.
# A guard that stays green when its subject is gutted is theater
# (rules/constitution.md), so this test guts the rule one clause at a time,
# in BOTH the repo copy and the live copy, and demands a red verdict each time.
#
# It asserts the exit code AND the last stdout line. A return code alone does
# not discriminate: an eval with the wrong name, an ASCII hyphen instead of the
# contract's em dash, or half the clause list still returns the right codes.
#
# The repo copy is exercised through a FAKE TREE, not an env override. The eval
# derives REPO_RULE from its own SCRIPT_DIR, so the test copies the eval into
# $TMP/tree/.claude/evals/ and the rule into $TMP/tree/.claude/rules/. That
# exercises the real path resolution and leaves no test-only backdoor.
#
# Mutations use awk index()/substr(), never sed: several literals hold regex
# metacharacters (`*`, `|`, `.`) that a pattern would reinterpret. Every
# mutation proves it applied before its verdict is trusted — a substitution
# that silently changes nothing makes the whole run vacuously green.
set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EVAL_SRC="$SCRIPT_DIR/report-style-deployed.sh"
RULE_SRC="$SCRIPT_DIR/../rules/report-style.md"
NAME="report-style-deployed_test"

for f in "$EVAL_SRC" "$RULE_SRC"; do
  [ -f "$f" ] || { echo "$NAME: FAIL — missing input: $f"; exit 1; }
done

# An unchecked mktemp leaves TMP empty, targets fixtures at /, and turns every
# case into a misleading rc mismatch instead of an explicit abort.
TMP="$(mktemp -d)" || { echo "$NAME: FAIL — mktemp -d failed"; exit 1; }
case "$TMP" in
  /*) [ -d "$TMP" ] || { echo "$NAME: FAIL — mktemp -d gave no directory"; exit 1; } ;;
   *) echo "$NAME: FAIL — mktemp -d gave a non-absolute path: '$TMP'"; exit 1 ;;
esac
trap 'rm -rf "$TMP"' EXIT

# --- The fake tree: the eval resolves REPO_RULE relative to its own location. ---
TREE="$TMP/tree"
mkdir -p "$TREE/.claude/evals" "$TREE/.claude/rules"
cp "$EVAL_SRC" "$TREE/.claude/evals/report-style-deployed.sh"
EVAL="$TREE/.claude/evals/report-style-deployed.sh"
REPO_FIXTURE="$TREE/.claude/rules/report-style.md"
cmp -s "$EVAL_SRC" "$EVAL" || { echo "$NAME: FAIL — eval copy differs from source"; exit 1; }

fails=0
cases=0

# $1 case name, $2 expected rc, $3 expected substring of the last stdout line,
# $4 path for EVAL_SUBJECT (the live copy).
run_case() {
  local name="$1" want_rc="$2" want_line="$3" live="$4" out rc last
  cases=$((cases + 1))
  out="$(EVAL_SUBJECT="$live" bash "$EVAL" 2>&1)"
  rc=$?
  last="$(printf '%s\n' "$out" | tail -1)"
  if [ "$rc" -ne "$want_rc" ]; then
    echo "  FAIL $name — want rc=$want_rc, got rc=$rc | $last"
    fails=$((fails + 1))
    return
  fi
  case "$last" in
    *"$want_line"*) echo "  ok   $name (rc=$rc)" ;;
    *) echo "  FAIL $name — rc ok but verdict line wrong"
       echo "         want substring: $want_line"
       echo "         got:            $last"
       fails=$((fails + 1)) ;;
  esac
}

# Literal-safe substitution. $1 src, $2 dst, $3 literal, $4 replacement.
# Returns non-zero when the literal was absent or survived.
mutate() {
  local src="$1" dst="$2" lit="$3" rep="$4" before after
  before="$(grep -cF -- "$lit" "$src")"
  awk -v lit="$lit" -v rep="$rep" '
    { i = index($0, lit)
      if (i > 0) $0 = substr($0, 1, i-1) rep substr($0, i + length(lit))
      print }
  ' "$src" > "$dst"
  after="$(grep -cF -- "$lit" "$dst")"
  [ "${before:-0}" -ge 1 ] && [ "${after:-1}" -eq 0 ]
}

PASS_LINE="EVAL report-style-deployed: PASS — "
FAIL_LINE="EVAL report-style-deployed: FAIL — "
SKIP_LINE="EVAL report-style-deployed: SKIP — "

# ---------------------------------------------------------------- baseline ---
cp "$RULE_SRC" "$REPO_FIXTURE"
cp "$RULE_SRC" "$TMP/live-good.md"
run_case "intact repo + intact live -> PASS" 0 "$PASS_LINE" "$TMP/live-good.md"

# ------------------------------------------------------------ file absence ---
run_case "live copy absent -> SKIP" 2 "$SKIP_LINE" "$TMP/does-not-exist.md"

mv "$REPO_FIXTURE" "$TMP/repo-parked.md"
run_case "repo copy absent -> FAIL" 1 "$FAIL_LINE" "$TMP/live-good.md"
mv "$TMP/repo-parked.md" "$REPO_FIXTURE"

# --------------------------------------------- one mutation per clause, x2 ---
# Every clause is gutted twice: once in the live copy with the repo copy
# intact, once in the repo copy with the live copy intact. The second half is
# what the first version of this eval could not catch at all.
i=0
while IFS= read -r lit; do
  [ -z "$lit" ] && continue
  i=$((i + 1))

  cp "$RULE_SRC" "$REPO_FIXTURE"
  if ! mutate "$RULE_SRC" "$TMP/live-mut.md" "$lit" "GUTTED"; then
    echo "$NAME: FAIL — mutation $i did not apply to the live fixture: $lit"
    exit 1
  fi
  run_case "live: clause $i gutted -> FAIL" 1 "$FAIL_LINE" "$TMP/live-mut.md"

  if ! mutate "$RULE_SRC" "$REPO_FIXTURE" "$lit" "GUTTED"; then
    echo "$NAME: FAIL — mutation $i did not apply to the repo fixture: $lit"
    exit 1
  fi
  run_case "repo: clause $i gutted -> FAIL" 1 "$FAIL_LINE" "$TMP/live-good.md"
done <<'LITERALS'
Output tokens cost more than input tokens, so density is the goal.
## Writing rules
- Use the active voice and the simple present tense.
- Give one idea per sentence. Keep a sentence under 25 words.
- State the finding first, then the rationale. No preamble and no filler.
- Put complex data in a table, not in a long sentence.
- Quote output, paths, identifiers, and errors verbatim. Never paraphrase one.
Outward-facing writing keeps a natural tone: PR text, email, Slack, blog posts.
Code and commit messages keep their own conventions.
LITERALS

if [ "$i" -ne 9 ]; then
  echo "$NAME: FAIL — expected 9 clauses in the battery, iterated $i"
  exit 1
fi

# ------------------------------------------------- semantic-inversion probe ---
# The clause list must pin MEANING. A rule whose scope is inverted keeps every
# heading and every bold marker, so a marker-only guard stays green while the
# rule is switched off.
cp "$RULE_SRC" "$REPO_FIXTURE"
mutate "$RULE_SRC" "$TMP/live-inverted.md" \
  "Outward-facing writing keeps a natural tone: PR text, email, Slack, blog posts." \
  "Outward-facing writing follows the same rules as everything else." \
  || { echo "$NAME: FAIL — inversion mutation did not apply"; exit 1; }
run_case "live: scope inverted -> FAIL" 1 "$FAIL_LINE" "$TMP/live-inverted.md"

# ------------------------------------------------------------- stub probe ---
# A file holding only the section headings is not the rule.
cp "$RULE_SRC" "$REPO_FIXTURE"
printf '# Report Style\n\n## Writing rules\n\n## Where this does not apply\n' \
  > "$TMP/live-stub.md"
run_case "live: headings-only stub -> FAIL" 1 "$FAIL_LINE" "$TMP/live-stub.md"

# ------------------------------------------------------------ empty probe ---
cp "$RULE_SRC" "$REPO_FIXTURE"
: > "$TMP/live-empty.md"
run_case "live: empty file -> FAIL" 1 "$FAIL_LINE" "$TMP/live-empty.md"

# ----------------------------------------------------------------- verdict ---
if [ "$fails" -eq 0 ]; then
  echo "$NAME: PASS — $cases/$cases cases; the eval discriminates on all 9 clauses, both copies"
  exit 0
fi
echo "$NAME: FAIL — $fails of $cases cases wrong"
exit 1
