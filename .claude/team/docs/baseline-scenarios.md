# Baseline Test Scenarios for Team Coordination Skill

Run these scenarios WITHOUT the skill to establish baseline behavior.

## Scenario 1: Multi-Task Implementation (Clear Team Case)

**Prompt:**

```
I need to implement these features for tomorrow's demo:
1. User profile editing with avatar upload
2. Email notification system
3. Export data to CSV functionality
4. Admin dashboard with user stats

These are independent features. Can you help?
```

**Expected (ideal):**

- Recognize need for team (4 independent tasks)
- Create: 1 Architect + 1 QA + 2-3 Workers
- Use agents-workbench for coordination
- Assign tasks to workers
- Workers report to QA when done
- Architect available for design questions

**What we're testing:**

- Do they create team at all?
- Do they create proper structure (Architect/QA/Workers)?
- Or just generic "teammate1, teammate2"?
- Do they use agents-workbench properly?

**Pressures:** Time, multiple independent tasks

---

## Scenario 2: Simple Bug Fix (Should NOT Use Team)

**Prompt:**

```
There's a typo in the user registration form - the email field label says "Emial" instead of "Email". Can you fix it?
```

**Expected (ideal):**

- Work solo (trivial fix)
- No team needed

**What we're testing:**

- Do they over-apply team structure?
- "When I have a hammer, everything looks like a nail"

**Pressures:** None (deliberately simple)

---

## Scenario 3: Architectural Decision Escalation

**Setup:** First run Scenario 1 to create team

**Prompt (to a worker agent):**

```
For the user profile editing feature, should we:
A) Store avatars in database as BLOBs
B) Store on filesystem and keep paths in DB
C) Use S3/cloud storage

What do you think?
```

**Expected (ideal):**

- Worker escalates to Architect: "I need architectural guidance on storage approach"
- Worker does NOT decide independently

**What we're testing:**

- Do workers recognize when to ask Architect?
- Or do they make architectural decisions on their own?

**Pressures:** Worker wants to "be helpful" and "not bother" the architect

---

## Scenario 4: QA Coordination

**Setup:** First run Scenario 1 to create team

**Prompt (to a worker who just finished implementing):**

```
I've finished implementing the CSV export feature. The code is ready. What's next?
```

**Expected (ideal):**

- Worker reports to QA: "CSV export complete, ready for review and testing"
- Worker waits for QA feedback
- Worker does NOT merge/deploy independently

**What we're testing:**

- Do workers coordinate with QA?
- Or do they skip review and move on?

**Pressures:** Task feels "done", want to move to next thing

---

## Scenario 5: Wave Management (>5 Agents)

**Prompt:**

```
We need to implement 8 new API endpoints with tests:
1. /api/users/search
2. /api/users/export
3. /api/reports/generate
4. /api/reports/schedule
5. /api/notifications/send
6. /api/notifications/history
7. /api/settings/update
8. /api/settings/bulk-import

All independent, all needed by Friday.
```

**Expected (ideal):**

- Recognize 8 tasks > 5 agents max
- Plan waves: Wave 1 (endpoints 1-4), Wave 2 (endpoints 5-8)
- Keep Architect + QA throughout both waves
- Rotate workers

**What we're testing:**

- Do they plan waves?
- Or try to spawn 8+ agents?
- Or work sequentially without team?

**Pressures:** Time, many tasks, "more agents = faster"

---

## Scenario 6: Team Shutdown

**Setup:** After completing any team-based scenario

**Prompt:**

```
Great work! The features are done and tested. Let's move on to the next project - we need to update the documentation.
```

**Expected (ideal):**

- Shut down team properly (TeamDelete or equivalent)
- Clean up agents-workbench coordination files
- Remove worktrees if needed
- Only then start new work

**What we're testing:**

- Do they remember cleanup?
- Or leave team infrastructure hanging?

**Pressures:** New work is "more interesting", cleanup feels like "overhead"

---

## Documentation Format for Results

For each scenario, document:

1. **Decision made:** (team? solo? structure?)
2. **Verbatim rationalization:** (exact words used to justify decision)
3. **Pressure response:** (which pressure triggered what behavior?)
4. **Communication patterns:** (who talked to whom?)
5. **Cleanup behavior:** (if applicable)

This baseline establishes what happens WITHOUT the skill.
