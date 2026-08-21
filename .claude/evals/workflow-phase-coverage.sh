#!/usr/bin/env bash
# workflow-phase-coverage.sh — the phase names a workflow DECLARES must be the
# phase names it USES.
#
# Why: `meta.phases` drives the progress tree the user watches; `phase: '...'`
# on an agent() call is what assigns that agent to a group. Nothing reconciles
# the two. A typo in either direction is silent: an agent carrying an undeclared
# phase gets its own unlabelled group, and a declared-but-unused phase renders an
# empty box that never fills. Neither raises, and both survive every other gate,
# so the workflow looks like it ran a stage it never ran. That failure is
# invisible in exactly the situation the phase list exists for.
#
# Contract (.claude/evals/README.md):
#   exit 0 PASS / 1 FAIL / 2 SKIP
#   last stdout line: `EVAL workflow-phase-coverage: PASS|FAIL|SKIP — <detail>`
#
# Scope: single-quoted `title:` inside the meta.phases array, and single-quoted
# `phase:` anywhere in the file. Both are the form every workflow in this repo
# uses; a workflow that switches quote style is out of scope by design rather
# than by accident, because the meta block must stay a pure literal anyway.
#
# Sibling harness: workflow-phase-coverage_test.sh (the runner excludes *_test.sh).
set -uo pipefail

NAME="workflow-phase-coverage"

# Resolve the subject from THIS script's directory, never from $HOME: a
# $HOME/.claude/... default grades the DEPLOYED copy, so a repo regression stays
# green and the harness green-lights the wrong artifact.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
SUBJECT="${EVAL_SUBJECT:-$REPO_DIR/.claude/workflows}"
SUBJECT="${SUBJECT%/}"

if [ ! -e "$SUBJECT" ]; then
  echo "EVAL $NAME: SKIP — subject not found ($SUBJECT)"
  exit 2
fi
if [ ! -d "$SUBJECT" ]; then
  echo "EVAL $NAME: SKIP — subject is not a directory ($SUBJECT)"
  exit 2
fi

# Declared: title: values, but ONLY inside the meta.phases array. A bare
# file-wide grep for `title:` also collects schema descriptions and prompt text.
declared_of() {
  sed -n "/phases:[[:space:]]*\[/,/^[[:space:]]*\][,]*[[:space:]]*$/p" "$1" \
    | grep -o "title: '[^']*'" | sed "s/title: '//;s/'\$//" | sort -u
}
# Used: phase: values anywhere, which is where agent() calls carry them.
used_of() {
  grep -o "phase: '[^']*'" "$1" | sed "s/phase: '//;s/'\$//" | sort -u
}

scanned=0
while IFS= read -r js; do
  [ -z "$js" ] && continue
  scanned=$((scanned + 1))
  rel="${js#"$SUBJECT"/}"
  declared="$(declared_of "$js")"
  used="$(used_of "$js")"

  # A workflow with neither is a plain script, not a phased one: nothing to check.
  if [ -z "$declared" ] && [ -z "$used" ]; then
    continue
  fi

  undeclared="$(comm -13 <(printf '%s\n' "$declared") <(printf '%s\n' "$used") | grep -c .)"
  unused="$(comm -23 <(printf '%s\n' "$declared") <(printf '%s\n' "$used") | grep -c .)"

  if [ "${undeclared:-0}" -ne 0 ]; then
    first="$(comm -13 <(printf '%s\n' "$declared") <(printf '%s\n' "$used") | head -1)"
    echo "EVAL $NAME: FAIL — $rel uses phase '$first' but meta.phases does not declare it; that agent renders in its own unlabelled group"
    exit 1
  fi
  if [ "${unused:-0}" -ne 0 ]; then
    first="$(comm -23 <(printf '%s\n' "$declared") <(printf '%s\n' "$used") | head -1)"
    echo "EVAL $NAME: FAIL — $rel declares phase '$first' but no agent call uses it; that stage renders as a box that never fills"
    exit 1
  fi
done < <(find "$SUBJECT" -type f \( -name '*.js' -o -name '*.mjs' \) | sort)

# An empty result set is not evidence of absence: without this the eval reports
# PASS forever once the workflows move or change extension.
if [ "$scanned" -eq 0 ]; then
  echo "EVAL $NAME: FAIL — no .js or .mjs file under $SUBJECT; the scan would pass vacuously"
  exit 1
fi

echo "EVAL $NAME: PASS — scanned $scanned .js/.mjs files; declared and used phase names agree in every one"
exit 0
