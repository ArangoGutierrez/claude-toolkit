#!/bin/bash
# run-evals_test.sh — fixture harness for scripts/run-evals.sh
#
# run-evals.sh resolves REPO from its OWN location (SCRIPT_DIR/..), not from
# an env override. To fixture REPO, each case copies the real runner into a
# fake REPO/scripts/ dir next to a fake REPO/.claude/evals/ directory of stub
# eval scripts, then invokes that copy.
#
# ok() below cannot fail, so each `[ test ] && ok || fail ...` is a safe
# if-then-else (the fail branch runs only on a real assertion failure).
# shellcheck disable=SC2015
set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
RUNNER_SRC="$SCRIPT_DIR/run-evals.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

PASS=0
FAIL=0
ok()   { PASS=$((PASS + 1)); }
fail() { echo "FAIL: $1"; [ -n "${2:-}" ] && echo "  $2"; FAIL=$((FAIL + 1)); }

assert_fgrep() { if grep -qF -- "$2" "$3"; then ok; else fail "$1" "missing: $2 (got: $(cat "$3"))"; fi; }

build_repo() {
  local repo="$1"
  mkdir -p "$repo/scripts" "$repo/.claude/evals"
  cp "$RUNNER_SRC" "$repo/scripts/run-evals.sh"
  chmod +x "$repo/scripts/run-evals.sh"
}

write_eval() {
  # $1 = repo  $2 = filename  $3 = verdict word (PASS|FAIL|SKIP)  $4 = exit code
  local repo="$1" fname="$2" verdict="$3" rc="$4"
  cat > "$repo/.claude/evals/$fname" <<EVALSCRIPT
#!/bin/bash
echo "EVAL ${fname%.sh}: ${verdict} — fixture"
exit ${rc}
EVALSCRIPT
  chmod +x "$repo/.claude/evals/$fname"
}

# ============ Case 1: all pass ============
R1="$TMP/repo1"
build_repo "$R1"
write_eval "$R1" "a-eval.sh" "PASS" 0
write_eval "$R1" "b-eval.sh" "PASS" 0
OUT1="$TMP/case1.out"
bash "$R1/scripts/run-evals.sh" > "$OUT1" 2>&1
rc=$?
[ "$rc" -eq 0 ] && ok || fail "case1: all-pass exits 0" "rc=$rc $(cat "$OUT1")"
assert_fgrep "case1: summary line" "EVALS: 2/2 pass, 0 fail, 0 skip" "$OUT1"

# ============ Case 2: one fail ============
R2="$TMP/repo2"
build_repo "$R2"
write_eval "$R2" "a-eval.sh" "PASS" 0
write_eval "$R2" "b-eval.sh" "FAIL" 1
write_eval "$R2" "c-eval.sh" "PASS" 0
OUT2="$TMP/case2.out"
bash "$R2/scripts/run-evals.sh" > "$OUT2" 2>&1
rc=$?
[ "$rc" -eq 1 ] && ok || fail "case2: one-fail exits 1" "rc=$rc $(cat "$OUT2")"
assert_fgrep "case2: summary line" "EVALS: 2/3 pass, 1 fail, 0 skip" "$OUT2"
assert_fgrep "case2: fail verdict line surfaced" "EVAL b-eval: FAIL" "$OUT2"

# ============ Case 3: skip does not fail the run ============
R3="$TMP/repo3"
build_repo "$R3"
write_eval "$R3" "a-eval.sh" "PASS" 0
write_eval "$R3" "b-eval.sh" "SKIP" 2
OUT3="$TMP/case3.out"
bash "$R3/scripts/run-evals.sh" > "$OUT3" 2>&1
rc=$?
[ "$rc" -eq 0 ] && ok || fail "case3: skip-not-fail exits 0" "rc=$rc $(cat "$OUT3")"
assert_fgrep "case3: summary line" "EVALS: 1/2 pass, 0 fail, 1 skip" "$OUT3"

# ============ Case 4: *_test.sh helper is excluded ============
R4="$TMP/repo4"
build_repo "$R4"
write_eval "$R4" "a-eval.sh" "PASS" 0
cat > "$R4/.claude/evals/a-eval_test.sh" <<'HELPER'
#!/bin/bash
echo "EVAL a-eval_test: FAIL — this must never run from the runner"
exit 1
HELPER
chmod +x "$R4/.claude/evals/a-eval_test.sh"
OUT4="$TMP/case4.out"
bash "$R4/scripts/run-evals.sh" > "$OUT4" 2>&1
rc=$?
[ "$rc" -eq 0 ] && ok || fail "case4: *_test.sh excluded, exits 0" "rc=$rc $(cat "$OUT4")"
assert_fgrep "case4: summary line" "EVALS: 1/1 pass, 0 fail, 0 skip" "$OUT4"
if grep -qF "a-eval_test" "$OUT4"; then
  fail "case4: *_test.sh helper was NOT executed" "found a-eval_test output"
else
  ok
fi

# ============ Case 5: unexpected exit code is treated as a FAIL ============
R5="$TMP/repo5"
build_repo "$R5"
write_eval "$R5" "a-eval.sh" "PASS" 0
write_eval "$R5" "b-eval.sh" "WEIRD" 3
OUT5="$TMP/case5.out"
bash "$R5/scripts/run-evals.sh" > "$OUT5" 2>&1
rc=$?
[ "$rc" -eq 1 ] && ok || fail "case5: unexpected rc treated as FAIL, runner exits 1" "rc=$rc $(cat "$OUT5")"
assert_fgrep "case5: summary line" "EVALS: 1/2 pass, 1 fail, 0 skip" "$OUT5"

echo ""
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ] || exit 1
