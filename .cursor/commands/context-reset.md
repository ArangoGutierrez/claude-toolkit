# Context Reset
`/context-reset`→reset|`--status`→show health
Reset/inspect context tracking state

## What It Does
`context-monitor.sh` estimates token usage:
- Iterations:+8%|Files:+2%|Tasks:+15%|Summarize:-25%

## Health States
|Score|State|Action|
|0-50%|Healthy|Continue|
|50-75%|Filling|Consider `/summarize`|
|75-90%|Critical|Run `/summarize`|
|90%+|Degraded|New session|

## Flow
### --status
Read `.cursor/context-state.json`:
```
Health: {state} | Score: {N}% | Tasks: {N} | Summarizes: {N}
Recommendation: {last_recommendation}
```

### Reset (default)
```bash
rm -f .cursor/context-state.json .cursor/context-state.lock
echo "✓ Context tracking reset."
```

## When to Use
|Situation|Action|
|after `/summarize`|`/context-reset` (recalibrate)|
|false "stuck"|`/context-reset`|
|fresh start|`/context-reset`|
|check health|`/context-reset --status`|

## Config
`~/.cursor/context-config.json`:
```json
{
  "thresholds": { "healthy_max": 50, "filling_max": 75, "critical_max": 90 },
  "weights": { "iteration": 8, "file": 2, "task": 15, "summarize_recovery": 25 },
  "tasks_before_new_session": 3
}
```

## Troubleshoot
|Issue|Fix|
|false-stuck|run `/context-reset`|
|score-wrong|check config weights|reset to recalibrate|
|no-recommendations|verify hook in hooks.json `stop` array|
