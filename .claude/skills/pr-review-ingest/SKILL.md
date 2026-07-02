---
name: pr-review-ingest
description: Learn from PR review feedback — classify comments, propose rule updates. Triggered by "learn from PR", "review feedback", or /pr-review-ingest
user-invocable: true
tools:
  - Read
  - Grep
  - Bash
  - Edit
---

# PR Review Ingest

Parse GitHub PR review comments, classify them, and propose rule updates.

## Limitation (until memory ships)
Each invocation is stateless — cannot detect recurring patterns across PRs. Only high-severity findings (bug, architecture, security) are written to rules/ directly.

## Process

1. **Fetch reviews:** `scripts/parse-gh-reviews.sh <PR-number-or-URL>`
2. **Classify each comment:**
   - `style` — formatting, naming (note but don't promote)
   - `bug` — correctness issue (propose rule if pattern)
   - `architecture` — design issue (propose rule if pattern)
   - `security` — vulnerability (always propose rule)
   - `testing` — test quality (propose rule if pattern)
   - `nit` — trivial (ignore)
3. **For bug/architecture/security:** check if matching rule exists in `rules/`, propose addition if not
4. **Output summary:** counts by category, new rules proposed, existing coverage

## Gotchas
- Don't promote every nit to a rule
- A single PR comment is not a pattern — note it, wait for second occurrence
- Don't duplicate what hooks already catch
