# /pr-review: review a PR and post one GitHub review

`/pr-review [<pr-number-or-url>]` runs a multi-agent review pipeline over a pull
request and posts the result as a **single** GitHub Pull Request Review: a short
prose summary plus one inline comment anchored to each finding's line. Five
generic reviewers always run; the skill also detects the PR's content domains and
adds one specialist per domain fired. Posting is outward-facing, so it never
writes without an explicit confirm.

## When to use it

- Reviewing a colleague's PR when you want the findings on the PR itself rather
  than in your terminal scrollback.
- Reviewing a wide PR where you want language and domain lenses (Go, Kubernetes,
  JS/TS, Python, tests and CI, security) applied automatically instead of picking
  reviewers by hand.
- Producing a review you can inspect before it goes out. `--dry-run` builds and
  renders the exact review and posts nothing.
- Checking your review against what CodeRabbit, Copilot or Greptile already said,
  so you corroborate rather than repeat them, and can answer a bot claim you
  believe is wrong.
- **Not for:** reviewing your own uncommitted work, or learning from review
  feedback after the fact. For the former use the individual review skills
  ([`go-review`](../go-review/), [`test-review`](../test-review/), and so on); for
  the latter use [`pr-review-ingest`](../pr-review-ingest/), which turns landed
  review comments into rule proposals.

## Examples

    > /pr-review 482
    → Resolves the PR and freezes its head SHA, checks eligibility (skips
      closed, merged, draft and bot PRs, and PRs you already reviewed at this
      SHA), fetches the diff pinned to that SHA, detects domains from the
      changed paths, fans out reviewers through the `pr-review-fanout`
      workflow, keeps only findings scoring 80 or above, renders the review
      for your approval, and on confirm POSTs it as one review.

    > /pr-review --dry-run
    → Targets the current branch's PR, runs the whole pipeline, prints the
      rendered review and the payload path, then stops. Posts nothing.

    > /pr-review https://github.com/org/repo/pull/117 --yes
    → Same pipeline, skipping the confirm for a COMMENT review. An APPROVE or
      a REQUEST_CHANGES still stops and asks, and so does every threaded reply.

## Setup

Needs the `gh` CLI authenticated against the target repo, and `python3` for the
two scripts. The specialist reviewers read the `*-review` skills' checklists
under `references/`; if one is not on disk the specialist still runs from its
domain lens, and the final summary says it ran degraded.

## Notes

- **The reviewed SHA is frozen.** The diff is fetched pinned to it, and the diff
  path carries that SHA, so the payload builder refuses a diff that does not
  match the commit the review submits against. This is what stops inline anchors
  being computed against one tree and submitted against another.
- **Fan-out width is a deliberate cost.** A PR touching many domains can add up
  to six specialists on top of the five generic reviewers.
- Findings are scored 0 to 100 by a per-finding scorer, and only those at 80 or
  above survive; specialist findings get no special treatment. Nothing surviving
  is reported as "no issues" rather than as a forced nitpick.
- **Tone is a hard contract**, and parts of it are executable. The payload
  builder rejects emoji, em-dashes, filler words, text that narrates the review
  instead of describing the change, severity tags such as `[must-fix]`, and any
  sentence counting the review's own output. An approval must carry a specific
  thank-you line; the builder raises rather than approving without one.
- **Every outward write is confirmed separately.** The render enumerates each
  write with its exact body before you are asked. A submitted review cannot be
  retracted through the API, so APPROVE and REQUEST_CHANGES always ask, and
  threaded replies ask again on their own.
- The build and post handoff uses fixed, SHA-scoped `/tmp/pr-review-<number>-*`
  paths rather than `$TMPDIR`, which resolves differently sandboxed and
  unsandboxed. A fixed basename once let a stale payload from an earlier review
  of a different PR get posted.
- If the POST fails with `The commitOID is not part of the pull request`, the PR
  head is a merge commit. Drop the top-level `commit_id` and re-POST; the inline
  comments anchor by `path`, `line` and `side: RIGHT`.
- Related: [`pr-review-ingest`](../pr-review-ingest/),
  [`go-review`](../go-review/), [`k8s-review`](../k8s-review/),
  [`js-review`](../js-review/), [`python-review`](../python-review/),
  [`test-review`](../test-review/). Index:
  [`docs/skills-and-commands.md`](../../../docs/skills-and-commands.md).
