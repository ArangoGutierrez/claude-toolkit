#!/usr/bin/env bash
# probe.sh <skill> <evals.json> <N> <staging_dir>
# env: CLAUDE_BIN (default claude), CLAUDE_MODEL (default claude-haiku-4-5-20251001)
# stdout: normalized results JSON {skill,n,cases:[{id,expect,runs:[[skill...]|null]}]}.
#
# Each probe runs `claude -p` with --max-turns 1 so we capture the ACTIVATION
# decision (the Skill tool_use) WITHOUT the inner agent executing the skill body.
# --max-turns 1 makes claude exit non-zero, so we gate on OUTPUT PRESENCE (did it
# emit any stream events?), not exit code: events present → extract (may be []);
# no events → a real invocation failure → null.
set -euo pipefail
skill="${1:?skill}"; evals="${2:?evals.json}"; N="${3:?N}"; stage="${4:?staging_dir}"
CLAUDE_BIN="${CLAUDE_BIN:-claude}"; CLAUDE_MODEL="${CLAUDE_MODEL:-claude-haiku-4-5-20251001}"
here="$(cd "$(dirname "$0")" && pwd)"
cases='[]'
while IFS= read -r c; do
  id=$(jq -r '.id' <<<"$c"); prompt=$(jq -r '.prompt' <<<"$c"); expect=$(jq -r '.expect' <<<"$c")
  runs='[]'
  for _ in $(seq 1 "$N"); do
    out=$(cd "$stage" && "$CLAUDE_BIN" -p "$prompt" --model "$CLAUDE_MODEL" \
            --output-format stream-json --verbose --max-turns 1 < /dev/null 2>/dev/null || true)
    nev=$(printf '%s\n' "$out" | jq -s '[.[]|.type]|length' 2>/dev/null || echo 0)
    if [ "${nev:-0}" -ge 1 ]; then
      activated=$(printf '%s\n' "$out" | jq -s -f "$here/extract.jq" 2>/dev/null || echo null)
    else
      activated=null
    fi
    runs=$(jq --argjson a "$activated" '. + [$a]' <<<"$runs")
  done
  cases=$(jq --arg id "$id" --arg ex "$expect" --argjson r "$runs" '. + [{id:$id,expect:$ex,runs:$r}]' <<<"$cases")
done < <(jq -c '.cases[]' "$evals")
jq -n --arg s "$skill" --argjson n "$N" --argjson c "$cases" '{skill:$s,n:$n,cases:$c}'
