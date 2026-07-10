# Evals — the Failure→Eval convention

An **eval** is one small, executable check that fails when a specific
regression comes back. Evals are how a fix earns permanence: instead of a note
that says "remember not to do X," you ship a check that goes red the moment X
returns.

> **The Failure→Eval rule.** A failure observed twice ships its fix *with* an
> executable check that fails when the fix regresses. A memory note is not a
> fix — it is a reminder that decays. The eval is the fix's guardrail.

`scripts/run-evals.sh` discovers and runs every eval in this directory, prints
each verdict, and returns non-zero if any eval failed. Wire that runner into a
weekly job (below) and regressions announce themselves.

## Writing an eval

Copy [`TEMPLATE.eval.sh`](TEMPLATE.eval.sh) to `<your-check>.eval.sh` and fill
in the subject and the assertion. The template is a runnable, commented
skeleton for the whole contract. Note: as shipped, `TEMPLATE.eval.sh` itself is
discovered by the runner and prints one `SKIP` line (its placeholder subject
does not exist) — your weekly run stays green; the line disappears once you
copy or customize it.

Each eval is a self-contained script that:

1. Lives in `.claude/evals/` and is named `*.sh` (but **not** `*_test.sh` — see
   below). The runner sorts by filename, so a numeric prefix orders them.
2. Checks exactly one thing. One eval, one regression, one reason to be red.
3. Exits with the contract code and prints a verdict line as its **last**
   stdout line.

### Exit-code / verdict contract

| Exit | Verdict | Meaning | Effect on the run |
|------|---------|---------|-------------------|
| `0`  | PASS    | the guarded regression is absent | run stays green |
| `1`  | FAIL    | the regression is present | run goes red (runner exits 1) |
| `2`  | SKIP    | cannot run in this environment | run stays green |
| other | (crash) | unexpected exit | treated as FAIL — a crash is not a pass |

The last stdout line must be:

```
EVAL <name>: PASS|FAIL|SKIP — <detail>
```

Make `<detail>` specific. On FAIL it should name the exact regression
("subject no longer pins `set -euo pipefail`"), not just "check failed" — the
detail is what you read at 2am when the weekly run is red.

### Make the assertion discriminate

An eval is only worth shipping if it actually flips when its regression
returns. Two failure modes make an eval theater:

- **Re-deriving the implementation.** If the check computes the expected value
  the same way the subject does, they will always agree and the check asserts
  nothing. Derive the expected value by an *independent* path — grep for the
  exact token, count the exact rows, diff against a known-good literal.
- **Asserting only that "an error occurred."** A check that passes on any
  non-empty error, or on an error *prefix*, stays green when the subject breaks
  for an unrelated reason. Assert the exact discriminating condition.

Sanity-check by mutation: reintroduce the regression (or delete the guard the
eval protects) and confirm the eval goes red. If it stays green, it is theater
— rewrite it.

### Testing an eval

An eval can have a sibling `<name>_test.sh` harness. The runner **excludes**
`*_test.sh`, so a harness never runs as a real eval. Give the eval an
environment override for its subject (the template uses `EVAL_SUBJECT`) so the
harness can point it at a fixture copy and assert both the PASS and the FAIL
paths.

## Red-until-deploy

Some evals probe a **deployed** copy of an artifact — e.g. a hook installed at
`$HOME/.claude/hooks/…` rather than the source in the repo. Such an eval is
*expected* to be red between the moment you commit the fix and the moment you
deploy it. That is a feature: the red eval is the reminder that the fix is not
yet live. It turns green when the deploy lands. Note this in the eval's FAIL
detail (e.g. "deployed copy stale — run the deploy") so a red run reads as
"deploy pending," not "logic broken."

## Running

From the repo root:

```sh
bash scripts/run-evals.sh
```

Output ends with a summary and a matching exit code:

```
EVALS: 7/8 pass, 1 fail, 0 skip
```

### Wire a weekly run

Have CI (or a local scheduler) invoke the runner on a cadence and fail the job
on non-zero exit. A minimal GitHub Actions step:

```yaml
# .github/workflows/evals.yml
on:
  schedule:
    - cron: "0 14 * * 1"   # Mondays 14:00 UTC
  workflow_dispatch:
jobs:
  evals:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - run: bash scripts/run-evals.sh
```

Locally, any cron/launchd/systemd-timer that runs `bash scripts/run-evals.sh`
and alerts on a non-zero exit works the same way.
