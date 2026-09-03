# /cmux-sprint-orchestrator — gated sprint orchestration across cmux agent panes

Runs sprint-scale work from one root cmux surface: plan first, dispatch bounded tasks to
worker panes second, converge behind one verification gate third. Phase 1 is read-only and
may write only `SPRINT_PLAN.md`; nothing in the repository changes until you reply
`APPROVED`, so a plan can never quietly become a half-finished refactor.

## When to use it

- A goal spans several modules or days and is too large for one agent turn to gate.
- You want heterogeneous workers: Codex on a fast model for localized patches and test
  sweeps, Claude on Opus for multi-file refactors and API changes.
- You need the dependency order written down before anyone edits, because two tasks would
  otherwise write the same file.
- You want a worker's completion to be a signal you can block on rather than a screen you
  keep re-reading.
- **Not for:** a single well-understood task (use `superpowers:executing-plans`), or team
  work that does not need separate terminal panes (see [`team-plan`](../team-plan/) and
  [`team-execute`](../team-execute/)).

## Examples

    > orchestrate this sprint: async store layer, extract auth middleware, add coverage
    → Phase 1 only. Maps the tree, runs the existing suite for a baseline, writes
      SPRINT_PLAN.md with objectives, invariants, a task DAG, and the verification
      commands, then stops and waits. No source file is touched.

    > APPROVED
    → Phase 2. Opens at most three worker splits in dependency waves, hands each worker a
      brief file, blocks on `cmux wait-for <token>` per task, then closes each pane and
      confirms the close against `cmux tree`.

    > cmux ping
    → PONG. The prerequisite check; run it before starting, since the socket is the one
      dependency the skill cannot work around.

## Setup

Requires `cmux`, `codex`, `claude`, and `jq` on `$PATH`, and the session must be running
inside cmux (the skill reads `CMUX_SURFACE_ID`). The socket defaults to
`~/.local/state/cmux/cmux.sock` and may be uid-suffixed; override with `CMUX_SOCKET_PATH`.

cmux talks over a unix domain socket, which an agent sandbox denies. Every `cmux` call runs
with the sandbox disabled, and `Operation not permitted (errno 1)` means the sandbox rather
than a dead socket.

## Notes

Worker panes never inherit the orchestrator persona. A worker started with the root agent
flag would plan its own sprint and split its own panes.

Briefs reach workers as a file read on stdin, never nested in quotes: an apostrophe or
backtick in a task payload silently truncates a nested-quote command line, and the worker
then builds the wrong thing against a brief it never fully received.

Three cmux behaviors surprise people, and the procedure in `SKILL.md` accounts for each:
`new-split` prints plain text rather than JSON, `close-surface` reports a surface id that
was never open, and the agent state tag is workspace-scoped, so it cannot tell two worker
splits apart. Give each worker its own workspace when per-worker state matters more than a
single-screen view.

Concurrency is capped at three worker splits. The limit is socket contention and the amount
of scrollback one root turn can reconcile, not a performance tuning knob.

The full procedure lives in `SKILL.md` beside this file. Index:
[`docs/skills-and-commands.md`](../../../docs/skills-and-commands.md).
