# /tdd-protocol — the Red → Green → Mutate → Refactor cycle

`/tdd-protocol` is the reference for this toolkit's TDD cycle: Plan → Red (write
a failing test) → Green (minimum code to pass it) → Mutate (a mutation-testing
gate) → Refactor, never skipping a phase. Most people meet it not by typing the
command but by hitting the `tdd-guard.sh` hook, which blocks a `Write`/`Edit` on
an implementation file until a test file has been touched in the session;
`SKIP_TDD_GUARD=1` is the documented escape hatch for genuine exceptions.

## When to use it

- Starting implementation work — load the full cycle and its phase signals
  (`[RED]`, `[GREEN]`, `[MUTATE]`, `[REFACTOR]`) before touching any code.
- The `tdd-guard.sh` hook just blocked a `Write`/`Edit` with "No test file
  found" — this skill is the protocol behind that block: write the failing
  test first, then retry.
- Deciding whether to run the mutation gate (`mutation-gate.sh`) between Green
  and Refactor, and interpreting what a survived-mutant result means.
- A diff is growing large and you want to isolate Red (test-writing) from
  Green (implementation) into separate subagent contexts, so the test author
  doesn't unconsciously shape the tests around the implementation they're
  already picturing.
- **Not for:** deciding *what* to build — that's `superpowers:brainstorming`
  and `superpowers:writing-plans`; this skill governs the code-writing cycle
  once a plan already exists.

## Examples

    > /tdd-protocol
    → Loads the cycle into context: Plan → Red → Green → Mutate → Refactor.
      For the task at hand, write the failing test first and signal `[RED]`
      before any implementation file is touched.

    > tdd-guard.sh fires on a Write/Edit to an implementation file with no
      test file touched yet this session
    → Blocks (exit 2) with: "TDD GUARD: No test file found for implementation
      file... Write the failing test FIRST (Red phase), then implement,"
      plus the expected test-file locations on stderr.

    > after Green, run the mutation gate before Refactor
    → `mutation-gate.sh` runs gremlins (Go) or Stryker (TS/JS) on just the
      changed packages; a result like "MUTATION GATE FAILED: 45% of mutants
      survived (threshold: 30%)" means the tests are theater — go back to
      Red and strengthen them before Refactor.

## Setup

`tdd-guard.sh` (PreToolUse hook) ships wired into this toolkit's hook config —
no extra setup to get the Red-phase block. The Mutate phase is optional and
needs one mutation tool on `PATH`:

```sh
go install github.com/go-gremlins/gremlins/cmd/gremlins@latest   # Go
npx stryker init                                                  # TS/JS, once per repo
```

Without either, `mutation-gate.sh` skips the gate for that language instead of
blocking.

## Notes

- The guard's exemption list is broad (docs, configs, `*.sh`, generated
  bridge/schema files, `cmd/*/main.go`, and more) — check `tdd-guard.sh`'s
  case patterns before assuming a given file needs a companion test.
- A block's stderr includes a dependency-mapped list of related test files
  when one can be found — read it before writing a new test from scratch.
- Related: [`worktree-guide`](../worktree-guide/) for where this cycle runs;
  `superpowers:brainstorming` and `superpowers:writing-plans` own the Plan
  phase upstream of it. Index:
  [`docs/skills-and-commands.md`](../../../docs/skills-and-commands.md).
