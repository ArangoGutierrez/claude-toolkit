#!/usr/bin/env bash
# workflow-behavior_test.sh — behaviour tests for the workflows under
# .claude/workflows/, driven by scripts/workflow-harness.js (which RUNS the
# workflow with stubbed agents).
#
# Subjects: review-verify.js and pr-review-fanout.js. Both fan agents out and
# both must tell "nothing was wrong" apart from "every agent died".
#
# check-workflow-syntax.sh only parses a workflow, so it cannot see a broken
# abort guard. These cases run the real workflow file and assert what it returns.
#
# Subject resolution is SCRIPT_DIR-relative on purpose: a test that reached
# through $HOME/.claude/... would green-light the deployed copy, not the tree
# under change.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
HARNESS="$SCRIPT_DIR/workflow-harness.js"
SUBJECT="$REPO_DIR/.claude/workflows/review-verify.js"
FANOUT="$REPO_DIR/.claude/workflows/pr-review-fanout.js"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
pass=0; fail=0

# Prerequisites: the two files this suite drives, plus jq, which every assertion
# below runs the harness report through. `jq` is in ubuntu-latest, so the CI gate
# never trips this — the point is that a bare machine gets the same clear line as
# a missing file instead of a cryptic `jq: command not found` mid-suite.
# `[ -f ]` cannot see a binary on PATH and `command -v` is the check that can, so
# each entry passes on either.
for required in "$HARNESS" "$SUBJECT" "$FANOUT" jq; do
  if [ -f "$required" ] || command -v "$required" > /dev/null 2>&1; then
    continue
  fi
  echo "ERROR: missing prerequisite: $required" >&2
  exit 1
done

expect() { # <desc> <jq filter> <scenario-name>
  local desc="$1" filter="$2" name="$3"
  if jq -e "$filter" < "$TMP/$name.out" > /dev/null 2>&1; then
    pass=$((pass + 1)); echo "PASS: $desc"
  else
    fail=$((fail + 1)); echo "FAIL: $desc"
    echo "  filter: $filter"
    echo "  report: $(cat "$TMP/$name.out")"
  fi
}

run() { # <scenario-name> [subject] — reads $TMP/<name>.json, writes $TMP/<name>.out
  local name="$1" subject="${2:-$SUBJECT}" rc=0
  node "$HARNESS" "$subject" "$TMP/$name.json" > "$TMP/$name.out" 2> "$TMP/$name.err" || rc=$?
  if [ "$rc" -ne 0 ]; then
    fail=$((fail + 1))
    echo "FAIL: $name: harness exited rc=$rc — stderr: $(cat "$TMP/$name.err")"
    return 0
  fi
  # Anti-vacuity gate, and it is not optional. When the workflow throws, the
  # harness reports {"return": null}, and jq evaluates `null | has("error")`
  # to false and `null | length` to 0 — so EVERY "no error field" and "zero
  # confirmed" assertion below would pass against a workflow that never ran.
  # Pin the return to a real object first, so those assertions mean something.
  expect "$name: the workflow returned an object and did not throw" \
    '(.return | type) == "object" and (has("threw") | not)' "$name"
}

ARGS='{"target":"probe-target","dimensions":["alpha","beta","gamma"]}'

# ---------------------------------------------------------------------------
# Case 1: every finder agent dies. The workflow MUST NOT report a clean review.
# This is the defect: agent() resolves to null on death, it does not throw.
# ---------------------------------------------------------------------------
cat > "$TMP/all-dead.json" <<EOF
{"args": $ARGS, "agent": {"default": null}}
EOF
run all-dead
expect "all-dead: harness launched all 3 finders in order" \
  '.agents == ["review:alpha","review:beta","review:gamma"]' all-dead
expect "all-dead: return carries the exact abort error" \
  '.return.error == "review-verify: all 3 of 3 finder agent(s) died; no review ran"' all-dead
expect "all-dead: return carries the dead count" '.return.deadFinders == 3' all-dead
expect "all-dead: return carries the attempted count" '.return.attemptedFinders == 3' all-dead
# The guard also logs the abort. Nothing else asserted on .logs, so a workflow
# that returned the error but logged nothing would have shipped unnoticed.
# Match the exact line, not a prefix: a truncated or reworded log is a defect.
expect "all-dead: the abort reaches the log stream verbatim" \
  '.logs | index("review-verify: all 3 of 3 finder agent(s) died; no review ran") != null' all-dead

# ---------------------------------------------------------------------------
# Case 2: one finder lives and its finding survives verification.
# Also proves the harness really drives pipeline/parallel: confirmed == 1 is
# only reachable when stage 1, stage 2 and the verifier all run.
# ---------------------------------------------------------------------------
cat > "$TMP/one-confirmed.json" <<EOF
{"args": $ARGS,
 "agent": {"default": null,
   "byLabel": {"review:alpha": {"findings": [
     {"file":"src/a.js","line":42,"title":"off-by-one","detail":"loop overruns","severity":"major"}]}},
   "byLabelPrefix": {"verify:": {"refuted": false, "reason": "the defect is real"}}}}
