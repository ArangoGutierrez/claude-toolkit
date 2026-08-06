#!/bin/bash
# report-style-deployed.sh — the report-style rule must exist in the repo AND be
# live in ~/.claude, with its load-bearing clauses intact in BOTH.
#
# 2026-08-06: the rule was cut from a 69-line ASD-STE100 digest to a 9-clause
# density directive (config audit; ~505 tokens of every-session context saved).
# The clause list below tracks that rewrite. The guard's shape is unchanged.
#
# Guards three regressions:
#   1. a deploy that drops rules/report-style.md
#   2. an edit that guts the scope block, the writing rules, the sentence
#      limits, the preferred-word table, or the copyright disclaimer
#   3. a semantically INVERTED scope block, which leaves the section markers in
#      place while turning the rule off
#
# It checks the repo copy as well as the live copy. Checking only the live copy
# hid the most likely case: you edit the repo file and run the evals before you
# deploy, so the guard reads a stale live copy and reports PASS.
#
# It does NOT read the agent's prose. The subject of this check is the file.
#
# Contract: exit 0 PASS / 1 FAIL / 2 SKIP; last stdout line:
#   EVAL report-style-deployed: PASS|FAIL|SKIP — <detail>
# Spec: docs/superpowers/specs/2026-07-28-ste100-report-style-design.md
set -o pipefail

NAME="report-style-deployed"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_RULE="$SCRIPT_DIR/../rules/report-style.md"
LIVE_RULE="${EVAL_SUBJECT:-$HOME/.claude/rules/report-style.md}"

# Load-bearing clauses, matched as exact literals with grep -F. These pin
# MEANING, not section markers: delete the scope text, the writing-rule
# bullets, either limit, the table rows, or the copyright line and this eval
# goes red. A file that keeps only its headings is not the rule.
read_literals() {
  cat <<'LITERALS'
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
}

LITERAL_COUNT=9

# $1 = file to inspect, $2 = label used in the detail text.
# Appends to $missing and increments $count in the caller's shell.
check_file() {
  local f="$1" label="$2" lit
  while IFS= read -r lit; do
    [ -z "$lit" ] && continue
    if ! grep -qF -- "$lit" "$f"; then
      missing="$missing[$label: $lit] "
      count=$((count + 1))
    fi
  done < <(read_literals)
}

# --- The repo copy. Absent means a real regression -> FAIL. ---
if [ ! -f "$REPO_RULE" ]; then
  echo "EVAL $NAME: FAIL — repo rule missing: $REPO_RULE"
  exit 1
fi

# --- The live copy. Absent means "not deployed yet" -> SKIP. ---
if [ ! -f "$LIVE_RULE" ]; then
  echo "EVAL $NAME: SKIP — live rule not deployed: $LIVE_RULE"
  exit 2
fi

missing=""
count=0
check_file "$REPO_RULE" "repo"
check_file "$LIVE_RULE" "live"

if [ "$count" -ne 0 ]; then
  echo "EVAL $NAME: FAIL — $count clause(s) lost: $missing"
  exit 1
fi

echo "EVAL $NAME: PASS — $LITERAL_COUNT clauses intact in repo and live ($LIVE_RULE)"
exit 0
