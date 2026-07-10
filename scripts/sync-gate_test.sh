#!/usr/bin/env bash
# Tests for sync-lib.sh + the capture.sh/diff.sh leak sweep it powers.
# Fixture-driven: every test builds its own throwaway repo + HOME under a
# mktemp -d tmproot; nothing here touches the real ~/.claude.
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CAPTURE="$SCRIPT_DIR/capture.sh"
DIFF="$SCRIPT_DIR/diff.sh"
LIB="$SCRIPT_DIR/sync-lib.sh"

fails=0
tmproot="$(mktemp -d)" || { echo "FAIL: mktemp -d failed" >&2; exit 1; }
[[ -n "$tmproot" ]] || { echo "FAIL: mktemp -d returned an empty path" >&2; exit 1; }
trap 'rm -rf "$tmproot"' EXIT
pass(){ echo "ok: $1"; }
fail(){ echo "FAIL: $1"; fails=$((fails+1)); }

# The literal warning text sync-lib.sh must emit when LEAK_PATTERNS_FILE is
# absent (load-bearing per brief; em dash is U+2014, not a hyphen).
WARN_LINE='WARNING: scripts/leak-patterns.local not found — leak sweep running with generic patterns only'

# T1: shared-lib parity. Catches: reintroduced duplicate CURATED arrays (the
# original drift class where capture.sh and diff.sh's lists silently diverged).
n1=$(grep -c '^CURATED=(' "$CAPTURE" || true)
n2=$(grep -c '^CURATED=(' "$DIFF" || true)
[ "$n1" -eq 0 ] && [ "$n2" -eq 0 ] && pass "T1 no duplicate CURATED= in capture.sh/diff.sh" \
  || fail "T1 duplicate CURATED array present (capture.sh:$n1 diff.sh:$n2)"
grep -q 'sync-lib.sh' "$CAPTURE" && grep -q 'sync-lib.sh' "$DIFF" \
  && pass "T1 both scripts source sync-lib.sh" \
  || fail "T1 one or both scripts do not source sync-lib.sh"

# T2: curated exact-file skip. Catches: the original diff.sh false-drift bug
# where learned-anti-patterns.md was CURATED in capture.sh but not diff.sh.
repo="$tmproot/t2-repo"; home="$tmproot/t2-home"
mkdir -p "$repo/.claude/rules" "$home/.claude/rules"
git init -q "$repo"
echo "REPO_CONTENT_X" > "$repo/.claude/rules/learned-anti-patterns.md"
git -C "$repo" add -A
echo "LIVE_CONTENT_Y" > "$home/.claude/rules/learned-anti-patterns.md"
out="$(HOME="$home" REPO_DIR="$repo" bash "$CAPTURE" --claude-only 2>&1)"; rc=$?
content="$(cat "$repo/.claude/rules/learned-anti-patterns.md")"
[ "$rc" -eq 0 ] && [ "$content" = "REPO_CONTENT_X" ] \
  && pass "T2 curated exact-file left untouched by capture" \
  || fail "T2 capture rc=$rc, content=$content: $out"
out="$(HOME="$home" REPO_DIR="$repo" bash "$DIFF" --claude-only 2>&1)"
echo "$out" | grep -q 'learned-anti-patterns.md' \
  && fail "T2 diff.sh listed curated file as changed: $out" \
  || pass "T2 diff.sh silent on curated file"

# T3: curated glob skip. Catches: a quoted-RHS regression breaking is_curated's
# glob match for .claude/team/* (would stop matching the whole subtree).
repo="$tmproot/t3-repo"; home="$tmproot/t3-home"
mkdir -p "$repo/.claude/team/lib" "$home/.claude/team/lib"
git init -q "$repo"
echo "REPO_X" > "$repo/.claude/team/lib/architect-decisions.md"
git -C "$repo" add -A
echo "LIVE_Y" > "$home/.claude/team/lib/architect-decisions.md"
HOME="$home" REPO_DIR="$repo" bash "$CAPTURE" --claude-only >/dev/null 2>&1
content="$(cat "$repo/.claude/team/lib/architect-decisions.md")"
[ "$content" = "REPO_X" ] && pass "T3 curated glob (.claude/team/*) left untouched" \
  || fail "T3 glob-curated file overwritten: $content"
