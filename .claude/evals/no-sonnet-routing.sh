#!/usr/bin/env bash
# no-sonnet-routing.sh — guards the model values in .claude/workflows/*.js.
#
# Why: the bare alias `sonnet` resolves to a model this workspace rate-limits to
# 0 requests per minute, so every dispatch that pins it returns HTTP 429. The
# routing tables dropped that tier. No gate reads a model value, so a future
# `model: 'sonnet'` passes every check and brings the outage back.
# rules/constitution.md requires an executable check with such a fix.
#
# Contract (.claude/evals/README.md):
#   exit 0 PASS / 1 FAIL / 2 SKIP
#   last stdout line: `EVAL no-sonnet-routing: PASS|FAIL|SKIP — <detail>`
#
# Scope: the QUOTED literal only, and only under .claude/workflows/. Two
# workflows carry a routing COMMENT that names Sonnet on purpose, to record why
# the tier is absent. A word-level grep flags those comments and makes this eval
# a false alarm. The docs name the alias legitimately too, so they stay out of
# scope.
#
# Within that scope the match is wide: all 3 JavaScript quote characters
# (single, double, backtick) and any capitalisation, over .js and .mjs files. A
# narrower match let `model: `sonnet``, `model: 'Sonnet'` and a .mjs file slip
# through.
#
# Sibling harness: no-sonnet-routing_test.sh (the runner excludes *_test.sh).
set -uo pipefail

NAME="no-sonnet-routing"

# Resolve the default subject from THIS script's directory, never from $HOME. A
# $HOME/.claude/... default grades the DEPLOYED copy, so a regression in the repo
# stays green and the harness green-lights the wrong artifact. EVAL_SUBJECT lets
# the sibling harness point the eval at a fixture.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
SUBJECT="${EVAL_SUBJECT:-$REPO_DIR/.claude/workflows}"
SUBJECT="${SUBJECT%/}"

# Not applicable here -> SKIP, never FAIL. A SKIP keeps the weekly run green
# while making it obvious the check did not run.
if [ ! -e "$SUBJECT" ]; then
  echo "EVAL $NAME: SKIP — subject not found ($SUBJECT)"
  exit 2
fi
if [ ! -d "$SUBJECT" ]; then
  echo "EVAL $NAME: SKIP — subject is not a directory ($SUBJECT)"
  exit 2
fi

# The character class holds the 3 JavaScript quote characters: " ' and `. The
# pattern is the whole assertion: the alias between two of them, i.e. a VALUE a
# workflow would hand to the Agent model field. -i covers `Sonnet`. The quotes
# are what keep the routing comments tolerated.
QUOTE_CLASS="[\"'\`]"
scanned=0
while IFS= read -r js; do
  [ -z "$js" ] && continue
  scanned=$((scanned + 1))
  hit="$(grep -n -i -E -- "${QUOTE_CLASS}sonnet${QUOTE_CLASS}" "$js" | head -1)"
  if [ -n "$hit" ]; then
    echo "EVAL $NAME: FAIL — quoted sonnet literal in ${js#"$SUBJECT"/} line ${hit%%:*}; the bare alias is rate-limited to 0 rpm, so pin opus or haiku"
    exit 1
  fi
done < <(find "$SUBJECT" -type f \( -name '*.js' -o -name '*.mjs' \) | sort)

# A subject with no script file makes the scan vacuous: the eval would report
# PASS forever once the workflows move or change extension. An empty result set
# is not evidence of absence.
if [ "$scanned" -eq 0 ]; then
  echo "EVAL $NAME: FAIL — no .js or .mjs file under $SUBJECT; the scan would pass vacuously"
  exit 1
fi

echo "EVAL $NAME: PASS — scanned $scanned .js/.mjs files; no quoted sonnet literal"
exit 0
