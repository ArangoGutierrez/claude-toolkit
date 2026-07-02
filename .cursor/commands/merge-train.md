# Merge Train

Discover → DAG → Plan → Execute (per-PR: assess → fix → merge → verify) → Report.
Orchestrates merging multiple PRs in correct dependency order.

## Usage

```
/merge-train                          # all open approved PRs targeting default branch
/merge-train #12 #34 #56             # specific PRs
/merge-train --label ready-to-merge   # PRs with this label
/merge-train --milestone v2.1         # PRs in this milestone
/merge-train --dry-run                # build DAG + plan only, no execution
/merge-train --auto                   # skip confirmation gates
```

## Flags

| Flag | Effect |
|------|--------|
| `#N #M ...` | Explicit PR list. |
| `--label X` | Select PRs by label. |
| `--milestone X` | Select PRs by milestone. |
| `--dry-run` | Stop after Plan. Print DAG + merge order, exit. |
| `--auto` | Skip all confirmation gates. |
| `--repo owner/repo` | Target repo. Default: current repo. |

If no selector given → all open PRs targeting the default branch with `reviewDecision=APPROVED`.

---

## Phase 1: DISCOVER

Gather the set of PRs to merge. No mutations.

### 1.1 Fetch PR candidates

```sh
# By explicit list
gh pr view {N} --json number,title,state,baseRefName,headRefName,mergeable,isDraft,url,reviewDecision,labels,milestone,body,commits

# By label
gh pr list --label {label} --state open --json number,title,baseRefName,headRefName,mergeable,isDraft,url,reviewDecision,labels,milestone,body,commits

# By milestone
gh pr list --search "milestone:{milestone}" --state open --json number,title,baseRefName,headRefName,mergeable,isDraft,url,reviewDecision,labels,milestone,body,commits

# Default: all approved PRs targeting default branch
gh pr list --state open --json number,title,baseRefName,headRefName,mergeable,isDraft,url,reviewDecision,labels,milestone,body,commits \
  | jq '[.[] | select(.reviewDecision == "APPROVED")]'
```

### 1.2 Validate candidates

For each PR:
- If state != OPEN → exclude, note: "PR #{N} is {state}, skipping."
- If isDraft → exclude by default, note: "PR #{N} is draft, skipping. Include with --include-drafts."
- If already merged → exclude.

Print discovery summary:

```
## Merge Train: Discovery
Found {N} PRs to process.

| # | PR | Title | Base | Head | Approved | CI |
|---|-----|-------|------|------|----------|----|
| 1 | #12 | Add auth | main | feat/auth | ✅ | ✅ |
| 2 | #34 | Auth tests | feat/auth | feat/auth-tests | ✅ | ❌ |
| 3 | #56 | Update deps | main | chore/deps | ✅ | ✅ |

Excluded: #78 (draft), #90 (closed)
```

---

## Phase 2: DEPENDENCY DAG

Build a directed acyclic graph of PR dependencies. This determines merge order.

### 2.1 Detect dependencies

For each pair of PRs, check these signals (strongest to weakest):

**Structural (definitive):**
1. **Stacked branches**: PR-B's `baseRefName` == PR-A's `headRefName` → B depends on A.
   PR-A must merge first; B targets A's branch.
2. **Explicit reference**: PR body or comments contain "depends on #N", "blocked by #N", "after #N" → parse dependency.

**Heuristic (inferred):**
3. **File overlap**: Both PRs modify the same files → likely conflict if merged in wrong order. The PR with fewer changes to shared files should merge first (less disruptive rebase for the other).
4. **Semantic reference**: PR body references the same issue as another PR → likely related, may have ordering preference.

```sh
# Get changed files per PR for overlap detection
gh pr diff {N} --name-only

# Get PR body + comments for explicit dependency references
gh pr view {N} --json body,comments
```

### 2.2 Build the DAG

Construct the dependency graph:

```
For each PR pair (A, B):
  IF B.baseRefName == A.headRefName:
    edge: A → B  (A must merge before B)
  IF B.body matches /depends on #A|blocked by #A|after #A/i:
    edge: A → B
  IF file_overlap(A, B) > 0 AND no structural dependency:
    soft_edge: smaller_changeset → larger_changeset  (suggestion, not hard constraint)
```

### 2.3 Validate DAG

