#!/usr/bin/env bash
# check-workflow-syntax.sh — parse-check every workflow script by compiling
# its body as an AsyncFunction (makes top-level await AND top-level return
# legal, matching the Workflow tool's execution context). node --check would
# false-fail valid workflows (top-level return is illegal in plain ESM).
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
WF_DIR="${WORKFLOWS_DIR:-$REPO_DIR/.claude/workflows}"

shopt -s nullglob
files=("$WF_DIR"/*.js)
if [ "${#files[@]}" -eq 0 ]; then
  echo "ERROR: no *.js workflows found in $WF_DIR" >&2
  exit 1
fi

status=0
for f in "${files[@]}"; do
  if node -e '
    const fs = require("fs");
    const src = fs.readFileSync(process.argv[1], "utf8");
    if (!/^export const meta = \{/m.test(src)) {
      console.error("missing `export const meta = {` literal");
      process.exit(1);
    }
    const body = src.replace(/^export const meta/m, "const meta");
    const AsyncFunction = Object.getPrototypeOf(async function () {}).constructor;
    new AsyncFunction("agent", "pipeline", "parallel", "log", "phase", "args", "budget", "workflow", body);
  ' "$f" 2>&1; then
    echo "OK: $(basename "$f")"
  else
    echo "FAIL: $(basename "$f")"
    status=1
  fi
done
exit $status
