#!/usr/bin/env bash
# Tests for graphify-install.sh — installs the graphify hook+rule+settings entries
# into a target Claude config dir, idempotently, preserving existing hooks.
set -uo pipefail
SCRIPT="$(cd "$(dirname "$0")" && pwd)/graphify-install.sh"
SOURCE="$(cd "$(dirname "$0")/.." && pwd)/.claude"   # real toolkit .claude (read-only source)
fails=0
# Anchor at $TMPDIR: macOS mktemp with no template resolves through
# _CS_DARWIN_USER_TEMP_DIR instead, which an agent sandbox denies.
tmp="$(mktemp -d "${TMPDIR:-/tmp}/graphify-install-test.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT
pass(){ echo "ok: $1"; }; fail(){ echo "FAIL: $1"; fails=$((fails+1)); }

# Fake target home with PRE-EXISTING hooks that MUST be preserved — one on the event
# the graphify hook now installs onto (SessionStart), one on another event, one on
# another lifecycle event entirely.
mkdir -p "$tmp/hooks" "$tmp/rules"
cat > "$tmp/settings.json" <<'JSON'
{
  "hooks": {
    "SessionStart": [
      { "hooks": [ { "type": "command", "command": "$HOME/.claude/hooks/inject-date.sh" } ] }
    ],
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

gs=$(jq '[.hooks.SessionStart[].hooks[].command | select(test("graphify-graph-hint"))] | length' "$tmp/settings.json")
{ [ "$gs" -eq 1 ]; } && pass "registered once on SessionStart" || fail "SessionStart count=$gs, want 1"

# The port: the hook must NOT be left on any PreToolUse matcher. This is what goes red
# if the installer keeps writing the old Bash / Glob|Grep blocks.
gp=$(jq '[.hooks.PreToolUse[]?.hooks[]?.command // "" | select(test("graphify-graph-hint"))] | length' "$tmp/settings.json")
{ [ "$gp" -eq 0 ]; } && pass "not registered on PreToolUse" || fail "still on PreToolUse (count=$gp)"

jq -e '[.hooks.SessionStart[].hooks[].command] | any(test("inject-date"))'  "$tmp/settings.json" >/dev/null && pass "inject-date preserved"  || fail "inject-date dropped"
jq -e '[.hooks.PreToolUse[].hooks[].command]   | any(test("sign-commits"))' "$tmp/settings.json" >/dev/null && pass "sign-commits preserved" || fail "sign-commits dropped"
jq -e '[.hooks.Stop[].hooks[].command]         | any(test("verify-gate"))'  "$tmp/settings.json" >/dev/null && pass "verify-gate preserved"  || fail "verify-gate dropped"
ls "$tmp"/settings.json.bak-graphify-* >/dev/null 2>&1 && pass "backup created" || fail "no backup"

# Idempotency: a second run must add nothing (still exactly 1 graphify command) and exit 0.
bash "$SCRIPT" --target "$tmp" --source "$SOURCE" >/dev/null 2>&1; rc2=$?
total=$(jq '[.hooks.SessionStart[].hooks[].command | select(test("graphify-graph-hint"))] | length' "$tmp/settings.json")
{ [ "$rc2" -eq 0 ] && [ "$total" -eq 1 ]; } && pass "idempotent re-run (1 entry, rc=0)" || fail "not idempotent (total=$total rc=$rc2)"

# A target with no SessionStart key at all must still get one (jq null + [x] path).
mkdir -p "$tmp/bare/hooks" "$tmp/bare/rules"
echo '{"hooks":{"Stop":[{"matcher":"","hooks":[{"type":"command","command":"x.sh"}]}]}}' > "$tmp/bare/settings.json"
bash "$SCRIPT" --target "$tmp/bare" --source "$SOURCE" >/dev/null 2>&1; rc3=$?
bare=$(jq '[.hooks.SessionStart[]?.hooks[]?.command // "" | select(test("graphify-graph-hint"))] | length' "$tmp/bare/settings.json")
{ [ "$rc3" -eq 0 ] && [ "$bare" -eq 1 ]; } && pass "creates SessionStart when absent" || fail "no SessionStart created (bare=$bare rc=$rc3)"

echo "---"; if [ "$fails" -eq 0 ]; then echo "ALL PASS"; else echo "$fails FAILED"; exit 1; fi
