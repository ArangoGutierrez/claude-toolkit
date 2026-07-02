#!/usr/bin/env bash
# probe_test.sh — probe.sh against the fake-claude double (activate/silent/error).
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
cat > "$tmp/evals.json" <<'JSON'
{ "skill":"kickoff","cases":[
  {"id":"a","prompt":"please ACT now","expect":"activate"},
  {"id":"s","prompt":"just chatting","expect":"silent"},
  {"id":"e","prompt":"ERRCASE boom","expect":"activate"},
  {"id":"t","prompt":"TURNLIMIT please","expect":"activate"} ] }
JSON
out=$(CLAUDE_BIN="$here/fixtures/fake-claude.sh" "$here/probe.sh" kickoff "$tmp/evals.json" 3 "$tmp")
[ "$(jq -c '.cases[]|select(.id=="a").runs' <<<"$out")" = '[["kickoff"],["kickoff"],["kickoff"]]' ] || { echo "FAIL a: $out"; exit 1; }
[ "$(jq -c '.cases[]|select(.id=="s").runs' <<<"$out")" = '[[],[],[]]' ]             || { echo "FAIL s: $out"; exit 1; }
[ "$(jq -c '.cases[]|select(.id=="e").runs' <<<"$out")" = '[null,null,null]' ]        || { echo "FAIL e: $out"; exit 1; }
# t: exit-1-WITH-output (--max-turns 1) must still extract, not be recorded null.
# This discriminates an output-presence gate from a (broken) exit-code gate.
[ "$(jq -c '.cases[]|select(.id=="t").runs' <<<"$out")" = '[["kickoff"],["kickoff"],["kickoff"]]' ] || { echo "FAIL t: $out"; exit 1; }
echo "PASS probe_test"
