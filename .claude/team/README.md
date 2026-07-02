# Team Coordination System

Structured team workflow for parallel implementation with architectural oversight and quality gates. Uses three slash commands (`/team-plan`, `/team-execute`, `/team-shutdown`) to coordinate 2+ independent implementation tasks requiring parallel work by agent teams.

## Directory Structure

```
~/.claude/
  commands/
    team-plan.md              # /team-plan slash command
    team-execute.md           # /team-execute slash command
    team-shutdown.md          # /team-shutdown slash command
  team/
    README.md                 # This file
    lib/
      planning-guide.md       # Planning methodology
      branch-validator.md     # Git branch sync validation
      qa-validator.md         # Language-aware QA validation
      architect-decisions.md  # Technology selection guidance
      architect-patterns.md   # Design patterns library
      architect-security.md   # STRIDE threat model
      architect-validation.md # Dependency/complexity analysis
      decision-template.md    # ADR template
    docs/
      baseline-analysis.md    # Agent behavior without structure
      baseline-scenarios.md   # Baseline test scenarios
    examples/
      decision-user-profile-caching.md
```

## How the Commands Work Together

Three-phase workflow:

1. **`/team-plan`** -- Structured planning phase. Reads `planning-guide.md` for task decomposition, estimation, risk analysis, and wave sequencing. Uses `branch-validator.md` to validate git state and worktree safety before any work begins.

2. **`/team-execute`** -- Spawn the team and implement. The Architect agent reads `architect-*.md` libraries for design decisions, patterns, security, and validation. The QA agent reads `qa-validator.md` for language-aware quality gates. Workers implement in isolated worktrees.

3. **`/team-shutdown`** -- Clean shutdown. Terminates agents, removes worktrees, preserves context on `agents-workbench`.

## Library Files

| File | Purpose |
|------|---------|
| `planning-guide.md` | Structured planning methodology: decomposition, estimation, risk assessment, wave sequencing, output format |
| `branch-validator.md` | Git branch sync validation and worktree creation safety checks |
| `qa-validator.md` | Language-aware QA validation for Go, TypeScript, Rust, and Python |
| `architect-decisions.md` | Technology and framework selection guidance with decision trees |
| `architect-patterns.md` | Design patterns library: architectural, creational, structural, behavioral |
| `architect-security.md` | STRIDE threat model with per-language mitigations |
| `architect-validation.md` | Dependency cycle detection, layer violation checks, complexity analysis, API contract validation |
| `decision-template.md` | ADR (Architecture Decision Record) template for recording decisions |

## Team Structure

| Role | Count | Responsibility |
|------|-------|---------------|
| Lead (you) | 1 | Coordination on `agents-workbench` branch |
| Architect | 1 (mandatory) | Architectural decisions, pattern selection, security review |
| QA | 1 (mandatory) | Quality gates, test validation, merge readiness |
| Workers | 1-3 | Implementation in isolated worktrees |

Maximum 5 agents total. Tasks exceeding 3 workers are sequenced into waves.

## Design Doc

Full design rationale: `docs/plans/2026-02-16-team-slash-commands-design.md`
