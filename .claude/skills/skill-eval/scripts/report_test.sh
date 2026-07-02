#!/usr/bin/env bash
# report_test.sh — golden-ish test of report.sh over a known scores array.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
# capture rc explicitly — report.sh exits 1 when FAILs are present, which would
# trip this test's own `set -e` if the call were not guarded:
set +e; md=$("$here/report.sh" "$here/fixtures/scores-sample.json"); rc=$?; set -e
grep -q "pos-strong" <<<"$md"               || { echo "FAIL: missing case row";  exit 1; }
grep -q "2 pass, 2 fail, 1 error" <<<"$md"  || { echo "FAIL: totals line: $md";   exit 1; }
[ "$rc" -eq 1 ]                             || { echo "FAIL: exit want 1 got $rc"; exit 1; }
echo "PASS report_test"
