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
  echo 'toolkit rule 2'  > "$d/repo/.claude/rules/toolkit-only.md"
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
write_deletions() { # <overlay-dir> <line>...; writes the overlay's deletion manifest
  local o="$1"; shift
  printf '%s\n' "$@" > "$o/.claude-deploy-deletions"
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

# ── Case E: runtime-state files never transfer, even without a pointer ──
make_fixture e
rc=$(run_deploy "$TMP/e" "$TMP/e.out")
check_rc     "E: exits 0" 0 "$rc"
check_absent "E: installed_plugins.json never transfers" "installed_plugins.json" "$TMP/e.out"
check_absent "E: policy-limits.json never transfers" "policy-limits.json" "$TMP/e.out"

# ── Case F: overlay DELETED a path but declares nothing → toolkit copy returns ──
# The behaviour the manifest exists to override: deleting a file from the overlay
# untracks it, which drops its exclusion, so this repo writes its own copy back.
make_fixture f
make_overlay "$TMP/f/overlay"
printf '%s\n' "$TMP/f/overlay" > "$TMP/f/repo/scripts/deploy-overlay.local"
rc=$(run_deploy "$TMP/f" "$TMP/f.out")
check_rc     "F: absent manifest exits 0" 0 "$rc"
check_has    "F: undeclared deletion still transfers" "generic-only.md" "$TMP/f.out"
check_absent "F: absent manifest reports no deletions" "declared deletion" "$TMP/f.out"
check_has    "F: absent manifest leaves the tracked count alone" "overlay: excluding 2 overlay-owned paths" "$TMP/f.out"

# ── Case G: manifest declares the deletion → the toolkit copy is excluded ──
make_fixture g
make_overlay "$TMP/g/overlay"
printf '%s\n' "$TMP/g/overlay" > "$TMP/g/repo/scripts/deploy-overlay.local"
write_deletions "$TMP/g/overlay" ".claude/generic-only.md"
rc=$(run_deploy "$TMP/g" "$TMP/g.out")
check_rc     "G: manifest exits 0" 0 "$rc"
check_absent "G: declared deletion is excluded" "generic-only.md" "$TMP/g.out"
check_has    "G: undeclared toolkit file still transfers" "rules/toolkit-only.md" "$TMP/g.out"
check_has    "G: declared deletions get their own line" "overlay: honouring 1 declared deletion" "$TMP/g.out"
check_has    "G: tracked count keeps its old meaning" "overlay: excluding 2 overlay-owned paths" "$TMP/g.out"

# ── Case H: comments, blank lines and padding ignored; real entries survive ──
make_fixture h
make_overlay "$TMP/h/overlay"
printf '%s\n' "$TMP/h/overlay" > "$TMP/h/repo/scripts/deploy-overlay.local"
write_deletions "$TMP/h/overlay" \
  "# .claude/rules/toolkit-only.md is commented out and must NOT be excluded" \
  "" \
  "   " \
  "  .claude/generic-only.md  "
rc=$(run_deploy "$TMP/h" "$TMP/h.out")
check_rc     "H: comments and blanks exit 0" 0 "$rc"
check_has    "H: only the real entry is counted" "overlay: honouring 1 declared deletion" "$TMP/h.out"
check_absent "H: padded entry is trimmed and excluded" "generic-only.md" "$TMP/h.out"
check_has    "H: commented path is not excluded" "rules/toolkit-only.md" "$TMP/h.out"

# ── Case I: entry still tracked by the overlay → warn, exclude anyway, exit 0 ──
make_fixture i
make_overlay "$TMP/i/overlay"
printf '%s\n' "$TMP/i/overlay" > "$TMP/i/repo/scripts/deploy-overlay.local"
write_deletions "$TMP/i/overlay" ".claude/CLAUDE.md"
rc=$(run_deploy "$TMP/i" "$TMP/i.out")
check_rc     "I: still-tracked entry exits 0" 0 "$rc"
check_has    "I: still-tracked entry warns by name" "WARNING: overlay deletion manifest lists a still-tracked path: .claude/CLAUDE.md" "$TMP/i.out"
check_absent "I: still-tracked entry stays excluded" ">f+++++++ CLAUDE.md" "$TMP/i.out"

# ── Case J: entry outside .claude/ → fail-closed abort (no arbitrary excludes) ──
make_fixture j
make_overlay "$TMP/j/overlay"
printf '%s\n' "$TMP/j/overlay" > "$TMP/j/repo/scripts/deploy-overlay.local"
write_deletions "$TMP/j/overlay" "docs/deployment.md"
rc=$(run_deploy "$TMP/j" "$TMP/j.out")
check_rc     "J: out-of-scope entry aborts rc=4" 4 "$rc"
check_has    "J: abort names the manifest" "ERROR: overlay deletion manifest" "$TMP/j.out"
check_has    "J: abort quotes the offending entry" "entry must start with '.claude/': 'docs/deployment.md'" "$TMP/j.out"
check_absent "J: aborted deploy transfers nothing" "rules/toolkit-only.md" "$TMP/j.out"

# ── Case K: parent traversal → fail-closed abort ──
make_fixture k
make_overlay "$TMP/k/overlay"
printf '%s\n' "$TMP/k/overlay" > "$TMP/k/repo/scripts/deploy-overlay.local"
write_deletions "$TMP/k/overlay" ".claude/../outside.md"
rc=$(run_deploy "$TMP/k" "$TMP/k.out")
check_rc     "K: traversal entry aborts rc=4" 4 "$rc"
check_has    "K: abort quotes the traversal entry" "entry must not contain '..': '.claude/../outside.md'" "$TMP/k.out"

# ── Case L: empty manifest → no-op, never an error ──
make_fixture l
make_overlay "$TMP/l/overlay"
printf '%s\n' "$TMP/l/overlay" > "$TMP/l/repo/scripts/deploy-overlay.local"
: > "$TMP/l/overlay/.claude-deploy-deletions"
rc=$(run_deploy "$TMP/l" "$TMP/l.out")
check_rc     "L: empty manifest exits 0" 0 "$rc"
check_absent "L: empty manifest reports no deletions" "declared deletion" "$TMP/l.out"
check_has    "L: empty manifest leaves the tracked count alone" "overlay: excluding 2 overlay-owned paths" "$TMP/l.out"
check_has    "L: empty manifest still deploys other files" "generic-only.md" "$TMP/l.out"

echo "==== Results: $pass passed, $fail failed ===="
[ "$fail" -eq 0 ]
