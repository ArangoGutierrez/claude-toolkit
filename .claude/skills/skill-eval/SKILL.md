---
name: skill-eval
user-invocable: true
description: >
  Measure skill discoverability — run each skill's evals.json (positive +
  decoy prompts) through a real headless-claude activation probe and emit a
  pass/fail scorecard. Use to check routing/decoy behavior or catch
  mis-trigger regressions. Triggered by /skill-eval [skill ...]. Not for
  measuring output correctness or running skills for their side effects.
argument-hint: "[skill ...]"
tools:
  - Bash
  - Read
---

# skill-eval

## Purpose
Quantify whether a skill activates on prompts that should trigger it and stays
silent on near-neighbor decoys, by probing real `claude` activation.

## Instructions
Run `scripts/skill-eval.sh` with zero args (all skills that have an `evals.json`)
or a list of skill names. Read the printed scorecard; a non-zero exit means at
least one FAIL or ERROR.

## Available Scripts
- `scripts/skill-eval.sh [skill ...]` — orchestrator.
- `scripts/probe.sh` / `score.jq` / `report.sh` / `extract.jq` — the units.

## Prerequisites
`claude` CLI and `jq` on PATH. Each evaluated skill needs an `evals.json`
(schema: `{skill, cases:[{id, prompt, expect:"activate"|"silent"}]}`).

## Limitations
Discoverability only (no output-correctness). Activation is measured headlessly,
a proxy for interactive routing. Rates use N attempts (default 5) — tune with
`SKILL_EVAL_N` / `SKILL_EVAL_PASS` / `SKILL_EVAL_DECOY`.

## Troubleshooting
- All ERROR verdicts → `claude` invocation failing; run one probe manually.
- Decoys always fire → tighten the skill's description negative-scope.
