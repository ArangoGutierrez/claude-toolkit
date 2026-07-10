# Engineering Discipline: Tuning Claude Code Into a System

A coding agent is fast and tireless, and it will happily skip the boring parts:
the failing test you were supposed to write first, the signature on the commit,
the command that proves the change actually works. Convention documents do not
stop it — under any pressure at all, "just this once" becomes the norm, and a
few weeks later the convention lives only in a file nobody reads.

This toolkit takes a different position: **discipline that matters is enforced
at the toolchain level, not written down and hoped for.** The configuration in
this repository turns a handful of engineering principles into machinery that
fires on every relevant action, produces evidence instead of claims, and makes
regressions announce themselves.

This page walks the six ideas the toolkit is built on. Each one links to the
shipped artifact that implements it, so you can read the source, run its tests,
and adapt it to your own stack.

Cross-references: [Architecture](architecture.md) |
[Claude Code Configuration](claude-code.md) |
[Skills & Commands](skills-and-commands.md)

---

## 1. Enforcement over convention — hooks fire every time

A [hook](claude-code.md#hooks) is a small shell script Claude Code runs at a
lifecycle event. It reads the event JSON on stdin, does exactly one thing, and
exits. The contract is deterministic: `exit 0` allows the action, `exit 2`
blocks it and sends the script's stderr back to the model as feedback. No model
call, no judgment — the same input always produces the same decision.

That determinism is the whole point. A hook cannot be talked out of its rule,
cannot forget under deadline, and applies identically to a human and to an
agent that has no idea your team even has the convention. The shipped
enforcement hooks each close one recurring gap:

| Hook | Fires on | Closes the gap |
|------|----------|----------------|
| `sign-commits.sh` | every `git commit` | commits missing `-s` (DCO) or `-S` (GPG) |
| `tdd-guard.sh` | Write/Edit of an implementation file | implementation written before any test exists |
| `enforce-worktree.sh` | Write/Edit on the coordination branch | source edited on the wrong branch |
| `prevent-push-workbench.sh` | every `git push` | the local-only coordination branch leaking to a remote |
| `validate-year.sh` | new-file creation | a stale training-data year in a copyright header |

The lesson generalizes past this list: when a rule is worth having, express it
as a hook that blocks the violation with an actionable message, not as a bullet
in a style guide. The full hook reference — every event, matcher, and error
message — lives in [Claude Code Configuration](claude-code.md#hooks), and the
scripts themselves are in [`.claude/hooks/`](../.claude/hooks/).

---

## 2. Evidence over claims — verification pipelines

An agent that says "all tests pass" has told you nothing you can act on. The
claim and the evidence for it are different things, and only one of them
survives review. The toolkit ships two hooks that make evidence structural
rather than optional.

**`verify-gate.sh`** is a `Stop` hook. It scans the session transcript: if
source files changed this session but no test, build, or lint command ran, it
blocks the stop once with a nudge to actually verify. It does not judge
pass or fail — the bar is simply "a verification command ran." It fails open on
any error and honors `export VERIFY_GATE=off` as an escape hatch. The full
contract is in [`verify-gate.README.md`](../.claude/hooks/verify-gate.README.md).

**`bash-audit-log.sh`** is a `PostToolUse` hook. It appends one line per Bash
command the agent runs to a dated log under `~/.claude/audit/`, folding
compound commands onto a single line so every sub-command shares the session
marker, and redacting URL-embedded credentials and `--token` / `--password` /
`--api-key` / `--secret` values before anything is written. It always exits 0 —
an audit log must never block the work it records.

Together they encode a single habit: **produce the evidence as you go, and keep
a record of what was actually run.** Registration snippets for both hooks are in
[`.claude/hooks/README.md`](../.claude/hooks/README.md).

---

## 3. Budget governance

Long agent sessions and fanned-out subagents burn output tokens in ways that are
easy to lose track of until the bill arrives. **`budget-governor.sh`** is a
`Stop` hook that sums output tokens across the session transcript and any
subagent transcripts, then emits a one-time advisory as spend crosses 80% and
100% of a declared budget.

It is purely advisory — always exits 0, never blocks — and it degrades silently
when its one input is absent, so it is safe to wire before anything produces the
input. That input is a per-session goal file; the last `Budget: <N>` line in it
(for example `Budget: 200k`) sets the ceiling. No goal file or no budget line
means the hook stays quiet. Overrides and the full contract are documented in
[`.claude/hooks/README.md`](../.claude/hooks/README.md).

The principle: make cost visible at the moment it is spent, as a gentle signal
rather than a hard wall, so budget awareness becomes ambient instead of a
post-hoc surprise.

---

## 4. Tests are contracts — theater-test discipline

The most expensive test is the one that passes whether or not the code works. A
green suite full of tautologies is worse than no suite: it manufactures
confidence with no coverage behind it. The toolkit's
[`constitution.md`](../.claude/rules/constitution.md) rule — loaded into every
session — makes the standard explicit and non-negotiable:

- **A test must fail when its subject is broken.** If deleting the code under
  test leaves the test green, the test proves nothing. Delete it and write a
  real one.
- **Every assertion compares to an independently-derived value.** Re-computing
  the expected result the same way the implementation does is a mirror, not a
  check. Derive it by a different path — a literal, a hand-count, a known-good
  fixture.
- **After green, name the bug this test catches.** If you cannot name one, the
  test is theater.
- **Mutation-check the guard.** For a test that guards against a specific
  regression, reintroduce the regression (or delete the guard) and confirm the
  test goes red. If it stays green, it never protected anything.

The `test-quality-lint.sh` hook flags the most common theater patterns
automatically, but the constitution is the standard the hook approximates. When
in doubt, delete the code the test claims to cover and watch what the test does.

---

## 5. Failure → Eval

A note that says "remember not to do X" is a reminder that decays. The moment
the person who wrote it moves on, X comes back. The toolkit's answer is a
convention with teeth:

> **A failure observed twice ships its fix *with* an executable check that fails
> when the fix regresses.** The check — an *eval* — is the fix's guardrail.

Evals live in [`.claude/evals/`](../.claude/evals/). Each one is a small,
self-contained script that checks exactly one thing and prints a verdict as its
last line. The exit-code contract is narrow on purpose:

| Exit | Verdict | Effect on the run |
|------|---------|-------------------|
| `0` | PASS | the guarded regression is absent |
| `1` | FAIL | the regression is back — the run goes red |
| `2` | SKIP | cannot run in this environment |

`scripts/run-evals.sh` discovers every eval, runs it, and returns non-zero if
any failed — wire it into a weekly job and regressions announce themselves.
[`TEMPLATE.eval.sh`](../.claude/evals/TEMPLATE.eval.sh) is a runnable skeleton
to copy.

The discipline that makes an eval worth shipping is the same one from the
constitution: **the assertion must discriminate.** An eval that re-derives the
implementation, or that passes on any error rather than the exact one, is
theater in a different costume. Sanity-check by mutation before you trust it.
The full framework — writing, testing, and the red-until-deploy nuance — is in
[`.claude/evals/README.md`](../.claude/evals/README.md).

---

## 6. The orchestrator pattern — a pattern, not a magic command

The most reliable multi-agent setup does not run on trust. It runs on
fully-specified briefs, isolated workspaces, written reports, and an adversarial
review that treats every report as an unverified claim until the evidence checks
out.

The toolkit ships the pieces to run this yourself:

- **Fully-specified briefs.** One agent implements exactly one task from a
  written brief — the requirements, the working directory, the report path, and
  the exact commit format. Ambiguity is escalated, not guessed. The
  [`team-plan`](../.claude/skills/team-plan/README.md) skill decomposes work
  into briefs like this.
- **Isolated worktrees.** Each worker implements in its own Git worktree, so
  concurrent work is physically separated (see [Architecture](architecture.md)).
  The [`team-execute`](../.claude/skills/team-execute/README.md) skill spawns
  the workers; [`team-shutdown`](../.claude/skills/team-shutdown/README.md)
  retires them.
- **Report files with a status vocabulary.** Each worker writes a report and
  returns a status: `DONE`, `DONE_WITH_CONCERNS`, `BLOCKED`, or
  `NEEDS_CONTEXT`. The vocabulary forces an honest signal — "done, but here is
  what I am unsure about" is a first-class outcome, not a footnote.
- **An adversarial review gate.** Before anything merges, a reviewer reads the
  work against its brief and treats the implementer's report as claims to
  verify, not facts to accept. The shipped
  [`principal-engineer`](../.claude/agents/principal-engineer.md) (architecture,
  conventions, security) and [`qa-engineer`](../.claude/agents/qa-engineer.md)
  (test quality, mutation checks, CI replication) agents are this gate.

Note what is **not** here: no single command runs the whole
plan → execute → review → merge loop end to end. The conductor that
sequences all of the above is deliberately
left out, because the right orchestration depends on your repository, your CI,
and your risk tolerance. What ships is the *pattern* and its building blocks —
wire them into a loop that fits your project. Documenting the pattern is the
point; a one-command black box would hide exactly the decisions you should be
making.

---

## Where to go next

- [Architecture](architecture.md) — the worktree and coordination-branch model
  these principles run on top of.
- [Claude Code Configuration](claude-code.md) — the full hook, settings, and
  permission reference.
- [Getting Started](getting-started.md) — install the toolkit and watch the
  enforcement fire on your first session.
