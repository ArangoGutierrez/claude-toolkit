#!/usr/bin/env bash
set -euo pipefail
# fake-claude.sh — test double for `claude -p ... --output-format stream-json`.
# Models the real dependency's per-input behavior AND failure modes (not blanket
# success): activation, silence, co-activation, and invocation failure.
prompt=""
while [ $# -gt 0 ]; do case "$1" in -p) prompt="$2"; shift 2;; *) shift;; esac; done
case "$prompt" in
  *ERRCASE*) exit 1 ;;                                   # invocation failure (no output) → probe records null
  *TURNLIMIT*)                                           # --max-turns 1: real output BUT non-zero exit
    printf '%s\n' '{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Skill","input":{"skill":"kickoff"}}]}}'
    exit 1 ;;
  *COACT*)
    printf '%s\n' '{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Skill","input":{"skill":"kickoff"}},{"type":"tool_use","name":"Skill","input":{"skill":"goal"}}]}}'
    printf '%s\n' '{"type":"result","subtype":"success","result":"ok"}' ;;
  *ACT*)
    printf '%s\n' '{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Skill","input":{"skill":"kickoff"}}]}}'
    printf '%s\n' '{"type":"result","subtype":"success","result":"ok"}' ;;
  *)
    printf '%s\n' '{"type":"assistant","message":{"content":[{"type":"text","text":"no skill"}]}}'
    printf '%s\n' '{"type":"result","subtype":"success","result":"ok"}' ;;
esac
