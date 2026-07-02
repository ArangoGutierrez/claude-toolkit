#!/bin/bash
# task-loop.sh - Prevent infinite loops
# Hook: stop
set -euo pipefail

if ! command -v jq &>/dev/null; then
    echo '{"decision":"continue"}'
    exit 0
fi

input=$(cat)
iteration=$(echo "$input" | jq -r '.loop_iteration // 0')
# Limit is the source of truth in this script. The matching value in
# hooks.json is documentation only (Cursor does not propagate hook-config
# fields into the stdin payload, so the prior `// 5` fallback was masking
# a no-op read).
LIMIT=5

if [ "$iteration" -ge "$LIMIT" ]; then
    echo "{\"decision\":\"stop\",\"reason\":\"Loop limit reached (${LIMIT})\"}"
else
    echo '{"decision":"continue"}'
fi
