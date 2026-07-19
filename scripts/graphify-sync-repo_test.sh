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

# T4: upstream advances non-conflictingly; dirty tracked file on AW that does NOT
# conflict with the replayed commit or upstream's change -> autostash rebase
# succeeds AND cleanly re-applies the WIP: CLEAN, AW replayed onto new master,
# dirty content survives, stash left empty (verified P2: clean round-trip).
make_fork f4
tmpc4="$tmproot/f4-upwork"; git clone -q "$tmproot/f4-up" "$tmpc4"
( cd "$tmpc4" && echo more >> a.txt && gci commit -aqm upstream-change && gci push -q origin master )
( cd "$tmproot/f4" && echo aw > b.txt && gci add b.txt && gci commit -qm aw-work )
( cd "$tmproot/f4" && echo dirty-edit >> b.txt )   # dirty tracked file, non-conflicting
line="$(bash "$SCRIPT" "$tmproot/f4")"
case "$line" in *rebase:CLEAN:WIP-STASHED*) fail "T4 unexpectedly stashed ($line)";; *rebase:CLEAN*) pass "T4 clean rebase with dirty WIP";; *) fail "T4 expected CLEAN ($line)";; esac
upsha4=$(cd "$tmproot/f4" && git rev-parse upstream/master)
awbase4=$(cd "$tmproot/f4" && git rev-parse "agents-workbench~1" 2>/dev/null || echo "")
[ "$awbase4" = "$upsha4" ] && pass "T4 AW replayed onto new master" || fail "T4 AW base wrong (got $awbase4 want $upsha4)"
grep -qxF 'dirty-edit' "$tmproot/f4/b.txt" && pass "T4 dirty WIP still present" || fail "T4 dirty WIP lost"
stashn4=$(cd "$tmproot/f4" && git stash list | wc -l | tr -d ' ')
[ "$stashn4" = "0" ] && pass "T4 stash list empty" || fail "T4 stash not empty ($stashn4)"

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

# T7: AW commit touches only a NEW file (non-conflicting with upstream's a.txt
# edit); dirty WIP edits a.txt, which conflicts with upstream's a.txt edit
# during the autostash re-apply (not during the commit replay) -> the commit
# replay succeeds (rc=0) but the stash pop leaves UU entries; script must
# reset --hard and report CLEAN:WIP-STASHED (verified P1).
make_fork f7
tmpc7="$tmproot/f7-upwork"; git clone -q "$tmproot/f7-up" "$tmpc7"
( cd "$tmpc7" && echo UPSTREAM-EDIT >> a.txt && gci commit -aqm up-edit && gci push -q origin master )
( cd "$tmproot/f7" && echo new > nf.txt && gci add nf.txt && gci commit -qm aw-newfile )
( cd "$tmproot/f7" && echo DIRTY-EDIT >> a.txt )   # dirty, conflicts with upstream's a.txt edit
line="$(bash "$SCRIPT" "$tmproot/f7")"
case "$line" in *rebase:CLEAN:WIP-STASHED*) pass "T7 status CLEAN:WIP-STASHED";; *) fail "T7 expected CLEAN:WIP-STASHED ($line)";; esac
porcelain7=$(cd "$tmproot/f7" && git status --porcelain)
[ -z "$porcelain7" ] && pass "T7 working tree clean (reset --hard)" || fail "T7 tree not clean: $porcelain7"
stashn7=$(cd "$tmproot/f7" && git stash list | wc -l | tr -d ' ')
[ "$stashn7" = "1" ] && pass "T7 exactly one stash entry" || fail "T7 stash count $stashn7"
upsha7=$(cd "$tmproot/f7" && git rev-parse upstream/master)
awbase7=$(cd "$tmproot/f7" && git rev-parse "agents-workbench~1" 2>/dev/null || echo "")
[ "$awbase7" = "$upsha7" ] && pass "T7 AW rebased onto new master" || fail "T7 AW base wrong (got $awbase7 want $upsha7)"

# T8: AW has a conflicting COMMIT (like T3) plus dirty non-conflicting WIP on a
# different tracked file -> the commit replay itself fails (rc!=0); script
# must abort. Abort restores AW's SHA AND re-applies the autostashed WIP
# (verified P3), so the WIP survives and the stash ends up empty.
make_fork f8
( cd "$tmproot/f8" && echo trackedbase > c.txt && gci add c.txt && gci commit -qm aw-c )
tmpc8="$tmproot/f8-upwork"; git clone -q "$tmproot/f8-up" "$tmpc8"
( cd "$tmpc8" && echo UP > a.txt && gci commit -aqm up-edit && gci push -q origin master )
( cd "$tmproot/f8" && echo AW > a.txt && gci commit -aqm aw-edit )
( cd "$tmproot/f8" && echo dirty-c >> c.txt )   # dirty, non-conflicting WIP
before8=$(cd "$tmproot/f8" && git rev-parse agents-workbench)
line="$(bash "$SCRIPT" "$tmproot/f8")"
after8=$(cd "$tmproot/f8" && git rev-parse agents-workbench)
[ "$before8" = "$after8" ] && pass "T8 AW SHA unchanged after conflict" || fail "T8 AW rewritten!"
case "$line" in *rebase:CONFLICT*) pass "T8 status CONFLICT";; *) fail "T8 expected CONFLICT ($line)";; esac
grep -qxF 'dirty-c' "$tmproot/f8/c.txt" && pass "T8 WIP still present after abort" || fail "T8 WIP lost"
[ ! -d "$tmproot/f8/.git/rebase-merge" ] && [ ! -d "$tmproot/f8/.git/rebase-apply" ] && pass "T8 no rebase in progress" || fail "T8 rebase left mid-flight"
stashn8=$(cd "$tmproot/f8" && git stash list | wc -l | tr -d ' ')
[ "$stashn8" = "0" ] && pass "T8 stash list empty (WIP re-applied by abort)" || fail "T8 stash not empty ($stashn8)"

# T9: op-in-progress fabricated -> SKIP:op-in-progress, no rebase attempted.
make_fork f9
mkdir -p "$tmproot/f9/.git/rebase-merge"
before9=$(cd "$tmproot/f9" && git rev-parse agents-workbench)
line="$(bash "$SCRIPT" "$tmproot/f9")"
after9=$(cd "$tmproot/f9" && git rev-parse agents-workbench)
case "$line" in *rebase:SKIP:op-in-progress*) pass "T9 status SKIP:op-in-progress";; *) fail "T9 expected SKIP:op-in-progress ($line)";; esac
[ "$before9" = "$after9" ] && pass "T9 AW SHA unchanged (no rebase attempted)" || fail "T9 AW rewritten!"

echo "---"; if [ "$fails" -eq 0 ]; then echo "ALL PASS"; else echo "$fails FAILED"; exit 1; fi
