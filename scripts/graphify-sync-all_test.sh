#!/usr/bin/env bash
# claude-toolkit/scripts/graphify-sync-all_test.sh
set -uo pipefail
SCRIPT="$(cd "$(dirname "$0")" && pwd)/graphify-sync-all.sh"
fails=0
tmproot="$(mktemp -d)"; trap 'rm -rf "$tmproot"' EXIT
pass(){ echo "ok: $1"; }
fail(){ echo "FAIL: $1"; fails=$((fails+1)); }

fakebin="$tmproot/bin"; mkdir -p "$fakebin"
printf '#!/usr/bin/env bash\nif [ "${1:-}" = update ]; then mkdir -p "${2:-.}/graphify-out"; echo "{\\"nodes\\":[]}" > "${2:-.}/graphify-out/graph.json"; fi\n' > "$fakebin/graphify"
chmod +x "$fakebin/graphify"; export PATH="$fakebin:$PATH"
gci(){ GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t git "$@"; }

ROOT="$tmproot/src"; mkdir -p "$ROOT/a/x" "$ROOT/b/y" "$ROOT/c/z"
# graphed repo
( cd "$ROOT/a/x" && git init -q && echo a>f && gci add f && gci commit -qm a && mkdir graphify-out && echo '{}' > graphify-out/graph.json )
# graphed repo with a DEAD .git/hooks/post-commit to be remediated
( cd "$ROOT/b/y" && git init -q && echo b>f && gci add f && gci commit -qm b && mkdir graphify-out && echo '{}' > graphify-out/graph.json
  printf '#!/usr/bin/env bash\n# graphify-refresh\n' > .git/hooks/post-commit; chmod +x .git/hooks/post-commit )
# NON-graphed repo -> must be ignored by discovery
( cd "$ROOT/c/z" && git init -q && echo c>f && gci add f && gci commit -qm c )
# graphed-LOOKING dir that is NOT a git repo -> discovery must SKIP it (guard test).
mkdir -p "$ROOT/d/notgit/graphify-out"; echo '{}' > "$ROOT/d/notgit/graphify-out/graph.json"

LOGDIR="$tmproot/logs"
GRAPHIFY_SCAN_ROOT="$ROOT" GRAPHIFY_LOG_DIR="$LOGDIR" bash "$SCRIPT" >/dev/null 2>&1

# 1) discovers exactly the two graphed repos (LATEST mentions x and y, not z).
L="$LOGDIR/graphify-sync-LATEST.md"
{ grep -qF "/a/x " "$L" && grep -qF "/b/y " "$L" && ! grep -qF "/c/z " "$L"; } \
  && pass "discovery: graphed only" || fail "discovery wrong: $(cat "$L")"
# 2) remediation removed the dead hook.
[ ! -f "$ROOT/b/y/.git/hooks/post-commit" ] && pass "dead post-commit removed" || fail "dead hook remains"
# 3) append-only log has timestamped lines.
grep -qE '^[0-9]{4}-[0-9]{2}-[0-9]{2}T' "$LOGDIR/graphify-sync.log" && pass "log timestamped" || fail "no log lines"
# 4) non-git graphed dir is SKIPPED (absent from log) — discriminates the
#    `git rev-parse --git-dir || continue` guard; without it sync-repo would
#    emit an ERROR line for /d/notgit. Both real repos still processed.
! grep -qF "/d/notgit " "$LOGDIR/graphify-sync.log" 2>/dev/null \
  && pass "non-git graphed dir skipped" || fail "non-git dir not skipped"
n=$(grep -c '| upstream:' "$LOGDIR/graphify-sync.log" 2>/dev/null || echo 0)
[ "$n" -ge 2 ] && pass "both real repos processed (loop continues past skip)" || fail "only $n processed"

echo "---"; if [ "$fails" -eq 0 ]; then echo "ALL PASS"; else echo "$fails FAILED"; exit 1; fi