- **Cycle detection**: If the graph has cycles → STOP. Report: "Circular dependency detected: #A → #B → #C → #A. Resolve manually."
- **Missing dependencies**: If a PR targets a branch that belongs to a PR NOT in the train → WARN: "PR #{N} targets branch {X} which belongs to PR #{M} not in this train. Add #{M}?"

### 2.4 Print the DAG

```
## Dependency Graph

#12 (Add auth) ──→ #34 (Auth tests)
  └── stacked: #34 targets feat/auth (head of #12)

#56 (Update deps) ── (independent)

Soft edges (file overlap, not enforced):
  #12 ~~ #56: 2 shared files (package.json, go.mod)

Merge order (topological sort):
  1. #12 (Add auth)        — no dependencies
  2. #56 (Update deps)     — no dependencies, but yields to #12 on file overlap
  3. #34 (Auth tests)      — depends on #12
```

---

## Phase 3: PLAN

For each PR in topological order, assess readiness. Still no mutations.

### 3.1 Per-PR assessment

For each PR, gather:

```sh
# CI status
gh pr checks {N} --watch --fail-fast --json name,state,conclusion,detailsUrl

# Reviews & threads
gh api graphql -f query='
  query($owner:String!,$repo:String!,$pr:Int!) {
    repository(owner:$owner,name:$repo) {
      pullRequest(number:$pr) {
        reviewThreads(first:100) {
          nodes { isResolved isOutdated comments(first:1) { nodes { body author { login } path line } } }
        }
      }
    }
  }
' -f owner={owner} -f repo={repo} -F pr={number}

# Branch freshness
git fetch origin
git rev-list --count {headRefName}..origin/{baseRefName}
```

### 3.2 Merge train plan

Print the full plan:

```
## Merge Train Plan

| Order | PR | Title | Dependencies | Readiness | Actions needed |
|-------|----|-------|-------------|-----------|----------------|
| 1 | #12 | Add auth | none | ✅ ready | merge |
| 2 | #56 | Update deps | none | ⚠️ CI | fix-lint, merge |
| 3 | #34 | Auth tests | #12 | ⚠️ rebase | rebase (after #12 merges), wait-ci, merge |

Total: 3 PRs, 1 ready, 2 need work.
Estimated: ~15 min (CI wait dominates).

⚠️  After each merge, downstream PRs will need rebase against updated target.
```

### 3.3 Per-PR action plan

For each PR, build its action list using the decision tree:

```
1. IF unresolved_threads > 0:
     → review-comments (categorize, draft responses, apply trivial fixes)

2. IF checks_fail not empty:
     → For each: lint → fix-lint | type → fix-types | test → fix-test-simple | other → notify-human

3. IF isDraft:
     → mark-ready (gh pr ready)

4. IF commits_behind > 0 OR upstream PR just merged:
     → rebase (AFTER code fixes, to avoid double-rebase)

5. IF checks_pending after rebase:
     → wait-ci (timeout 15min)

6. IF reviewDecision != APPROVED:
     → blocked-on-review (pause train, notify user)

7. IF mergeable == CONFLICTING:
     → blocked-on-conflicts (pause train, notify user)

8. IF all green:
     → merge (squash-merge by default)
```

### 3.4 Gate

- If `--dry-run` → print DAG + plan, stop: "Dry run complete. Re-run without --dry-run to execute."
- If `--auto` → proceed to Execute.
- Otherwise → ask: "Proceed with this merge train? (yes / edit / abort)"
  - **yes** → Execute
  - **edit** → remove PRs, reorder independents, skip actions
  - **abort** → stop

---

## Phase 4: EXECUTE

Process each PR in topological order. **Sequential, never parallel.** Each merge changes the target branch, so downstream PRs must rebase against the new state.

**Worktree requirement:** All code modifications happen in an isolated worktree, never on the current branch (which may be `agents-workbench`). A worktree is created per-PR only when fixes are needed (step 4.2), and cleaned up after the PR merges (step 4.6). Read-only operations (assess, wait-ci, merge via `gh`) run from the main workspace.

### 4.0 Train loop

```
for each PR in merge_order:
    4.1 assess(PR)
    4.2 fix(PR)        — create worktree, apply review comments / CI fixes
    4.3 rebase(PR)     — inside worktree, against (possibly updated) target branch
    4.4 wait-ci(PR)    — if rebase or fixes triggered new CI
    4.5 merge(PR)      — squash-merge via gh (no worktree needed)
    4.6 verify(PR)     — confirm target branch CI, update DAG state, clean up worktree
    4.7 retarget downstream PRs if needed
    
    IF merge fails → pause train, report, ask user
    IF verify fails → warn but continue (next PR will rebase anyway)
```

