---
name: cmux-sprint-orchestrator
description: Use when asked to orchestrate a sprint, produce a sprint plan, run a sprint task, coordinate agents in cmux, or drive a multi-agent implementation, and when a goal spans multiple modules, several days, or more work than one agent turn can gate. Also use when worker panes must be dispatched, polled, or torn down inside cmux.
---

# cmux Sprint Orchestrator

## Overview

Drives sprint-scale work from a single root surface by dispatching bounded tasks to
heterogeneous agent panes in cmux, then converging their output behind one verification gate.

**Core principle: the plan is the product of Phase 1, and code is not.** An orchestrator that
edits files while it is still deciding what to build has no plan, only a diff. Splitting the
decision from the execution is what makes the work reviewable.

Measured baseline: three fresh agents given a three-item sprint under deadline pressure all
began editing source immediately. None produced a plan artifact and none paused for approval.
One rewrote production source before naming a single invariant. That is the failure this skill
exists to prevent.

## The Iron Gate

```
PHASE 1 IS READ-ONLY. NO FILE IN THE TARGET REPO CHANGES BEFORE `APPROVED`.
```

In Phase 1 you may read, search, list, run existing test suites, and write exactly one file:
`SPRINT_PLAN.md`. Nothing else.

**Forbidden in Phase 1, without exception:**

- Editing, creating, or deleting any application, test, config, or build file.
- Running a formatter, linter, or codemod that writes to the tree.
- `git commit`, `git checkout -b`, `git stash`, or any index mutation.
- Creating a cmux split, pane, or workspace.
- Sending a single character to any worker CLI.
- "Scaffolding", "a stub so the DAG typechecks", or "one obvious fix while I read".

Violating the letter of this gate is violating the spirit of it. If you changed a file before
`APPROVED`, revert it (`git checkout -- <path>`, delete untracked files), say so plainly, and
restart Phase 1.

### Rationalizations, and what is actually true

| Rationalization | Reality |
|---|---|
| "The deadline is tomorrow, planning is ceremony." | The baseline agents that skipped the plan produced three uncoordinated diffs that no reviewer could gate. The plan is the cheapest artifact in the sprint. |
| "The lead already signed off on the direction." | Sign-off on direction is not approval of a task graph. `APPROVED` gates the DAG, the invariants, and the routing, none of which existed when the lead spoke. |
| "It's one small fix, I'm already in the file." | Phase 1 has no small fixes. An unplanned edit is an untracked task with no owner, no verification, and no line in the report. |
| "I need a stub to validate the dependency order." | Validate order by reading imports and the test suite. A stub is code. |
| "I'll write the plan after, from what I learned building." | A plan written after the diff documents the diff. It cannot change a decision that is already spent. |
| "Spawning the workers now saves wall-clock, I'll plan while they run." | Workers dispatched without a DAG collide on shared files. Concurrency without a plan is a merge conflict with extra steps. |
| "The user obviously wants working code, not a document." | The user wants working code they can verify. Phase 3 is where code is judged; Phase 1 is where it is made judgeable. |
| "Reading is slow, I'll learn faster by changing something." | Then change it in a scratch clone outside the target repo, and cite it as evidence in the plan. |

### Red flags: stop and restart Phase 1

- `git status` in the target repo is not clean and you have not printed `APPROVED`.
- You are composing a `cmux send` payload and `SPRINT_PLAN.md` does not exist.
- You catch yourself writing "while I'm here" or "quick".
- You are about to ask the user to approve a plan you have already half-built.

## Prerequisites

Run this first. cmux talks over a unix domain socket, which the agent sandbox denies, so
**every `cmux` call in this skill runs with the sandbox disabled.** An
`Operation not permitted (errno 1)` from `cmux` is the sandbox, not a broken socket.

