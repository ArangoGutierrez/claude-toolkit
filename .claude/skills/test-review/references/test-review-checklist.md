# Test Review Checklist

Each item is a concrete, detectable signal — not a vibe. For every item: **look
for** the signal, understand **why it bites**, and know what **right** looks like.
When in doubt on a test, apply the deletion test first (item 1.1): a test that
survives deletion of its subject asserts nothing.

## 1. Theater-test detection

1. **The deletion test** — Mentally (or actually) delete the function under test.
   Does the test still pass? *Bites:* a green test that survives deletion gives
   false confidence and hides the very bug it claims to cover. *Right:* every test
   fails with a clear message when its subject is removed or broken.

2. **Tautological assertions** — `assert x == x`, `expect(true)`,
   `assert.Equal(t, x, x)`, or asserting that a mock returns exactly what the mock
   was configured to return. *Bites:* compares a value to itself or to a constant
   the test itself set — no property of real code is checked. *Right:* each
   assertion compares against a literal or a value derived independently of the
   implementation.

3. **Expected value re-derived from the implementation** — the test computes its
   expected value by re-running the implementation's own logic (same formula, same
   helper). *Bites:* any bug in that logic is copied into the expectation, so the
   two always agree. *Right:* derive the expected value by hand, from a spec, or by
   a different method than the code uses.

4. **Error-prefix / error-type-only assertion on a discriminating guard** — a
   negative test asserts only that *an* error occurred, or matches a prefix
   (`startswith("ERROR")`) or type, when the guard's *exact message* is what
   distinguishes it. *Bites:* stays green if the guard is deleted and the code
   errors for an unrelated reason, so it never proves the guard fired. *Right:*
   assert the exact discriminating message or field the guard produces.

5. **Guard fixture that can't trip the guard** — a guard/negative test whose input
   would not be flagged even with the guard removed. Example: a `\badmin\b`
   word-boundary check "tested" only against the string `administrator`, which the
   `\b` boundary never matches, so the test passes even against code with the guard
   deleted. *Bites:* the guard is never exercised. *Right:* the fixture MUST contain
   an input the guard actually flips (here, a standalone `admin`); confirm by
   deleting the guard and watching the test go red.

6. **Over-mocking** — mocks more than one layer deep, mocking the subject under
   test itself, or replacing everything inside the outermost boundary. *Bites:* the
   test exercises the mocks' behavior, not the code's; real integration bugs pass
   through untouched. *Right:* mock at most one layer deep (the outermost external
   boundary); use real implementations inside it.

7. **Asserting on mock call counts instead of behavior** — the only assertions are
   `assert_called_once()` / `verify(x).times(1)` with no check on the produced
   result. *Bites:* tests how the code is wired, not what it does; a correct
   refactor that changes call patterns breaks it while broken behavior passes.
   *Right:* assert the observable output or effect; use call-count checks only to
   pin a contract that has no observable output.

8. **Large test diff green on first run with zero implementation change** — a big
   block of new tests all passing immediately against unchanged code. *Bites:*
   strong signal the tests were written after the implementation to fit it, not to
   constrain it; they encode current behavior, bugs included. *Right:* scrutinize
   each assertion via the deletion test; the tests for new/changed behavior should
   have driven a code change.

9. **Missing negative / edge / error-path cases** — only happy-path assertions for
   behavior the PR claims to add (no error branch, boundary, empty, or nil case).
   *Bites:* the failure modes that actually ship bugs are exactly the untested ones.
   *Right:* cover the error and edge paths for the changed behavior, not just the
   success path.

10. **Seam-only assertion across a serialization / protocol boundary** — the test
    asserts the pre-wire value (the struct or string a function returns) and assumes
    the framework that serializes it for the wire is transparent. *Bites:* the
    emitted artifact can be malformed (extra fields, wrong envelope) while the inner
    value is correct — green test, broken wire contract. *Right:* at least one test
    round-trips through the real serializer or in-memory client and asserts the
    actual emitted bytes.

## 2. e2e and integration quality

1. **`sleep` as synchronization** — a fixed `sleep N` to wait for a condition.
   *Bites:* flaky — too short fails under CI load, too long wastes minutes; the real
   ready-signal is never checked. *Right:* poll with a timeout (`Eventually`,
   retry-until-condition) on the actual condition.

