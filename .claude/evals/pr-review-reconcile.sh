#!/bin/bash
# pr-review-reconcile.sh - guard the Reconcile phase's invariants.
set -uo pipefail
cd "$(dirname "$0")"
WF="../workflows/pr-review-fanout.js"
fails=0
check() {  # check <description> <pattern>
    if grep -q "$2" "$WF"; then
        echo "ok: $1"
    else
        echo "FAIL: $1 (pattern: $2)"
        fails=$((fails + 1))
    fi
}

node --check "$WF" || { echo "FAIL: workflow does not parse"; exit 1; }

check "Reconcile is a declared phase" "title: 'Reconcile'"
check "novel claims are score-gated at 80" "score < 80"
check "contradictions require concrete=true" "c.concrete === true"
check "corroboration is bounds-checked by index" "c.findingIndex >= finalFindings.length"
check "bot text is marked untrusted" "UNTRUSTED EXTERNAL INPUT"
check "the no-post clause reaches reconcile prompts" "NO_POST_CLAUSE}"

# The phase must be skippable: a PR with no bot comments reviews as before.
check "reconcile is gated on aiCommentsPath" "if (aiCommentsPath)"

if [ "$fails" -gt 0 ]; then
    echo "pr-review-reconcile: $fails invariant(s) broken"
    exit 1
fi
echo "pr-review-reconcile: all invariants hold"