```bash
for b in cmux codex claude jq; do
  command -v "$b" >/dev/null 2>&1 || { echo "MISSING: $b"; exit 1; }
done
cmux ping || { echo "cmux socket unreachable"; exit 1; }
ROOT_SURFACE=$(cmux identify | jq -r '.caller.surface_ref')
WORKSPACE=$(cmux identify | jq -r '.caller.workspace_ref')
echo "root=$ROOT_SURFACE workspace=$WORKSPACE"
```

`cmux ping` prints `PONG`. Surface refs are 1-indexed: the root orchestrator is `surface:1`,
and there is no `surface:0`. The socket defaults to `~/.local/state/cmux/cmux.sock` and may be
uid-suffixed (`cmux-<uid>.sock`); override with `CMUX_SOCKET_PATH`. It is not `/tmp/cmux.sock`.

## Phase 1: architectural formulation (read-only)

### 1.1 Map the ground truth

Every count, path, and command that reaches `SPRINT_PLAN.md` comes from a command you ran in
this session and pasted. A remembered module list is not evidence.

```bash
git -C "$REPO" status --short          # must be clean, and stay clean
git -C "$REPO" log --oneline -10

# Scratch dir, self-ignoring so the census and logs never dirty git status.
mkdir -p "$REPO/.sprint" && printf '*\n' > "$REPO/.sprint/.gitignore"

# File census. `rg --files` alone SKIPS HIDDEN DIRECTORIES, so a repo that keeps
# its content under .claude/, .github/ or .cursor/ reports a fraction of itself.
git -C "$REPO" ls-files > "$REPO/.sprint/census.txt"                   # tracked files
# not a git repo? use: rg --files --hidden --glob '!.git' "$REPO"
wc -l < "$REPO/.sprint/census.txt"

# Language mix. The `grep '\.'` guard matters: an extensionless file (LICENSE,
# Makefile) would otherwise have its whole path counted as an extension.
grep '\.' "$REPO/.sprint/census.txt" | sed 's|.*\.||' | sort | uniq -c | sort -rn | head

# Dependency shape, over the census rather than a fresh blind walk.
rg -n '^(import|from|require|use )' --hidden --glob '!.git' "$REPO" --stats | tail -5
ls "$REPO"/{Makefile,justfile,package.json,pyproject.toml,go.mod} 2>/dev/null
```

Prove the census can see before you trust what it does not show. Pick a file you
already know exists, ideally a deep or hidden one, and confirm it is in the list:

```bash
grep -c 'some/file/you/know/exists' "$REPO/.sprint/census.txt"   # must be >= 1
```

Measured on a real repo, the difference is not marginal: `rg --files` reported 56
files where `git ls-files` reported 383, and it listed exactly 0 of the 246 files
under `.claude/`. A census that cannot see a directory reports no work there and
no risk there, and the DAG you build on it inherits both blind spots.

Then run the existing suite once, unchanged, and record the result. A green baseline is the
only thing that makes a Phase 3 regression legible.

```bash
( cd "$REPO" && make test ) > "$REPO/.sprint/baseline.log" 2>&1; echo "baseline rc=$?"
tail -5 "$REPO/.sprint/baseline.log"
```

If a repo has a code knowledge graph (`graphify-out/graph.json`), orient with
`graphify query "<question>"` before grepping.

Identify high-risk integration zones explicitly: files imported by three or more modules,
anything in an auth or crypto path, and any file two planned tasks would both touch. The last
category is the one that decides your DAG edges.

### 1.2 Confirm the target repo is dispatch-ready

A dispatched worker runs inside **your** hook stack, not a clean one. Hooks you wrote for
your own repositories will fire against the target repo, and when one blocks a worker the
orchestrator sees nothing but a stall: no error, no signal, just a timeout.

Observed on the first live run of this skill. A worker created its own worktree, ran the
baseline suite green, wrote correct tests, and every write was then refused by a PreToolUse
hook demanding a linked worktree. Three dispatches burned about five minutes each and the
root surface could not tell that from a slow worker. Adding the marker the hook asked for
made the same brief succeed unchanged.

