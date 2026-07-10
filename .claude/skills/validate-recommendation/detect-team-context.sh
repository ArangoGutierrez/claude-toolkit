#!/bin/bash
# detect-team-context.sh — classify the workspace as "team" or "solo".
#
# Prints "team" when BOTH hold (an active team coordination context):
#   1. at least one plan file exists under <root>/.agents/plans/
#   2. <root>/AGENTS.md has at least one UNCHECKED task line ("- [ ]")
# Otherwise prints "solo". Always exits 0.
#
# Usage: detect-team-context.sh [--root <dir>]   (default root = git toplevel, else $PWD)
# Consumed by the validate-recommendation skill to decide whether to enable the
# PE+QA panelists. TeamList (a live team) is checked separately by the skill.
set -uo pipefail

ROOT=""
if [ "${1:-}" = "--root" ]; then ROOT="${2:-}"; fi
if [ -z "$ROOT" ]; then
    ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
fi

plans_present=false
if ls "$ROOT"/.agents/plans/*.md >/dev/null 2>&1; then
    plans_present=true
fi

unchecked_task=false
if [ -f "$ROOT/AGENTS.md" ] && grep -qE '^[[:space:]]*-[[:space:]]\[[[:space:]]\]' "$ROOT/AGENTS.md"; then
    unchecked_task=true
fi

if [ "$plans_present" = true ] && [ "$unchecked_task" = true ]; then
    echo "team"
else
    echo "solo"
fi
