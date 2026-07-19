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

grep -qF "$BEGIN" "$DOCS" && grep -qF "$END" "$DOCS" || {
  echo "ERROR: markers '$BEGIN' / '$END' not found in $DOCS" >&2; exit 1; }

shopt -s nullglob
files=("$WF_DIR"/*.js)
[ "${#files[@]}" -gt 0 ] || { echo "ERROR: no workflows in $WF_DIR" >&2; exit 1; }

TABLE="$(mktemp)"; trap 'rm -f "$TABLE" "$TABLE.new"' EXIT
{
  echo '| Workflow | Invoke | Purpose |'
  echo '|---|---|---|'
  for f in "${files[@]}"; do
    name="$(sed -n "s/^[[:space:]]*name: '\(.*\)',*$/\1/p" "$f" | head -1)"
    desc="$(sed -n "s/^[[:space:]]*description: '\(.*\)',*$/\1/p" "$f" | head -1)"
    if [ -z "$name" ] || [ -z "$desc" ]; then
      echo "ERROR: $(basename "$f"): meta needs single-line quoted name and description" >&2
      exit 1
    fi
    desc="${desc//|/\\|}"   # a literal | would inject a phantom table column
    printf '| `%s` | `/%s` | %s |\n' "$name" "$name" "$desc"
  done
} > "$TABLE"

awk -v begin="$BEGIN" -v end="$END" -v table="$TABLE" '
  $0 == begin { print; while ((getline line < table) > 0) print line; close(table); skipping = 1; next }
  $0 == end   { skipping = 0 }
  !skipping   { print }
' "$DOCS" > "$TABLE.new"
mv "$TABLE.new" "$DOCS"
echo "OK: regenerated table in $DOCS from ${#files[@]} workflow(s)"