Before dispatching anything, check what your own hooks require of a repo:

```bash
ls "$REPO"/{AGENTS.md,CLAUDE.md} 2>/dev/null      # project instruction files the hooks read
grep -rl 'PreToolUse' ~/.claude/settings*.json 2>/dev/null
```

Then satisfy the requirement in the target repo, or hand each worker a properly linked
worktree. Either is fine; discovering which one your hooks want after three silent stalls is
not. A worker blocked by a policy hook has not failed the task, and re-briefing it will not
help, so this belongs in Phase 1 rather than in the failure policy.

Clean up after a blocked worker: it may have created a git worktree of its own before being
stopped. `git -C "$REPO" worktree list` shows them and they outlive the surface you closed.

### 1.3 Decide whether to fan out at all

Do this before writing the DAG, and be willing to answer no. Three independent agents given a
three-item sprint all reached the same conclusion unprompted: two of the items rewrote the same
file, so any two workers would have collided and one would have had to rebase onto the other.
Their words: "coordination overhead would have exceeded the work."

Fan out only when every one of these holds:

- Two or more tasks share no path in their `outputs` column.
- Those tasks have no `depends_on` edge between them.
- Each task is large enough that a worker's startup and your reconciliation cost less than
  doing it inline.

If none of that holds, say so in section 3, run the sprint serially from the root surface, and
skip Phase 2. A serial sprint executed against an approved plan is a success, not a fallback.
The most common seam that does parallelize is tests-after-interface: land the interface change
first, freeze it, then fan out the test sweep across the settled API.

An orchestrator that dispatches three workers onto one file has not parallelized the sprint,
it has scheduled a merge conflict.

### 1.4 Write SPRINT_PLAN.md

Write it to the repo root. It has exactly these four sections, with these headings:

```markdown
## 1. High-Level Objectives & Anti-Goals

Objectives: numbered, each one observable. "Store layer exposes async get/put and the suite
passes" is observable. "Improve the store" is not.

Anti-Goals: what this sprint will not touch, named as paths or subsystems. This is the
boundary that keeps a worker from wandering. Every anti-goal is a path a reviewer can check.

## 2. Invariants & Security Boundaries

Contracts that hold before and after every single task, not just at the end. Each invariant
states the command that falsifies it, and each command has been shown to discriminate.

- Public HTTP handler signatures unchanged: `rg -n 'def (get|put)_item' src/api/`
- No credential literal enters the tree: `rg -n 'token\s*=\s*"' src/`
- Baseline tests keep passing: `make test`

## 3. Worker Task Graph (DAG)

One row per task. `depends_on` is what makes this a graph rather than a list, and tasks with
no path between them are the only ones that may run concurrently.

| id | task | agent | depends_on | inputs (paths) | outputs (paths) | done when |
|----|------|-------|------------|----------------|-----------------|-----------|
| T1 | async store layer | Opus | - | src/store/db.py | src/store/db.py | `make test` green, get/put awaitable |
| T2 | extract auth middleware | Opus | - | src/api/handlers.py | src/api/middleware.py, src/api/handlers.py | no inline token compare in handlers |
| T3 | async + middleware tests | GPT-5.6-Sol | T1, T2 | tests/ | tests/test_store.py, tests/test_middleware.py | new tests fail when T1/T2 reverted |

Two tasks that list the same path in `outputs` must have a `depends_on` edge. If they do not,
the DAG is wrong and the workers will overwrite each other.

## 4. Verification Harness

The exact commands Phase 3 runs, copied from what you ran in 1.1, plus what the new work adds.

- Suite: `make test`
- Lint: `make lint`
- Invariant sweep: the commands from section 2
- Mutation spot-check: revert T1's source, confirm T3's tests go red
```

Prove every invariant command discriminates before it enters the plan. A check that cannot
go red is not a check, and both failure directions were observed in testing:

- **Too broad.** A `rg 'get_item'` invariant also matched the import line, so it would keep
  passing after the definition it guards was deleted. Run it and read the matches, do not
  just read the exit code.
