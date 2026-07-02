# skill-eval

Discoverability harness for agent skills. Each skill ships an `evals.json` with
positive and decoy prompts; `skill-eval.sh` probes real `claude` activation N
times per case and scores activation/false-fire rates against thresholds.

Adopts a per-skill evaluation pattern (a "discoverability" dimension),
scoped to a single agent and measured against real activation.

## Usage

```bash
.claude/skills/skill-eval/scripts/skill-eval.sh            # all skills with evals.json
.claude/skills/skill-eval/scripts/skill-eval.sh kickoff goal
```

Run from the repo root so `.claude/skills/` is discoverable. Output: a Markdown
scorecard on stdout (and `.out/scorecard.md` + `.out/scores.json`); exit code is
non-zero if any case FAILs or ERRORs.

| Env | Default | Meaning |
|---|---|---|
| `SKILL_EVAL_N` | 5 | attempts per case |
| `SKILL_EVAL_PASS` | 0.6 | min activation rate for a positive case |
| `SKILL_EVAL_DECOY` | 0.2 | max false-fire rate for a decoy case |
| `CLAUDE_MODEL` | claude-haiku-4-5-20251001 | probe model |

## eval schema

```json
{ "skill": "kickoff",
  "cases": [
    { "id": "pos-x", "prompt": "...", "expect": "activate" },
    { "id": "decoy-y", "prompt": "...", "expect": "silent", "note": "routes elsewhere" }
  ] }
```

## Running the tests

Bash `*_test.sh` live beside the scripts (plus `tests/skill-structure_test.sh`):

```bash
for t in .claude/skills/skill-eval/scripts/*_test.sh .claude/skills/skill-eval/tests/*_test.sh; do bash "$t" < /dev/null; done
```

The suites use here-strings and `mktemp`; under a restrictive sandbox they need a
writable `$TMPDIR` (or run sandbox-disabled).
