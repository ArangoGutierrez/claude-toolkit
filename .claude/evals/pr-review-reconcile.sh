#!/bin/bash
# pr-review-reconcile.sh - guard the Reconcile phase's invariants.
set -uo pipefail
cd "$(dirname "$0")"
WF="../workflows/pr-review-fanout.js"
# The house verdict line (.claude/evals/README.md) is the LAST stdout line on every
# exit path. run-evals.sh keys on the exit code alone, so the line is for the human
# reading a red weekly run; the README spells it with an em dash, which this repo's
# ai-tell-guard forbids, so it is written with a hyphen.
NAME="pr-review-reconcile"
fails=0
check() {  # check <description> <pattern>
    if grep -q "$2" "$WF"; then
        echo "ok: $1"
    else
        echo "FAIL: $1 (pattern: $2)"
        fails=$((fails + 1))
    fi
}

# Parse gate. `node --check` CANNOT do this job, in both directions: it is inert on
# any file Node detects as ESM (on v26 a file with a stray `export` and an unbalanced
# paren still exits 0), and it would also false-fail a valid workflow, whose
# top-level return is illegal in plain ESM. Compile the body as an AsyncFunction
# instead, which is the context the Workflow tool actually runs it in and exactly what
# scripts/check-workflow-syntax.sh does. Scoped to this one workflow on purpose: that
# script checks every workflow, so reusing it would turn this eval red for an
# unrelated file.
if ! node -e '
      const fs = require("fs");
      const src = fs.readFileSync(process.argv[1], "utf8");
      if (!/^export const meta = \{/m.test(src)) {
        console.error("missing `export const meta = {` literal");
        process.exit(1);
      }
      const body = src.replace(/^export const meta/m, "const meta");
      const AsyncFunction = Object.getPrototypeOf(async function () {}).constructor;
      new AsyncFunction("agent", "pipeline", "parallel", "log", "phase", "args", "budget", "workflow", body);
    ' "$WF"; then
    echo "EVAL $NAME: FAIL - $WF does not compile; its invariants cannot be trusted"
    exit 1
fi

check "Reconcile is a declared phase" "title: 'Reconcile'"
check "novel claims are score-gated at 80" "score < 80"
check "contradictions require concrete=true" "c.concrete === true"
check "corroboration is bounds-checked by index" "c.findingIndex >= finalFindings.length"
check "bot text is marked untrusted" "UNTRUSTED EXTERNAL INPUT"
check "the no-post clause reaches reconcile prompts" "NO_POST_CLAUSE}"

# The phase must be skippable: a PR with no bot comments reviews as before.
check "reconcile is gated on aiCommentsPath" "if (aiCommentsPath)"

# The corroborated count must derive from what was ATTACHED. Counting the agent's
# returned array instead over-reports corroboration in the operator's summary
# whenever the bounds check above rejects an index.
check "the corroborated count derives from attachments" "corroborated: corroboratedIndices.size"

# The replies route accepts a top-level review comment id only, which is what the
# `inline` surface returns. A comment id with no surface beside it cannot be told
# apart from an issue-comment or review id, so the reply loop 404s after the
# review has already posted. Both lists carry it: replies may be written for a
# corroboration as well as for a contradiction.
check "contradicted records require their surface" \
  "required: \['reviewer', 'commentId', 'surface', 'claim', 'refutation', 'concrete'\]"
check "corroborated records require their surface" \
  "required: \['findingIndex', 'reviewer', 'commentId', 'surface'\]"
check "the attached corroboration carries the surface through" "surface: c.surface"

if [ "$fails" -gt 0 ]; then
    echo "EVAL $NAME: FAIL - $fails Reconcile invariant(s) broken (see the FAIL lines above)"
    exit 1
fi
echo "EVAL $NAME: PASS - all 11 Reconcile invariants hold"