- **Too narrow.** A lint target with hardcoded filenames never compiles a module a worker
  adds, so the invariant passes vacuously for exactly the new code it was meant to cover.
  Any task whose outputs include a new file owns updating the harness that must see it.

The cheap proof is to run the command against the current tree and confirm it returns the
positive it is supposed to find. A pattern that matches nothing today will also match nothing
after a worker breaks the thing it guards, and you will read that silence as success.

### 1.5 The execution gate

Print a summary of the plan: objective count, task count, the concurrency-eligible set, and
the verification commands. Then stop and ask, with `AskUserQuestion`, whether to execute.
Offer approval as one option and revision as the other; never end a turn with a bare prose
question, because a prose choice loses the picker and the review panel both.

**You are blocked until the user answers.** Proceed to Phase 2 only on an explicit approval:
the literal string `APPROVED`, or the approve option chosen in the picker. Silence is not
approval. "Looks good" on a different question is not approval. A user asking a clarifying
question about task T2 is not approval of T1.

## Phase 2: heterogeneous cmux dispatch

### Verified command contract

Every form below was run against a live cmux socket. The corrections matter: three plausible
variants of these commands do not exist.

| Need | Command | Behaviour |
|---|---|---|
| Create worker | `cmux new-split right --focus false` | prints `OK surface:11 workspace:1` as **plain text**. There is no `--json` flag. |
| Capture its id | `... \| cut -d' ' -f2` | yields `surface:11` |
| Send a command | `cmux send --surface "$S" "$CMD"'\n'` | the trailing `\n` is interpreted by cmux and submits the line |
| Send a bare key | `cmux send-key --surface "$S" enter` | use when a TUI swallowed the newline |
| Read the pane | `cmux read-screen --surface "$S" --lines 50` | add `--scrollback` for history |
| Block on completion | `cmux wait-for "$TOK" --timeout 900` | rc=0 when signalled, rc=1 on timeout |
| Signal from worker | `cmux wait-for -S "$TOK"` | the worker's last action |
| Agent state | `cmux top --all --format tsv` | tag rows carry `Running` or `Needs input` |
| Close worker | `cmux close-surface --surface "$S"` | see the warning below |
| Enumerate | `cmux tree` | the authoritative list of live surfaces |

**`close-surface` prints a misleading confirmation.** Closing `surface:13` printed
`OK surface:14 workspace:1`, an id that never existed. The number in that line is not the
surface you closed. Never parse it. Confirm a close against the tree:

```bash
cmux close-surface --surface "$S" >/dev/null 2>&1
cmux tree | grep -q "surface $S " && echo "STILL OPEN: $S" || echo "closed: $S"
```

**`list-pane-surfaces` only lists the caller's own pane**, so it will not show workers you
split off. Use `cmux tree` to enumerate.

### Surface lifecycle

The root orchestrator stays on its own surface under `--agent chief-operator` and never
executes task work itself. **Maximum three concurrent worker splits.** The cap is about
socket contention and your own attention: four panes of scrollback exceeds what one root turn
can reconcile. Dispatch the DAG in topological waves, at most three wide.

### Deliver the brief through a file, never through nested quotes

The quoting hazard is the most common way this dispatch breaks. A task payload containing an
apostrophe, a double quote, a backtick, or a `$` corrupts a nested-quote command line, and
the worker silently receives a truncated brief. Write the brief to a file in the repo and let
the worker CLI read it from stdin. Verified byte-exact against a brief containing all four
hostile characters.

Use a repo-relative path, not `$TMPDIR`: `$TMPDIR` resolves differently for a sandboxed
orchestrator (`/tmp/claude-NNN/...`) than for the unsandboxed worker shell
(`/var/folders/.../T/...`), so a brief written to one is missing in the other.

Every brief states: the task id, the exact paths the worker may touch, the paths it must not,
the invariants from section 2, the done-when condition from the DAG, a clause waiving the
worker's own approval reflex, and this last line:

