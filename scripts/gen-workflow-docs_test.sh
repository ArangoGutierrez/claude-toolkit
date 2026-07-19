#!/usr/bin/env bash
# gen-workflow-docs_test.sh — harness for gen-workflow-docs.sh
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUBJECT="$SCRIPT_DIR/gen-workflow-docs.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
pass=0; fail=0
check() { if [ "$2" -eq "$3" ]; then pass=$((pass+1)); echo "PASS: $1"; else fail=$((fail+1)); echo "FAIL: $1 (expected rc=$2 got rc=$3)"; fi }

mkdir -p "$TMP/wf"
cat > "$TMP/wf/fixture-flow.js" <<'EOF'
export const meta = {
  name: 'fixture-flow',
  description: 'a fixture that proves extraction works',
}
return 1
EOF
cat > "$TMP/doc.md" <<'EOF'
# Library

<!-- workflow-table:begin -->
stale content that must be replaced
<!-- workflow-table:end -->

tail prose that must survive
EOF

# Case 1: generates the exact discriminating row and preserves surrounding prose
rc=0; WORKFLOWS_DIR="$TMP/wf" DOCS_FILE="$TMP/doc.md" bash "$SUBJECT" || rc=$?
check "generator runs" 0 "$rc"
grep -qF '| `fixture-flow` | `/fixture-flow` | a fixture that proves extraction works |' "$TMP/doc.md" \
  && { pass=$((pass+1)); echo "PASS: exact row generated"; } || { fail=$((fail+1)); echo "FAIL: exact row missing"; }
grep -q 'stale content that must be replaced' "$TMP/doc.md" \
  && { fail=$((fail+1)); echo "FAIL: stale content survived"; } || { pass=$((pass+1)); echo "PASS: stale content replaced"; }
grep -q 'tail prose that must survive' "$TMP/doc.md" \
  && { pass=$((pass+1)); echo "PASS: tail prose preserved"; } || { fail=$((fail+1)); echo "FAIL: tail prose lost"; }

# Case 2: idempotent — second run changes nothing
cp "$TMP/doc.md" "$TMP/doc.first"
WORKFLOWS_DIR="$TMP/wf" DOCS_FILE="$TMP/doc.md" bash "$SUBJECT"
if diff -q "$TMP/doc.first" "$TMP/doc.md" > /dev/null; then pass=$((pass+1)); echo "PASS: idempotent"; else fail=$((fail+1)); echo "FAIL: not idempotent"; fi

# Case 3: missing markers fail loudly
printf '# no markers here\n' > "$TMP/nomark.md"
rc=0; WORKFLOWS_DIR="$TMP/wf" DOCS_FILE="$TMP/nomark.md" bash "$SUBJECT" 2>/dev/null || rc=$?
check "missing markers rejected" 1 "$rc"

# Case 4: workflow missing a description fails loudly
cat > "$TMP/wf/nodesc.js" <<'EOF'
export const meta = {
  name: 'nodesc',
}
return 1
EOF
rc=0; WORKFLOWS_DIR="$TMP/wf" DOCS_FILE="$TMP/doc.md" bash "$SUBJECT" 2>/dev/null || rc=$?
check "missing description rejected" 1 "$rc"

echo "---"; echo "pass=$pass fail=$fail"
[ "$fail" -eq 0 ]
