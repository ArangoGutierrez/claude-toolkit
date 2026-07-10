---
name: kickoff
user-invocable: true
description: >
  Turn a rough task opener into a scoped prompt, routed skills, and a
  verification checklist via a cheap tool-calling LLM that inspects the repo, then
  set the session goal and enter brainstorming — one command that hides /goal
  and brainstorming. Triggered by /kickoff <rough idea>. Fail-open: if no
  model is reachable or the engine is unavailable, the raw idea proceeds
  untouched.
argument-hint: <rough idea>
tools:
  - Bash
  - Skill
  - Read
---

# kickoff — agentic LLM front door

Run when the user types `/kickoff <rough idea>`.

## Steps

1. **Enrich.** Run (sandbox **disabled** — the engine reaches your inference
   endpoint and reads repo files) with an explicit Bash-tool `timeout: 420000`
   (ms). The engine's wall-clock budget is 300s + 30s SIGALRM margin; the Bash
   default of 120s kills legitimate runs mid-flight and masquerades as an
   engine stall (2026-07-07, twice — guarded by evals/kickoff-timeout-contract.sh):
   Sessions running as the chief-operator agent add `--profile chief` so the
   engine compiles an orchestration plan instead of a solo prompt:
   ```sh
   # standard sessions — run exactly ONE of these two:
   bash ~/.claude/skills/kickoff/scripts/enrich.sh --mode interactive "<the user's rough idea>"
   # chief-operator sessions:
   bash ~/.claude/skills/kickoff/scripts/enrich.sh --mode interactive --profile chief "<the user's rough idea>"
   ```
   `enrich.sh` is a thin shim over `python -m tool.kickoff` (deployed at
   `~/.claude/tool/kickoff.py`). The engine drives a cheap tool-calling LLM that
   inspects the repo via read-only tools (multi-turn) before producing the
   scoped prompt + routed skills + verification checklist. Capture stdout.

2. **Branch on the result.**
   - If stdout begins with `KICKOFF_PASSTHROUGH:` → enrichment was unavailable
     (engine not deployed / model unreachable). Tell the user briefly, use their
     raw idea as the working prompt, and skip to step 4 with no checklist. Never
     let this block the kickoff.
   - Otherwise parse the `## Kickoff` block: the **Scoped prompt**, **Skills**,
     **Execution** (`solo` | `orchestrate`), **Budget** (transcribed into the
     goal in step 3), and **Verification checklist**. Show it to the user.

     Each checklist item now carries a verdict ([runs; …], [BROKEN: …], [REJECTED: …],
     [unvalidated: …]) and the block ends with an `Acceptance (runnable):` list and a
     `**Grounded in:**` line naming the files the engine actually read. Broken/rejected
     checks are guidance only — never acceptance criteria.

3. **Set the session goal** with the checklist as acceptance criteria. Invoke
   the `goal` skill (or run `~/.claude/skills/goal/goal.sh`) with text formatted
   exactly as: (Run goal.sh with the sandbox **disabled** — it writes under
   `~/.claude/audit/`, which the Bash sandbox blocks; it now fails loudly if blocked.)
   ```
   Goal: <Scoped prompt (or the raw idea on passthrough)>
   Budget: <the **Budget:** value from the Kickoff block>
   Acceptance:
   - <checklist item 1>
   - <checklist item 2>
   ```
   The `Budget:` line must start at column 0 exactly as `Budget: <value>` — the
   budget-governor Stop hook greps `^Budget: `. On PASSTHROUGH, omit the `Budget:`
   line entirely (no engine value exists to transcribe).
   Use ONLY the commands under the engine's `Acceptance (runnable):` block as the
   `Acceptance:` items (these are proven runnable, so the `/done` Stop hook can execute
   them). Do not promote BROKEN/REJECTED/unvalidated checks to acceptance.
   This plants the verification checklist in the session goal file, where a
   Stop/verification hook can read it, so "did verification actually run" is
   observable later. (On passthrough,
   omit the `Acceptance:` items; brainstorming will establish them.)

4. **Enter the right path:**
   - **Execution = solo** (or passthrough) → invoke `superpowers:brainstorming`,
     seeded with the scoped prompt.
   - **Execution = orchestrate** → if the Kickoff block contains a
     **Dispatch plan:** section, seed from it instead of decomposing from
     scratch: brainstorm only the deltas (task boundaries the engine got wrong,
     missing tasks), then materialize per-task briefs at
     `.superpowers/sdd/task-N-brief.md` per the rendered Dispatch contract and
     run the chief dispatch loop (parallel where owns are disjoint and deps
     allow), or hand the fenced JSON seed to `/orchestrate` for cmux-scale
     work. Without a Dispatch plan section, invoke
     `superpowers:brainstorming` focused on decomposing the work into disjoint,
     parallelizable tasks, then hand off to `team-plan` as before.

The enricher is strictly additive — an enrichment failure must never block the
kickoff.
