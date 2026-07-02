# Parallel

Run independent tasks concurrently via subagents.

## Usage
```
/parallel task1 | task2 | task3
/parallel --analyze        # Check AGENTS.md for parallel opportunities
/parallel --from-agents    # Auto-run parallel [TODO]s
```

## Flow

1. **Parse**: Split by `|`
2. **Deps**: Check file overlap, data flow, explicit deps
3. **Group**: Independent → parallel, dependent → sequential
4. **Execute**: Launch Task subagents (fast model, max 4)
5. **Merge**: Report results, update AGENTS.md

## Dependency Rules

| Signal | Parallel? |
|--------|-----------|
| Same file | No |
| "after X", "needs X" | No |
| "test X" | No (needs impl) |
| Different dirs | Yes |
| Different concerns | Yes |

## Output
```
## /parallel Results
Executed: N tasks (P parallel, S sequential)
Changes: {task}: {files}
Next: {remaining or "done"}
```