```
You are running non-interactively. Nobody can answer a question, and asking one ends
your turn with the task untouched. The approval gate for this sprint already happened
at the plan level, so you have authority to implement this brief. Where the brief
leaves a design choice open, make it, record it in a docstring or comment, and carry
on. Do not ask for confirmation.
```

**Do not ask the worker to signal.** The dispatcher appends the signal to the worker's shell
chain, after the process exits and after its exit status is recorded. A brief that also tells
the worker to run the signal itself makes the token fire from inside a session that is still
finishing: observed here, the wait returned while the worker was still printing its diff, and
the exit-status file did not exist yet. One signal, owned by the chain, and the token then
means exactly "the worker process ended".

The waiver is not boilerplate. A dispatched worker inherits the operator's own engineering
standards, and those usually say "brainstorm and get the design approved before implementing".
That is right for interactive work and fatal here. Observed twice on one task: the worker
proposed a sensible design, asked "Do you approve this design?", and exited **rc=0** having
written nothing, in 57 and 69 seconds. Both runs looked like clean successes from the outside.

Without that chain-appended signal the orchestrator has nothing to block on and degrades to
screen-scraping.

### Run each worker in a linked worktree

`dispatch-worker.sh` puts each worker in `<repo>/.sprint/worktrees/<task>` on a `sprint/<task>`
branch by default. Pass `--in-place` to override, and expect trouble if you do.

This is a correctness requirement, not hygiene. A Codex worker inherits the operator's
PreToolUse policy, which permits edits only when `git rev-parse --absolute-git-dir` differs
from `--git-common-dir`. That is true inside a linked worktree and false in a main checkout:

```bash
cd "$REPO"                       && git rev-parse --absolute-git-dir --git-common-dir
cd "$REPO/.sprint/worktrees/T1"  && git rev-parse --absolute-git-dir --git-common-dir
```

The policy inspects the worker's **cwd**, not the path being written. A worker that creates a
worktree and then patches into it from the main checkout is still refused, which is exactly
how three dispatches stalled with no error and no signal. The dispatcher proves the predicate
holds before spending a worker on it.

Isolation is the second benefit: a worker's edits land on its own branch, so a wrong answer
never touches the main checkout and two workers cannot see each other's half-finished state.

### Worker routing matrix

| Task class | Agent | Why |
|---|---|---|
| `unit_tests`, `cli_debugging`, `lint_fix`, `localized_patch` | GPT-5.6-Sol via Codex | fast iterative loops inside one file or one test directory |
| `architecture`, `api_design`, `multi_file_refactor`, `migration` | Claude Opus | judgment across modules, where the brief cannot spell out every edit |

Route by whether the brief can fully specify the change. If it can, send it to Sol. If the
worker has to make a design call, send it to Opus.

### Dispatch

The dispatch itself lives in `scripts/dispatch-worker.sh` beside this file, not inline
here, and that placement is deliberate. See the warning below.

```bash
# dispatch-worker.sh <sol|opus> <task-id> <brief-path> <repo>
# prints "<task> <agent> <surface> <token>" for your dispatch ledger
SKILL_DIR="$HOME/.claude/skills/cmux-sprint-orchestrator"
"$SKILL_DIR/scripts/dispatch-worker.sh" sol  T1 "$REPO/.sprint/briefs/T1.md" "$REPO"
"$SKILL_DIR/scripts/dispatch-worker.sh" opus T2 "$REPO/.sprint/briefs/T2.md" "$REPO"
```

**Never write a shell positional or an awk field reference into this file** (a dollar sign
followed by a digit). When the skill is invoked with arguments, the loader replaces every one
of them in the SKILL.md body with a word from those arguments before the agent reads it.
Observed here: the awk print-second-field idiom was delivered with a path from the invocation
in place of the field reference, so it captured no surface id, and the next
`cmux send --surface ""` targeted the wrong pane. That is the single most dangerous failure
in this whole document, and the loader causes it.

