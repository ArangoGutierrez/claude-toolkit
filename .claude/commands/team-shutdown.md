# Team Shutdown Phase

## Team Structure

You are the **Team Lead**. You coordinate work from the `agents-workbench` branch. You do NOT make technical decisions.

**Mandatory Roles (spawn in this order):**

1. **Systems Architect** (spawn first): Makes architectural decisions, ensures code quality, reviews system integration. Location: `agents-workbench` (read-only access to source code).
2. **QA Agent** (spawn second): Tests implementations, verifies quality gates, blocks merges if issues found. Location: `agents-workbench` (read-only access to source code).
3. **Workers (1-3)**: Implement tasks following TDD. Ask Architect for design decisions. Report to QA when ready for testing. Location: dedicated worktrees (one per task).

**Team Size Limits:**
- Maximum 5 spawned agents: 1 Architect + 1 QA + up to 3 Workers
- You (Lead) do not count toward this limit
- More than 3 tasks: use waves (Architect and QA persist across waves, Workers rotate)

## Communication Protocol

- **Workers to Architect:** Design decisions (present 3 or more options with trade-offs)
- **Workers to QA:** Ready for testing (feature name, summary, test status)
- **QA to Architect:** Quality issues requiring design changes

## Common Mistakes

| Mistake | Fix |
|---------|-----|
| Creating generic teammates without roles | Use Architect + QA + Workers |
| "Team Lead (me) - Systems Architect" | Lead coordinates, Architect is a SEPARATE agent |
| Spawning N agents for N tasks (no limit) | Max 5. Use waves. |
| Workers making architectural decisions | Workers escalate to Architect |

---

## Shutdown Workflow

You are in the **SHUTDOWN** phase of team coordination.

**When to use:** All tasks complete, PRs merged (or explicitly abandoned).

**Steps:**

1. **Verify completion status:**
   - Check that all PRs are merged or explicitly abandoned
   - Run: `git branch --merged` to verify feature branches are merged
   - If PRs are still open, warn the user and confirm before proceeding

2. **Shutdown team agents:**
   - Use TeamDelete to remove team infrastructure
   - This shuts down ALL agents (Architect, QA, Workers)
   - CRITICAL: Do NOT skip this step. Leaving team infrastructure running wastes resources and pollutes context.

3. **Remove worktrees:**
   - Remove all worktrees in `.worktrees/`:
     ```
     git worktree remove .worktrees/<each-feature>
     ```
   - Verify: `git worktree list` should only show the main working tree

4. **Update AGENTS.md:**
   - Mark all tasks as complete (or abandoned with reason)
   - Record final status
   - Commit the update to agents-workbench (local only, never push)

5. **Context hygiene:**
   - Run `/compact Focus on next task` to clean up context
   - This prevents context pollution from the completed team work

---

## Common Shutdown Mistakes

| Mistake | Fix |
|---------|-----|
| Cleaning worktrees but not TeamDelete | Always TeamDelete FIRST, then worktrees |
| Skipping AGENTS.md update | Record final status for future reference |
| Leaving orphan branches | Verify with `git branch` after cleanup |
| Skipping /compact | Context hygiene prevents confusion in next task |

---

## Arguments

User arguments: $ARGUMENTS
