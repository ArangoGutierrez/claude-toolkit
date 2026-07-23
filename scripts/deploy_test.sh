#!/usr/bin/env bash
# deploy_test.sh — harness for deploy.sh: overlay exclusions + runtime-state guard.
# The subject is resolved SCRIPT_DIR-relative (repo copy, never the deployed one)
# and copied into a fixture repo so $SCRIPT_DIR/$HOME resolution stays hermetic.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUBJECT="$SCRIPT_DIR/deploy.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
pass=0; fail=0
check_rc() { # <desc> <expected_rc> <actual_rc>
  if [ "$2" -eq "$3" ]; then pass=$((pass+1)); echo "PASS: $1"; else fail=$((fail+1)); echo "FAIL: $1 (expected rc=$2 got rc=$3)"; fi
}
check_has() { # <desc> <fixed-string> <file>
  if grep -qF "$2" "$3"; then pass=$((pass+1)); echo "PASS: $1"; else fail=$((fail+1)); echo "FAIL: $1 (missing: $2)"; fi
}
check_absent() { # <desc> <fixed-string> <file>
  if grep -qF "$2" "$3"; then fail=$((fail+1)); echo "FAIL: $1 (present: $2)"; else pass=$((pass+1)); echo "PASS: $1"; fi
}

make_fixture() { # <name>; creates $TMP/<name>/{repo,home}; copies SUBJECT in
  local d="$TMP/$1"
  mkdir -p "$d/repo/scripts" "$d/repo/.claude/rules" "$d/repo/.claude/plugins" "$d/home/.claude"
  command cp -f "$SUBJECT" "$d/repo/scripts/deploy.sh"
  echo 'toolkit CLAUDE'  > "$d/repo/.claude/CLAUDE.md"
  echo 'toolkit rule'    > "$d/repo/.claude/rules/learned-anti-patterns.md"
  echo 'generic only'    > "$d/repo/.claude/generic-only.md"
  echo '{}'              > "$d/repo/.claude/plugins/installed_plugins.json"
  echo '{}'              > "$d/repo/.claude/policy-limits.json"
}
make_overlay() { # <dir>; a git repo TRACKING .claude paths (index suffices for ls-files)
  local o="$1"
  mkdir -p "$o/.claude/rules"
  git -C "$o" init -q
  echo 'private CLAUDE' > "$o/.claude/CLAUDE.md"
  echo 'private rule'   > "$o/.claude/rules/learned-anti-patterns.md"
  git -C "$o" add .claude
}
run_deploy() { # <fixture-dir> <out-file> [extra args...]; returns deploy rc
  local d="$1" out="$2"; shift 2
  local rc=0
  HOME="$d/home" bash "$d/repo/scripts/deploy.sh" --dry-run --force --claude-only "$@" > "$out" 2>&1 || rc=$?
  echo "$rc"
}

# ── Case A: no pointer → normal deploy, overlap paths transfer ──
make_fixture a
rc=$(run_deploy "$TMP/a" "$TMP/a.out")
check_rc  "A: no pointer exits 0" 0 "$rc"
check_has "A: CLAUDE.md transfers without overlay" "CLAUDE.md" "$TMP/a.out"

# ── Case B: pointer → overlay-tracked paths excluded, others transfer ──
make_fixture b
make_overlay "$TMP/b/overlay"
printf '%s\n' "$TMP/b/overlay" > "$TMP/b/repo/scripts/deploy-overlay.local"
rc=$(run_deploy "$TMP/b" "$TMP/b.out")
check_rc     "B: pointer exits 0" 0 "$rc"
check_absent "B: overlay-owned CLAUDE.md excluded" ">f+++++++ CLAUDE.md" "$TMP/b.out"
check_absent "B: overlay-owned rules file excluded" "rules/learned-anti-patterns.md" "$TMP/b.out"
check_has    "B: non-overlay file still transfers" "generic-only.md" "$TMP/b.out"
check_has    "B: exclusion count reported" "overlay: excluding 2 overlay-owned paths" "$TMP/b.out"

# ── Case C: pointer to a missing directory → fail-closed abort ──
make_fixture c
printf '%s\n' "$TMP/c/does-not-exist" > "$TMP/c/repo/scripts/deploy-overlay.local"
rc=$(run_deploy "$TMP/c" "$TMP/c.out")
check_rc  "C: missing overlay dir aborts rc=4" 4 "$rc"
check_has "C: abort names the pointer problem" "ERROR: overlay pointer" "$TMP/c.out"

# ── Case D: pointer to a non-git directory → fail-closed abort ──
make_fixture d
mkdir -p "$TMP/d/notarepo"
printf '%s\n' "$TMP/d/notarepo" > "$TMP/d/repo/scripts/deploy-overlay.local"
rc=$(run_deploy "$TMP/d" "$TMP/d.out")
check_rc  "D: non-git overlay aborts rc=4" 4 "$rc"
check_has "D: abort names ls-files failure" "failed or returned nothing" "$TMP/d.out"

echo "==== Results: $pass passed, $fail failed ===="
[ "$fail" -eq 0 ]
