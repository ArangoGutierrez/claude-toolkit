#!/usr/bin/env bash
# Tests for graphify-install.sh — installs the graphify hook+rule+settings entries
# into a target Claude config dir, idempotently, preserving existing hooks.
set -uo pipefail
SCRIPT="$(cd "$(dirname "$0")" && pwd)/graphify-install.sh"
SOURCE="$(cd "$(dirname "$0")/.." && pwd)/.claude"   # real toolkit .claude (read-only source)
fails=0
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
pass(){ echo "ok: $1"; }; fail(){ echo "FAIL: $1"; fails=$((fails+1)); }

# Fake target home with PRE-EXISTING hooks that MUST be preserved.
mkdir -p "$tmp/hooks" "$tmp/rules"
cat > "$tmp/settings.json" <<'JSON'
{
  "hooks": {
    "PreToolUse": [
      { "matcher": "Bash", "hooks": [ { "type": "command", "command": "$HOME/.claude/hooks/sign-commits.sh", "if": "Bash(git commit *)" } ] }
    ],
    "Stop": [
      { "matcher": "", "hooks": [ { "type": "command", "command": "$HOME/.claude/hooks/verify-gate.sh" } ] }
    ]
  }
}
JSON

out="$(bash "$SCRIPT" --target "$tmp" --source "$SOURCE" 2>&1)"; rc=$?
{ [ "$rc" -eq 0 ]; } && pass "install rc=0" || fail "install rc=$rc ($out)"
{ [ -x "$tmp/hooks/graphify-graph-hint.sh" ]; } && pass "hook installed+exec" || fail "hook missing/not exec"
{ [ -f "$tmp/rules/graphify.md" ]; } && pass "rule installed" || fail "rule missing"
jq -e . "$tmp/settings.json" >/dev/null 2>&1 && pass "valid JSON" || fail "invalid JSON"

gb=$(jq '[.hooks.PreToolUse[] | select(.matcher=="Bash")      | .hooks[].command | select(test("graphify-graph-hint"))] | length' "$tmp/settings.json")
gg=$(jq '[.hooks.PreToolUse[] | select(.matcher=="Glob|Grep") | .hooks[].command | select(test("graphify-graph-hint"))] | length' "$tmp/settings.json")
{ [ "$gb" -ge 1 ]; } && pass "registered on Bash" || fail "not on Bash (gb=$gb)"
{ [ "$gg" -ge 1 ]; } && pass "registered on Glob|Grep" || fail "not on Glob|Grep (gg=$gg)"

jq -e '[.hooks.PreToolUse[].hooks[].command] | any(test("sign-commits"))' "$tmp/settings.json" >/dev/null && pass "sign-commits preserved" || fail "sign-commits dropped"
jq -e '[.hooks.Stop[].hooks[].command]       | any(test("verify-gate"))'  "$tmp/settings.json" >/dev/null && pass "verify-gate preserved"  || fail "verify-gate dropped"
ls "$tmp"/settings.json.bak-graphify-* >/dev/null 2>&1 && pass "backup created" || fail "no backup"

# Idempotency: a second run must add nothing (still exactly 2 graphify commands) and exit 0.
bash "$SCRIPT" --target "$tmp" --source "$SOURCE" >/dev/null 2>&1; rc2=$?
total=$(jq '[.hooks.PreToolUse[].hooks[].command | select(test("graphify-graph-hint"))] | length' "$tmp/settings.json")
{ [ "$rc2" -eq 0 ] && [ "$total" -eq 2 ]; } && pass "idempotent re-run (2 entries, rc=0)" || fail "not idempotent (total=$total rc=$rc2)"

echo "---"; if [ "$fails" -eq 0 ]; then echo "ALL PASS"; else echo "$fails FAILED"; exit 1; fi
