# Quality

Multi-perspective review with parallel agents.

## Usage
```
/quality              # Review git diff
/quality {path}       # Review file/dir
/quality #{PR}        # Review PR
/quality --fast       # auditor + verifier only
/quality --api        # api-reviewer focus
/quality --perf       # perf-critic focus
```

## Pipeline

```
/quality
    ├──→ auditor      (security, races, leaks)
    ├──→ perf-critic  (N+1, complexity)
    ├──→ api-reviewer (if handlers)
    └──→ verifier     (tests pass)
           ↓
       Synthesis
```

## Workflow

1. **Scope**: `git diff --name-only HEAD` or provided path
2. **Parallel agents**: Launch all applicable simultaneously
3. **Synthesize**: Combine into unified report

## Output

```markdown
## Quality Report: {scope}

### Risk: 🔴/🟡/🟢

| Category | Issues | Severity |
|----------|--------|----------|
| Security | N | crit/high |
| Perf | N | high/med |
| API | N | major/minor |
| Tests | pass/fail | — |

### Blocking
{must fix}

### Verdict
✅ Ready / ⚠️ Fix Required / 🚫 Blocked
```

## Constraints
- Parallel execution required
- Synthesis required (no raw dumps)
- Critical/High = blocked