This is why the capture idiom above is `cut -d' ' -f2` rather than awk, why the agent-state
row is read with `cut -f4,6,7` rather than a field comparison, and why the dispatch function
sits in `scripts/dispatch-worker.sh`. A referenced file is read from disk and is never
rewritten. Keep it that way: if you move that script's body back inline, it breaks silently
and only when someone passes arguments.


The `< /dev/null` on the Claude worker is not optional. Without it `claude -p` waits three
seconds for stdin that a PTY never sends, then prints `Warning: no stdin data received in 3s`
into the pane. That warning is noise a stall check can misread, and it delays every Opus
worker you launch.

`codex exec` is the non-interactive subcommand and it takes the prompt as a positional
argument or on stdin. `codex run` does not exist, and there is no `--prompt` flag; both
appear in older notes and both fail. Add `--dangerously-bypass-approvals-and-sandbox` only
when a Sol worker must edit files without prompting, and record that you did.

Child Claude workers **never** get `--agent chief-operator`. A worker running this persona
would start planning its own sprint and splitting its own panes. Mirror the root's model,
effort, and permission flags only. The combined
`--permission-mode auto --dangerously-skip-permissions` form was verified to run.

### Convergence and stall detection

Block on the token rather than polling text. `wait-for` returns rc=0 the moment the worker
signals, and rc=1 at the timeout, which is your stall detector.

**The token proves the worker's process ended. It does not prove the task succeeded.** The
signal is the next command in the worker's shell chain, so it fires just as reliably when the
agent refused, errored, or asked a question and quit. `dispatch-worker.sh` therefore also
records the worker's exit status to `.sprint/status/<task>.rc`, but even that is not enough:
in the observed failure the worker exited **0** having written nothing. Only the task's own
done-when condition, re-run by you at the root, separates finished from succeeded:

```bash
grep -c 'def slugify' src/strings.py      # the done-when from the DAG row, run by YOU
```

Treat a worker's report the way you would treat any unverified claim.

```bash
if cmux wait-for "$TOK" --timeout 900; then
  echo "$TASK signalled"
else
  echo "$TASK STALLED after 900s"
  cmux read-screen --surface "$S" --lines 80        # dump PTY to root context
fi
```

Between waves, or when a wait times out, read agent state:

```bash
cmux top --all --format tsv | cut -f4,6,7 | grep '^tag'
```

`Needs input` means the worker is blocked on a prompt, not working. That is a stall: read the
pane, answer it with `cmux send` if the answer is unambiguous, otherwise treat it as a failure
and re-diagnose. Note the scope limit: this tag is **workspace-scoped, not per-surface**. A
workspace holding several agent surfaces reports one aggregated tag whose state can be blank,
verified on a workspace with seven agent surfaces. So the tag tells you a workspace needs
attention; `read-screen` per surface tells you which worker. When per-worker state matters
more than a single-screen view, give each worker its own workspace with
`cmux new-workspace --command ...` instead of a split.

### Can workers talk to each other

Default answer: no, and they should not need to. The root mediates, and two workers that need
to talk mid-task are a dependency edge you failed to draw in the DAG. Turn the conversation
into an edge and the second worker into a later wave.

Worktree isolation makes this concrete rather than a preference. Each worker is on its own
branch in its own checkout, so it cannot see another worker's half-finished state even if it
looks. That is the point: partial work is not a contract, and a worker that reads another's
uncommitted file has coupled itself to something that may still be reverted.

Three mechanisms exist, in the order you should reach for them:

| Need | Mechanism | Cost |
|---|---|---|
| B needs A's finished output | a `depends_on` edge; B runs in a later wave | none, this is the DAG doing its job |
| B needs A's interface but not its tests | root merges A's branch, then dispatches B | one extra wave, full attribution |
| B must block mid-task on A reaching a point | `cmux wait-for` as a named rendezvous | real coupling, use sparingly |

