#!/usr/bin/env bash
# extract_test.sh — verify extract.jq against representative SYNTHETIC claude transcripts.
# NOTE: fixtures are hand-authored, not real session captures. Never commit real
# `claude --print` output here — it leaks cwd, MCP servers, skill inventory, and UUIDs.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
act=$(jq -s -f "$here/extract.jq" "$here/fixtures/claude-run-activate.jsonl")
sil=$(jq -s -f "$here/extract.jq" "$here/fixtures/claude-run-silent.jsonl")
# activate capture must surface exactly the routed skill; silent must surface none
[ "$(jq 'length' <<<"$act")" -ge 1 ]    || { echo "FAIL: activate extracted nothing: $act"; exit 1; }
[ "$(jq -r '.[0]' <<<"$act")" = "day" ] || { echo "FAIL: activate want day, got: $act"; exit 1; }
[ "$(jq 'length' <<<"$sil")" -eq 0 ]    || { echo "FAIL: silent extracted skills: $sil"; exit 1; }
echo "PASS extract_test"