EOF
run one-confirmed
expect "one-confirmed: no error field" '.return | has("error") | not' one-confirmed
expect "one-confirmed: one finding survives" '.return.confirmed | length == 1' one-confirmed
expect "one-confirmed: the surviving finding is the injected one" \
  '.return.confirmed[0].file == "src/a.js" and .return.confirmed[0].line == 42' one-confirmed
expect "one-confirmed: the verifier ran on that finding" \
  '.agents | index("verify:src/a.js:42") != null' one-confirmed
expect "one-confirmed: args.target reaches the return value" \
  '.return.target == "probe-target"' one-confirmed

# ---------------------------------------------------------------------------
# Case 3: THE DISCRIMINATOR. Two finders die, one lives and honestly reports
# no findings. A guard that fires on an empty result would turn this clean
# review into an error. It must not.
# ---------------------------------------------------------------------------
cat > "$TMP/one-live-empty.json" <<EOF
{"args": $ARGS,
 "agent": {"default": null, "byLabel": {"review:alpha": {"findings": []}}}}
EOF
run one-live-empty
expect "one-live-empty: harness launched all 3 finders" '.agents | length == 3' one-live-empty
expect "one-live-empty: NO error field (a live finder found nothing)" \
  '.return | has("error") | not' one-live-empty
# Assert the TYPE as well as the length, and it is not optional. jq evaluates
# `null | length` to 0, so a bare `.return.confirmed | length == 0` also passes
# when `confirmed` is ABSENT — the same vacuous-pass class as the `.return`
# gate above. Pin it to an array first, so "zero confirmed" means the workflow
# built the list and left it empty.
expect "one-live-empty: zero confirmed findings" \
  '(.return.confirmed | type) == "array" and (.return.confirmed | length == 0)' one-live-empty

# ---------------------------------------------------------------------------
# Case 4: every finder lives and every one reports nothing — a clean review.
# ---------------------------------------------------------------------------
cat > "$TMP/all-live-empty.json" <<EOF
{"args": $ARGS, "agent": {"default": {"findings": []}}}
EOF
run all-live-empty
expect "all-live-empty: harness launched all 3 finders" '.agents | length == 3' all-live-empty
expect "all-live-empty: NO error field" '.return | has("error") | not' all-live-empty
expect "all-live-empty: zero confirmed findings" \
  '(.return.confirmed | type) == "array" and (.return.confirmed | length == 0)' all-live-empty

# ---------------------------------------------------------------------------
# Case 5: a live finder reports a finding and the verifier refutes it.
# Confirmed is empty here too, so this is a second discriminator against a
# guard keyed on confirmed.length.
# ---------------------------------------------------------------------------
cat > "$TMP/all-refuted.json" <<EOF
{"args": $ARGS,
 "agent": {"default": null,
   "byLabel": {"review:beta": {"findings": [
     {"file":"src/b.js","line":7,"title":"race","detail":"unsynchronized write","severity":"critical"}]}},
   "byLabelPrefix": {"verify:": {"refuted": true, "reason": "the write is guarded"}}}}
EOF
run all-refuted
expect "all-refuted: NO error field" '.return | has("error") | not' all-refuted
expect "all-refuted: zero confirmed findings" \
  '(.return.confirmed | type) == "array" and (.return.confirmed | length == 0)' all-refuted
expect "all-refuted: one finding counted as refuted" '.return.refutedCount == 1' all-refuted

# ===========================================================================
# SUBJECT 2: .claude/workflows/pr-review-fanout.js
#
# Same abort-guard class of defect as review-verify, with a sharper edge: this
# workflow decides what gets posted on a real PR, so "every reviewer died"
# reported as "the PR is clean" lets code merge unreviewed.
# ===========================================================================

# domains is empty, so the reviewer set is exactly the 5 generic reviewers.
FARGS='{"diffPath":"/tmp/probe.diff","prNumber":7,"ownerRepo":"o/r","repoCheckout":"/tmp/co","domains":[],"claudeMdPaths":["/tmp/CLAUDE.md"]}'
FREVIEWERS='["review:claude-md-adherence","review:bug-scan","review:git-history","review:prior-prs","review:code-comments"]'

# ---------------------------------------------------------------------------
# Case 6: every reviewer agent dies. agent() resolves null on a terminal API
# error — it does not throw — so the pre-guard file returned
#   {"findings":[],"degradedReviewers":[],"counts":{"raw":0,"survived":0}}
# which a caller cannot tell from a genuinely clean PR.
# ---------------------------------------------------------------------------
cat > "$TMP/fanout-all-dead.json" <<EOF
{"args": $FARGS, "agent": {"default": null}}
EOF
run fanout-all-dead "$FANOUT"
expect "fanout-all-dead: all 5 reviewers launched, in order" \
  ".agents == $FREVIEWERS" fanout-all-dead