out="$(HOME="$home" REPO_DIR="$repo" bash "$DIFF" --claude-only 2>&1)"
echo "$out" | grep -q 'architect-decisions.md' \
  && fail "T3 diff.sh listed glob-curated file: $out" \
  || pass "T3 diff.sh silent on glob-curated file"

# T4: machine-state curated. Catches: installed_plugins.json / policy-limits.json
# reintroduction on every capture (the mirror-run class from the brief).
repo="$tmproot/t4-repo"; home="$tmproot/t4-home"
mkdir -p "$repo/.claude/plugins" "$home/.claude/plugins"
git init -q "$repo"
echo '{"repo":true}' > "$repo/.claude/plugins/installed_plugins.json"
echo '{"repo":true}' > "$repo/.claude/policy-limits.json"
git -C "$repo" add -A
echo '{"live":true}' > "$home/.claude/plugins/installed_plugins.json"
echo '{"live":true}' > "$home/.claude/policy-limits.json"
HOME="$home" REPO_DIR="$repo" bash "$CAPTURE" --claude-only >/dev/null 2>&1
c1="$(cat "$repo/.claude/plugins/installed_plugins.json")"
c2="$(cat "$repo/.claude/policy-limits.json")"
[ "$c1" = '{"repo":true}' ] && [ "$c2" = '{"repo":true}' ] \
  && pass "T4 machine-state files left untouched by capture" \
  || fail "T4 machine-state file overwritten (plugins=$c1 policy=$c2)"

# T5: generic leak gate flips. Catches: a leak-invisible /Users/ path making it
# into a captured file with no gate to stop it (leak class 1 from the brief).
repo="$tmproot/t5-repo"; home="$tmproot/t5-home"
mkdir -p "$repo/.claude/hooks" "$home/.claude/hooks"
git init -q "$repo"
echo "echo hello" > "$repo/.claude/hooks/x.sh"
git -C "$repo" add -A
echo "echo /Users/testuser/secret-project" > "$home/.claude/hooks/x.sh"
out="$(HOME="$home" REPO_DIR="$repo" bash "$CAPTURE" --claude-only 2>&1)"; rc=$?
[ "$rc" -ne 0 ] && pass "T5 leak gate exits non-zero on /Users/ path" \
  || fail "T5 expected non-zero rc, got $rc: $out"
echo "$out" | grep -q 'LEAK?.*\.claude/hooks/x\.sh' \
  && pass "T5 LEAK? names .claude/hooks/x.sh" \
  || fail "T5 LEAK? did not name the file: $out"

# T6: local pattern file honored. Catches: LEAK_PATTERNS_FILE loading broken
# (identity patterns silently never applied).
repo="$tmproot/t6-repo"; home="$tmproot/t6-home"
mkdir -p "$repo/.claude/hooks" "$home/.claude/hooks"
git init -q "$repo"
echo "echo hello" > "$repo/.claude/hooks/y.sh"
git -C "$repo" add -A
echo "echo ZZSENTINELZZ" > "$home/.claude/hooks/y.sh"
patfile="$tmproot/t6-patterns.local"
echo "ZZSENTINELZZ" > "$patfile"
out="$(HOME="$home" REPO_DIR="$repo" LEAK_PATTERNS_FILE="$patfile" bash "$CAPTURE" --claude-only 2>&1)"; rc=$?
[ "$rc" -ne 0 ] && echo "$out" | grep -q 'LEAK?.*\.claude/hooks/y\.sh' \
  && pass "T6 local pattern file flips the gate" \
  || fail "T6 local pattern not honored (rc=$rc): $out"

# T7: missing local file is LOUD. Catches: the DA's silent-failure mode where
# an absent local pattern file quietly runs with no local patterns at all.
repo="$tmproot/t7-repo"; home="$tmproot/t7-home"
mkdir -p "$repo/.claude/hooks" "$home/.claude/hooks"
git init -q "$repo"
echo "echo hello" > "$repo/.claude/hooks/z.sh"
git -C "$repo" add -A
echo "echo hello" > "$home/.claude/hooks/z.sh"
out="$(HOME="$home" REPO_DIR="$repo" LEAK_PATTERNS_FILE="$tmproot/t7-nonexistent.local" bash "$CAPTURE" --claude-only 2>&1)"; rc=$?
echo "$out" | grep -qF "$WARN_LINE" \
  && pass "T7 missing local pattern file warns loudly" \
  || fail "T7 missing warning line: $out"