2. **Retries that mask real failures** — a blanket retry or `|| true` around a step
   that can fail for real reasons. *Bites:* converts a genuine regression into an
   intermittent pass; the bug ships. *Right:* retry only known-transient operations,
   bounded count, and fail loudly otherwise.

3. **Exit-code-only "pass"** — the test asserts the process or command exited 0 with
   no assertion on its output or effect. *Bites:* many broken behaviors still exit 0;
   the test proves the binary ran, not that it did the right thing. *Right:* assert a
   behavioral property (output content, resource state, side effect).

4. **Missing teardown / cleanup** — created namespaces, pods, ports, temp dirs, or
   files are not removed. *Bites:* leaks accumulate across runs, cause later tests to
   collide, and mask state dependence. *Right:* clean up in `defer` / `t.Cleanup` /
   `AfterEach`, runnable even when the test fails midway.

5. **Order / state dependence between tests** — a test depends on state a prior test
   left behind, or on suite ordering. *Bites:* passes locally, breaks under shuffle,
   parallelism, or when run in isolation. *Right:* each test sets up its own state
   and is independent.

6. **Index-based access into list-returning APIs** — `.Items[0]`, `results[2]` from
   a List/Range call. *Bites:* list order is not guaranteed; the test passes on the
   author's machine and breaks under reordering. *Right:* key by name/UID into a map,
   or sort before comparison (`ElementsMatch` for unordered sets).

7. **Hermeticity — live network / registry dependence** — the e2e pulls a `:latest`
   image, hits a public URL, or resolves DNS it doesn't control. *Bites:* fails when
   the network or upstream is down; not reproducible; can silently test a different
   artifact than intended. *Right:* pin digests, use a local registry or fixture,
   stub external hosts.

8. **Unrealistic timeouts for CI hardware** — timeouts tuned to a fast dev laptop.
   *Bites:* CI runners are slower and contended; the test flakes only in CI, the
   worst place to debug. *Right:* set timeouts against the slowest supported runner
   with headroom.

9. **Parallel safety** — `t.Parallel()` or parallel e2e that shares a fixed port,
   file path, or cluster resource name. *Bites:* concurrent runs collide
   non-deterministically. *Right:* unique per-test resource names; no shared mutable
   global.

10. **Fixture timestamps fixed in absolute time + TTL logic** — a fixture hard-codes
    a date and the code applies a freshness/TTL window against the real clock.
    *Bites:* the test rots — it passes now and fails purely by passage of time once
    the fixture ages past the window. *Right:* compute fixture times relative to now
    (`now - Δ`), or inject/freeze the clock.

## 3. GitHub Actions correctness

1. **Actions not pinned to a full commit SHA** — `uses: owner/action@v4` or `@main`.
   *Bites:* tags and branches are mutable; a retagged or compromised action runs with
   your token. *Right:* pin to a full 40-char commit SHA, with the version in a
   trailing comment.

2. **Over-broad `permissions:`** — no `permissions:` block, or a workflow-level
   `write-all`. *Bites:* the default `GITHUB_TOKEN` is broadly privileged; any
   compromised step can push, comment, or release. *Right:* least-privilege,
   job-level `permissions:` granting only what each job needs (`contents: read`
   baseline).

3. **`pull_request_target` + checkout of PR head** — a `pull_request_target` workflow
   (which runs with repo secrets) that checks out and executes the fork's code.
   *Bites:* fork code runs with write-scoped secrets — full repo compromise. *Right:*
   use `pull_request` for untrusted code, or check out the base ref and never execute
   PR-head scripts under `pull_request_target`.

4. **Untrusted `${{ github.event.* }}` in `run:`** — interpolating
   `github.event.issue.title`, `.pull_request.body`, etc. directly into a shell
   `run:`. *Bites:* an attacker controls those strings → shell injection into the
   runner. *Right:* pass through an `env:` variable and reference `"$VAR"` (env
   indirection); never inline the expression.

5. **Secrets reachable from fork PRs** — plain fork `pull_request` runs get no secrets
   by default; exposure comes from `pull_request_target` (item 3) or the repo opt-in
   that sends secrets to fork runs. *Bites:* a malicious fork change exfiltrates them.
   *Right:* keep secret-using jobs off fork-triggered events, or use environments with
   required reviewers.

