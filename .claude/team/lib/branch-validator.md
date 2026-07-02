# Branch Validator

## Critical Problem

**The agents-workbench branch MUST stay synchronized with the default branch to avoid merge conflicts.**

When the default branch (main/master/develop) moves ahead on the remote (origin), the agents-workbench branch falls behind. If you create a worktree from an outdated agents-workbench branch, you're branching from stale code, which leads to:
- Merge conflicts when creating PRs
- Feature branches based on outdated code
- Wasted work implementing against old baselines

**Solution:** Always validate and sync before creating worktrees.

---

## Validation Commands

### Step 1: Fetch Latest from Origin

```bash
git fetch origin
```

This updates your local repository's knowledge of the remote without modifying any branches.

### Step 2: Check Branch Status

```bash
# Get the default branch name
DEFAULT_BRANCH=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@')

# If that fails, try common names
if [ -z "$DEFAULT_BRANCH" ]; then
  for branch in main master develop; do
    if git show-ref --verify --quiet refs/remotes/origin/$branch; then
      DEFAULT_BRANCH=$branch
      break
    fi
  done
fi

# Check if agents-workbench is behind origin's default branch
LOCAL=$(git rev-parse agents-workbench 2>/dev/null)
REMOTE=$(git rev-parse origin/$DEFAULT_BRANCH 2>/dev/null)
BASE=$(git merge-base agents-workbench origin/$DEFAULT_BRANCH 2>/dev/null)

if [ "$LOCAL" = "$REMOTE" ]; then
  echo "✓ agents-workbench is up to date with origin/$DEFAULT_BRANCH"
elif [ "$LOCAL" = "$BASE" ]; then
  echo "✗ agents-workbench is behind origin/$DEFAULT_BRANCH"
  echo "  Run: git merge origin/$DEFAULT_BRANCH"
  exit 1
elif [ "$REMOTE" = "$BASE" ]; then
  echo "⚠ agents-workbench is ahead of origin/$DEFAULT_BRANCH"
  echo "  This is normal if you have local commits on agents-workbench"
else
  echo "✗ agents-workbench has diverged from origin/$DEFAULT_BRANCH"
  echo "  Run: git merge origin/$DEFAULT_BRANCH"
  exit 1
fi
```

### Step 3: Show Branch Status (User-Friendly)

```bash
# Show a simple status summary
git fetch origin --quiet

DEFAULT_BRANCH=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@')
if [ -z "$DEFAULT_BRANCH" ]; then
  for branch in main master develop; do
    if git show-ref --verify --quiet refs/remotes/origin/$branch; then
      DEFAULT_BRANCH=$branch
      break
    fi
  done
fi

echo "Branch Status:"
echo "  Current: $(git branch --show-current)"
echo "  Default: $DEFAULT_BRANCH"
echo "  Origin: origin/$DEFAULT_BRANCH"
echo ""

# Compare agents-workbench with origin's default branch
if git rev-parse agents-workbench >/dev/null 2>&1; then
  BEHIND=$(git rev-list --count agents-workbench..origin/$DEFAULT_BRANCH 2>/dev/null || echo "0")
  AHEAD=$(git rev-list --count origin/$DEFAULT_BRANCH..agents-workbench 2>/dev/null || echo "0")

  if [ "$BEHIND" -eq 0 ] && [ "$AHEAD" -eq 0 ]; then
    echo "✓ agents-workbench is up to date"
  elif [ "$BEHIND" -gt 0 ] && [ "$AHEAD" -eq 0 ]; then
    echo "✗ agents-workbench is $BEHIND commits behind"
    echo "  Sync with: git merge origin/$DEFAULT_BRANCH"
  elif [ "$BEHIND" -eq 0 ] && [ "$AHEAD" -gt 0 ]; then
    echo "⚠ agents-workbench is $AHEAD commits ahead"
  else
    echo "✗ agents-workbench has diverged ($AHEAD ahead, $BEHIND behind)"
    echo "  Sync with: git merge origin/$DEFAULT_BRANCH"
  fi
else
  echo "⚠ agents-workbench branch does not exist"
  echo "  Run setup-workbench.sh to create it"
fi
```

---

## Usage in Commands

### In /team:plan

Before writing any plans or creating coordination context, validate:

```bash
# Fetch and check
git fetch origin
[Run validation script from Step 2 above]
```

If validation fails, prompt user:

> **Warning:** agents-workbench is behind origin/main by X commits.
>
> You should sync before planning:
> ```
> git merge origin/main
> ```
>
> Continue anyway? (not recommended)

### In /team:execute

Before creating ANY worktree, always validate:

```bash
# Fetch and validate before worktree creation
git fetch origin
[Run validation script from Step 2 above]
```

If validation fails, prompt user:

> **Error:** agents-workbench is not up to date with origin/main.
>
> You must sync before creating a worktree:
> ```
> git merge origin/main
> ```
>
> This prevents merge conflicts in your feature branch.

---

## Branching Strategy Options

When agents-workbench falls behind, you have four options:

### Option A: Merge (Recommended)

**Best for:** Most situations. Preserves local history.

```bash
git checkout agents-workbench
git merge origin/main
```

**Result:** Creates a merge commit on agents-workbench. All local commits are preserved.

**Pros:**
- Safe - never loses work
- Preserves full history
- Standard Git workflow

**Cons:**
- Creates merge commits (agents-workbench history gets noisy)

---

### Option B: Rebase

**Best for:** Keeping agents-workbench history linear. Only use if you haven't pushed agents-workbench (you shouldn't push it anyway).

```bash
git checkout agents-workbench
git rebase origin/main
```

**Result:** Replays your agents-workbench commits on top of origin/main.

**Pros:**
- Linear history
- Cleaner than merge commits

**Cons:**
- Rewrites history (dangerous if shared)
- Can be complex if conflicts occur

**Warning:** Only use if agents-workbench is local-only (it should be).

---

### Option C: Reset (Destructive)

**Best for:** When your agents-workbench commits don't matter. Throws away local coordination work.

```bash
git checkout agents-workbench
git reset --hard origin/main
```

**Result:** Discards all local commits on agents-workbench. Points it directly at origin/main.

**Pros:**
- Simple
- Guaranteed clean sync

**Cons:**
- **LOSES ALL LOCAL WORK**
- Must be absolutely sure you don't need agents-workbench commits

**Only use if:** You're okay discarding AGENTS.md updates, .agents/ plans, etc.

---

### Option D: Create Fresh Workbench

**Best for:** Starting over completely. Nuclear option.

```bash
# Delete old agents-workbench
git branch -D agents-workbench

# Create new one from origin's default branch
DEFAULT_BRANCH=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@')
git checkout -b agents-workbench origin/$DEFAULT_BRANCH

# Re-run setup
~/.claude/scripts/setup-workbench.sh
```

**Result:** Brand new agents-workbench, synchronized with origin.

**Pros:**
- Guaranteed fresh start
- No merge/rebase complexity

**Cons:**
- **LOSES ALL AGENTS.MD AND .AGENTS/ CONTENT**
- Must recreate coordination context from scratch

**Only use if:** You want to completely abandon current planning and start fresh.

---

## Recommendation

**Default to Option A (merge).** It's safe, standard, and preserves your work.

Only use Option B-D if you understand the consequences and have a specific reason.
