#!/usr/bin/env bash
# score_test.sh — table-driven test of score.jq over a normalized-results fixture.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
out=$(jq --argjson pass 0.6 --argjson decoy 0.2 -f "$here/score.jq" "$here/fixtures/normalized-sample.json")
check(){ local id="$1" key="$2" want="$3" got
  got=$(jq -r --arg id "$id" --arg k "$key" '.cases[]|select(.id==$id)|.[$k]|tostring' <<<"$out")
  [ "$got" = "$want" ] || { echo "FAIL $id.$key: got=$got want=$want"; exit 1; }; }
# verdicts derived independently: 4/5=.8>=.6 PASS; 2/5=.4<.6 FAIL; 0/5 PASS; 2/5=.4>.2 FAIL; n=0 ERROR
check pos-strong     verdict PASS
check pos-borderline verdict FAIL
check decoy-clean    verdict PASS
check decoy-fires    verdict FAIL
check all-error      verdict ERROR
[ "$(jq '.summary.pass'  <<<"$out")" = 2 ] || { echo "FAIL summary.pass";  exit 1; }
[ "$(jq '.summary.fail'  <<<"$out")" = 2 ] || { echo "FAIL summary.fail";  exit 1; }
[ "$(jq '.summary.error' <<<"$out")" = 1 ] || { echo "FAIL summary.error"; exit 1; }
echo "PASS score_test"
