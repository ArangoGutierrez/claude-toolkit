#!/bin/bash
# verify-gate_test.sh — TDD harness for verify-gate.sh. Run: bash verify-gate_test.sh < /dev/null
# Directives inherent to a sourcing test harness (must precede the first command):
#   SC1090: $SH is sourced from a variable path by design.
#   SC2034: env overrides are consumed by the sourced verify-gate.sh.
# shellcheck disable=SC1090,SC2034
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SH="$ROOT/verify-gate.sh"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
FAIL=0
ok(){  echo "PASS: $1"; }
bad(){ echo "FAIL: $1"; FAIL=$((FAIL+1)); }
is(){  local l="$1" got="$2" want="$3"; if [ "$got" = "$want" ]; then ok "$l"; else bad "$l (got=$got want=$want)"; fi; }
has(){ local l="$1" pat="$2" f="$3"; if grep -qF -- "$pat" "$f"; then ok "$l"; else bad "$l — missing [$pat]"; fi; }

source "$SH"

# ── Task 1: extract_rows ──────────────────────────────────────────────────────
{
  printf '%s\n' '{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","name":"Bash","input":{"command":"go test ./..."}}]}}'
  printf '%s\n' '{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Edit","input":{"file_path":"/repo/pkg/x.go"}}]}}'
} > "$WORK/t1.jsonl"
extract_rows "$WORK/t1.jsonl" > "$WORK/rows1.out" 2>&1
has "extract: Bash command row"   "$(printf 'Bash\tgo test ./...')"   "$WORK/rows1.out"
has "extract: Edit file_path row" "$(printf 'Edit\t/repo/pkg/x.go')"  "$WORK/rows1.out"

# ── Task 2: code_changed ──────────────────────────────────────────────────────
GO_EDIT=$(printf 'Edit\t/repo/pkg/x.go')
MD_EDIT=$(printf 'Edit\t/repo/README.md')
PY_WRITE=$(printf 'Write\t/repo/app.py')
READ_ROW=$(printf 'Read\t/repo/pkg/x.go')
is "code_changed: .go edit -> file"  "$(printf '%s\n' "$GO_EDIT"  | code_changed)" "/repo/pkg/x.go"
is "code_changed: .py write -> file" "$(printf '%s\n' "$PY_WRITE" | code_changed)" "/repo/app.py"
is "code_changed: .md only -> empty" "$(printf '%s\n' "$MD_EDIT"  | code_changed)" ""
is "code_changed: Read .go -> empty" "$(printf '%s\n' "$READ_ROW" | code_changed)" ""

# ── Task 3: verification_ran (rc 0 = a verify command ran) ────────────────────
if printf 'Bash\tgo test ./...\n'    | verification_ran; then ok "verify: go test detected"; else bad "verify: go test not detected"; fi
if printf 'Bash\tgolangci-lint run\n'| verification_ran; then ok "verify: golangci-lint detected"; else bad "verify: golangci-lint not detected"; fi
# Guard discriminator: a NON-verify Bash command must NOT count as verification.
if printf 'Bash\tls -la /repo\n'     | verification_ran; then bad "verify: 'ls' wrongly counted"; else ok "verify: 'ls' is not verification"; fi
# Override: a custom pattern detects a custom command.
if printf 'Bash\tmycheck --all\n'    | VERIFY_GATE_PATTERN='mycheck' verification_ran; then ok "verify: VERIFY_GATE_PATTERN override"; else bad "verify: pattern override ignored"; fi

# ── Task 4: main() end-to-end ─────────────────────────────────────────────────
mk_block() { # .go Edit + a NON-verify Bash (ls)
  {
    printf '%s\n' '{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Edit","input":{"file_path":"/repo/pkg/x.go"}}]}}'
    printf '%s\n' '{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Bash","input":{"command":"ls -la /repo"}}]}}'
  } > "$1"
}
mk_ok() { # .go Edit + a verify Bash (go test)
  {
    printf '%s\n' '{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Edit","input":{"file_path":"/repo/pkg/x.go"}}]}}'
    printf '%s\n' '{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Bash","input":{"command":"go test ./..."}}]}}'
  } > "$1"
}
mk_docs() { printf '%s\n' '{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Edit","input":{"file_path":"/repo/README.md"}}]}}' > "$1"; }
run_gate() { # $1=transcript $2=stop_hook_active(true/false); sets RC, ERROUT
  local tj; tj=$(jq -nc --arg t "$1" --argjson s "$2" '{transcript_path:$t, stop_hook_active:$s}')
  ERROUT="$WORK/err.out"
  printf '%s' "$tj" | bash "$SH" 2>"$ERROUT" >/dev/null; RC=$?
}

mk_block "$WORK/block.jsonl"; run_gate "$WORK/block.jsonl" false
is  "main: code change + no verify -> BLOCK" "$RC" 2
has "main: block names changed file"        "/repo/pkg/x.go" "$ERROUT"

mk_ok "$WORK/ok.jsonl"; run_gate "$WORK/ok.jsonl" false
is "main: code change + verify ran -> ALLOW" "$RC" 0

mk_block "$WORK/guard.jsonl"; run_gate "$WORK/guard.jsonl" false
is "main: non-verify Bash still BLOCKS" "$RC" 2

mk_docs "$WORK/docs.jsonl"; run_gate "$WORK/docs.jsonl" false
is "main: docs-only change -> ALLOW" "$RC" 0

mk_block "$WORK/loop.jsonl"; run_gate "$WORK/loop.jsonl" true
is "main: stop_hook_active -> ALLOW (loop guard)" "$RC" 0

run_gate "$WORK/nonexistent.jsonl" false
is "main: missing transcript -> ALLOW" "$RC" 0

printf 'this is not json\n' > "$WORK/bad.jsonl"; run_gate "$WORK/bad.jsonl" false
is "main: malformed transcript -> ALLOW" "$RC" 0

mk_block "$WORK/esc.jsonl"
ERROUT="$WORK/err.esc"
printf '%s' "$(jq -nc --arg t "$WORK/esc.jsonl" '{transcript_path:$t,stop_hook_active:false}')" | VERIFY_GATE=off bash "$SH" 2>"$ERROUT" >/dev/null; RC=$?
is "main: VERIFY_GATE=off -> ALLOW" "$RC" 0

# ── Task 5: wiring ────────────────────────────────────────────────────────────
SETTINGS="$ROOT/../settings.json"
if jq -e '.hooks.Stop[].hooks[]? | select((.command // "") | test("verify-gate.sh"))' "$SETTINGS" >/dev/null 2>&1; then
  ok "wiring: verify-gate.sh registered under Stop"
else
  bad "wiring: verify-gate.sh NOT in settings.json Stop hooks"
fi

echo ""
if [ "$FAIL" -eq 0 ]; then echo "All tests PASS"; exit 0; else echo "$FAIL FAILED"; exit 1; fi
