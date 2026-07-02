#!/usr/bin/env bash
set -uo pipefail
SCRIPT="$(cd "$(dirname "$0")" && pwd)/graphify-launchd-install.sh"
fails=0
tmproot="$(mktemp -d)"; trap 'rm -rf "$tmproot"' EXIT
pass(){ echo "ok: $1"; }; fail(){ echo "FAIL: $1"; fails=$((fails+1)); }

PD="$tmproot/agents"
GRAPHIFY_PLIST_DIR="$PD" bash "$SCRIPT" >/dev/null 2>&1
plist="$PD/com.${USER}.graphify-sync.plist"
[ -f "$plist" ] && pass "plist written" || fail "no plist"
if command -v plutil >/dev/null 2>&1; then
  plutil -lint "$plist" >/dev/null 2>&1 && pass "plutil -lint OK" || fail "plist invalid"
fi
sync_abs="$(dirname "$SCRIPT")/graphify-sync-all.sh"
grep -qF "$sync_abs" "$plist" && pass "points at absolute fleet driver path" || fail "ProgramArguments not absolute sibling path"
grep -qF '<key>Weekday</key>' "$plist" && pass "weekly schedule" || fail "no weekly schedule"

echo "---"; if [ "$fails" -eq 0 ]; then echo "ALL PASS"; else echo "$fails FAILED"; exit 1; fi
