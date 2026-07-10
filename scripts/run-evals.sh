#!/usr/bin/env bash
# run-evals.sh — executes every .claude/evals/*.sh (sorted, excluding
# *_test.sh helpers), prints each eval's verdict line, and summarizes.
# Exit 1 iff any eval FAILed; SKIPs never fail the run.
#
# Each eval is self-contained: exit 0 PASS / 1 FAIL / 2 SKIP, last stdout
# line `EVAL <name>: PASS|FAIL|SKIP — <detail>`. An eval exiting with any
# other code is treated as a FAIL (a crash is not a pass).
#
# Convention: .claude/evals/README.md
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$SCRIPT_DIR/.." && pwd)"
EVALS_DIR="$REPO/.claude/evals"

pass=0
fail=0
skip=0

if [ -d "$EVALS_DIR" ]; then
  while IFS= read -r eval_script; do
    [ -z "$eval_script" ] && continue
    bash "$eval_script"
    rc=$?
    case "$rc" in
      0) pass=$((pass + 1)) ;;
      1) fail=$((fail + 1)) ;;
      2) skip=$((skip + 1)) ;;
      *)
        echo "run-evals: $(basename "$eval_script") exited unexpected rc=$rc (treated as FAIL)" >&2
        fail=$((fail + 1))
        ;;
    esac
  done < <(find "$EVALS_DIR" -maxdepth 1 -type f -name '*.sh' ! -name '*_test.sh' | sort)
else
  echo "run-evals: no evals directory at $EVALS_DIR" >&2
fi

total=$((pass + fail + skip))
echo "EVALS: ${pass}/${total} pass, ${fail} fail, ${skip} skip"

[ "$fail" -eq 0 ]
