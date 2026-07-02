# Baseline Analysis: Team Coordination Patterns

Analysis of agent behavior WITHOUT the team coordination skill.

## Summary of Findings

| Scenario | Baseline Behavior | Missing Elements |
|----------|-------------------|------------------|
| **Multi-Task (4 features)** | Created team with agents-workbench workflow | No Architect role, No QA role, generic "feature agents" |
| **Simple Bug Fix** | Correctly avoided team ✅ | N/A - handled well |
| **Architectural Decision** | Escalated to "team lead or architect" ✅ | Assumes role exists, doesn't know who to ask |
| **QA Coordination** | Requested code review from "teammate or lead" | No specific QA agent, vague review process |
| **Wave Management (8 tasks)** | Created 4 teammates sensibly | No wave concept, no Architect/QA, no max-5 limit awareness |
| **Team Shutdown** | Recognized worktree cleanup needed ✅ | No team shutdown, no TeamDelete, teammates left running |

## Key Patterns Identified

### Pattern 1: Generic Teams Without Roles

**Observation:** When creating teams, agents spawn generic "feature agents" or "worker agents" without specialized roles.

**Verbatim examples:**

- "4 Teammate Agents - each gets dedicated worktree"
- "Profile Agent, Notification Agent, Export Agent, Dashboard Agent"

**Missing:**

- No Systems Architect role for architectural decisions
- No QA Agent role for testing and quality gates
- Workers aren't distinguished as "workers reporting to Architect/QA"

**Rationalization:** Agents think in terms of "divide features among agents" not "structured team with roles"

---

### Pattern 2: Good Escalation Instinct, Unclear Target

**Observation:** When hitting architectural decisions, agents DO recognize need to escalate.

**Verbatim examples:**

- "I would ask the team lead or architect"
- "Request review from teammate (code reviewer agent or team lead)"

**Missing:**

- They don't assume Architect/QA roles exist as part of team structure
- They're guessing who to ask ("or" indicates uncertainty)
- No clear communication protocol

**Rationalization:** "Someone should review this, but I don't know the team structure"

---

### Pattern 3: No Wave Management Concept

**Observation:** When faced with >5 agents needed, agents create "optimal number" without wave concept.

**Verbatim examples:**

- "4 Parallel Teammates + 1 Lead" for 8 tasks
- No mention of sequential waves
- No mention of 5-agent maximum

**Missing:**

- No concept of "Wave 1 (tasks 1-4), Wave 2 (tasks 5-8)"
- No mention of keeping Architect/QA constant across waves
- No plan for wave transitions

**Rationalization:** "Optimize parallelism" without considering team size constraints

---

### Pattern 4: Partial Cleanup

**Observation:** Agents recognize need for worktree cleanup but not team shutdown.

**Verbatim examples:**

- "Remove completed worktrees"
- "Update AGENTS.md to reflect completed work"
- "Run /compact after major task"

**Missing:**

- No mention of TeamDelete
- No mention of shutting down teammate agents
- No mention of full team teardown

**Rationalization:** "Clean up artifacts" but forget the team infrastructure itself

---

### Pattern 5: Good Judgment on When NOT to Use Teams

**Observation:** Agents correctly identify trivial tasks don't need teams ✅

**Verbatim examples:**

- "No. Absolutely not." (for typo fix)
- "Using a team would be massive overhead for a one-word fix"

**This pattern is GOOD** - no skill needed to fix this.

---

### Pattern 6: Agents-Workbench Integration Works

**Observation:** Agents naturally use agents-workbench workflow from CLAUDE.md ✅

**Verbatim examples:**

- "Stay on agents-workbench branch"
- "Each teammate gets dedicated worktree"
- "Update AGENTS.md for task tracking"

**This pattern is GOOD** - they follow existing CLAUDE.md guidance.

---

## What the Skill Must Address

Based on these patterns, the skill MUST:

1. **Define Required Roles:**
   - Systems Architect (required) - architectural decisions, code quality, dependencies
   - QA Agent (required) - testing, quality gates, stability
   - Workers (1-3) - implementation under Architect guidance

2. **Establish Communication Protocol:**
   - Workers → Architect: for architectural decisions
   - Workers → QA: when changes ready for testing
   - QA → Architect: for quality findings requiring architectural changes

3. **Introduce Wave Management:**
   - Max 5 agents (1 Architect + 1 QA + 3 Workers)
   - For >5 tasks: sequential waves
   - Architect + QA stay constant across waves
   - Workers rotate

4. **Mandate Team Shutdown:**
   - TeamDelete after work complete
   - Clean up team infrastructure, not just worktrees
   - Before starting new unrelated work

5. **Provide Commands:**
   - `/team:plan` - planning phase on agents-workbench
   - `/team:execute` - spawn team with proper structure
   - `/team:shutdown` - proper teardown

## Rationalizations to Counter

The skill must explicitly forbid these rationalizations:

| Rationalization | Counter |
|----------------|---------|
| "I'll just create generic teammates" | Required structure: 1 Architect + 1 QA + N Workers |
| "Someone should review this" | Specific protocol: Workers report to QA for testing |
| "I'll create N agents for N tasks" | Max 5 agents. Use waves if more tasks. |
| "I'll clean up worktrees" | Also shutdown team with TeamDelete |
| "I'll optimize parallelism" | Optimize within 5-agent constraint + roles |
| "Team lead can handle architecture" | Architect is dedicated role, not lead's side job |

## Success Criteria for Skill

When skill is loaded, agents should:

1. ✅ Create teams with Architect + QA + Workers structure
2. ✅ Follow communication protocol (Workers ↔ Architect, Workers → QA)
3. ✅ Plan waves when >5 agents needed
4. ✅ Use TeamDelete for shutdown
5. ✅ Still correctly avoid teams for trivial tasks (preserve Pattern 5)
