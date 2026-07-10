# Getting Started

Welcome to the claude-toolkit repo. This guide walks you through installing the configuration, verifying it works, and running your first workflow. If you are new to Claude Code or Cursor, that is fine — this guide explains what everything does as you go.

For a deeper look at why things are structured this way, see [Architecture](architecture.md); for the principles the toolkit enforces, see [Engineering Discipline](engineering-discipline.md).

---

## Prerequisites

You need the following tools installed before deploying these dotfiles.

### macOS or Linux

Windows and WSL have not been tested. macOS (12 Monterey or later) and common Linux distributions (Ubuntu 22.04+, Fedora 38+) are known to work.

### Git 2.20+

Required for `git worktree` support, which is central to this workflow.

```bash
# macOS
brew install git

# Ubuntu / Debian
sudo apt update && sudo apt install git

# Verify
git --version
```

### jq

Used by hooks that parse JSON configuration and output.

```bash
# macOS
brew install jq

# Ubuntu / Debian
sudo apt install jq

# Verify
jq --version
```

### GPG with a signing key

Commits made during Claude Code sessions are enforced to be signed. You need GPG installed and a signing key configured.

```bash
# macOS
brew install gnupg

# Ubuntu / Debian
sudo apt install gnupg

# Generate a key if you do not have one
gpg --gen-key

# List your keys to confirm
gpg --list-keys

# Configure Git to use your key (replace KEY_ID with the fingerprint shown above)
git config --global user.signingkey <KEY_ID>
git config --global commit.gpgsign true
```

### rsync

Used by `deploy.sh` and `capture.sh` to sync files between the repo and your home directory.

```bash
# macOS (the system rsync is usually sufficient, but brew provides a newer version)
brew install rsync

# Linux — rsync is typically pre-installed. If not:
sudo apt install rsync   # Ubuntu / Debian
sudo dnf install rsync   # Fedora
```

---

## Installation

### 1. Clone the repository

```bash
git clone https://github.com/ArangoGutierrez/claude-toolkit.git
cd claude-toolkit
```

### 2. Preview what will be deployed

Run a dry-run first so you can see exactly which files will be installed and what will be backed up:

```bash
./scripts/deploy.sh --dry-run
```

This shows the rsync output without writing anything to disk.

### 3. Deploy

```bash
./scripts/deploy.sh
```

What this does:

- Rsyncs `.claude/` from the repo into `~/.claude/`
- Rsyncs `.cursor/` from the repo into `~/.cursor/`
- Creates a timestamped backup of any existing files at `~/.config/dotfiles-backup/` before overwriting them (for example: `~/.config/dotfiles-backup/dotfiles-backup-20260220-143000.tar.gz`)

The script is safe to re-run. Each run creates a fresh backup before making changes, so you can always roll back.

For a full explanation of `deploy.sh`, `capture.sh`, and `diff.sh`, see [Deployment Scripts](deployment.md).

---

## Verify Installation

After deploying, run the following checks to confirm everything is in place.

### Hooks are executable

```bash
ls -la ~/.claude/hooks/
```

Verify the scripts are present and executable. To see how many hooks were installed:

```bash
ls ~/.claude/hooks/*.sh | wc -l
```

All hooks should have executable permissions (`-rwxr-xr-x`). See [Claude Code Configuration](claude-code.md) for the full list of hooks and what each one does.

If any file is missing the executable bit:

```bash
chmod +x ~/.claude/hooks/*.sh
```

### Signed commit enforcement

Open a Claude Code session inside any Git repository and ask it to commit something without the `-s -S` flags. The `sign-commits.sh` hook should block the commit and ask you to use `git commit -s -S -m "..."` instead.

### TDD guard

In a Claude Code session, ask it to write an implementation file (for example, a new `.go` or `.py` file) without first creating a corresponding test file. The `tdd-guard.sh` hook should block the write and prompt you to write the test first.

To bypass for a one-off case (for example, when adding a config file that genuinely has no test), export the variable before the file write/edit operation that triggers the hook:

```bash
export SKIP_TDD_GUARD=1
# then perform the write/edit operation that triggers tdd-guard.sh
```

### Claude Code plugins loaded

Open Claude Code and run `/status` (or check the settings panel) to confirm plugins are enabled. You should see entries for at minimum:

- `superpowers` — brainstorming, CoVe verification, and planning commands
- `code-review` — structured code review slash command
- `code-simplifier` — complexity reduction slash command
- `gopls-lsp` — Go language server integration

---

## Your First Workflow

This repo enforces a worktree-based development model. You never commit implementation work directly to `main` or `master`. Instead:

1. A local coordination branch serves as your planning hub (never pushed to remote).
2. All feature work happens in `.worktrees/<name>/`, each on its own branch.

Here is a minimal walkthrough.

### Step 1: Set up the coordination branch

From inside the project you want to work in, run the shipped setup script:

```bash
~/.claude/scripts/setup-workbench.sh
```