6. **Cache-key / restore-keys poisoning** — a `restore-keys` fallback that lets a
   PR-populated cache be restored into trusted jobs. *Bites:* an attacker primes a
   cache entry that a privileged job then trusts. *Right:* scope cache keys by
   ref/trust; don't share writable caches across trust boundaries.

7. **`if: always()` swallowing failures** — a final step or gate with `if: always()`
   that reports success regardless of prior failures. *Bites:* a red step is masked
   and the job goes green. *Right:* use `if: always()` only for cleanup/upload; gate
   pass/fail on the real step's result.

8. **Missing concurrency group** — no `concurrency:` to cancel superseded runs on a
   busy PR. *Bites:* wastes runners and can let a stale run's status win. *Right:* a
   `concurrency:` group keyed on ref with `cancel-in-progress`. *(usually `consider`)*

9. **Matrix / OS coverage inconsistent with claims** — the matrix omits an OS or
   version the repo says it supports. *Bites:* the "supported" platform is never
   actually tested. *Right:* the matrix covers every platform the repo claims to
   support.

10. **Artifact upload / retention sanity** — uploads with no path filter (dragging in
    secrets or the whole workspace) or an unbounded retention. *Bites:* leaks or
    storage bloat. *Right:* scoped upload paths; explicit sane `retention-days`.
    *(usually `consider`)*

## 4. Prow correctness

1. **Job type vs intent mismatch** — presubmit / postsubmit / periodic chosen
   inconsistently with the job's purpose. *Bites:* e.g. a gating check authored as a
   postsubmit never blocks the PR it was meant to guard. *Right:* presubmit for PR
   gates, postsubmit for merge-to-branch actions, periodic for scheduled sweeps.

2. **`run_if_changed` / `skip_if_only_changed` regex mismatch** — the regex doesn't
   actually match the paths it intends (unescaped `.`, missing directory anchor,
   wrong alternation). *Bites:* the job silently never runs on the changes it guards,
   or always runs. *Right:* test the regex against real matching and non-matching
   example paths before trusting it; use `always_run: true` only when truly
   unconditional.

3. **`decorate` / utility images** — `decorate: false` where pod-utils are needed, or
   pinned-stale utility images. *Bites:* missing log/artifact upload and clone
   tooling; stale images carry known bugs. *Right:* `decorate: true` for standard
   jobs; utility images current.

4. **Missing resource requests/limits on job pods** — the job spec has no
   `resources`. *Bites:* the pod can starve the build cluster or get OOM-killed
   nondeterministically → flakes. *Right:* explicit requests and limits sized to the
   job.

5. **`branches` / `skip_branches` consistency** — the branch filters contradict each
   other or the intended release lines. *Bites:* the job runs on the wrong branches
   or skips ones it must cover. *Right:* filters match the branches the job is meant
   to gate; regexes anchored.

6. **Missing testgrid annotations on new jobs** — a new job with no
   `testgrid-dashboards` / related annotations. *Bites:* the job's health is
   invisible on the dashboard; failures go unnoticed. *Right:* testgrid annotations
   present so the job surfaces on a dashboard.

7. **Job name uniqueness** — a new job reuses an existing job name. *Bites:* name
   collisions break history, triggering, and dashboard attribution. *Right:* a
   unique, descriptive job name.

8. **cluster / trusted-cluster for privileged jobs** — a job needing secrets or
   privilege not pinned to the trusted `cluster:`. *Bites:* privileged work on the
   wrong cluster is a security-boundary violation. *Right:* privileged jobs pinned to
   the designated trusted cluster; others on the build cluster.

9. **OWNERS alignment** — who can trigger or approve the job doesn't match the OWNERS
   for the paths it covers. *Bites:* trigger rights drift from code ownership.
   *Right:* OWNERS reflect the intended approvers for the job and its paths.

## Reporting

For each finding: `file:line`, a 1–2 sentence description, `category`
(theater-test / flakiness / ci-config / coverage-gap), `severity` (must-fix /
should-fix / consider), and the checklist item number that flagged it. Flag
coverage gaps only for behavior the PR claims to add — never demand 100% coverage.
