#!/usr/bin/env bash
# Tests for graphify-hooks-install.sh — installs global graphify-refresh hooks.
set -uo pipefail
SCRIPT="$(cd "$(dirname "$0")" && pwd)/graphify-hooks-install.sh"
fails=0
tmproot="$(mktemp -d)"; trap 'rm -rf "$tmproot"' EXIT
pass(){ echo "ok: $1"; }
fail(){ echo "FAIL: $1"; fails=$((fails+1)); }

HD="$tmproot/hooks"
# 1) fresh install -> all three hooks created, executable, with marker + update line.
GRAPHIFY_HOOKS_DIR="$HD" bash "$SCRIPT" >/dev/null 2>&1
ok=1
for h in post-commit post-merge post-rewrite; do
  [ -x "$HD/$h" ] || ok=0
  grep -qF 'graphify-refresh' "$HD/$h" 2>/dev/null || ok=0
  grep -qF 'graphify update .' "$HD/$h" 2>/dev/null || ok=0
done
[ "$ok" -eq 1 ] && pass "three guarded hooks installed" || fail "missing/incomplete hooks"

# 2) idempotent -> second run does not duplicate the marker.
GRAPHIFY_HOOKS_DIR="$HD" bash "$SCRIPT" >/dev/null 2>&1
n=$(grep -cF 'graphify-refresh' "$HD/post-commit" 2>/dev/null || echo 99)
[ "$n" -eq 1 ] && pass "idempotent (marker once)" || fail "marker count=$n"

# 3) append-safe -> a pre-existing hook's own logic is preserved.
HD2="$tmproot/hooks2"; mkdir -p "$HD2"
printf '#!/usr/bin/env bash\necho CUSTOM_PRECOMMIT\n' > "$HD2/post-commit"; chmod +x "$HD2/post-commit"
GRAPHIFY_HOOKS_DIR="$HD2" bash "$SCRIPT" >/dev/null 2>&1
{ grep -qF 'CUSTOM_PRECOMMIT' "$HD2/post-commit" && grep -qF 'graphify-refresh' "$HD2/post-commit"; } \
  && pass "append preserves existing hook" || fail "clobbered or did not append"

# 4) behavioral guard -> hook is a no-op without graphify-out/, runs graphify with it.
fakebin="$tmproot/bin"; mkdir -p "$fakebin"
export CALLS="$tmproot/calls"; : > "$CALLS"
printf '#!/usr/bin/env bash\necho "$@" >> "$CALLS"\n' > "$fakebin/graphify"; chmod +x "$fakebin/graphify"
nog="$tmproot/nograph"; mkdir -p "$nog"
( cd "$nog" && PATH="$fakebin:$PATH" CALLS="$CALLS" bash "$HD/post-commit" )
[ ! -s "$CALLS" ] && pass "no-op without graphify-out/" || fail "ran graphify without graph: $(cat "$CALLS")"
withg="$tmproot/withgraph"; mkdir -p "$withg/graphify-out"
( cd "$withg" && PATH="$fakebin:$PATH" CALLS="$CALLS" bash "$HD/post-commit" )
# Hook runs graphify in ( ... & ); poll up to ~0.5s instead of a fixed sleep (loaded-host safe).
for _i in 1 2 3 4 5; do grep -qF 'update .' "$CALLS" 2>/dev/null && break; sleep 0.1; done
grep -qF 'update .' "$CALLS" && pass "runs graphify update . with graph" || fail "did not refresh: $(cat "$CALLS")"

echo "---"; if [ "$fails" -eq 0 ]; then echo "ALL PASS"; else echo "$fails FAILED"; exit 1; fi