### 4.1 Assess (per-PR, fresh state)

Re-assess because earlier merges may have changed the landscape:

```sh
gh pr view {N} --json number,state,mergeable,reviewDecision,headRefName,baseRefName
gh pr checks {N} --watch --fail-fast --json name,state,conclusion
```

- If PR was closed/merged since plan → skip: "PR #{N} already merged, skipping."
- If new conflicts appeared (from prior merge) → flag, attempt rebase.

### 4.2 Fix (per-PR)

**Worktree setup (if fixes needed):**

Before making any code changes, create an isolated worktree for this PR:

```sh
# Create worktree from the PR's head branch
git worktree add .worktrees/mt-{number} {headRefName}
cd .worktrees/mt-{number}
```

All file edits, linter runs, and commits happen inside `.worktrees/mt-{number}/`. Never modify files in the main workspace.

**Review comments:**
For each unresolved thread:
1. Read the comment and the code it references
2. Categorize:
   - **trivial**: typo, naming, formatting → apply fix in worktree, draft reply "Fixed in {commit}"
   - **question**: reviewer asked a question → draft a reply based on code context
   - **disagreement**: reviewer disagrees with approach → draft reply presenting rationale, flag for user
   - **complex**: requires significant code change → flag for user, skip auto-fix
3. Present ALL drafted replies to user for approval. NEVER auto-post.
4. On approval: post replies, commit fixes in worktree with `-s -S` and descriptive message.

**CI failures (scoped):**

```sh
gh run view {run_id} --log-failed
```

- **lint errors** → run linter with `--fix` in worktree, commit with `-s -S -m "fix: resolve lint errors"`
- **type errors** → apply obvious type fixes in worktree, commit with `-s -S -m "fix: resolve type errors"`
- **simple test assertion** → fix assertion or code in worktree, commit with `-s -S -m "fix: correct test assertions"`
- **anything else** → skip, flag for human: "CI failure in {check} is out of scope for auto-fix."
- Max 2 fix attempts per failure category.

**If no fixes needed:** skip worktree creation, proceed directly to 4.3.

### 4.3 Rebase (per-PR)

Critical in a merge train — the target branch has changed since the last PR merged.

All rebase operations happen inside the worktree (created in 4.2 if fixes were needed, or created now if skipped):

```sh
# Ensure worktree exists
if [ ! -d ".worktrees/mt-{number}" ]; then
  git worktree add .worktrees/mt-{number} {headRefName}
fi
cd .worktrees/mt-{number}

# Safety: create backup ref
git tag merge-train/pre-rebase/{number} HEAD

# Rebase onto (updated) target
git fetch origin {baseRefName}
git rebase origin/{baseRefName}

# Push (never bare --force)
git push --force-with-lease
```

- If conflicts → abort rebase, pause train: "Rebase conflicts in PR #{N} after merging #{prev}. Files: {list}. Resolve manually in `.worktrees/mt-{number}/`, then re-run."
- On success → note backup ref.

### 4.4 Wait for CI (per-PR)

```sh
gh pr checks {N} --watch --fail-fast
```

- Timeout: 15 minutes per PR.
- If new failures → attempt fix (max 1 retry cycle), then wait again.
- If still failing after retry → pause train: "CI failing on PR #{N} after fix attempt. Resolve manually."

### 4.5 Merge (per-PR)

```sh
# Final pre-merge verification
gh pr view {N} --json reviewDecision,mergeable

# Squash merge (default)
gh pr merge {N} --squash --delete-branch
```

- If reviewDecision != APPROVED → pause train.
- If mergeable == CONFLICTING → pause train.
- On success → record merge SHA, proceed to verify.

### 4.6 Verify & clean up worktree (per-PR)

```sh
# Confirm merge landed
gh pr view {N} --json state,mergeCommit

# Check target branch CI (don't block, just report)
gh run list --branch {baseRefName} --limit 1 --json status,conclusion,headSha

# Clean up worktree (if one was created for this PR)
cd /path/to/main/workspace
if [ -d ".worktrees/mt-{number}" ]; then
  git worktree remove .worktrees/mt-{number}
fi
```

- If target branch CI fails → WARN but don't pause (the next PR's rebase will catch it).
- Record result for final report.

### 4.7 Retarget downstream PRs

After merging PR-A, if PR-B targeted PR-A's head branch (stacked PRs):