The rendezvous is a genuine primitive, not a workaround: `cmux wait-for -S <name>` signals and
`cmux wait-for <name> --timeout N` blocks, returning rc=0 when signalled and rc=1 on timeout.
A worker can therefore block on `interface-frozen` while another signals it. Reach for it only
on the tests-after-interface seam, where the alternative is serialising a long task behind a
short one, and name the token in both briefs so the coupling is visible in the plan.

What you should not do is let workers `cmux send` into each other's surfaces. It works, and it
produces a sprint whose failures are unattributable: when the result is wrong you cannot tell
which worker's instruction caused it, the root's ledger no longer describes what happened, and
the three-strikes policy has nothing coherent to re-brief. Keep the star topology. The root is
the only writer of instructions.

### Failure policy

Three strikes per task, and the strike that matters most is the quiet one.

The dangerous worker is not the one that errors. It is the one that exits **0**, leaves its own
suite **green**, and is wrong anyway. Observed: a task under-specified its tie-breaking rule, a
Codex worker reached for the standard library exactly as the brief suggested, documented the
tie-to-even behaviour it had chosen in a docstring, exited 0 with 24 tests passing, and failed
half the sprint's acceptance cases. Nothing in the pane, the exit status or the worker's suite
said so. Only the root's own acceptance check did.

That is the whole argument for re-running done-when yourself. A worker's green suite tests what
the worker decided to build.

**Re-briefing is a new dispatch, not a conversation.** The worker process has already exited, so
you cannot reply to it. Re-dispatch the same task id: `dispatch-worker.sh` reuses the existing
`.sprint/worktrees/<task>`, so the worker opens its own previous attempt and fixes it in place
rather than starting over. A re-brief that lands the fix contains four things, in this order:

1. That this is attempt N of 3, and that the previous attempt is already in the worktree.
2. The failure output verbatim, passing cases included. Showing which cases passed tells the
   worker the shape of the rule rather than only that it is wrong.
3. A one-line diagnosis naming the cause, and saying plainly where the brief was at fault when
   it was. A worker told its defensible call was reasonable but superseded fixes the code; one
   told it was simply wrong tends to rewrite more than it needs to.
4. The requirement, now stated explicitly, with the exact expected values.

That recipe fixed the rounding task on attempt 2: all eight acceptance cases correct, the
docstring rewritten to state the real rule, four tie tests added, and reverting the fix takes
the suite red, so the new tests discriminate.

On the third failure, or on any repeated identical output (a loop):

1. `cmux read-screen --surface "$S" --lines 100 --scrollback` and keep the dump.
2. Close the surface and confirm the close against `cmux tree`.
3. Revert that task's partial work so the tree returns to a known state.
4. Re-diagnose at the root. A task that failed three times has a wrong brief or a wrong DAG
   edge, not an unlucky worker. Fix the plan, and say in the report that you did.

Never dispatch a replacement worker for a task whose brief you have not changed. Re-running an
unchanged brief is how three strikes get spent on one bug.

## Phase 3: consolidation and verification

Run from the root surface. Paste the output; a remembered pass is not a pass.

```bash
cd "$REPO"
mkdir -p .sprint && printf '*\n' > .sprint/.gitignore   # scratch stays out of git status
make test > .sprint/test.log 2>&1; test_rc=$?
tail -20 .sprint/test.log; echo "test rc=$test_rc"
make lint > .sprint/lint.log 2>&1; lint_rc=$?
tail -10 .sprint/lint.log; echo "lint rc=$lint_rc"
[ "$test_rc" -eq 0 ] || echo "SUITE RED: do not report this sprint as done"
```

Gate on the command, not on a pipe. `cmd | tail && commit` inspects tail's exit code and will
happily commit a red suite. Do not reach for `${PIPESTATUS[0]}` as the fix either: the root
surface runs zsh, where that expands to the empty string, so the rc check prints nothing and
passes vacuously. Verified: the same pipeline reports `7` in bash and an empty value in zsh.
Redirect to a file, capture `$?` on the next line, then read the file.

