# /pr-review-ingest — turn PR review comments into rule proposals

`/pr-review-ingest <PR-number-or-URL>` fetches a pull request's review
comments (top-level and inline threads, via `gh`) and classifies each one,
then checks the substantive categories — bug, architecture, security —
against `rules/` and proposes an addition where no matching rule exists yet.
It's stateless: each run only sees the one PR, so a first occurrence gets
noted rather than promoted.

## When to use it

- After a PR review lands, to see whether the feedback exposed a gap in your
  `rules/` instead of just filing it away in memory.
- To check whether a bug/architecture/security comment already has rule
  coverage before drafting a new one from scratch.
- To get a quick per-PR tally of feedback — how much was substantive versus
  style/nit noise.
- **Not for:** recognizing that an issue is a recurring pattern across
  multiple PRs — a single invocation can't see PR history. Pair it with
  [`reflection`](../reflection/)'s mistake-capture mode to track whether a
  noted issue recurs before it becomes a rule.

## Examples

    > /pr-review-ingest 482
    → Runs scripts/parse-gh-reviews.sh 482, which fetches the PR's
      title/state/author/decision, top-level comments, and inline review
      threads via `gh`. The skill classifies each comment and prints a
      summary: counts per category, any new rule proposed for uncovered
      bug/architecture/security comments, and which categories already had
      matching rules in `rules/`.

    > /pr-review-ingest https://github.com/org/repo/pull/117
    → Same flow with a full PR URL — parse-gh-reviews.sh extracts the PR
      number, then fetches and classifies the review the same way.

## Setup

Requires the `gh` CLI, authenticated with access to the target repo
(`parse-gh-reviews.sh` calls `gh pr view` and `gh api
repos/{owner}/{repo}/pulls/.../comments`). Run it from within the repo whose
PR you're reviewing.

## Notes

- A single comment is treated as a note, not a pattern — bug and
  architecture proposals wait for a second occurrence; security comments are
  always proposed. Style and nit comments are counted but never promoted.
- Doesn't duplicate what hooks already catch — check existing hooks before
  proposing a new rule for something already enforced mechanically.
- Related: [`reflection`](../reflection/), which shares the same `rules/`
  target and handles pattern promotion and rule curation over time. Index:
  [`docs/skills-and-commands.md`](../../../docs/skills-and-commands.md).
