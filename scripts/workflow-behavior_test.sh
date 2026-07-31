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

# ---------------------------------------------------------------------------
# Case 9: ONE scorer agent per reviewer, not one per finding. This is the case
# that proves the batch actually happened — 11 reviewers x 5 findings used to
# mean 66 agents for a single review, with no cap.
# ---------------------------------------------------------------------------
cat > "$TMP/fanout-batch-count.json" <<EOF
{"args": $FARGS,
 "agent": {"default": null,
   "byLabel": {"review:bug-scan": {"findings": [
     {"file":"src/x.js","line":1,"description":"d0","category":"bug","severity":"must-fix","reason":"r0"},
     {"file":"src/y.js","line":2,"description":"d1","category":"bug","severity":"must-fix","reason":"r1"},
     {"file":"src/z.js","line":3,"description":"d2","category":"bug","severity":"must-fix","reason":"r2"}],
    "degraded": false}},
   "byLabelPrefix": {"score:": {"scores": [
     {"id":0,"score":90,"rationale":"a"},{"id":1,"score":90,"rationale":"b"},{"id":2,"score":90,"rationale":"c"}]}}}}
EOF
run fanout-batch-count "$FANOUT"
expect "fanout-batch-count: 3 findings from one reviewer spawn exactly ONE scorer" \
  '[.agents[] | select(startswith("score:"))] | length == 1' fanout-batch-count
expect "fanout-batch-count: the scorer is labelled per reviewer, not per finding" \
  '[.agents[] | select(startswith("score:"))] == ["score:bug-scan"]' fanout-batch-count
expect "fanout-batch-count: 6 agents total (5 reviewers + 1 scorer), not 8" \
  '.agents | length == 6' fanout-batch-count
expect "fanout-batch-count: batching loses no finding — all 3 scored and survive" \
  '.return.counts.raw == 3 and .return.counts.survived == 3' fanout-batch-count

# ---------------------------------------------------------------------------
# Case 10: THE MAPPING CASE. The batch scorer returns its entries in an order
# that does NOT match the order of the findings it was given. A mapping by
# array position silently attaches each score to the wrong finding, and the
# threshold then posts the wrong things on a real PR.
#
# Every assertion looks findings up BY FILE, never by position, so the test
# itself cannot inherit the bug it is hunting. scoreRationale is checked as
# well as score: it is an independent signal, so a mapping fixed for one field
# and not the other still fails here.
#
# Input order  : alpha(id 0), bravo(id 1), charlie(id 2)
# Returned order: id 2, id 0, id 1  ->  alpha 85, bravo 10, charlie 100
# Mapped by position instead: alpha 100, bravo 85, charlie 10.
# ---------------------------------------------------------------------------
cat > "$TMP/fanout-score-ids.json" <<EOF
{"args": $FARGS,
 "agent": {"default": null,
   "byLabel": {"review:bug-scan": {"findings": [
     {"file":"src/alpha.js","line":11,"description":"d-alpha","category":"bug","severity":"must-fix","reason":"r0"},
     {"file":"src/bravo.js","line":22,"description":"d-bravo","category":"bug","severity":"must-fix","reason":"r1"},
     {"file":"src/charlie.js","line":33,"description":"d-charlie","category":"bug","severity":"must-fix","reason":"r2"}],
    "degraded": false}},
   "byLabelPrefix": {"score:": {"scores": [
     {"id":2,"score":100,"rationale":"r-charlie"},
     {"id":0,"score":85,"rationale":"r-alpha"},
     {"id":1,"score":10,"rationale":"r-bravo"}]}}}}
EOF
run fanout-score-ids "$FANOUT"
expect "fanout-score-ids: alpha (id 0) keeps its own score of 85" \
  '[.return.findings[] | select(.file == "src/alpha.js")] | length == 1 and (.[0].score == 85)' fanout-score-ids
expect "fanout-score-ids: alpha keeps its own rationale" \
  '[.return.findings[] | select(.file == "src/alpha.js")][0].scoreRationale == "r-alpha"' fanout-score-ids
expect "fanout-score-ids: charlie (id 2) keeps its own score of 100" \
  '[.return.findings[] | select(.file == "src/charlie.js")] | length == 1 and (.[0].score == 100)' fanout-score-ids
