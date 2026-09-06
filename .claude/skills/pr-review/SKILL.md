---
name: pr-review
description: Review a pull request and post the findings as one GitHub review, approving it when nothing blocks, in a friendly, technical tone with no emojis, no AI lingo, no severity tags and no narration of the review itself. Triggered by /pr-review [<pr-number-or-url>], "review this PR and post comments".
user-invocable: true
allowed-tools:
  - Bash
  - Read
  - Grep
  - Glob
  - Agent
---

# PR Review

Review a pull request with a multi-agent pipeline, then post the findings as a SINGLE
GitHub Pull Request Review: a short prose summary, plus an inline comment anchored to the
line of each finding that has one. The summary does not repeat what the inline comments
already say.

The pipeline is content-aware: it always runs five generic reviewers, and it detects the PR's
content domains and adds one specialized reviewer per detected domain. A PR that touches no
detected domain reviews EXACTLY as it did before this dispatcher existed — five generic
reviewers, nothing added.

## Arguments

`/pr-review [<pr-number-or-url>]` — if omitted, target the PR for the current branch.

Flags (anywhere in the args):
- `--dry-run` — build and print the review; post nothing.
- `--yes` — skip the preview/confirm and post immediately. Covers a COMMENT
  review ONLY, and never a threaded reply. An APPROVE or a REQUEST_CHANGES always
  stops and asks, because a submitted review cannot be retracted through the API
  and both change whether the PR can merge. Each reply is a separate write into a
  thread on someone else's PR, so replies stop and ask with or without this flag.
- `--request-changes` — post as REQUEST_CHANGES rather than COMMENT. Never
  derived from the findings: it is a blocking act on someone else's work, and a
  wrong one costs a maintainer a dismissal, so it stays an explicit choice.

## Tone contract (non-negotiable)

Every sentence posted is read by an author trying to get their change merged.
Anything that does not serve that is noise. The payload builder rejects the worst
offenders outright, but write it right the first time.

**The reviewer is never the subject.** Every other rule follows from this one.
"I read the diff", "what I checked", "the v1/v2 dispatch holds up", "nothing here
blocks merge" all describe your pass over the change rather than the change
itself. The author learns nothing from them, and they are the thing that makes a
review read as machine written. Write about the code. `validate_tone` rejects
this whole family, so a body that narrates the review fails the build rather than
reaching the PR.

- Short, friendly, technical. One finding is one or two sentences: what breaks,
  then what to do about it.
- Name the symbol, invariant or test involved. Specifics are what make a comment
  worth reading, and what make it read as a person who looked at the change.
- Write each finding body as the bare description. Do NOT add a `(file:line)`
  citation yourself: the builder appends `(path:line)` to every summary entry, so
  citing it in the body double-cites.
- No emojis, no filler adjectives, no em dashes. All three are enforced.
- No severity tag in the text. `[must-fix]` is linter-report format; the
  `severity` field carries it and already decides inline against summary.
