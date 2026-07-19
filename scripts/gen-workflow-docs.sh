#!/usr/bin/env bash
# gen-workflow-docs.sh — regenerate the workflow summary table in the docs
# from each workflow's meta literal. Contract: meta fields are single-line,
# single-quoted (enforced stylistically; extraction is line-based on purpose
# so the docs can never desync from what actually ships).
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
WF_DIR="${WORKFLOWS_DIR:-$REPO_DIR/.claude/workflows}"
DOCS="${DOCS_FILE:-$REPO_DIR/docs/patterns/workflow-library.md}"
BEGIN='<!-- workflow-table:begin -->'
END='<!-- workflow-table:end -->'

# -x (exact whole-line) is load-bearing: it must validate exactly what the
# awk below matches. A substring gate + exact-line awk let a marker with
# trailing whitespace/CRLF pass the gate and then silently delete everything
# after the table (confirmed live, 2026-07-19).
grep -qxF "$BEGIN" "$DOCS" && grep -qxF "$END" "$DOCS" || {
  echo "ERROR: exact marker lines '$BEGIN' / '$END' not found in $DOCS (check trailing whitespace/CRLF)" >&2; exit 1; }

shopt -s nullglob
files=("$WF_DIR"/*.js)
[ "${#files[@]}" -gt 0 ] || { echo "ERROR: no workflows in $WF_DIR" >&2; exit 1; }

TABLE="$(mktemp)"; trap 'rm -f "$TABLE" "$TABLE.new"' EXIT
{
  echo '| Workflow | Invoke | Purpose |'
  echo '|---|---|---|'
  for f in "${files[@]}"; do
    # Scope extraction to the meta literal: a name:/description: line
    # elsewhere in the file must never win over meta's fields.
    meta_block="$(sed -n '/^export const meta = {/,/^}/p' "$f")"
    name="$(printf '%s\n' "$meta_block" | sed -n "s/^[[:space:]]*name: '\(.*\)',*$/\1/p" | head -1)"
    desc="$(printf '%s\n' "$meta_block" | sed -n "s/^[[:space:]]*description: '\(.*\)',*$/\1/p" | head -1)"
    if [ -z "$name" ] || [ -z "$desc" ]; then
      echo "ERROR: $(basename "$f"): meta needs single-line quoted name and description" >&2
      exit 1
    fi
    desc="${desc//|/\\|}"   # a literal | would inject a phantom table column
    printf '| `%s` | `/%s` | %s |\n' "$name" "$name" "$desc"
  done
} > "$TABLE"

# The table is passed as awk's FIRST input file (NR==FNR), never via -v:
# -v applies escape processing to its value, so a backslash in the mktemp
# path silently emptied the table via a failed getline (getline returns -1,
# the loop saw "not > 0", awk exited 0). ARGV operands get no escaping, and
# an unreadable file makes awk exit non-zero, which set -e catches.
awk -v begin="$BEGIN" -v end="$END" '
  NR == FNR   { tbl[++n] = $0; next }
  $0 == begin { print; for (i = 1; i <= n; i++) print tbl[i]; skipping = 1; next }
  $0 == end   { skipping = 0 }
  !skipping   { print }
' "$TABLE" "$DOCS" > "$TABLE.new"
mv "$TABLE.new" "$DOCS"
echo "OK: regenerated table in $DOCS from ${#files[@]} workflow(s)"
