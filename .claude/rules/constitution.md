# Constitution (Hot Memory)

Failure modes observed more than once. Violating any of these is a blocking issue.

## Theater Tests — The #1 Problem
- A test must fail when its subject is broken. If deleting the subject under test leaves the test green, delete the test and write a real one.
- Each assertion compares to a literal or independently-derived expected value; `expect(true)`, `assert.Equal(t, x, x)`, and bare `t.Log` are not assertions.
- Each test function calls the code under test and asserts at least one meaningful property of the result.
- Mock at most one layer deep; use real implementations for anything inside the outermost boundary.
- Derive the expected value by a different path from the implementation — duplicating the implementation's logic in the test tests nothing.

## Test Quality Gate
- After Green: name the bug this test catches. If you can't name one, the test is theater.
- Test behavior, not structure — what the code does, not how it's organized.
- Prioritize edge cases and error paths over happy paths.

## Implementation Discipline
- When a test fails, fix the implementation. Modify the test only when the test itself has a genuine bug.
- Change tests and implementation in separate turns and separate commits.

## Common Agent Failure Modes
- Writing 500 LOC of tests that all pass immediately — this means you wrote tests AFTER implementation, not before.
- Creating test helpers/utilities before writing any actual test — premature abstraction.
- Excessive mocking that decouples tests from real behavior entirely.
