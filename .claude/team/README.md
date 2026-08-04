# Team Coordination System

Structured team workflow for parallel implementation with architectural oversight and quality gates. The three `team-*` skills (`/team-plan`, `/team-execute`, `/team-shutdown`) coordinate 2+ independent implementation tasks requiring parallel work by agent teams. (The former command-file copies under `.claude/commands/` drifted and were removed; the skills are the single source of truth.)

## Directory Structure

```
~/.claude/
  skills/
    team-plan/SKILL.md        # /team-plan skill
    team-execute/SKILL.md     # /team-execute skill
    team-shutdown/SKILL.md    # /team-shutdown skill
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

## How the Skills Work Together

Three-phase workflow:

1. **`/team-plan`** -- Structured planning phase: task decomposition, estimation, risk analysis, and wave sequencing (methodology in `lib/planning-guide.md`), with git state and worktree safety validated before any work begins (`lib/branch-validator.md`).

2. **`/team-execute`** -- Spawn the team and implement. Roles are the Principal Engineer (architecture, conventions, security review), the QA Engineer (quality gates, test validation, merge readiness), and Workers implementing in isolated worktrees. The `lib/` files below are reference material for these phases; agents do not load them automatically.

3. **`/team-shutdown`** -- Clean shutdown: terminates agents and delegates branch/worktree cleanup to `superpowers:finishing-a-development-branch`, preserving context on `agents-workbench`.

## Library Files (reference material)

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
| Principal Engineer | 1 (mandatory) | Architectural decisions, pattern selection, security review |
| QA Engineer | 1 (mandatory) | Quality gates, test validation, merge readiness |
| Workers | 1-3 | Implementation in isolated worktrees |

Maximum 5 agents total. Tasks exceeding 3 workers are sequenced into waves.
