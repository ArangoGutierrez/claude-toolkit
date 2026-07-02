#!/usr/bin/env bash
# Tests for graphify-bootstrap.sh — builds a Graphify code graph for a repo.
# Plain bash (no bats), matching the repo's *_test.sh convention. A fake
# `graphify` on PATH records its args and mimics `update` by writing a graph.
set -uo pipefail
SCRIPT="$(cd "$(dirname "$0")" && pwd)/graphify-bootstrap.sh"
fails=0
tmproot="$(mktemp -d)"; trap 'rm -rf "$tmproot"' EXIT

fakebin="$tmproot/bin"; mkdir -p "$fakebin"
export GRAPHIFY_CALLS="$tmproot/calls.log"
cat > "$fakebin/graphify" <<'FAKE'
#!/usr/bin/env bash
echo "$@" >> "$GRAPHIFY_CALLS"
if [ "${1:-}" = "update" ]; then
  mkdir -p "${2:-.}/graphify-out"
  echo '{}' > "${2:-.}/graphify-out/graph.json"
fi
FAKE
chmod +x "$fakebin/graphify"

pass(){ echo "ok: $1"; }
fail(){ echo "FAIL: $1"; fails=$((fails+1)); }

# 1) graphify NOT on PATH -> non-zero exit + a helpful "not found" message.
out="$(PATH=/usr/bin:/bin bash "$SCRIPT" "$tmproot" 2>&1)"; rc=$?
if [ "$rc" -ne 0 ] && printf '%s' "$out" | grep -qi "not found"; then
  pass "missing graphify -> error"
else
  fail "missing graphify -> error (rc=$rc, out=$out)"
fi

# 2) valid explicit path -> calls 'graphify update <path>' and succeeds.
: > "$GRAPHIFY_CALLS"
proj="$tmproot/proj"; mkdir -p "$proj"
out="$(PATH="$fakebin:$PATH" bash "$SCRIPT" "$proj" 2>&1)"; rc=$?
if [ "$rc" -eq 0 ] && grep -qF "update $proj" "$GRAPHIFY_CALLS"; then
  pass "valid path -> graphify update <path>"
else
  fail "valid path (rc=$rc, calls=$(cat "$GRAPHIFY_CALLS"))"
fi

# 3) default path (no arg) -> uses '.' (the current directory).
: > "$GRAPHIFY_CALLS"
proj2="$tmproot/proj2"; mkdir -p "$proj2"
out="$(cd "$proj2" && PATH="$fakebin:$PATH" bash "$SCRIPT" 2>&1)"; rc=$?
if [ "$rc" -eq 0 ] && grep -qF "update ." "$GRAPHIFY_CALLS"; then
  pass "default path -> graphify update ."
else
  fail "default path (rc=$rc, calls=$(cat "$GRAPHIFY_CALLS"))"
fi

# 4) non-existent path -> non-zero exit (guard before invoking graphify).
out="$(PATH="$fakebin:$PATH" bash "$SCRIPT" "$tmproot/nope" 2>&1)"; rc=$?
if [ "$rc" -ne 0 ]; then
  pass "bad path -> error"
else
  fail "bad path -> error (rc=$rc, out=$out)"
fi

# 5) git repo -> excludes graphify-out/ + .graphifyignore via .git/info/exclude (idempotent),
#    does NOT touch .gitignore, and does NOT write a .git/hooks/post-commit (global hooks now).
gp="$tmproot/gitproj"; mkdir -p "$gp"; ( cd "$gp" && git init -q )
HD="$tmproot/bootstrap-hooks"
PATH="$fakebin:$PATH" GRAPHIFY_HOOKS_DIR="$HD" bash "$SCRIPT" "$gp" >/dev/null 2>&1
PATH="$fakebin:$PATH" GRAPHIFY_HOOKS_DIR="$HD" bash "$SCRIPT" "$gp" >/dev/null 2>&1
ex=$(grep -cxF 'graphify-out/' "$gp/.git/info/exclude" 2>/dev/null || echo 0)
exg=$(grep -cxF '.graphifyignore' "$gp/.git/info/exclude" 2>/dev/null || echo 0)
{ [ "$ex" -eq 1 ] && [ "$exg" -eq 1 ]; } && pass "info/exclude has graphify-out/ + .graphifyignore once" || fail "exclude counts ext=$ex gfi=$exg"
{ ! grep -qF 'graphify-out' "$gp/.gitignore" 2>/dev/null; } && pass "does NOT pollute .gitignore" || fail "polluted .gitignore"
{ [ ! -f "$gp/.git/hooks/post-commit" ] || ! grep -qF 'graphify-refresh' "$gp/.git/hooks/post-commit" 2>/dev/null; } \
  && pass "no per-repo .git/hooks/post-commit refresh" || fail "still writes dead .git/hooks/post-commit"
grep -qF 'graphify-refresh' "$HD/post-commit" 2>/dev/null && pass "ensures global refresh hook" || fail "global hook not installed"

# 6) (removed) husky special-casing — superseded by global core.hooksPath install.

# 7) seeds a default .graphifyignore when absent; does NOT overwrite an existing one.
sp="$tmproot/seedproj"; mkdir -p "$sp"; ( cd "$sp" && git init -q )
PATH="$fakebin:$PATH" bash "$SCRIPT" "$sp" >/dev/null 2>&1
grep -qxF 'vendor/' "$sp/.graphifyignore" 2>/dev/null && pass "seeds default .graphifyignore" || fail "no default .graphifyignore"
ep="$tmproot/existignore"; mkdir -p "$ep"; ( cd "$ep" && git init -q ); printf 'custom-dir/\n' > "$ep/.graphifyignore"
{ [ "$(cat "$ep/.graphifyignore")" = "custom-dir/" ]; }   # baseline
PATH="$fakebin:$PATH" bash "$SCRIPT" "$ep" >/dev/null 2>&1
{ [ "$(cat "$ep/.graphifyignore")" = "custom-dir/" ]; } && pass "existing .graphifyignore preserved" || fail "overwrote existing .graphifyignore"

# 8) warns when vendored nodes leak into the built graph; silent on a clean graph.
vbin="$tmproot/vbin"; mkdir -p "$vbin"
cat > "$vbin/graphify" <<'FAKE'
#!/usr/bin/env bash
if [ "${1:-}" = "update" ]; then
  mkdir -p "${2:-.}/graphify-out"
  echo '{"nodes":[{"source_file":"docs/vendor/bundle/gems/foo/x.rb"}]}' > "${2:-.}/graphify-out/graph.json"
fi
FAKE
chmod +x "$vbin/graphify"
vp="$tmproot/vendorproj"; mkdir -p "$vp"; ( cd "$vp" && git init -q )
warnout="$(PATH="$vbin:$PATH" bash "$SCRIPT" "$vp" 2>&1)"
printf '%s' "$warnout" | grep -qiF 'come from vendored paths' && pass "warns on vendored nodes" || fail "no vendored-nodes warning"
cp2="$tmproot/cleanproj"; mkdir -p "$cp2"; ( cd "$cp2" && git init -q )
cleanout="$(PATH="$fakebin:$PATH" bash "$SCRIPT" "$cp2" 2>&1)"
printf '%s' "$cleanout" | grep -qiF 'come from vendored paths' && fail "false warning on clean graph" || pass "no warning on clean graph"

echo "---"; if [ "$fails" -eq 0 ]; then echo "ALL PASS"; else echo "$fails FAILED"; exit 1; fi
