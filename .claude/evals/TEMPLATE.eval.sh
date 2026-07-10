#!/usr/bin/env bash
# TEMPLATE.eval.sh — copy me to <your-check>.eval.sh and fill in the blanks.
#
# An eval is ONE executable check that fails (exit 1) when a specific
# regression is reintroduced, and passes (exit 0) otherwise. See
# .claude/evals/README.md for the full convention.
#
# Contract this skeleton implements:
#   - exit 0  -> PASS   (the guarded regression is absent)
#   - exit 1  -> FAIL   (the regression is present; run-evals.sh returns 1)
#   - exit 2  -> SKIP   (cannot run here; never fails the run)
#   - last stdout line: `EVAL <name>: PASS|FAIL|SKIP — <detail>`
#
# As shipped, this template is discovered by run-evals.sh but SKIPs (its
# SUBJECT placeholder does not resolve), so an uncustomized copy never turns
# the weekly run red. Point SUBJECT at a real artifact to activate it.
set -uo pipefail

# Short identifier for this eval; appears in the verdict line.
NAME="template"

# --- Probe-subject resolution (with env override) ----------------------------
# SUBJECT is the artifact this eval inspects. The EVAL_SUBJECT override lets a
# sibling <name>_test.sh point the eval at a fixture copy instead of the live
# artifact, so the eval itself can be tested. Replace the default below with
# the real path (e.g. "$HOME/.claude/hooks/your-hook.sh").
SUBJECT="${EVAL_SUBJECT:-$HOME/.claude/REPLACE_ME}"

# Unconfigured / not-applicable here -> SKIP, do not FAIL. A SKIP keeps the
# weekly run green while making it obvious the check did not actually run.
if [ ! -e "$SUBJECT" ]; then
  echo "EVAL $NAME: SKIP — subject not found ($SUBJECT); copy this template and set SUBJECT/EVAL_SUBJECT"
  exit 2
fi

# --- Fixture setup (hermetic; mktemp) ----------------------------------------
# Work on a COPY in a throwaway dir; never mutate the live artifact.
WORK="$(mktemp -d)"
# shellcheck disable=SC2329  # invoked indirectly via the EXIT trap below.
cleanup() { rm -rf "$WORK"; }   # explicit path only — never a glob (a failed
trap cleanup EXIT               # glob would abort the whole rm and leak temp).
cp "$SUBJECT" "$WORK/subject"

# --- Discriminating assertion ------------------------------------------------
# The check MUST flip when its guarded regression is reintroduced. Derive the
# expected condition by a path INDEPENDENT of the implementation (grep for the
# exact token, count the exact rows, diff against a known-good literal) — a
# check that re-derives the implementation's own logic asserts nothing, and a
# check that only asserts "an error occurred" stays green when it errors for an
# unrelated reason. Emit a FAIL detail that names the specific regression.
#
# Worked example (replace with your own guard): this eval regresses if the
# subject ever stops pinning strict mode. Swap the pattern and the messages.
if ! grep -q 'set -euo pipefail' "$WORK/subject"; then
  echo "EVAL $NAME: FAIL — subject no longer pins 'set -euo pipefail' (strict mode dropped)"
  exit 1
fi

echo "EVAL $NAME: PASS — subject pins 'set -euo pipefail'"
exit 0
