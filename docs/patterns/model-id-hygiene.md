# Pattern: Model ID Hygiene

## What

Model catalog IDs come in two shapes: **single-namespace** public catalog IDs
(`nvidia/nemotron-3-ultra-550b-a55b:free`) and **double-namespace ("hub-form")**
IDs, where an org's name is repeated as both the top-level namespace and a
sub-namespace underneath it. Hub-form IDs are internal-catalog references —
they resolve only against a private endpoint and must never ship in a public
repo. The toolkit's sync gate treats this as a mechanical leak check, not a
style nit: an internal default sailing through a capture into this repo would
be a silent leak of internal infrastructure shape.

## How

The carve-out policy is one rule: **single-namespace IDs are always fine;
double-namespace hub-form IDs are always flagged**, regardless of which file
they appear in. This is enforced by a generic leak pattern in
`scripts/sync-lib.sh` (`GENERIC_LEAK_PATTERNS`), the shared library sourced
by both `scripts/capture.sh` (refresh this repo from the live `~/.claude`)
and `scripts/diff.sh` (compare without refreshing).

Run the gate directly:

```bash
scripts/capture.sh --claude-only   # refreshes + gates in one pass
# or, to check without touching any files:
scripts/diff.sh --claude-only
```

A hub-form ID anywhere in a refreshed/diffed file produces a non-zero exit
and a `LEAK?` line naming the file:

```
LEAK? .claude/tool/cfg.py
```

A single-namespace catalog ID in the same file passes clean — no `LEAK?`,
exit 0. This is what test case T13 in `scripts/sync-gate_test.sh` verifies:
a fixture carrying a repeated-org hub-form ID must flip the gate, and a
fixture carrying `nvidia/nemotron-3-ultra-550b-a55b:free` must not.

## Env

This pattern has no runtime env vars of its own — it's a static text scan.
`REPO_DIR` and `HOME` (both overridable, mainly for the test harness) control
which trees `capture.sh`/`diff.sh` compare.

## Pitfalls

- **The pattern is substring-based, not semantic.** It flags the hub-form
  shape wherever it appears — comments, fixtures, docstrings — not just live
  model-selection code. If you need to document the shape itself, keep the
  example generic (e.g. an `acme/acme/model-x` placeholder) rather than
  writing out the real internal org's repeated-namespace form, or the
  documentation would trip its own gate.
- **New files aren't auto-covered.** `capture.sh` only refreshes files
  already tracked in this repo (allowlist model) — a brand-new file with a
  leaked ID won't be caught until it's `git add`ed and captured/diffed at
  least once.
- **Curated files are exempt from refresh, not from the gate.** Files listed
  in `CURATED` in `sync-lib.sh` are never overwritten by capture, but they
  are still hand-maintained — review them for hub-form IDs manually.
