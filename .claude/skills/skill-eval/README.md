# /skill-eval — measure skill discoverability

`/skill-eval [skill ...]` probes real `claude` activation N times per prompt to
check that a skill fires on the prompts that should trigger it and stays silent
on near-neighbor decoys, then emits a pass/fail scorecard. It measures
*discoverability* (routing), not output correctness. A non-zero exit means at
least one case ended in FAIL or ERROR, so it doubles as a CI gate.

## When to use it

- After editing a skill's `description`, to confirm it still activates on real
  prompts and hasn't started swallowing near-neighbor ones.
- To catch false-fire regressions across the whole set — run with no args to
  score every skill that ships an `evals.json`.
- To tune a decoy that keeps firing or a positive case that keeps missing.
- **Not for:** checking whether a skill's *output* is correct, or running
  skills for their side effects — this only measures whether they activate.

## Examples

    > /skill-eval
    → probes every skill that has an evals.json (N attempts per case); prints a
      Markdown scorecard (also written to .out/scorecard.md + .out/scores.json).
      Exit is non-zero if any case reports FAIL or ERROR.

    > /skill-eval kickoff goal
    → scores just those two skills — activation rate for each positive case and
      false-fire rate for each decoy — against the pass/decoy thresholds.

## Setup

Run from the repo root so `.claude/skills/` is discoverable (the runner is
`.claude/skills/skill-eval/scripts/skill-eval.sh` for direct/CI use). Requires
the `claude` CLI and `jq` on `PATH`, and an `evals.json` in each evaluated skill:

```json
{ "skill": "kickoff",
  "cases": [
    { "id": "pos-x", "prompt": "...", "expect": "activate" },
    { "id": "decoy-y", "prompt": "...", "expect": "silent", "note": "routes elsewhere" }
  ] }
```

| Env | Default | Meaning |
|---|---|---|
| `SKILL_EVAL_N` | 5 | attempts per case |
| `SKILL_EVAL_PASS` | 0.6 | min activation rate for a positive case |
| `SKILL_EVAL_DECOY` | 0.2 | max false-fire rate for a decoy case |
| `CLAUDE_MODEL` | claude-haiku-4-5-20251001 | probe model |

## Notes

- Headless activation is a proxy for interactive routing — treat scores as a
  signal, not proof.
- All ERROR verdicts → the `claude` invocation itself is failing; run one probe
  manually to see why. Decoys always firing → tighten the skill's negative
  scope in its `description`.
- Run the harness's own tests with:
  `for t in .claude/skills/skill-eval/scripts/*_test.sh .claude/skills/skill-eval/tests/*_test.sh; do bash "$t" < /dev/null; done`
  (they need a writable `$TMPDIR` under a restrictive sandbox).
- Related: [`writing-skills`](../../../docs/skills-and-commands.md). Index:
  [`docs/skills-and-commands.md`](../../../docs/skills-and-commands.md).
