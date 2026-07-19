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

# Case 5: a literal | in a description is escaped in the emitted row —
# otherwise it injects a phantom Markdown table column (fresh fixture dir:
# Case 4 left a broken workflow in $TMP/wf)
mkdir -p "$TMP/wf2"
cat > "$TMP/wf2/pipey.js" <<'EOF'
export const meta = {
  name: 'pipey',
  description: 'runs a | b safely',
}
return 1
EOF
cat > "$TMP/doc2.md" <<'EOF'
<!-- workflow-table:begin -->
<!-- workflow-table:end -->
EOF
rc=0; WORKFLOWS_DIR="$TMP/wf2" DOCS_FILE="$TMP/doc2.md" bash "$SUBJECT" || rc=$?
check "pipe-description run" 0 "$rc"
grep -qF '| `pipey` | `/pipey` | runs a \| b safely |' "$TMP/doc2.md" \
  && { pass=$((pass+1)); echo "PASS: pipe escaped in row"; } || { fail=$((fail+1)); echo "FAIL: pipe not escaped"; }

# Case 6: END marker with trailing whitespace must be rejected LOUDLY with the
# doc untouched — inexact markers previously deleted everything after the
# table while printing OK (confirmed critical, live E2E 2026-07-19)
printf '# T\n\n<!-- workflow-table:begin -->\nold\n<!-- workflow-table:end --> \n\ntail stays\n' > "$TMP/doc3.md"
cp "$TMP/doc3.md" "$TMP/doc3.orig"
rc=0; WORKFLOWS_DIR="$TMP/wf2" DOCS_FILE="$TMP/doc3.md" bash "$SUBJECT" 2>/dev/null || rc=$?
check "inexact END marker rejected" 1 "$rc"
if diff -q "$TMP/doc3.orig" "$TMP/doc3.md" > /dev/null; then pass=$((pass+1)); echo "PASS: doc untouched on inexact END"; else fail=$((fail+1)); echo "FAIL: doc modified on inexact END"; fi

# Case 7: BEGIN marker with trailing whitespace — same contract (previously a
# silent no-op that still printed OK)
printf '# T\n\n<!-- workflow-table:begin --> \nold\n<!-- workflow-table:end -->\n\ntail stays\n' > "$TMP/doc4.md"
cp "$TMP/doc4.md" "$TMP/doc4.orig"
rc=0; WORKFLOWS_DIR="$TMP/wf2" DOCS_FILE="$TMP/doc4.md" bash "$SUBJECT" 2>/dev/null || rc=$?
check "inexact BEGIN marker rejected" 1 "$rc"
if diff -q "$TMP/doc4.orig" "$TMP/doc4.md" > /dev/null; then pass=$((pass+1)); echo "PASS: doc untouched on inexact BEGIN"; else fail=$((fail+1)); echo "FAIL: doc modified on inexact BEGIN"; fi

# Case 8: extraction is scoped to the meta block — a decoy name:/description:
# object ABOVE meta must not win (previously first-match-anywhere)
mkdir -p "$TMP/wf3"
cat > "$TMP/wf3/scoped.js" <<'EOF'
const DECOY = {
  name: 'decoy',
  description: 'decoy description',
}
export const meta = {
  name: 'scoped',
  description: 'the real description',
}
return 1
EOF
cat > "$TMP/doc5.md" <<'EOF'
<!-- workflow-table:begin -->
<!-- workflow-table:end -->
EOF
rc=0; WORKFLOWS_DIR="$TMP/wf3" DOCS_FILE="$TMP/doc5.md" bash "$SUBJECT" || rc=$?
check "meta-scoped run" 0 "$rc"
grep -qF '| `scoped` | `/scoped` | the real description |' "$TMP/doc5.md" \
  && { pass=$((pass+1)); echo "PASS: meta block wins over decoy"; } || { fail=$((fail+1)); echo "FAIL: decoy leaked into row"; }

echo "---"; echo "pass=$pass fail=$fail"
[ "$fail" -eq 0 ]
