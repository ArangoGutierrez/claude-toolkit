#!/usr/bin/env bash
# Tests for graphify-sync-repo.sh using REAL git repos + a fake graphify.
set -uo pipefail
SCRIPT="$(cd "$(dirname "$0")" && pwd)/graphify-sync-repo.sh"
fails=0
tmproot="$(mktemp -d)"; trap 'rm -rf "$tmproot"' EXIT
pass(){ echo "ok: $1"; }
fail(){ echo "FAIL: $1"; fails=$((fails+1)); }

fakebin="$tmproot/bin"; mkdir -p "$fakebin"
cat > "$fakebin/graphify" <<'FAKE'
#!/usr/bin/env bash
if [ "${1:-}" = "update" ]; then mkdir -p "${2:-.}/graphify-out"; echo '{"nodes":[]}' > "${2:-.}/graphify-out/graph.json"; fi
FAKE
chmod +x "$fakebin/graphify"
export PATH="$fakebin:$PATH"
# Neutralize the user's GLOBAL core.hooksPath: its agents-workbench pre-commit
# allowlist would reject fixture commits (e.g. b.txt) and break the test for an
# environmental reason. Each repo gets a local, empty hooks dir.
NOHOOKS="$tmproot/nohooks"; mkdir -p "$NOHOOKS"
gci(){ GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t git "$@"; }

# Build: bare "upstream", a clone with master + agents-workbench.
# Point bare HEAD at master after push so clones check it out correctly
# regardless of the user's global init.defaultBranch setting.
make_fork(){
  up="$tmproot/$1-up"; wk="$tmproot/$1"
  git init -q --bare "$up"
  git init -q "$wk"; git -C "$wk" config --local core.hooksPath "$NOHOOKS"
  ( cd "$wk"
    echo base > a.txt; gci add a.txt; gci commit -qm base
    git branch -m master; git remote add upstream "$up"; gci push -q upstream master
    git -C "$up" symbolic-ref HEAD refs/heads/master
    gci checkout -q -b agents-workbench )
}

# T1+T2: upstream advances; AW has a non-conflicting commit -> ff master + clean rebase.
make_fork f1
( cd "$tmproot/f1-up-clone" 2>/dev/null; true )
tmpc="$tmproot/f1-upwork"; git clone -q "$tmproot/f1-up" "$tmpc"
( cd "$tmpc" && echo more >> a.txt && gci commit -aqm upstream-change && gci push -q origin master )
( cd "$tmproot/f1" && echo aw > b.txt && gci add b.txt && gci commit -qm aw-work )
line="$(bash "$SCRIPT" "$tmproot/f1")"
mastersha=$(cd "$tmproot/f1" && git rev-parse master)
upsha=$(cd "$tmproot/f1" && git rev-parse upstream/master)
[ "$mastersha" = "$upsha" ] && pass "T1 master fast-forwarded" || fail "T1 master not ff ($line)"
case "$line" in *rebase:CLEAN*) pass "T2 clean rebase";; *) fail "T2 expected CLEAN ($line)";; esac
( cd "$tmproot/f1" && git rev-parse "agents-workbench~1" >/dev/null 2>&1 ) && \
  { awbase=$(cd "$tmproot/f1" && git rev-parse "agents-workbench~1"); [ "$awbase" = "$upsha" ] && pass "T2 AW replayed onto master" || fail "T2 AW base wrong"; }

# T3: conflicting AW commit -> rebase aborts, AW byte-identical, status CONFLICT.
make_fork f3
tmpc3="$tmproot/f3-upwork"; git clone -q "$tmproot/f3-up" "$tmpc3"
( cd "$tmpc3" && echo UP > a.txt && gci commit -aqm up-edit && gci push -q origin master )
( cd "$tmproot/f3" && echo AW > a.txt && gci commit -aqm aw-edit )
before=$(cd "$tmproot/f3" && git rev-parse agents-workbench)
line="$(bash "$SCRIPT" "$tmproot/f3")"
after=$(cd "$tmproot/f3" && git rev-parse agents-workbench)
[ "$before" = "$after" ] && pass "T3 AW unchanged after conflict" || fail "T3 AW rewritten!"
case "$line" in *rebase:CONFLICT*) pass "T3 status CONFLICT";; *) fail "T3 expected CONFLICT ($line)";; esac
[ ! -d "$tmproot/f3/.git/rebase-merge" ] && [ ! -d "$tmproot/f3/.git/rebase-apply" ] && pass "T3 no rebase in progress" || fail "T3 rebase left mid-flight"

# T4: dirty tracked tree -> SKIP:dirty, no rebase attempted.
make_fork f4
( cd "$tmproot/f4" && echo dirty >> a.txt )   # modify tracked file, leave unstaged
line="$(bash "$SCRIPT" "$tmproot/f4")"
case "$line" in *rebase:SKIP:dirty*) pass "T4 SKIP:dirty";; *) fail "T4 expected SKIP:dirty ($line)";; esac

# T5: worktree gets a graphify-out symlink resolving to the main checkout.
make_fork f5
( cd "$tmproot/f5" && git worktree add -q "$tmproot/f5-wt" -b feat >/dev/null 2>&1 )
bash "$SCRIPT" "$tmproot/f5" >/dev/null
[ -L "$tmproot/f5-wt/graphify-out" ] && [ -e "$tmproot/f5-wt/graphify-out/graph.json" ] \
  && pass "T5 worktree symlink resolves" || fail "T5 no usable symlink"
grep -qxF 'graphify-out' "$tmproot/f5/.git/info/exclude" && pass "T5 symlink ignored" || fail "T5 not ignored"

# T6: non-fork (no upstream) -> graph refresh only, no fetch/rebase.
nf="$tmproot/nf"; git init -q "$nf"; git -C "$nf" config --local core.hooksPath "$NOHOOKS"
( cd "$nf" && echo x > x.txt && gci add x.txt && gci commit -qm x )
line="$(bash "$SCRIPT" "$nf")"
case "$line" in *upstream:N*ff:NA*rebase:NA*) pass "T6 non-fork refresh-only";; *) fail "T6 ($line)";; esac
[ -f "$nf/graphify-out/graph.json" ] && pass "T6 graph built" || fail "T6 no graph"

echo "---"; if [ "$fails" -eq 0 ]; then echo "ALL PASS"; else echo "$fails FAILED"; exit 1; fi