```sh
# Retarget B to A's base (the branch A just merged into)
gh pr edit {B} --base {A.baseRefName}
```

This ensures B now targets the correct branch (e.g., `main` instead of `feat/auth`).

---

## Phase 5: REPORT

After all PRs processed (or train paused), print the full report.

```
## Merge Train Complete 🚃

| Order | PR | Title | Status | Actions taken | Merge SHA |
|-------|----|-------|--------|--------------|-----------|
| 1 | #12 | Add auth | ✅ merged | rebase, merge | abc1234 |
| 2 | #56 | Update deps | ✅ merged | fix-lint, rebase, merge | def5678 |
| 3 | #34 | Auth tests | ✅ merged | retarget, rebase, wait-ci, merge | ghi9012 |

Merged: 3/3
Target branch CI: ✅ green
Branches cleaned: 3 deleted
Backup refs: merge-train/pre-rebase/{12,56,34}

Duration: 12m 34s
```

If train paused:

```
## Merge Train Paused ⏸️

| Order | PR | Title | Status |
|-------|----|-------|--------|
| 1 | #12 | Add auth | ✅ merged |
| 2 | #56 | Update deps | ❌ blocked — rebase conflicts |
| 3 | #34 | Auth tests | ⏸️ waiting — depends on #56 |

Paused at: PR #56 (Update deps)
Reason: Rebase conflicts in package.json, go.sum
Next step: Resolve conflicts in #56, then re-run /merge-train #56 #34

Completed: 1/3
Backup refs: merge-train/pre-rebase/{12}
```

---

## Safety rails

1. **Never `--no-verify`** — all commits go through hooks.
2. **Never bare `git push --force`** — only `--force-with-lease` after rebase.
3. **Never auto-post review replies** — always draft, always ask.
4. **Never auto-fix complex CI failures** — only lint, types, simple assertions.
5. **Pre-rebase backup** — tagged ref per PR for rollback.
6. **Max 1 retry cycle** per PR for CI fix → rebase → wait loop.
7. **Commit convention** — all commits use `-s -S` (DCO + GPG signed).
8. **No force push to default branch** — ever.
9. **Sequential execution** — one PR at a time, never parallel. Each merge changes the target.
10. **Pause on failure** — if any PR in the train fails, stop. Don't skip and merge downstream PRs against a potentially broken target.
11. **Cycle detection** — refuse to proceed if dependency graph has cycles.
12. **Retarget stacked PRs** — after merging base, retarget child PRs before processing them.
13. **Worktree isolation** — all code modifications (fixes, rebases) happen in `.worktrees/mt-{number}/`, never in the main workspace. The main workspace (which may be on `agents-workbench`) stays read-only for source code.
14. **Worktree cleanup** — remove each PR's worktree after merge is verified. On train pause, leave worktrees intact for manual resolution.
15. **CI always watched** — every `gh pr checks` call uses `--watch` so the agent never acts on stale check status. Exception: Phase 4.6 uses `gh run list`, which has no watch equivalent; that step is intentionally non-blocking.

---

## Error handling

| Situation | Behavior |
|-----------|----------|
| No PRs found | Stop with instructions |
| Cycle in dependency graph | Stop, show cycle, ask user to resolve |
| Missing dependency (PR not in train) | Warn, suggest adding it |
| PR merged by someone else mid-train | Skip, note in report |
| Rebase conflicts | Pause train, report which PR and files |
| CI timeout (>15min per PR) | Pause train, suggest re-run |
| Merge blocked (not approved) | Pause train, explain what's needed |
| Merge blocked (conflicts) | Pause train, attempt rebase, if still blocked → stop |
| API rate limit | Wait and retry once, then pause train |
| Target branch CI fails after merge | Warn but continue (next rebase will surface issues) |
| git push fails | Pause train, show error |
| Worktree creation fails | Likely branch already checked out; remove stale worktree, retry once |
| On agents-workbench branch | Never modify source directly; all code work via worktrees |

---

## Customization points

These can be overridden by passing instructions after the command:

| Default | Override example |
|---------|-----------------|
| Squash merge | `/merge-train --merge-strategy rebase` |
| Delete branch after merge | "keep branches after merge" |
| 15min CI timeout per PR | "wait up to 30 minutes for CI" |
| Max 1 retry cycle | "retry CI fixes up to 3 times" |
| Exclude drafts | `/merge-train --include-drafts` |
| Approved PRs only (default selector) | `/merge-train --label ready-to-merge` |
