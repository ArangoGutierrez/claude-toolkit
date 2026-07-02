#!/usr/bin/env bash
set -uo pipefail
SCRIPT="$(cd "$(dirname "$0")" && pwd)/graphify-doc-contract-install.sh"
fails=0
tmproot="$(mktemp -d)"; trap 'rm -rf "$tmproot"' EXIT
pass(){ echo "ok: $1"; }; fail(){ echo "FAIL: $1"; fails=$((fails+1)); }

repo="$tmproot/r"; mkdir -p "$repo"; printf '# CLAUDE.md\n\nExisting content.\n' > "$repo/CLAUDE.md"
bash "$SCRIPT" "$repo" >/dev/null 2>&1
grep -qF 'graphify-maintenance-contract' "$repo/CLAUDE.md" && pass "contract appended" || fail "no contract"
grep -qF 'Existing content.' "$repo/CLAUDE.md" && pass "existing content preserved" || fail "clobbered CLAUDE.md"
bash "$SCRIPT" "$repo" >/dev/null 2>&1
n=$(grep -cF 'graphify-maintenance-contract' "$repo/CLAUDE.md" 2>/dev/null || echo 99)
[ "$n" -eq 1 ] && pass "idempotent (marker once)" || fail "marker count=$n"

# Missing CLAUDE.md -> skip gracefully (exit 0, no file created) — exercises the [ -f ] guard.
repo2="$tmproot/no-claude"; mkdir -p "$repo2"
bash "$SCRIPT" "$repo2" >/dev/null 2>&1; rc=$?
[ "$rc" -eq 0 ] && pass "missing CLAUDE.md exits 0" || fail "missing CLAUDE.md nonzero exit (rc=$rc)"
[ ! -f "$repo2/CLAUDE.md" ] && pass "no file created on missing CLAUDE.md" || fail "spurious CLAUDE.md created"

echo "---"; if [ "$fails" -eq 0 ]; then echo "ALL PASS"; else echo "$fails FAILED"; exit 1; fi