expect "fanout-score-ids: charlie keeps its own rationale" \
  '[.return.findings[] | select(.file == "src/charlie.js")][0].scoreRationale == "r-charlie"' fanout-score-ids
expect "fanout-score-ids: bravo (id 1) scored 10 and is dropped" \
  '[.return.findings[] | select(.file == "src/bravo.js")] | length == 0' fanout-score-ids
expect "fanout-score-ids: 3 scored, 2 survive" \
  '.return.counts.raw == 3 and .return.counts.survived == 2' fanout-score-ids

# ---------------------------------------------------------------------------
# Case 11: the batch scorer skips a finding and invents an id that was never
# handed to it. A skipped finding scores 0 (the same as a dead scorer); an
# invented id must not conjure a finding that no reviewer raised.
#
# Given ids 0,1,2 the scorer returns only id 1 and a fabricated id 7.
# ---------------------------------------------------------------------------
cat > "$TMP/fanout-score-badids.json" <<EOF
{"args": $FARGS,
 "agent": {"default": null,
   "byLabel": {"review:bug-scan": {"findings": [
     {"file":"src/alpha.js","line":11,"description":"d-alpha","category":"bug","severity":"must-fix","reason":"r0"},
     {"file":"src/bravo.js","line":22,"description":"d-bravo","category":"bug","severity":"must-fix","reason":"r1"},
     {"file":"src/charlie.js","line":33,"description":"d-charlie","category":"bug","severity":"must-fix","reason":"r2"}],
    "degraded": false}},
   "byLabelPrefix": {"score:": {"scores": [
     {"id":1,"score":95,"rationale":"r-bravo"},
     {"id":7,"score":100,"rationale":"invented"}]}}}}
EOF
run fanout-score-badids "$FANOUT"
expect "fanout-score-badids: the one scored finding is bravo, at 95" \
  '[.return.findings[] | select(.file == "src/bravo.js")] | length == 1 and (.[0].score == 95)' fanout-score-badids
expect "fanout-score-badids: the skipped findings score 0 and drop out" \
  '[.return.findings[] | select(.file == "src/alpha.js" or .file == "src/charlie.js")] | length == 0' fanout-score-badids
expect "fanout-score-badids: the invented id 7 adds no phantom finding" \
  '.return.counts.raw == 3 and .return.counts.survived == 1' fanout-score-badids
expect "fanout-score-badids: exactly one finding is returned" \
  '(.return.findings | type) == "array" and (.return.findings | length == 1)' fanout-score-badids
# The bounds check is redundant for the LOOKUP — `byId.get(i)` walks the real
# indices, so an out-of-range key can never be read back. Its one observable
# effect is `byId.size`, which the shortfall log reports. Match the line exactly:
# drop the bounds check and the invented id 7 inflates the count, so the line
# reads "2 usable score(s)" and this assertion fails. A prefix match would not
# discriminate, because the line still fires either way.
expect "fanout-score-badids: the shortfall log counts 1 usable score, not the invented id" \
  '.logs | index("pr-review-fanout: scorer for bug-scan returned 1 usable score(s) for 3 finding(s); the rest score 0") != null' fanout-score-badids

# ---------------------------------------------------------------------------
# Case 12: blast radius. One dead scorer used to cost ONE finding; batched, it
# costs that reviewer's WHOLE list. Score them all 0 (unchanged behaviour for a
# dead scorer) and say so in degradedReviewers, so the loss is not silent.
# ---------------------------------------------------------------------------
cat > "$TMP/fanout-scorer-dead.json" <<EOF
{"args": $FARGS,
 "agent": {"default": null,
   "byLabel": {"review:bug-scan": {"findings": [
     {"file":"src/p.js","line":5,"description":"d0","category":"bug","severity":"must-fix","reason":"r0"},
     {"file":"src/q.js","line":6,"description":"d1","category":"bug","severity":"must-fix","reason":"r1"}],
    "degraded": false}}}}
EOF
run fanout-scorer-dead "$FANOUT"
expect "fanout-scorer-dead: NO error field (the reviewer itself lived)" \
  '.return | has("error") | not' fanout-scorer-dead
expect "fanout-scorer-dead: exactly one scorer was attempted" \
  '[.agents[] | select(startswith("score:"))] | length == 1' fanout-scorer-dead
expect "fanout-scorer-dead: both findings scored 0, so none survives" \
  '.return.counts.raw == 2 and .return.counts.survived == 0' fanout-scorer-dead