expect "fanout-all-dead: return carries the exact abort error" \
  '.return.error == "pr-review-fanout: all 5 of 5 reviewer agent(s) died; no review ran"' fanout-all-dead
expect "fanout-all-dead: return carries the dead count" '.return.deadReviewers == 5' fanout-all-dead
expect "fanout-all-dead: return carries the attempted count" '.return.attemptedReviewers == 5' fanout-all-dead
expect "fanout-all-dead: the abort reaches the log stream verbatim" \
  '.logs | index("pr-review-fanout: all 5 of 5 reviewer agent(s) died; no review ran") != null' fanout-all-dead
# Nothing to score when nothing was reviewed. Without this the guard could be
# "satisfied" by a run that still burned scorer agents on a dead fan-out.
expect "fanout-all-dead: no scorer agent ran" \
  '[.agents[] | select(startswith("score:"))] | length == 0' fanout-all-dead

# ---------------------------------------------------------------------------
# Case 7: THE DISCRIMINATOR for invariant 2. Four reviewers die, one lives and
# honestly reports nothing. A guard keyed on findings.length (rather than on
# reviewers that RETURNED) would turn this clean PR into an error.
# ---------------------------------------------------------------------------
cat > "$TMP/fanout-one-live-empty.json" <<EOF
{"args": $FARGS,
 "agent": {"default": null,
   "byLabel": {"review:bug-scan": {"findings": [], "degraded": false}}}}
EOF
run fanout-one-live-empty "$FANOUT"
expect "fanout-one-live-empty: all 5 reviewers launched" '.agents | length == 5' fanout-one-live-empty
expect "fanout-one-live-empty: NO error field (a live reviewer found nothing)" \
  '.return | has("error") | not' fanout-one-live-empty
# Assert the TYPE as well as the length: jq evaluates `null | length` to 0, so a
# bare length check also passes when the field is ABSENT.
expect "fanout-one-live-empty: zero findings, as a real array" \
  '(.return.findings | type) == "array" and (.return.findings | length == 0)' fanout-one-live-empty
expect "fanout-one-live-empty: no scorer agent ran (nothing to score)" \
  '[.agents[] | select(startswith("score:"))] | length == 0' fanout-one-live-empty
# Invariant 3: a dead reviewer is not an error, but it must not vanish either.
# The caller reads degradedReviewers to know the review was not full strength.
expect "fanout-one-live-empty: the 4 dead reviewers are recorded as degraded" \
  '(.return.degradedReviewers | type) == "array" and (.return.degradedReviewers | length == 4)' fanout-one-live-empty
expect "fanout-one-live-empty: a dead reviewer is named verbatim in degradedReviewers" \
  '.return.degradedReviewers | index("git-history (agent returned no result)") != null' fanout-one-live-empty
expect "fanout-one-live-empty: the LIVE reviewer is not marked degraded" \
  '[.return.degradedReviewers[] | select(startswith("bug-scan"))] | length == 0' fanout-one-live-empty

# ---------------------------------------------------------------------------
# Case 8: partial failure is NOT total failure. Three reviewers die, two live,
# and one of the live ones raises a finding that survives scoring.
#
# The scorer stub carries BOTH score shapes on purpose — the flat {score} the
# per-finding scorer reads and the {scores:[{id}]} list the batch scorer reads —
# so this abort-guard case stays valid across the scorer change and never had to
# be rewritten to keep passing.
# ---------------------------------------------------------------------------
cat > "$TMP/fanout-partial.json" <<EOF
{"args": $FARGS,
 "agent": {"default": null,
   "byLabel": {
     "review:bug-scan": {"findings": [
       {"file":"src/a.js","line":42,"description":"off-by-one","category":"bug","severity":"must-fix","reason":"loop overruns"}],
      "degraded": false},
     "review:code-comments": {"findings": [], "degraded": false}},
   "byLabelPrefix": {"score:": {"score": 90, "rationale": "real",
                                "scores": [{"id": 0, "score": 90, "rationale": "real"}]}}}}
EOF
run fanout-partial "$FANOUT"
expect "fanout-partial: NO error field (2 of 5 reviewers returned)" \
  '.return | has("error") | not' fanout-partial
expect "fanout-partial: the finding from the live reviewer survives" \
  '(.return.findings | type) == "array" and (.return.findings | length == 1)' fanout-partial
expect "fanout-partial: the survivor is the injected finding" \
  '.return.findings[0].file == "src/a.js" and .return.findings[0].line == 42 and .return.findings[0].score == 90' fanout-partial
expect "fanout-partial: exactly the 3 dead reviewers are degraded" \
  '(.return.degradedReviewers | sort) == ["claude-md-adherence (agent returned no result)","git-history (agent returned no result)","prior-prs (agent returned no result)"]' fanout-partial
expect "fanout-partial: counts reflect the one scored finding" \
  '.return.counts.raw == 1 and .return.counts.survived == 1' fanout-partial

echo "---"; echo "pass=$pass fail=$fail"
[ "$fail" -eq 0 ]
