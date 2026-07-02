#!/bin/bash
# skill-structure_test.sh — assert SKILL.md wires the kickoff front-door contract.
# Run: bash skill-structure_test.sh < /dev/null
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SK="$ROOT/SKILL.md"
FAIL=0
ok(){  echo "PASS: $1"; }
bad(){ echo "FAIL: $1"; FAIL=$((FAIL+1)); }
hasf(){  local l="$1" pat="$2"; if grep -qF -- "$pat" "$SK"; then ok "$l"; else bad "$l — missing [$pat]"; fi; }
hasre(){ local l="$1" re="$2";  if grep -qE  "$re"  "$SK"; then ok "$l"; else bad "$l — missing /$re/"; fi; }

hasre "name=kickoff"            '^name: kickoff$'
hasre "user-invocable"          '^user-invocable: true$'
hasf  "references enrich.sh"     "scripts/enrich.sh"
hasf  "handles passthrough"      "KICKOFF_PASSTHROUGH"
hasf  "sets goal Acceptance"     "Acceptance:"
hasf  "routes to brainstorming"  "brainstorming"
hasf  "routes orchestrate path"  "orchestrate"

echo ""
if [ "$FAIL" -eq 0 ]; then echo "All tests PASS"; exit 0; else echo "$FAIL FAILED"; exit 1; fi