[ "$rc" -eq 0 ] && pass "T7 clean fixture still rc=0 despite missing pattern file" \
  || fail "T7 rc=$rc (expected 0): $out"

# T8: clean fixture end-to-end. Catches: sweep false-positives, or broken
# capture/diff exit semantics when there is nothing to flag.
repo="$tmproot/t8-repo"; home="$tmproot/t8-home"
mkdir -p "$repo/.claude/hooks" "$home/.claude/hooks"
git init -q "$repo"
echo "echo hello" > "$repo/.claude/hooks/clean.sh"
git -C "$repo" add -A
echo "echo hello" > "$home/.claude/hooks/clean.sh"
out="$(HOME="$home" REPO_DIR="$repo" bash "$CAPTURE" --claude-only 2>&1)"; rc=$?
[ "$rc" -eq 0 ] && pass "T8 clean fixture: capture rc=0" || fail "T8 capture rc=$rc: $out"
out="$(HOME="$home" REPO_DIR="$repo" bash "$DIFF" --claude-only 2>&1)"; rc=$?
[ "$rc" -eq 0 ] && echo "$out" | grep -q 'Everything in sync' \
  && pass "T8 clean fixture: diff.sh rc=0, Everything in sync" \
  || fail "T8 diff.sh rc=$rc: $out"

# T9: bash -n on all three scripts. Catches: a syntax error slipping into any
# of the shared-lib refactor's three files.
for f in "$CAPTURE" "$DIFF" "$LIB"; do
  errfile="$tmproot/bashn-$(basename "$f").err"
  if bash -n "$f" 2>"$errfile"; then
    pass "T9 bash -n $(basename "$f")"
  else
    fail "T9 bash -n $(basename "$f") failed: $(cat "$errfile")"
  fi
done

# T10: diff.sh leak advisory. Catches: the CHANGED-file leak scan in diff.sh
# never wired up, or its advisory line format broken.
repo="$tmproot/t10-repo"; home="$tmproot/t10-home"
mkdir -p "$repo/.claude/hooks" "$home/.claude/hooks"
git init -q "$repo"
echo "echo hello" > "$repo/.claude/hooks/adv.sh"
git -C "$repo" add -A
echo "echo /Users/testuser/private" > "$home/.claude/hooks/adv.sh"
out="$(HOME="$home" REPO_DIR="$repo" bash "$DIFF" --claude-only 2>&1)"
echo "$out" | grep -qF '  LEAK?        .claude/hooks/adv.sh' \
  && pass "T10 diff.sh prints LEAK? advisory for a changed file" \
  || fail "T10 diff.sh missing LEAK? advisory: $out"


# T11 (discriminates Fix 2): placeholder exemption is per-match, not per-line.
# Scenario A: a file whose only "leak-shaped" content is a documented
# placeholder path must not flag. Catches: the generic /Users/ pattern
# flagging doc/fixture placeholder paths (e.g. "/Users/foo/repo") forever,
# even though they are legitimate example content, not real leaks.
repo="$tmproot/t11a-repo"; home="$tmproot/t11a-home"
mkdir -p "$repo/.claude/hooks" "$home/.claude/hooks"
git init -q "$repo"
echo "placeholder line" > "$repo/.claude/hooks/exempt.sh"
git -C "$repo" add -A
echo "see /Users/foo/repo for an example" > "$home/.claude/hooks/exempt.sh"
out="$(HOME="$home" REPO_DIR="$repo" bash "$CAPTURE" --claude-only 2>&1)"; rc=$?
[ "$rc" -eq 0 ] && ! echo "$out" | grep -q 'LEAK?' \
  && pass "T11 documented placeholder path (/Users/foo) does not flag" \
  || fail "T11a expected rc=0 and no LEAK?, got rc=$rc: $out"

