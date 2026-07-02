#!/usr/bin/env bash
set -uo pipefail
# Per-repo: ff fork's default branch from upstream, conditionally rebase
# agents-workbench (clean + conflict-free only), refresh the graph, symlink the
# graph into worktrees. Emits one status line. Never fatal on one repo. 2026.

REPO="${1:?usage: graphify-sync-repo.sh <repo-path>}"
cd "$REPO" 2>/dev/null || { echo "$REPO | ERROR:not-a-dir"; exit 0; }
MAIN="$(git rev-parse --show-toplevel 2>/dev/null)" || { echo "$REPO | ERROR:not-a-git-repo"; exit 0; }
cd "$MAIN" || { echo "$REPO | ERROR:cd-failed"; exit 0; }

up="N"; ff="NA"; reb="NA"; behind="0"

has_upstream(){ git remote | grep -qx upstream; }
default_branch(){
  local d; d="$(git symbolic-ref --quiet --short refs/remotes/upstream/HEAD 2>/dev/null)"; d="${d#upstream/}"
  if [ -n "$d" ]; then printf '%s\n' "$d"; return; fi
  for b in master main; do git show-ref --verify --quiet "refs/remotes/upstream/$b" && { printf '%s\n' "$b"; return; }; done
}
branch_exists(){ git show-ref --verify --quiet "refs/heads/$1"; }
tree_clean(){ git diff --quiet && git diff --cached --quiet; }
op_in_progress(){ [ -d "$(git rev-parse --git-path rebase-merge)" ] || [ -d "$(git rev-parse --git-path rebase-apply)" ] || [ -f "$(git rev-parse --git-path MERGE_HEAD)" ]; }

if has_upstream; then
  up="Y"
  if ! git fetch --prune upstream >/dev/null 2>&1; then
    echo "$MAIN | upstream:Y ff:FETCHFAIL rebase:NA nodes:? behind:?"; exit 0
  fi
  DEF="$(default_branch)"; CUR="$(git rev-parse --abbrev-ref HEAD)"
  if [ -n "$DEF" ]; then
    if [ "$CUR" = "$DEF" ]; then
      if git merge --ff-only "upstream/$DEF" >/dev/null 2>&1; then ff="OK"; else ff="DIVERGED"; fi
    else
      if git fetch upstream "$DEF:$DEF" >/dev/null 2>&1; then ff="OK"; else ff="DIVERGED"; fi
    fi
    if branch_exists agents-workbench; then
      if [ "$CUR" = "agents-workbench" ] && tree_clean && ! op_in_progress; then
        if git rebase "$DEF" >/dev/null 2>&1; then reb="CLEAN"; else git rebase --abort >/dev/null 2>&1; reb="CONFLICT"; fi
        behind="$(git rev-list --count "HEAD..$DEF" 2>/dev/null || echo 0)"
      elif [ "$CUR" != "agents-workbench" ]; then reb="SKIP:not-on-aw"
      elif ! tree_clean; then reb="SKIP:dirty"
      else reb="SKIP:op-in-progress"; fi
    fi
  fi
fi

env -u OPENAI_API_KEY -u ANTHROPIC_API_KEY graphify update "$MAIN" >/dev/null 2>&1
nodes="?"
if [ -f "$MAIN/graphify-out/graph.json" ] && command -v jq >/dev/null 2>&1; then
  nodes="$(jq '.nodes|length' "$MAIN/graphify-out/graph.json" 2>/dev/null || echo '?')"
fi

excl="$(git rev-parse --git-path info/exclude)"
mkdir -p "$(dirname "$excl")"
grep -qxF 'graphify-out' "$excl" 2>/dev/null || printf 'graphify-out\n' >> "$excl"
git worktree list --porcelain | awk '/^worktree /{print $2}' | while IFS= read -r wt; do
  [ "$wt" = "$MAIN" ] && continue
  if [ ! -e "$wt/graphify-out" ]; then
    ln -s "$MAIN/graphify-out" "$wt/graphify-out" 2>/dev/null && echo ">> symlinked graph into $wt" >&2
  fi
done

echo "$MAIN | upstream:$up ff:$ff rebase:$reb nodes:$nodes behind:$behind"
