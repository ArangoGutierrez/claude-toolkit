#!/bin/bash
# dispatch-worker.sh — open a cmux worker split and hand it a brief.
#
# This lives in a script rather than inline in SKILL.md on purpose. The skill
# loader performs positional-parameter substitution on the SKILL.md body when
# the skill is invoked with arguments, so any inline `$1`, `$2` or awk `$4`
# is rewritten with words from those arguments before the agent ever reads it.
# A referenced file is read from disk and is not rewritten.
#
# Usage: dispatch-worker.sh <sol|opus> <task-id> <brief-path> <repo>
# Prints: "<task> <agent> <surface> <token>" for the dispatch ledger.
set -uo pipefail

agent="${1:?agent: sol|opus}"
task="${2:?task id}"
brief="${3:?brief path}"
repo="${4:?repo path}"

[ -f "$brief" ] || { echo "FATAL: brief not found: $brief" >&2; exit 1; }
[ -d "$repo" ]  || { echo "FATAL: repo not found: $repo" >&2; exit 1; }

tok="sprint-${task}"

case "$agent" in
  # --dangerously-bypass-approvals-and-sandbox lets the worker write files without
  # a per-tool approval prompt. It does NOT stop the worker asking the USER to
  # approve a design first: that behaviour comes from the operator's own standards
  # ("brainstorm before implementing"), which a dispatched worker inherits. Only
  # the brief can waive it. See the non-interactive clause in SKILL.md.
  sol)  cmd="codex exec -m gpt-5.6-sol --skip-git-repo-check --dangerously-bypass-approvals-and-sandbox - < $brief" ;;
  opus) cmd="claude --model opus --effort xhigh --permission-mode auto --dangerously-skip-permissions -p \"\$(cat $brief)\" < /dev/null" ;;
  *)    echo "FATAL: unknown agent: $agent" >&2; exit 1 ;;
esac

# `new-split` prints plain text ("OK surface:11 workspace:1"); there is no --json.
# cut, not awk, so this idiom stays correct if it is ever pasted back into SKILL.md.
surface=$(cmux new-split right --focus false | cut -d' ' -f2)
case "$surface" in
  surface:*) : ;;
  *) echo "FATAL: no surface captured for $task (got '$surface')" >&2; exit 1 ;;
esac

# The token only proves the worker's PROCESS ended. Capture its exit status to a
# file so the orchestrator can tell "finished" from "succeeded", and still verify
# the task's own done-when condition independently.
mkdir -p "$repo/.sprint/status"
chain="cd $repo && $cmd; echo \$? > $repo/.sprint/status/$task.rc; cmux wait-for -S $tok"
cmux send --surface "$surface" "$chain"'\n' >/dev/null || {
  echo "FATAL: send failed for $task on $surface" >&2; exit 1; }

echo "$task $agent $surface $tok"
