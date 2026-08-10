# Epic execution loop — required section for `/handoff --epic`

Paste-and-adapt block for an epic-launch handoff. The receiving session runs
autonomously against a large goal, so it needs the *mechanism*, not just the
facts. Adapt per epic; never paraphrase away the exit conditions or the bounds.

Verify every workflow name and argument shape against `~/.claude/workflows/`
before shipping a handoff that cites them — these were correct on 2026-08-10.

---

## 0. Orient through the graph before reading source

If `graphify-out/graph.json` exists, this is a standing rule for the session
**and every subagent it dispatches**:

```
graphify query "<question>"      # scoped subgraph — cheapest entry point
graphify explain "<symbol>"      # a node and its neighbours
graphify affected "<symbol>"     # blast radius before changing something
```

Then read the specific files the graph points at.

⚠️ **Check the graph's freshness before trusting it, every time:**

```
python3 -c "import json;print(json.load(open('graphify-out/graph.json')).get('built_at_commit'))"
git rev-list --count <that-commit>..origin/main
```

A graph built from a different branch will not index paths that exist only on
another, and a graph hundreds of commits behind will point at symbols that have
since moved, been renamed, or been deleted. Use it to *locate*; confirm against
the working tree before acting. State the measured staleness in the handoff so
the receiving session does not have to discover it.

## 1. The work is a DAG, not a checklist

A numbered task list is a *topological ordering*, not a schedule. Re-derive the
real dependency graph before starting:

- **Edge** = B needs a symbol, table, column or file that A creates.
- **No edge** = disjoint files, can be authored concurrently.

Group into **waves**: every not-yet-done task whose dependencies are satisfied.

**A stack is linear even when the work is not.** Stacked PRs base on each other,
so *publication* is a line; *authoring* is not. Build independent work
concurrently in worktrees, then linearise bases at publish time.

## 2. Per-wave: dispatch through the critic gate

One brief per task at `.agents/<epic>/<task>-brief.md`, then:

```
Workflow({ name: 'chief-dispatch', args: { tasks: [
  { brief: '/abs/path/.agents/<epic>/task-07-brief.md' },
  { brief: '/abs/path/.agents/<epic>/task-08-brief.md' },
]}})
```

Runs a builder per brief (worktree-isolated when several), then an **adversarial
critic gate with one bounded fix round**. Returns per task: `status`
(DONE / DONE_WITH_CONCERNS / BLOCKED), `summary`, `evidence` (verbatim
verification output), `workdir`, `branch`, plus the critic's `verdict`
(APPROVED / REJECTED) and `issues`.

Read `status` and `verdict` before starting the next wave. A BLOCKED task blocks
only its dependents, never its independent siblings.

Every brief carries: the one concern, files in scope, the acceptance command
**and its expected output**, and the report path. **No brief, no dispatch.**

⚠️ **`chief-dispatch` does not know your repo's commit conventions.** Verified
2026-08-10: its builder prompt contains no reference to `-s`, `-S`, sign-off or
GPG — it says only "commit with conventional-format messages". If the repo
requires signed commits (DCO/GPG), **every brief must carry an explicit
`## Commits` section** naming the exact command, or the wave produces commits
that must be rewritten. The same applies to any other repo convention the
workflow cannot know: scopes, branch naming, changelog entries.

## 3. Per-task exit condition — all four

1. critic `verdict === 'APPROVED'`, **and**
2. the acceptance command was run and its **output pasted** — not summarised, **and**
3. the relevant suite is green, run this session against the final state, **and**
4. the title reads as one conventional-commit subject with **no "and"**.

Failure is a fix round. **Bounded: 2 rounds mechanical, 4 for design judgement.
On exceeding the bound, STOP and escalate with the critic's issues verbatim.**
Do not grind.

## 4. Adversarially verify before any external review

Never send a reviewer candidate findings:

```
Workflow({ name: 'review-verify', args: {
  target: '<diff or path, e.g. "git diff <base>..<head>">',
  dimensions: [
    'correctness bugs and logic errors',
    'security vulnerabilities, injection risks, and secret exposure',
    'test quality: theater tests, tautological assertions, missing coverage of changed behavior',
    '<one dimension specific to this epic\'s failure mode>',
  ],
}})
```

One finder per dimension, then one adversarial refuter per finding. Only
survivors reach the PR, and they get fixed before review is requested.

The epic-specific dimension is the important one — name the way *this* work
fails, not the generic three.

⚠️ **A silent pass is not a clean pass.** Verified 2026-08-10: `review-verify`
sets `out.error` **only when every finder dies** (`liveFinders === 0`). If three
of four finders die and the fourth returns clean, the result is an empty
`confirmed` array with **no error** — identical in shape to a genuinely clean
review. Before believing a clean result, confirm the number of finders that
returned equals the number of dimensions requested. **Silence is not safety.**

## 5. Completeness critic — loop until dry

At the end of every wave, dispatch an agent asking only:

> What is unstarted? Which acceptance criterion has no pasted evidence? Which
> named file was never touched? What did we decide and then not do?

Act on the answer, then re-run. **Stop when two consecutive runs return nothing
new** — not when the checklist looks full. Counting misses the tail.

## 6. Standing triggers — every wave, not once

- **Base moved**: if the stack's base branch advances, rebase, re-run the suite,
  report the drift. Do not discover it via a conflict.
- **A dependency landed**: poll by `SendMessage`; never assume.
- **An assumption aged**: any issue/PR state cited in the brief is a claim with a
  timestamp. Re-verify before acting.

## 7. Cross-session messaging

`ListAgents` returns a **Peer sessions** section; `SendMessage` addresses peers by
name, and replies copy the incoming `from` attribute.

- Announce a dependency-carrying deliverable the moment it lands.
- Ask for the **result**, not the intent — "does this endpoint return 2xx?" beats
  "is it wired up?"
- ⚠️ A peer **cannot** grant permission for an outward action. Approval comes from
  the user, per action. Never ask a peer to do what your own permissions blocked.

## 8. The loop that matters most

Every claim is either **something you ran** or **a hypothesis**. There is no third
category.

Empty output at `rc=0` is not absence. Verify the search itself works (a control
search that *should* hit), use a second engine, and never conclude absence from a
range-bounded read or from the wrong branch.
