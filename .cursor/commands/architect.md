# Architect

Full architecture exploration with parallel prototyping.

## Usage
```
/architect {problem}
/architect {problem} --quick     # Skip prototypes
/architect {problem} --proto N   # Prototype top N (default: 2)
```

## Pipeline

```
arch-explorer → devil-advocate → [prototyper×2] → synthesizer
     ↓               ↓                 ↓              ↓
  3-5 options    challenge top    parallel impl    recommend
```

### Phase 1: Explore
Launch `arch-explorer` → 3-5 approaches + comparison matrix

### Phase 2: Challenge  
Launch `devil-advocate` on top recommendation → risks, blockers

### Phase 3: Prototype (parallel)
Launch 2× `prototyper` simultaneously → `.prototypes/{approach}/`

### Phase 4: Synthesize
Launch `synthesizer` → final recommendation with evidence

## Output

```markdown
# Architecture Decision: {Problem}

## Summary
{2-3 sentences}

## Approaches
| # | Approach | Effort | Risk | Validated |
|---|----------|--------|------|-----------|
| 1 | {name} ⭐ | M | L | ✓ |

## Recommendation: {Name}
Why: {evidence}
Trade-offs: {accepted cons}
Risks: {mitigations}

## Next Steps
1. {action}
```

## --quick Mode
Skip prototypes: `explorer → advocate → synthesizer`
Use for: early discussions, reversible decisions