# Scenario B: a line containing BOTH an exempt placeholder AND a real path
# sharing the same line must still flag. Catches: exemption implemented as a
# lazy per-line filter (e.g. grep -v on any exempt substring), which would
# mask the real hit riding along on the same line as the placeholder.
repo="$tmproot/t11b-repo"; home="$tmproot/t11b-home"
mkdir -p "$repo/.claude/hooks" "$home/.claude/hooks"
git init -q "$repo"
echo "clean" > "$repo/.claude/hooks/mixed.sh"
git -C "$repo" add -A
echo "see /Users/foo/a and /Users/testuser/b" > "$home/.claude/hooks/mixed.sh"
out="$(HOME="$home" REPO_DIR="$repo" bash "$CAPTURE" --claude-only 2>&1)"; rc=$?
[ "$rc" -ne 0 ] && echo "$out" | grep -q 'LEAK?.*mixed\.sh' \
  && pass "T11 mixed placeholder+real-path line still flags (per-match proof)" \
  || fail "T11b expected rc!=0 and LEAK? naming mixed.sh, got rc=$rc: $out"

# T12 (discriminates Fix 1): true delta-scoping. Catches: capture.sh copying
# every live-present tracked file unconditionally regardless of whether it
# actually changed, so REFRESHED_FILES (and the leak sweep) covers the whole
# tree on every run instead of just this run's delta, and the "refreshed N"
# summary reports N > 0 even when live == repo for every file.
repo="$tmproot/t12-repo"; home="$tmproot/t12-home"
mkdir -p "$repo/.claude/hooks" "$home/.claude/hooks"
git init -q "$repo"
echo "echo hello" > "$repo/.claude/hooks/a.sh"
echo "see /Users/foo/repo for an example" > "$repo/.claude/hooks/b.sh"
git -C "$repo" add -A
echo "echo hello" > "$home/.claude/hooks/a.sh"
echo "see /Users/foo/repo for an example" > "$home/.claude/hooks/b.sh"
out="$(HOME="$home" REPO_DIR="$repo" bash "$CAPTURE" --claude-only 2>&1)"; rc=$?
[ "$rc" -eq 0 ] && echo "$out" | grep -q 'refreshed 0 file' \
  && pass "T12 fully-in-sync tree: capture rc=0, refreshed 0 (true delta-scope)" \
  || fail "T12 expected rc=0 and 'refreshed 0', got rc=$rc: $out"

# T13 (discriminates the hub-ID gate): double-namespace ("hub-form") model IDs
# must flag; single-namespace public catalog IDs must pass. Catches: an
# extracted engine file carrying an internal hub-form default sailing through
# capture into this public repo (the eval.py DEFAULT_MODEL class).
repo="$tmproot/t13a-repo"; home="$tmproot/t13a-home"
mkdir -p "$repo/.claude/tool" "$home/.claude/tool"
git init -q "$repo"
echo "MODEL = 'placeholder'" > "$repo/.claude/tool/cfg.py"
git -C "$repo" add -A
echo "MODEL = 'nvidia/nvidia/nemotron-x'" > "$home/.claude/tool/cfg.py"
out="$(HOME="$home" REPO_DIR="$repo" bash "$CAPTURE" --claude-only 2>&1)"; rc=$?
[ "$rc" -ne 0 ] && echo "$out" | grep -q 'LEAK?.*\.claude/tool/cfg\.py' \
  && pass "T13 hub-form (double-namespace) model ID flips the gate" \
  || fail "T13a expected rc!=0 + LEAK? naming cfg.py, got rc=$rc: $out"

repo="$tmproot/t13b-repo"; home="$tmproot/t13b-home"
mkdir -p "$repo/.claude/tool" "$home/.claude/tool"
git init -q "$repo"
echo "MODEL = 'placeholder'" > "$repo/.claude/tool/cfg.py"
git -C "$repo" add -A
echo "MODEL = 'nvidia/nemotron-3-ultra-550b-a55b:free'" > "$home/.claude/tool/cfg.py"
out="$(HOME="$home" REPO_DIR="$repo" bash "$CAPTURE" --claude-only 2>&1)"; rc=$?
[ "$rc" -eq 0 ] && ! echo "$out" | grep -q 'LEAK?' \
  && pass "T13 public catalog (single-namespace) ID passes clean" \
  || fail "T13b expected rc=0 and no LEAK?, got rc=$rc: $out"

echo "---"; if [ "$fails" -eq 0 ]; then echo "ALL PASS"; else echo "$fails FAILED"; exit 1; fi
