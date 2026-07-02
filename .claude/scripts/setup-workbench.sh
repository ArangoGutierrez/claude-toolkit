#!/bin/bash
# setup-workbench.sh - Set up agents-workbench for any project
#
# Usage: ~/.claude/scripts/setup-workbench.sh [project-path]
# If no path given, uses current directory.

set -e

PROJECT_DIR="${1:-.}"
cd "$PROJECT_DIR"

# Must be in a git repo
if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "ERROR: Not a git repository: $(pwd)" >&2
    exit 1
fi

GIT_ROOT=$(git rev-parse --show-toplevel)
cd "$GIT_ROOT"

# Detect default branch
detect_default_branch() {
    local branch
    branch=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@')
    if [ -n "$branch" ]; then
        echo "$branch"
        return
    fi
    for candidate in main master develop; do
        if git rev-parse --verify "refs/remotes/origin/$candidate" >/dev/null 2>&1; then
            echo "$candidate"
            return
        fi
        if git rev-parse --verify "refs/heads/$candidate" >/dev/null 2>&1; then
            echo "$candidate"
            return
        fi
    done
    git branch --show-current
}

DEFAULT_BRANCH=$(detect_default_branch)
PROJECT_NAME=$(basename "$GIT_ROOT")

echo "Project:        $PROJECT_NAME"
echo "Git root:       $GIT_ROOT"
echo "Default branch: $DEFAULT_BRANCH"
echo ""

# Check if agents-workbench already exists
if git rev-parse --verify agents-workbench >/dev/null 2>&1; then
    echo "agents-workbench branch already exists, switching to it..."
    git checkout agents-workbench
else
    echo "Creating agents-workbench from $DEFAULT_BRANCH..."
    git checkout -b agents-workbench "$DEFAULT_BRANCH"
fi

# Create .agents/ directory structure
mkdir -p .agents/{plans,tasks,context,notes}

# Create AGENTS.md if it doesn't exist
if [ ! -f AGENTS.md ]; then
    if [ -f ~/.claude/templates/AGENTS.md ]; then
        cp ~/.claude/templates/AGENTS.md ./AGENTS.md
        sed -i '' "s/{{PROJECT_NAME}}/$PROJECT_NAME/g" AGENTS.md 2>/dev/null || \
            sed -i "s/{{PROJECT_NAME}}/$PROJECT_NAME/g" AGENTS.md
        sed -i '' "s/{{DEFAULT_BRANCH}}/$DEFAULT_BRANCH/g" AGENTS.md 2>/dev/null || \
            sed -i "s/{{DEFAULT_BRANCH}}/$DEFAULT_BRANCH/g" AGENTS.md
        echo "Created AGENTS.md from template"
    else
        echo "WARNING: Template not found at ~/.claude/templates/AGENTS.md"
        echo "# Agents Workbench - $PROJECT_NAME" > AGENTS.md
        echo "Created minimal AGENTS.md"
    fi
else
    echo "AGENTS.md already exists, skipping"
fi

# Ensure .worktrees is in .gitignore
if [ -f .gitignore ]; then
    if ! grep -q '^\.worktrees' .gitignore 2>/dev/null; then
        printf '\n# Agent worktrees\n.worktrees/\n' >> .gitignore
        echo "Added .worktrees/ to .gitignore"
    fi
else
    printf '# Agent worktrees\n.worktrees/\n' > .gitignore
    echo "Created .gitignore with .worktrees/"
fi

# Create .worktrees directory
mkdir -p .worktrees

echo ""
echo "agents-workbench is ready!"
echo ""
echo "Next steps:"
echo "  1. Review AGENTS.md"
echo "  2. Create a worktree (always from remote, never local):"
echo "     # For forks (upstream remote exists):"
echo "     git fetch upstream && git worktree add .worktrees/<name> -b <branch> upstream/$DEFAULT_BRANCH"
echo "     # For non-forks:"
echo "     git fetch origin && git worktree add .worktrees/<name> -b <branch> origin/$DEFAULT_BRANCH"
echo ""
echo "Remember: agents-workbench is LOCAL ONLY. Never push it."