- Do not count your own output. "Found 3 issues." is a machine reporting on itself.
- Do not restate an inline comment in the summary. The builder enforces this.
- Never name OUR tooling: not the agents, not the pipeline, not `CLAUDE.md`. The
  builder rejects `CLAUDE.md` outright, because a review citing the config file
  driving it announces itself. A third-party AI reviewer that already commented
  publicly on this PR is the exception and is named directly ("CodeRabbit flagged
  this too"): that is a citation the author can go read, not an announcement of
  our own machinery.

**An approval opens with thanks.** When nothing is must-fix the review posts as
an APPROVE, and `thanks` is then required: one short, warm sentence naming what
the change improves. The builder raises rather than approving without it. Keep it
specific to this PR. A thank-you that would fit any PR is the same fixed-string
tell wearing a different hat, which is why neither of the old fixed bodies was
reworded: both were deleted.

## Process

Make a todo list first, then follow these steps in order.

### 1. Resolve the PR

```bash
gh pr view <pr-or-blank> --json number,headRefOid,baseRefOid,state,isDraft,url,author,headRepositoryOwner,headRepository
```
Capture `number`, `headRefOid` (the reviewed SHA), `baseRefOid`, and `owner/repo`.
`headRefOid` is frozen here and every later step is pinned to it. If no argument was given and
the current branch has no PR, stop and say so.

### 2. Eligibility check (Haiku agent)

Do NOT post (report why) if the PR is closed/merged, a draft, an automated PR (e.g.
dependabot), or already has a review you authored on the current `headRefOid`.

Also capture whether the PR author is you. GitHub rejects both APPROVE and
REQUEST_CHANGES on your own pull request, so when it is your PR, pass
`--force-comment` in step 8 and note in the final summary that the review posted
as a comment for that reason rather than because something blocked.

### 3. Gather CLAUDE.md paths (Haiku agent)

Return the paths (not contents) of the root `CLAUDE.md` and any `CLAUDE.md` in directories
the PR modifies. Pass these to the reviewers and scorers.

### 4. Detect PR domains

Decide which specialized reviewers to add to the fan-out by inspecting the changed file paths
and, where the table calls for it, the diff hunks:

```bash
gh pr diff <number> --name-only                            # changed file paths
# PINNED to the reviewed SHA, and the path carries that SHA. `gh pr diff
# <number>` resolves LIVE head, so a push landing between step 1 and here
# leaves the inline anchors computed against one tree and submitted against
# another: wrong-line comments, or a 422, after the write was authorised.
# The SHA in the name is also what stops a second review of the same PR from
# reading the first one's diff. build_review_payload.py refuses the old
# unpinned `pr-review-<number>.diff` name outright.
gh api -H "Accept: application/vnd.github.v3.diff" \
  "repos/<owner>/<repo>/compare/<baseRefOid>...<headRefOid>" \
  > "/tmp/pr-review-<number>-<headRefOid>.diff"
cp "/tmp/pr-review-<number>-<headRefOid>.diff" "$TMPDIR/pr-review.diff"  # for the content triggers below
```

A domain fires when ANY changed file matches its trigger. Multiple domains may fire. If NONE
fire, skip the specialist fan-out entirely — the pipeline is EXACTLY today's: the five generic
reviewers only.

| Domain | Trigger (changed files / diff content) |
|---|---|
| go | `*.go`, `go.mod`, `go.sum` |
| k8s | `Chart.yaml`, `values*.yaml`, `kustomization.*`, files under `templates/`, `charts/`, `crds/`, `manifests/`, `config/`, `deploy/`; OR any changed `*.yaml`/`*.yml` whose diff hunks contain `apiVersion:` or `kind:` |
| js | `*.ts`, `*.tsx`, `*.js`, `*.jsx`, `*.mjs`, `*.cjs`, `package.json`, `tsconfig*.json`, JS lockfiles |
| python | `*.py`, `pyproject.toml`, `requirements*.txt`, `uv.lock`, `poetry.lock`, `setup.py`, `setup.cfg` |
| test | `*_test.go`, `test_*.py`, `*_test.py`, `*.test.*`, `*.spec.*`, paths containing `/test/`, `/tests/`, `/e2e/`; `.github/workflows/*`; Prow configs (paths under `prow/` or `config/jobs/`, `*.prow.yaml`); `OWNERS` |
| security | GENEROUS by design: any dependency manifest or lockfile (all languages); `Dockerfile*`/`Containerfile*`; `.github/workflows/*`; RBAC manifests (diff contains `kind: Role`, `kind: ClusterRole`, or `Binding`); changed files whose path or diff hunks match `auth`, `token`, `secret`, `credential`, `crypto`, `tls`, `password`; new/changed HTTP handlers or input parsing at trust boundaries |

Record the set of fired domains; step 5 adds one specialist per fired domain.

### 4.5. Ingest prior AI-reviewer comments

```bash
python3 ~/.claude/skills/pr-review/scripts/fetch_ai_reviews.py \
  --repo "<owner>/<repo>" --number "<number>" \
  --out "/tmp/pr-review-<number>-ai-comments.json" \
  2> "/tmp/pr-review-<number>-ai-comments.stderr"; rc=$?
cat "/tmp/pr-review-<number>-ai-comments.stderr"; echo "rc=$rc"
```

`rc=$?` is in the SAME block as the command on purpose. Shell state does not
survive between Bash tool calls, so an `rc=$?` in a block of its own reads the
exit status of whatever ran last in THAT block and gates on a number the fetch
never produced.

Reads three surfaces, because the vendors do not share one: CodeRabbit posts its
walkthrough on `issues/{n}/comments`, Copilot and Greptile on `pulls/{n}/reviews`,
and inline findings land on `pulls/{n}/comments`. Detection is the login allowlist
at `~/.claude/skills/pr-review/ai-reviewers.json`, not `user.type == "Bot"`, which
misclassifies in both directions.

The fixed `/tmp/pr-review-<number>-*` path is required for the same reason step 8
gives: `$TMPDIR` differs between sandboxed and unsandboxed Bash.

**Gate on the exit code, not on stdout.** The script exits 0 on success, including
a genuine "no AI reviewer commented" result, 1 on an unhandled error (most often
an `--allowlist` path that does not exist or does not parse), 2 when every surface
was unreadable (expired `gh auth`, wrong repo, wrong number), and 3 when `--out`
could not be cleared. Do not branch on the `ai reviewers found: none` line: a
2-of-3 surface failure prints exactly that while warning only on stderr, so
reading stdout would silently treat a partial fetch failure as an absence of AI
review.

**The script clears `--out` before it reads anything.** Every abort below that
point, rc=1 included, therefore leaves no file at that path rather than an
earlier run's records, which step 5 would otherwise reconcile as this run's.
Do not add an `rm -f` for it here: the purge belongs in the step that reads the
path, and putting it in step 9 would be too late to prevent any read.

**`rc=0` with an empty file is not proof that no AI reviewer commented.** One or
two unreadable surfaces still exit 0, because another surface answered. Read the
captured stderr: a partial failure prints
`fetch_ai_reviews: N of 3 surfaces were unreadable (...), so findings from them
are missing.` The three surfaces carry different vendors, so losing one loses a
whole reviewer: a CodeRabbit walkthrough sits on `issue_comment`, and if that
surface 401s while the other two answer, the file can come back `[]` at rc=0 with
CodeRabbit's review sitting on the PR unread. Whenever that warning is present,
say in the final summary which surfaces were unreadable, and never write "no AI
reviewer commented" on the strength of an empty file alone.

- `rc=0`, stderr silent, and the file holds `[]`: no AI reviewer commented. Pass no
  `aiCommentsPath` in step 5, which leaves the workflow's Reconcile phase unrun. The
  review then runs exactly as it did before this step existed.
- `rc=0` with the unreadable-surfaces warning on stderr: a PARTIAL fetch. Use what
  came back, and report the gap in the final summary. If the missing surface matters
  (an empty file is the case where it matters most), fix the cause and rerun before
  concluding anything about what the bots said.
- `rc=0` and the file holds records: pass `aiCommentsPath` in step 5.
- `rc=1`: the run aborted before it fetched anything, and the traceback on stderr
  names the cause. Check the `--allowlist` path first. The output file is already
  gone, so there is nothing to clean up; fix the cause and rerun.
- `rc=2`: the fetch failed and the script has removed the output file. Tell the
  user the AI-reviewer comparison is unavailable and why, then either fix the
  cause and retry, or proceed without `aiCommentsPath` and say so in the final
  summary. Never report a `rc=2` run as "no AI reviewer commented".
- `rc=3`: `--out` could not be cleared, so nothing was fetched. Something else
  owns that path (a directory, or a directory you cannot write). Fix the path and
  rerun. Do not pass the path to step 5: whatever sits there is not this run's.

### 5. Fan out reviewers and score (pr-review-fanout workflow)

Run the reviewer fan-out and per-finding confidence scoring as a single workflow. Pass the
domains fired in step 4 and the paths gathered in steps 1–3:

```
Workflow({name: 'pr-review-fanout', args: {diffPath: '/tmp/pr-review-<number>-<headRefOid>.diff', prNumber, ownerRepo, headRefOid, repoCheckout, domains, claudeMdPaths, aiCommentsPath}})
```

The workflow runs five phases: Review (the fan-out), Score (confidence per reviewer),
Merge (cluster findings that one edit would fix), Verify (one refuter per finding bound
for an inline comment) and Summarize (write the review body prose).

Read back `{findings, thanks, summary_lead, degradedReviewers, counts}`:

- `findings` — the findings that survived scoring AND refutation (confidence ≥ 80, already
  ranked must-fix → should-fix → consider). Each carries `file`, `line` (NEW-file /
  RIGHT-side), `description`, `category`, `severity`, `reason`, `score`, `reviewer`, and
  `root_cause` when Merge found it a sibling. These feed the payload in step 8. If the
  array is empty, the review approves on the strength of `thanks` alone.
- `thanks` / `summary_lead` — the body prose, written by Summarize from the diff. Pass both
  to the builder unchanged. Write them yourself ONLY when they come back empty, which the
  workflow reports in `degradedReviewers`.
- `degradedReviewers` — reviewers that ran degraded, refuters that died (their finding was
  kept unverified), and a dead merge or summarize agent.
- `counts` — `{raw, survived, refuted, posting}`, for the final summary. Report `refuted`:
  a finding killed by its refuter is the pipeline working, and hiding it makes the review
  look thinner than the work behind it.
- `reconcile`: present only when AI-reviewer comments were ingested AND the workflow
  that ran carries the Reconcile phase:
  `{corroborated, contradicted, contradictionsDropped, novel, novelKept}`. Report
  these in the final summary. `contradictionsDropped` is the count of bot claims we
  thought were wrong but could not concretely refute, and saying so is the honest
  version of "we disagreed but stayed quiet". A workflow build without that phase
  returns no `reconcile` key even on a successful ingest, so a missing key is not by
  itself evidence that no bot commented.
- `contradictions`: bot claims we refuted concretely, each with `reviewer`,
  `commentId`, `surface`, `claim` and `refutation`. Present only under the same
  two conditions `reconcile` above needs, and absent on a workflow build without
  the Reconcile phase, so a missing key is not evidence that no bot commented and
  not evidence that nothing was refuted. Only the ones on `surface: "inline"` can
  become threaded replies in step 8; the rest go in the review body. A finding in
  `findings` may carry `corroborates`, which now also carries `surface`; pass it
  through untouched.

**Degradation rule:** if a specialist's checklist file is not on disk (not yet deployed), the
specialist proceeds with its domain lens from the prompt alone, and the final user-facing
summary — NOT the posted review — notes that that specialist ran degraded.

### Fallback: manual fan-out (Workflow tool unavailable)

This manual fan-out applies ONLY when the Workflow tool is not available in the environment; when
it is available, step 5 above runs the `pr-review-fanout` workflow instead.

It reproduces Review and Score only. Merge, Verify and Summarize do NOT run on this path, so
on it you must: dedup across reviewers yourself and set `root_cause` by hand where two findings
share one defect; treat every finding as unrefuted, which argues for a higher bar before calling
anything `must-fix`, since that decides the event; and write `thanks` and `summary_lead`
yourself against the tone contract above. Say in the final summary that the review ran without
those three phases.

#### Reviewers (opus agents, one message)

Dispatch all reviewers — the five generic reviewers AND one specialist per domain fired in
step 4 — in the SAME single message so they run in parallel. Each returns a list of issues; per
issue give the file (repo-relative path), the new-file (RIGHT-side) line number, a
one-to-two-sentence description, and the reason flagged.

**Five generic reviewers (always run, unchanged):**

1. CLAUDE.md adherence — only what the relevant CLAUDE.md explicitly calls out.
2. Shallow bug scan of the changed lines only — large bugs, not nitpicks.
3. Git blame/history of the modified code — bugs in light of historical context.
4. Prior PRs touching these files — comments there that also apply here.
5. Code comments in the modified files — changes that violate documented guidance.

**Specialists (one per domain fired in step 4):**

Specialists dispatch under the Principal Engineer / QA purview: the `principal-engineer` agent
runs the go, k8s, js, python, and security specialists, and the `qa-engineer` agent runs the
test specialist. Each specialist is an opus-tier, fully-specified, checklist-seeded lens.

| Domain | Agent type | Skill / checklist the specialist reads |
|---|---|---|
| go | `principal-engineer` | `~/.claude/skills/go-review/SKILL.md` + `references/go-review-checklist.md` |
| k8s | `principal-engineer` | `~/.claude/skills/k8s-review/SKILL.md` + `references/k8s-review-checklist.md` |
| js | `principal-engineer` | `~/.claude/skills/js-review/SKILL.md` + `references/js-review-checklist.md` |
| python | `principal-engineer` | `~/.claude/skills/python-review/SKILL.md` + `references/python-review-checklist.md` |
| test | `qa-engineer` | `~/.claude/skills/test-review/SKILL.md` + `references/test-review-checklist.md` |
| security | `principal-engineer` | no skill file — seeds `~/.claude/rules/security.md` (see below) |

**Agent-type availability:** `principal-engineer` and `qa-engineer` are defined in
`~/.claude/agents/`. The terminal CLI scans that directory, but a host that builds its registry
from the Agent SDK `agents` option does not, and the dispatch then fails with
`agent type '<name>' not found`. On that failure, re-dispatch the specialist with the
`general-purpose` agent type and the SAME prompt, then record the downgrade in the final
user-facing summary. Never drop a specialist silently: a reviewer that did not run must always
reach the summary, because a review that lost its test or security lens still reads clean.

For the go / k8s / js / python / test specialists, the dispatch prompt MUST instruct the agent to:

- Read `~/.claude/skills/<domain>-review/SKILL.md` (its "Dispatched mode" section) and
  `~/.claude/skills/<domain>-review/references/<domain>-review-checklist.md`. For go the file is
  `go-review-checklist.md`, already deployed today.
- Review ONLY the changed lines in the PR diff.
- Return findings as a list where each finding has: `file` (repo-relative path), `line`
  (NEW-file / RIGHT-side line number), a 1–2 sentence `description`, `category`, `severity`
  (must-fix / should-fix / consider), and `reason` (which checklist item flagged it).

**Degradation rule:** if a specialist's checklist file is not on disk (not yet deployed), the
specialist proceeds with its domain lens from the prompt alone, and the final user-facing
summary — NOT the posted review — notes that that specialist ran degraded.

**Security specialist:** it deliberately has NO skill file, so the built-in `/security-review`
name stays reserved for standalone use. Its prompt seeds `~/.claude/rules/security.md` and
directs focus to: secrets/credentials in the diff, injection sinks, authn/authz logic changes,
unsafe deserialization, supply-chain (new deps, install scripts), container privilege, and RBAC
wildcards.

**Cost:** a wide PR can add up to 6 specialists (go, k8s, js, python, test, security) on top of
the 5 generic reviewers; this fan-out width is an explicit design choice, not an accident.

**Every reviewer prompt — generic AND specialist — MUST include this clause verbatim** (it is a
mandatory block the reviewer prompts carry so no reviewer can act outward-facing):

> Do NOT post, comment, submit, push, or take any external action. Your deliverable is a
> findings report returned as your final message only.

Apply the false-positive guardrails below.

#### Confidence scoring (Haiku agent per finding)

Specialist findings merge with generic findings and get NO special treatment from the scorer:
the same ≥ 80 threshold, the same rubric, and the same false-positive guardrails apply to every
finding regardless of which reviewer produced it.

Score each finding 0–100 with the rubric below; KEEP ONLY findings ≥ 80. For
CLAUDE.md-flagged findings, confirm the CLAUDE.md actually calls out that issue. If nothing
survives, treat it as "no issues".

### 7. Re-check eligibility (Haiku agent), and confirm the head has not moved

Repeat step 2 in case the PR changed during the review.

Then re-read the head and compare it against the SHA frozen in step 1:

```bash
NOW=$(gh pr view <number> --json headRefOid -q .headRefOid)
echo "frozen=<headRefOid> now=$NOW"
```

If they differ the author pushed while the reviewers were running, and every
finding is anchored to lines in the OLD tree. Do not repin `--commit` to the new
head to make the build pass: that is the exact defect the pinned diff exists to
stop, and the payload builder will refuse it because the diff filename still
carries the old SHA. Either restart the review from step 1 against the new head,
or report to the user that the head moved and stop. Say which in the final
summary.

### 8. Build the payload

Write the findings JSON with a heredoc (not the Write tool), then build the payload. Use the
FIXED, PR-scoped `/tmp/pr-review-<number>-*` paths below — NOT `$TMPDIR`. The build typically
runs sandboxed but the post in step 9 needs `gh` unsandboxed, and `$TMPDIR` resolves to
different directories in the two modes. A same-named payload left in the unsandboxed `$TMPDIR`
by an EARLIER review of a DIFFERENT PR will then be read and posted silently — this shipped a
wrong review onto a colleague's PR once (2026-07-24). Fixed PR-scoped paths make the
build→post handoff sandbox-mode-proof and cannot collide across PRs. Reuse the diff already
captured at `/tmp/pr-review-<number>-<headRefOid>.diff` in step 4; do not refetch it.

**Carry `severity` through from step 5.** The fan-out scores every finding must-fix /
should-fix / consider, and dropping that on the floor here is what makes a review land
heavier than its content: three notes with no correctness defect between them read as three
demands. An inline comment reads as a demand; a summary line reads as a note.

**The summary is not an index of the inline comments.** A must-fix or should-fix
finding whose line is in the diff is reported by its inline comment and nowhere
else; the builder keeps it out of the body. What reaches the body is the lead,
plus only the findings with no inline home: `consider` findings, and any finding
whose line falls outside the diff. Writing each finding twice on one page was
what made the review read as generated and doubled its apparent weight.

Because of that, `thanks` and `summary_lead` do real work: on a PR whose findings
all anchor inline they are the entire body. Both come from the Summarize phase.
The builder raises rather than posting a blank body, and raises again if the
review approves without a `thanks` line.

```bash
cat > "/tmp/pr-review-<number>-findings.json" <<'JSON'
{"thanks": "Thanks for this, the v1/v2 split takes a real edge case out of the dispatch path.",
 "summary_lead": "Two things worth a look on the merge path, both inline.",
 "findings": [
   {"path": "pkg/foo.go", "line": 42, "severity": "must-fix",
    "body": "Nil deref when cfg is empty; guard before indexing.",
    "root_cause": "unguarded-cfg-index",
    "permalink": "https://github.com/<owner>/<repo>/blob/<headRefOid>/pkg/foo.go#L40-L44"}
 ]}
JSON
python3 ~/.claude/skills/pr-review/scripts/build_review_payload.py \
  --diff "/tmp/pr-review-<number>-<headRefOid>.diff" \
  --findings "/tmp/pr-review-<number>-findings.json" \
  --commit "<headRefOid>" \
  --replies-out "/tmp/pr-review-<number>-replies.json" \
  > "/tmp/pr-review-<number>-payload.json"
```

- `line` is the NEW-file (RIGHT-side) line number.
- `severity` is `must-fix`, `should-fix`, or `consider` — copy it from the step-5 finding,
  do not re-judge it. `must-fix` and `should-fix` get an inline comment plus a summary
  entry; `consider` gets the summary entry only. An unknown value is an error, so a typo
  cannot quietly demote a blocker. Omitting the key defaults to `should-fix`.
- `corroborates` is optional and comes from the workflow's Reconcile phase. Copy it
  through unchanged. It appends a clause naming the AI reviewer that independently
  found the same defect. It does NOT change severity: a bot agreeing is not evidence
  of how bad something is.
- `replies` is a top-level array of `{comment_id, surface, body}`, one per entry in
  the workflow's `contradictions` **that sits on `surface: "inline"`**, plus
  optionally one per corroborated finding when replying in the bot's thread adds
  something the inline comment does not. Rename the fields as you copy: the
  workflow's `commentId` becomes `comment_id` and its `refutation` becomes `body`.
  `surface` keeps its name and its value, copied verbatim. That is the same kind of
  mapping this step already does for findings (`file`/`description` to
  `path`/`body`); the builder reads snake_case only and raises on a missing or
  non-integer `comment_id`. Each body is tone checked like every other posted
  string. Write the refutation as a bare technical statement: name the guard, the
  defer or the caller. Do not thank the bot, and do not narrate the comparison.
- **Only an `inline` contradiction can become a threaded reply.** The reply route
  is `POST /repos/{owner}/{repo}/pulls/{n}/comments/{comment_id}/replies`, and it
  resolves a top-level review comment id, which is what the `inline` surface
  returns. An `issue_comment` or `review` id is a different id space and 404s
  there. Verified read-only against cli/cli on 2026-08-31: the inline id
  332430752 answers on `repos/cli/cli/pulls/comments/<id>`, while the
  issue-comment id 539473254 and the review id 2023457056 both return 404. This
  is the common case, not the corner one: step 4.5's own note says CodeRabbit
  posts its walkthrough on `issue_comment` and Copilot and Greptile post on
  `review`, so the surfaces that cannot be replied to are exactly where most bot
  claims live.
- **A contradiction on a non-repliable surface goes in the review body instead.**
  Do not drop it, and do not retarget it at some other comment id. Add it to
  `findings` as a `consider` entry whose `body` states the refutation and names
  the reviewer it answers (for example "CodeRabbit reads this as an unguarded
  index; the caller checks cfg before it gets here."), with the `path` and `line`
  of the code it is about. It then reaches the author in the summary, which is
  what a reply would have done. The builder raises on a reply whose `surface` is
  missing or is not `inline`, so a contradiction routed the wrong way fails the
  build rather than 404ing after the review has posted and can no longer be
  retracted.
- `thanks` is one short warm sentence naming what the change improves. REQUIRED
  whenever no finding is `must-fix`, because the review then posts as an APPROVE and
  the builder refuses to approve without it. Optional on a COMMENT review.
- `summary_lead` is prose about the change, NOT a count and NOT a list. "Found 3
  issues." is a machine describing its own output, and so is any sentence about what
  the review looked at. It is mandatory whenever every finding anchors inline and
  there is no `thanks`, because it is then the whole body.
- The event is derived, not chosen: nothing `must-fix` approves, otherwise COMMENT.
  Add `--request-changes` to post REQUEST_CHANGES instead, or `--force-comment` on
  your own PR. There is no line asserting the PR is non-blocking; an APPROVE says
  that structurally, and prose saying it as well is a verdict without an approval.
- `root_cause` is optional and free-form. Findings sharing one non-empty value collapse to a
  single summary entry and a single inline comment, with the folded siblings cited as
  `also <path>:<line>`. Use it when two symptoms trace to one defect — posting both doubles
  the apparent weight of the review without adding information. Omit it when unsure;
  findings without the key are never merged. When the group anchors inline, the
  folded siblings are cited on the inline comment as `Also at <path>:<line>.`
- `permalink` is used only when the line is not in the diff: the builder lists that finding
  in the summary body instead of as an inline comment, so one un-anchorable finding can't
  422 the whole review. Use a full-SHA permalink with a small context range.
- No surviving findings → write `{"thanks": "<the Summarize line>", "summary_lead": "",
  "findings": []}`. The review approves on the thanks line alone. There is no fixed
  clean-review body any more: a constant posted verbatim on every clean PR is identical
  text across many reviews under one name, which is what gives the tooling away.

### 9. Preview, then post

```bash
rm -f "/tmp/pr-review-<number>-review-rc" "/tmp/pr-review-<number>-review-result.json" \
      "/tmp/pr-review-<number>-payload.json" "/tmp/pr-review-<number>-replies.json"
python3 ~/.claude/skills/pr-review/scripts/build_review_payload.py \
  --diff "/tmp/pr-review-<number>-<headRefOid>.diff" --findings "/tmp/pr-review-<number>-findings.json" \
  --commit "<headRefOid>" \
  --replies-out "/tmp/pr-review-<number>-replies.json" \
  > "/tmp/pr-review-<number>-payload.json"
python3 ~/.claude/skills/pr-review/scripts/build_review_payload.py \
  --diff "/tmp/pr-review-<number>-<headRefOid>.diff" --findings "/tmp/pr-review-<number>-findings.json" \
  --commit "<headRefOid>" --pr-number <number> \
  --replies-out "/tmp/pr-review-<number>-replies.json" --render
```

**The `rm -f` is the first thing step 9 does, and it is not optional.** The rule
is purge-before-read, not purge-on-failure: the list must name every fixed-path
artifact a later part of this step consumes, because each of those names is
PR-scoped and stable, so a second review of the same PR reads whatever the first
one left. Purging only on a selected failure path leaves every other abort
holding a stale file. The four names today, and what each one would do stale:

- `-review-rc` permits the replies to run. An earlier run's `0` sitting there
  reads as this run's successful POST.
- `-review-result.json` is what gets echoed back as the outcome, so a stale one
  reports a review that this run did not post.
- `-payload.json` is the bytes `gh api --input` actually sends. Step 8 was its
  only writer, so editing the findings and re-running step 9 alone rendered the
  NEW body while the OLD bytes went over the wire. Step 9 now removes AND
  regenerates it, which is why the build above runs twice: once to write the
  payload, once to render it. Both runs read the same findings file, so the
  render and the POST describe the same review.
- `-replies.json` was purged only by the builder, and only when `--replies-out`
  was passed, so omitting the flag left an earlier run's replies to be posted.

`-ai-comments.json` is deliberately NOT in this list. Step 5 is its only reader
and it runs before step 9, so removing it here could not prevent any read of it.
`fetch_ai_reviews.py` clears it before its own first read instead, which is where
the same rule applies to it.

The render leads with `=== REVIEW EVENT: <event> ===` and then
`=== OUTWARD WRITES: 1 review + N threaded replies ===`, enumerating every write
with its target and exact body. Read both before anything else: together they are
what the confirm is authorising.

**Always pass `--replies-out`, even when there are no replies.** The builder
removes that file up front on every run, so passing the flag with an empty
`replies` array leaves `[]` there. OMITTING the flag leaves whatever a previous
run wrote, and step 9's post loop would then send an earlier run's replies. The
flag is not optional in this pipeline, and `--render` now refuses to run without
it: the render lists the replies as writes it is asking you to authorise, and
without the flag it would be describing a file this run neither wrote nor
cleared.

**The render pass writes the sidecar before you confirm.** That is intended (the
render and the post read the same file, so what you approve is what is sent), but
it means a declined confirm leaves the file on disk. That is safe because the next
run removes it before doing anything else, and because nothing reads it without
your explicit approval. Do not treat the file's existence as evidence anything was
posted.

**Every confirm names the count and the targets, and there is one per act that will
actually run.** Not "post this review?" but "This will submit a COMMENT review on
<owner>/<repo>#<number>, under your name. Post it?" and then, only once that has
returned and only when `replies` is non-empty, "This will add 2 replies, to comments
991 and 992 on <owner>/<repo>#<number>, under your name. Post them?" With no replies
there is one act and one ask; never ask for approval to post zero writes. Approval
for the review is not approval for the replies, and `--yes` reaches neither the
replies nor an APPROVE.

- `--dry-run`: print that render and the payload path, then STOP. Post nothing.
- **Event APPROVE or REQUEST_CHANGES: ALWAYS ask, even with `--yes`.** Show the render and
  ask in words that name the act, not "post this review?": *"This will submit an APPROVAL
  on <owner>/<repo>#<number> under your name. Approve and post?"* Wait for an explicit yes.
  A submitted review cannot be retracted through the API, and both events change whether
  the PR can merge, so `--yes` does not reach them. Never widen it to.
- Event COMMENT: show the render and, unless `--yes` was given, ask in the words the
  render's write list gives you, naming every write rather than "post this review?":
  *"This will submit a COMMENT review on <owner>/<repo>#<number>, under your name.
  Post it?"* When there are replies, name them and their comment IDs too, and see the
  reply bullet below: they need their own yes either way. Wait for a one-word confirm.
- **Replies ALWAYS ask, even with `--yes`, and always separately from the review.**
  A reply is a write into a thread on someone else's PR. Skip this ask entirely when
  `replies` is empty or the review did not post. Otherwise ask by count and target:
  *"This will add 2 replies, to comments 991 and 992 on <owner>/<repo>#<number>,
  under your name. Post them?"* Do not assert the review posted as part of the ask:
  read that from the status file rather than assuming it, and if it says the POST
  failed, report that instead of asking. A yes to the review is not a yes to the
  replies, and `--yes` does not reach them. Never widen it to.
- On confirm of the REVIEW (or `--yes`, COMMENT event only), post the review and
  nothing else:

```bash
gh api --method POST "repos/<owner>/<repo>/pulls/<number>/reviews" \
  --input "/tmp/pr-review-<number>-payload.json" \
  > "/tmp/pr-review-<number>-review-result.json"; echo "$?" > "/tmp/pr-review-<number>-review-rc"
cat "/tmp/pr-review-<number>-review-result.json"
```

The review POST goes first, and its exit status decides whether any reply is
allowed to run: a 422 on the review must not leave replies hanging on bot threads
with no review under them. The status goes to a FILE rather than a shell variable
because the reply confirm happens between the two blocks, and shell state does not
survive between Bash tool calls. A `$?` read in the reply block would be the status
of `cat`, which is 0 whatever the review did.

**The gate fails closed: no replies unless this run's file exists AND holds `0`.**
A missing file means no replies, and so does any other value. Three ordinary paths
produce a missing file, and every one of them must end with nothing posted: the
operator declined the review confirm, so the POST never ran; `/tmp` was unwritable,
so the redirect failed and `gh` never ran; or the POST block was never reached.

Test the file's existence separately from its contents. `[ "$rc" -ne 0 ]` on an
empty or unset value is an ERROR rather than a false comparison, and an erroring
condition takes the `else` branch, which posts the replies. That is backwards: the
one case where you know least is the case where it would write the most.

Ask for the reply confirm now, per the reply bullet above, and only after checking
that the review actually posted. Only on an explicit yes:

```bash
RC_FILE="/tmp/pr-review-<number>-review-rc"
if [ ! -f "$RC_FILE" ] || [ "$(cat "$RC_FILE")" != 0 ]; then
  echo "no confirmed review POST for this run. Posting no replies."
else
  python3 - "/tmp/pr-review-<number>-replies.json" <<'PY'
import json, subprocess, sys
for reply in json.load(open(sys.argv[1])):
    subprocess.run(["gh", "api", "--method", "POST",
                    "repos/<owner>/<repo>/pulls/<number>/comments/{0}/replies".format(
                        reply["comment_id"]),
                    "-f", "body=" + reply["body"]], check=True)
PY
fi
```

Replace `<owner>/<repo>` and `<number>` before running. The route is
`pulls/<number>/comments/<comment_id>/replies`: the reply endpoint is scoped by pull
number, and the shorter `pulls/comments/<comment_id>` form takes GET, PATCH and
DELETE only. Getting this wrong fails in the worst order, since the review has
already posted and cannot be retracted by the time the first reply 404s. A reply
that fails after a successful review is reported to the user, not retried silently.

Every entry in that file is on the `inline` surface, because the builder is its
only writer and it raises on anything else. That is what makes `check=True` safe
here: a 404 from this loop now means the comment was deleted or the token lost
access, not that a walkthrough id was sent to a route that never accepted one.

If the POST 422s with `The commitOID is not part of the pull request`, the PR head is a merge
commit (GitHub excludes it from the reviewable set). Drop the top-level `commit_id` key from
the payload and re-POST — the inline comments anchor by `path`+`line`+`side: RIGHT`, so GitHub
defaults them to the PR's latest reviewable commit.

Report the resulting review URL.

## False-positive guardrails (steps 5–6)

Ignore likely false positives:

- Pre-existing issues; real issues on lines the PR did not modify.
- Something that looks like a bug but is not.
- Pedantic nitpicks a senior engineer wouldn't raise.
- Issues a linter/typechecker/compiler would catch (imports, type errors, formatting). Assume
  CI runs these separately; do not build or typecheck yourself.
- General quality gripes (coverage, docs) unless the relevant CLAUDE.md requires them.
- Issues called out in CLAUDE.md but explicitly silenced in code (e.g. a lint-ignore).
- Changes that are likely intentional or directly related to the broader change.

## Confidence rubric (step 6, give to the scorer verbatim)

- 0: Not confident. False positive under light scrutiny, or pre-existing.
- 25: Somewhat. Might be real, could be a false positive; unverified, or stylistic and not
  explicitly called out in CLAUDE.md.
- 50: Moderately. Verified real, but a nitpick or rare in practice; not very important.
- 75: Highly. Double-checked; likely hit in practice; current approach insufficient; or
  directly named in the relevant CLAUDE.md.
- 100: Certain. Confirmed definitely real and frequent; evidence directly confirms it.
