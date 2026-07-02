# Worktree Lifecycle

Manage git worktrees for isolated feature development.

## Usage

```
/worktree create <name>           # create worktree + branch from default branch
/worktree create <name> <base>    # create from specific base branch
/worktree list                    # show all worktrees with status
/worktree status                  # current worktree info + branch + dirty state
/worktree done <name>             # clean up after merge (remove worktree + branch)
/worktree done --all              # clean up all merged worktrees
```

## Flags

| Flag | Effect |
|------|--------|
| `<name>` | Worktree name (becomes `.worktrees/<name>`) |
| `<base>` | Base branch (default: repo's default branch) |
| `--all` | Apply to all merged worktrees |

---

## Operation: create

Create an isolated worktree for feature development.

```sh
# Detect default branch
default_branch=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@' || echo "main")

# Verify not already existing
if [ -d ".worktrees/{name}" ]; then
  echo "Error: worktree .worktrees/{name} already exists"
  exit 1
fi

# Create worktree with new branch from default
git worktree add .worktrees/{name} -b {name} ${base:-$default_branch}

# Confirm
echo "Created worktree: .worktrees/{name}"
echo "Branch: {name} (from ${base:-$default_branch})"
echo ""
echo "Next steps:"
echo "  cd .worktrees/{name}"
echo "  # start implementing"
```

## Operation: list

Show all worktrees with their status.

```sh
git worktree list --porcelain | while read line; do
  case "$line" in
    worktree*) path="${line#worktree }" ;;
    branch*) branch="${line#branch refs/heads/}" ;;
    "")
      # Check if branch is merged into default
      if git branch --merged "$default_branch" | grep -q "$branch"; then
        status="merged"
      else
        status="active"
      fi
      echo "$status  $branch  ($path)"
      ;;
  esac
done
```

## Operation: status

Show current worktree information.

```sh
echo "Current directory: $(pwd)"
echo "Branch: $(git branch --show-current)"
echo "Worktree: $(git rev-parse --show-toplevel)"
echo ""
git status --short
echo ""
echo "Commits ahead of origin:"
git log --oneline origin/$(git branch --show-current)..HEAD 2>/dev/null || echo "(no remote tracking)"
```

## Operation: done

Clean up a worktree after its PR is merged.

```sh
# Verify the branch was merged
branch={name}
if ! git branch --merged "$default_branch" | grep -q "$branch"; then
  echo "Warning: Branch '$branch' is NOT merged into $default_branch."
  echo "Are you sure you want to remove it? (yes/no)"
  # Wait for confirmation
fi

# Remove worktree
git worktree remove .worktrees/{name}

# Delete local branch
git branch -d {name}

# Delete remote branch if it exists
if git ls-remote --heads origin {name} | grep -q {name}; then
  git push origin --delete {name}
fi

echo "Cleaned up: worktree .worktrees/{name}, branch {name}"
```

## Operation: done --all

Clean up all worktrees whose branches are merged.

```sh
default_branch=$(git symbolic-ref refs/remotes/origin/HEAD | sed 's@^refs/remotes/origin/@@')
git fetch origin

for wt in .worktrees/*/; do
  name=$(basename "$wt")
  if git branch --merged "$default_branch" | grep -q "$name"; then
    git worktree remove "$wt"
    git branch -d "$name"
    echo "Cleaned: $name"
  else
    echo "Skipped: $name (not merged)"
  fi
done
```

---

## Safety Rails

1. **Never delete unmerged branches** without explicit confirmation
2. **Never remove worktrees with uncommitted changes** — warn and abort
3. **All commits in worktrees use `-s -S`** (DCO + GPG)
4. **Worktree names match branch names** for consistency
5. **Always create from default branch** unless explicitly overridden