Then check the invariants and the boundary, one command per line of section 2:

```bash
git status --short
git diff --stat
git diff --name-only | while read -r f; do
  grep -qx "$f" .sprint-allowed-paths || echo "BOUNDARY VIOLATION: $f"
done
```

Any file changed that no task listed as an output is an invariant violation. Investigate it
before reporting, and do not launder it into "incidental cleanup".

Verify the new tests discriminate. A test suite that stays green when its subject is deleted
is theater:

```bash
cp src/store/db.py /tmp/db.bak && git checkout HEAD~1 -- src/store/db.py
make test 2>&1 | tail -3      # MUST be red
command cp -f /tmp/db.bak src/store/db.py
```

Collect each task branch before you verify the whole. The worker leaves its output
uncommitted in its own worktree, so the root commits it on the task branch and merges:

Workers differ in whether they commit. Opus workers committed their own output, in RED then
GREEN pairs; Codex workers left it uncommitted in the worktree. Collection must tolerate both
or it fails on whichever kind you did not expect:

```bash
W="$REPO/.sprint/worktrees/$TASK"
if [ -n "$(git -C "$W" status --porcelain)" ]; then
  git -C "$W" add -A
  git -C "$W" commit -m "feat(scope): $TASK"
fi
git -C "$REPO" merge --no-ff --no-edit "sprint/$TASK"
git -C "$REPO" worktree remove "$W" --force && git -C "$REPO" branch -d "sprint/$TASK"
```

Merge one task at a time and run the suite after each, so a conflict or a regression is
attributable to a single worker. `git -C "$REPO" worktree list` afterwards must show only the
main checkout: a worktree that outlives its task is the litter a blocked worker leaves behind.

Close every remaining worker surface and confirm against the tree.

Emit `SPRINT_COMPLETION_REPORT.md` with: per-task status against the DAG (`DONE` /
`DONE_WITH_CONCERNS` / `BLOCKED`), the routing breakdown (how many tasks to Sol, how many to
Opus, how many re-briefed), stall and retry counts, files changed against files planned, the
pasted verification output, and every deviation from `SPRINT_PLAN.md` with its reason.

## Common mistakes

| Mistake | Consequence | Fix |
|---|---|---|
| `cmux new-split right --json \| jq -r '.surface_id'` | empty `SURFACE_ID`; the next `cmux send` with an empty `--surface` targets the wrong pane | `--json` does not exist; `cut -d' ' -f2` the plain-text `OK` line |
| `codex run --model X --prompt '...'` | no such subcommand, no such flag | `codex exec -m X - < brief` |
| Parsing the id out of `close-surface` output | you believe a surface closed that is still running | confirm with `cmux tree` |
| Nesting the brief in quotes inside the send payload | truncated brief on any apostrophe; the worker builds the wrong thing | brief file plus stdin redirect |
| Passing `--agent chief-operator` to a worker | recursive orchestrator spawning its own splits | root persona stays on the root surface |
| Polling `read-screen` as the completion signal | you close a pane mid-write, or wait forever on a finished one | `cmux wait-for` token, screen reads for diagnosis |
| Briefs under `$TMPDIR` | worker cannot find the file across the sandbox boundary | repo-relative brief paths |
| Running `cmux` sandboxed | `Operation not permitted (errno 1)` misread as a dead socket | disable the sandbox for cmux calls |
| `make test \| tail; echo ${PIPESTATUS[0]}` in the root shell | empty rc under zsh, so a red suite reports as passing | redirect to a log, capture `$?` on the next line |
| An invariant grep that matches the import line, or a lint target with hardcoded filenames | the gate passes vacuously and a broken invariant reads as green | run each check and read its matches; a new output file owns updating the harness |
| More than three concurrent splits | socket contention and unreconcilable scrollback | topological waves, width 3 |
