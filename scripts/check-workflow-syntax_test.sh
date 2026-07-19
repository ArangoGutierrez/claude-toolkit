#!/usr/bin/env bash
# check-workflow-syntax_test.sh — harness for check-workflow-syntax.sh
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUBJECT="$SCRIPT_DIR/check-workflow-syntax.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
pass=0; fail=0
check() { # <desc> <expected_rc> <actual_rc>
  if [ "$2" -eq "$3" ]; then pass=$((pass+1)); echo "PASS: $1"; else fail=$((fail+1)); echo "FAIL: $1 (expected rc=$2 got rc=$3)"; fi
}

# Fixture 1: valid workflow (top-level await + return must be accepted)
mkdir -p "$TMP/valid"
cat > "$TMP/valid/good.js" <<'EOF'
export const meta = {
  name: 'good',
  description: 'fixture workflow',
}
const x = await agent('do a thing')
return { x }
EOF
rc=0; WORKFLOWS_DIR="$TMP/valid" bash "$SUBJECT" > "$TMP/out1" 2>&1 || rc=$?
check "valid workflow accepted" 0 "$rc"
grep -q "OK: good.js" "$TMP/out1" && { pass=$((pass+1)); echo "PASS: OK line emitted"; } || { fail=$((fail+1)); echo "FAIL: OK line missing"; }

# Fixture 2: syntax error must be rejected
mkdir -p "$TMP/broken"
cat > "$TMP/broken/bad.js" <<'EOF'
export const meta = {
  name: 'bad',
  description: 'fixture with a syntax error',
}
const x = await agent('unterminated
EOF
rc=0; WORKFLOWS_DIR="$TMP/broken" bash "$SUBJECT" > "$TMP/out2" 2>&1 || rc=$?
check "syntax error rejected" 1 "$rc"

# Fixture 3: missing meta literal must be rejected
mkdir -p "$TMP/nometa"
cat > "$TMP/nometa/nometa.js" <<'EOF'
const x = await agent('no meta block here')
return { x }
EOF
rc=0; WORKFLOWS_DIR="$TMP/nometa" bash "$SUBJECT" > "$TMP/out3" 2>&1 || rc=$?
check "missing meta rejected" 1 "$rc"

# Fixture 4: empty dir must fail loudly, not pass silently
mkdir -p "$TMP/empty"
rc=0; WORKFLOWS_DIR="$TMP/empty" bash "$SUBJECT" > "$TMP/out4" 2>&1 || rc=$?
check "empty dir fails loudly" 1 "$rc"

echo "---"; echo "pass=$pass fail=$fail"
[ "$fail" -eq 0 ]
