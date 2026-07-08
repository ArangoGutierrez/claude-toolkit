---
name: tdd-protocol
description: Use when starting implementation work
user-invocable: true
---

# TDD Protocol (DORA)

## Cycle
Plan → Red → Green → Mutate → Refactor. Never skip phases.

## Phases

- **Plan**: Design doc/plan before any code (brainstorm first)
- **Red**: Write failing test first. Signal: `[RED]`
  - Define the expected behavior as a test
  - Run test — confirm it fails for the right reason
  - Only then proceed to Green
- **Green**: Minimum code to pass. Signal: `[GREEN]`
  - Modify tests and implementation in separate turns
  - Write the simplest code that makes the test pass
  - No optimization, no cleanup — just pass
- **Mutate**: After Green, before Refactor. Signal: `[MUTATE]`
  - Mutation-check guards by hand: delete or weaken the guard under test (the condition, the regex, the boundary check) and confirm the suite goes red
  - If a mutated/weakened guard still passes the suite, your tests are theater — go back to Red and strengthen them
  - For non-guard logic, an automated mutation tool (`gremlins` for Go, Stryker for TS/JS) can supplement hand-checking when available; skip if tools unavailable
- **Refactor**: Clean up only after green + mutate. Signal: `[REFACTOR]`
  - Checkpoint first if >3 files or >50 LOC changed
  - Improve structure, naming, duplication
  - Tests must still pass after refactoring

## Rules

- **Fitness function**: Tests are contracts. Fix the implementation when a test fails (unless the test itself has a genuine bug).
- **Batch size**: Smallest PR-sized chunks. 1 concern = 1 PR
- Tests define "done". Implementation stops when tests pass

## Enforcement

- **Discipline-enforced, not hook-enforced**: no automated guard blocks implementation writes. Catching yourself writing implementation before a failing test exists means you're in the wrong phase — stop and go back to Red.
- **Escalation**: When diff exceeds threshold, use isolated subagent contexts — one for Red (test writing), one for Green (implementation). Prevents same-author blind spots where the test writer unconsciously shapes tests to match the implementation they're already imagining.
