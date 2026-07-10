#!/bin/bash
# Tests for detect-team-context.sh — team detection from filesystem signals.
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
SUT="$HERE/detect-team-context.sh"
FAIL=0

run() {  # run --root <dir>; echoes classification
    bash "$SUT" --root "$1"
}

# Test 1: team — a plan under .agents/plans/ AND an unchecked task in AGENTS.md
T1=$(mktemp -d); trap 'rm -rf "$T1" "$T2" "$T3" "$T4"' EXIT
mkdir -p "$T1/.agents/plans"; echo "# plan" > "$T1/.agents/plans/p.md"
printf -- '- [ ] do the thing\n' > "$T1/AGENTS.md"
OUT=$(run "$T1")
if [ "$OUT" != "team" ]; then echo "FAIL test1: expected team, got '$OUT'"; FAIL=1; fi

# Test 2: solo — unchecked task but NO plan files
T2=$(mktemp -d)
printf -- '- [ ] orphan task\n' > "$T2/AGENTS.md"
OUT=$(run "$T2")
if [ "$OUT" != "solo" ]; then echo "FAIL test2: expected solo (no plans), got '$OUT'"; FAIL=1; fi

# Test 3: solo — plan files exist but all AGENTS.md tasks are checked
T3=$(mktemp -d)
mkdir -p "$T3/.agents/plans"; echo "# plan" > "$T3/.agents/plans/p.md"
printf -- '- [x] already done\n' > "$T3/AGENTS.md"
OUT=$(run "$T3")
if [ "$OUT" != "solo" ]; then echo "FAIL test3: expected solo (all checked), got '$OUT'"; FAIL=1; fi

# Test 4: solo — empty workspace (no AGENTS.md, no plans)
T4=$(mktemp -d)
OUT=$(run "$T4")
if [ "$OUT" != "solo" ]; then echo "FAIL test4: expected solo (empty), got '$OUT'"; FAIL=1; fi

if [ "$FAIL" -eq 0 ]; then echo "PASS"; else exit 1; fi