This creates the local-only coordination branch and seeds an `AGENTS.md`. The branch is where you plan work, write `AGENTS.md`, and keep `.agents/plans/` documents; the `prevent-push-workbench.sh` hook keeps it from ever being pushed, and `enforce-worktree.sh` keeps source code read-only on it. See [Architecture](architecture.md) for the exact branch name and the enforcement details.

### Step 2: Create a worktree for your feature

Always branch from the remote ref (not local `main`) to avoid working from a stale base:

```bash
git fetch origin
BASE="origin/$(git symbolic-ref refs/remotes/origin/HEAD | sed 's@^refs/remotes/origin/@@')"
git worktree add .worktrees/my-feature -b feat/my-feature "$BASE"
cd .worktrees/my-feature
```

### Step 3: Write a failing test first

The TDD guard requires a test file to exist before you can write implementation. Create your test:

```bash
# Example for a Go project
touch pkg/myfeature/myfeature_test.go
# Write your failing test, then run it to confirm it fails
go test ./pkg/myfeature/...
```

### Step 4: Write the implementation

Now that a test file exists, the TDD guard will allow implementation files. Write the minimum code to make the test pass.

### Step 5: Commit with signing flags

The `sign-commits.sh` hook enforces both a DCO sign-off (`-s`) and a GPG signature (`-S`):

```bash
git add .
git commit -s -S -m "feat: add myfeature"
```

### Step 6: Push and open a PR

```bash
git push -u origin feat/my-feature
gh pr create --title "feat: add myfeature" --body "..."
```

### Step 7: Clean up after merge

Once the PR is merged, remove the worktree:

```bash
git worktree remove .worktrees/my-feature
```

For the full architectural rationale behind this workflow, see [Architecture](architecture.md).

---

## Customization

### Disable a hook

Hooks are registered in `~/.claude/settings.json` under the `hooks` array. To disable one, remove its entry from that array. You can also edit the source in `.claude/hooks/` and re-deploy.

### Change Claude Code permissions

The `allow`, `deny`, and `ask` lists in `~/.claude/settings.json` control what actions Claude Code can take without prompting. Edit these lists to match your risk tolerance. See [Claude Code Configuration](claude-code.md) for the full reference.

### Add a Cursor agent

Create a `.md` file in `.cursor/agents/` with the appropriate frontmatter (`name`, `description`, `model`). Deploy with `./scripts/deploy.sh` to sync it to `~/.cursor/agents/`. See [Cursor Configuration](cursor.md) for the frontmatter schema.

### Add a Cursor command

Create a `.md` file in `.cursor/commands/`. Commands group agents and define multi-step workflows. See [Cursor Configuration](cursor.md) for examples and the full reference.

---

## Troubleshooting

### "GPG not found" or signing fails

```bash
# Install GPG
brew install gnupg          # macOS
sudo apt install gnupg      # Ubuntu / Debian

# Generate a key if you do not have one
gpg --gen-key

# Find your key ID
gpg --list-secret-keys --keyid-format=long

# Configure Git (replace KEY_ID with the long key ID shown above)
git config --global user.signingkey <KEY_ID>
git config --global commit.gpgsign true
```

If you are on macOS and Git cannot find the GPG binary:

```bash
git config --global gpg.program gpg
```

### "Permission denied" on hooks

```bash
chmod +x ~/.claude/hooks/*.sh
```

### Worktree conflicts

If a worktree was deleted without being removed from Git's tracking:

```bash
# List all registered worktrees
git worktree list

# Remove stale entries
git worktree prune
```

### TDD guard blocking unexpectedly

The guard checks for the presence of a test file before allowing implementation writes. If it is blocking something that genuinely does not need a test (configuration files, generated files, documentation):

```bash
export SKIP_TDD_GUARD=1
# then perform the write/edit operation that triggers tdd-guard.sh
```

Use this sparingly. The guard exists to enforce TDD discipline. Note that `SKIP_TDD_GUARD` is checked by the Write/Edit hook, not by `git commit`, so it must be set in the environment before the file operation.

### Deploy overwrote my local changes

Check the automatic backups created before each deploy:

```bash
ls ~/.config/dotfiles-backup/
```

Each entry is a timestamped `.tar.gz` archive. Extract the one you need:

```bash
tar -xzf ~/.config/dotfiles-backup/claude-<timestamp>.tar.gz -C /tmp/restore/
```

Then copy the files you need back into place.

---

## Next Steps

- [Engineering Discipline](engineering-discipline.md) — The six ideas the toolkit enforces, each linked to its shipped hook, rule, or skill
- [Architecture](architecture.md) — Deep-dive into the coordination-branch model, hook internals, and design decisions
- [Claude Code Configuration](claude-code.md) — Full reference for hooks, settings, plugins, and policies
- [Cursor Configuration](cursor.md) — Agents, commands, rules, and hooks for Cursor IDE
- [Deployment Scripts](deployment.md) — How `deploy.sh`, `capture.sh`, and `diff.sh` work
- [Skills and Commands Reference](skills-and-commands.md) — Complete reference for all slash commands
