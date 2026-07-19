# Orchestration: Loops → Graphs

> "Here's your monthly reminder that you shouldn't be prompting coding
> agents anymore. You should be designing loops that prompt your agents."
> — [Peter Steinberger, June 2026](https://x.com/steipete/status/2063697162748260627)
>
> "Are we still talking loops or did we shift to graphs yet?"
> — [Peter Steinberger, July 2026](https://x.com/steipete/status/2078277297791189132)

Agent orchestration has a maturity model. Each stage changes what *you*
produce: prompts produce answers, loops produce automation, graphs produce
verified systems of agents. This page names the stages, tells you when each
one is enough, and maps them to the pieces this toolkit ships.

## The three stages

**Stage 1 — Prompts.** You type, the agent acts, you read, you type again.
You are the control flow. Perfectly fine for exploration, one-off fixes,
and anything you'd finish before automating it would pay off.

**Stage 2 — Loops.** The insight of loop engineering: stop being the
control flow. A loop re-invokes the agent on a schedule or a trigger —
"check CI and fix what broke", "keep the dependency PRs merged", "refresh
the code graph weekly". The agent gets re-prompted by a *program*, not by
you. Loops excel at recurring maintenance with a stable prompt. Their limit:
a loop is one agent thinking alone — no fan-out, no independent
verification, no structured hand-offs.

**Stage 3 — Graphs.** Work becomes a DAG of agents: fan-out over independent
subtasks, barriers where synthesis genuinely needs everything, adversarial
verification as a first-class node between "found" and "reported",
checkpointed state so a killed run resumes instead of restarting. The
orchestration is deterministic code; the agents supply judgment inside
well-defined boxes. This is where "one agent with a long prompt" becomes
"a system with structural quality guarantees".

There is a fourth axis the loops-vs-graphs debate tends to miss: **knowledge
graphs**. Orchestration graphs coordinate *work*; knowledge graphs give
agents a cheap, queryable map of *the territory* (code structure, prior
decisions) so every node starts oriented instead of grepping from zero.

## When each stage is enough

| You are doing… | Stay at |
|---|---|
| Exploring, spiking, one-off edits | Prompts |
| Recurring maintenance, a stable prompt, one agent suffices | Loops |
| Review/audit where findings must be verified, migrations over many files, work needing independent perspectives | Graphs |

Do not cargo-cult upward. A loop that works beats a graph that impresses;
every stage you climb adds cost, latency, and moving parts. Climb when the
*shape* of the work demands it — verification, fan-out, or scale one
context window can't hold — not when a tweet does.

## What this toolkit ships per stage

| Stage | Component | What it does |
|---|---|---|
| Loops | `/loop` | recurring or self-paced re-prompting |
| Loops | scheduled tasks (cron/launchd) | headless recurring runs, e.g. weekly graph refresh |
| Graphs | [Workflow Library](patterns/workflow-library.md) | named, reusable orchestration DAGs (`/review-verify`, `/chief-dispatch`, `/weekly-audit`) |
| Graphs | [kickoff enrichment](architecture.md) | compiles a rough goal into a scoped prompt, acceptance checks, and a dispatch plan |
| Knowledge graphs | [Graphify](graphify.md) | AST-derived code graph agents query before grepping |

## Composing the layers

The stages compose — that's the point. A **loop** can launch a **graph**:

```text
# weekly, headless: the loop is the scheduler, the graph does the work
claude -p "/weekly-audit"
```

Schedule that line with cron or launchd and you have recurring,
parallel, adversarially-synthesized repo hygiene — a loop prompting a
graph of agents, none of it prompted by you.

## Cost and safety rails

Graphs multiply agents, so the toolkit treats orchestration spend as
opt-in, never inferred:

- Multi-agent workflows run only on explicit user opt-in (a typed
  `/<workflow>` command is exactly that).
- Verification is structural: `review-verify` refuses to report a finding
  no refuter attacked; `chief-dispatch` refuses to accept an implementer's
  report as evidence.
- Workflows never push, post, or merge — external writes stay with the
  human operator.

## Further reading

- [Claude Code workflows documentation](https://code.claude.com/docs/en/workflows)
- [Workflow Library reference](patterns/workflow-library.md)
- [Engineering Discipline](engineering-discipline.md) — the verification
  culture the graphs encode