expect "fanout-scorer-dead: the reviewer is recorded as degraded, verbatim" \
  '.return.degradedReviewers | index("bug-scan (scorer returned no result; its findings scored 0)") != null' fanout-scorer-dead

# ---------------------------------------------------------------------------
# Case 13: the survival threshold is an ABSOLUTE cut-off at 80 and batching
# must not move it. 80 survives; 79 does not.
# ---------------------------------------------------------------------------
cat > "$TMP/fanout-threshold.json" <<EOF
{"args": $FARGS,
 "agent": {"default": null,
   "byLabel": {"review:bug-scan": {"findings": [
     {"file":"src/at-eighty.js","line":1,"description":"d0","category":"bug","severity":"must-fix","reason":"r0"},
     {"file":"src/at-seventynine.js","line":2,"description":"d1","category":"bug","severity":"must-fix","reason":"r1"}],
    "degraded": false}},
   "byLabelPrefix": {"score:": {"scores": [
     {"id":0,"score":80,"rationale":"exactly at the cut-off"},
     {"id":1,"score":79,"rationale":"one below the cut-off"}]}}}}
EOF
run fanout-threshold "$FANOUT"
expect "fanout-threshold: a finding scored 80 survives" \
  '[.return.findings[] | select(.file == "src/at-eighty.js")] | length == 1 and (.[0].score == 80)' fanout-threshold
expect "fanout-threshold: a finding scored 79 does not survive" \
  '[.return.findings[] | select(.file == "src/at-seventynine.js")] | length == 0' fanout-threshold
expect "fanout-threshold: 2 scored, 1 survives" \
  '.return.counts.raw == 2 and .return.counts.survived == 1' fanout-threshold

# ---------------------------------------------------------------------------
# Case 14: the batch scorer returns TWO entries for the SAME id, with different
# scores. Only one can win, and the documented contract is that the FIRST one
# does — `if (byId.has(s.id)) continue`. Drop that line and `byId.set` overwrites,
# so the LAST entry wins instead. Here that flips alpha from posted to dropped.
#
# alpha (id 0) is scored twice: 95 first, then 10. bravo (id 1) is scored once,
# at 90, and is the control — a duplicate must not disturb its neighbour.
#   first wins (correct): alpha 95 survives, bravo 90 survives -> 2 survive
#   last wins  (broken) : alpha 10 dropped,  bravo 90 survives -> 1 survives
# ---------------------------------------------------------------------------
cat > "$TMP/fanout-score-dupids.json" <<EOF
{"args": $FARGS,
 "agent": {"default": null,
   "byLabel": {"review:bug-scan": {"findings": [
     {"file":"src/alpha.js","line":11,"description":"d-alpha","category":"bug","severity":"must-fix","reason":"r0"},
     {"file":"src/bravo.js","line":22,"description":"d-bravo","category":"bug","severity":"must-fix","reason":"r1"}],
    "degraded": false}},
   "byLabelPrefix": {"score:": {"scores": [
     {"id":0,"score":95,"rationale":"r-alpha-first"},
     {"id":0,"score":10,"rationale":"r-alpha-second"},
     {"id":1,"score":90,"rationale":"r-bravo"}]}}}}
EOF
run fanout-score-dupids "$FANOUT"
expect "fanout-score-dupids: alpha takes the FIRST duplicate's score of 95, not the second's 10" \
  '[.return.findings[] | select(.file == "src/alpha.js")] | length == 1 and (.[0].score == 95)' fanout-score-dupids
# scoreRationale is an independent signal: a fix that keeps the first score but
# the second rationale still fails here.
expect "fanout-score-dupids: alpha takes the FIRST duplicate's rationale" \
  '[.return.findings[] | select(.file == "src/alpha.js")][0].scoreRationale == "r-alpha-first"' fanout-score-dupids
expect "fanout-score-dupids: the control finding bravo is untouched at 90" \
  '[.return.findings[] | select(.file == "src/bravo.js")] | length == 1 and (.[0].score == 90)' fanout-score-dupids
expect "fanout-score-dupids: 2 scored, both survive" \
  '.return.counts.raw == 2 and .return.counts.survived == 2' fanout-score-dupids

echo "---"; echo "pass=$pass fail=$fail"
[ "$fail" -eq 0 ]
