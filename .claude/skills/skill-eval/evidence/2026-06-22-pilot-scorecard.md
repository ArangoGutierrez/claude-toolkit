# skill-eval pilot scorecard — 2026-06-22

First real E2E of the discoverability harness (`kickoff` + `goal`, N=3,
`--max-turns 1` activation probe against live `claude`).

| skill | case | expect | rate | verdict |
|---|---|---|---:|---|
| kickoff | pos-rough-idea | activate | 0% | FAIL |
| kickoff | pos-kickoff-verb | activate | 100% | PASS |
| kickoff | decoy-goal | silent | 0% | PASS |
| kickoff | decoy-question | silent | 0% | PASS |
| goal | pos-set-goal | activate | 100% | PASS |
| goal | pos-amend-goal | activate | 100% | PASS |
| goal | decoy-kickoff | silent | 0% | PASS |
| goal | decoy-question | silent | 0% | PASS |

**Totals:** 7 pass, 1 fail, 0 error (exit 1)

## What this proves
- The harness runs end-to-end against real `claude` and produces a correct scorecard.
- All four decoys (including the near-neighbors `kickoff↔goal`) correctly stay
  silent — the discoverability discrimination works.
- `goal` activates reliably on both NL phrasings (3/3 each).

## Finding (real signal, not a harness bug)
`kickoff/pos-rough-idea` ("turn my rough idea … into a scoped task") did NOT
activate kickoff (0/3), while `pos-kickoff-verb` ("kick off work on …") did (3/3).
kickoff's SKILL.md frames it as `/kickoff`-triggered; the model under-routes the
pure-NL "rough idea → scoped task" phrasing despite it matching kickoff's stated
purpose — exactly the description-vs-activation gap this harness exists to surface.

Resolution is a SEPARATE change (broaden kickoff's description, or revise the eval
expectation), NOT part of this harness PR. The FAIL is left standing as the honest
signal — gaming the eval to green would defeat the harness's purpose.
