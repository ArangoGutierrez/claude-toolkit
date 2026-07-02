#!/usr/bin/env bash
set -euo pipefail
# Idempotently append the graphify maintenance contract to a repo's CLAUDE.md. 2026.
REPO="${1:?usage: graphify-doc-contract-install.sh <repo-path>}"
F="$REPO/CLAUDE.md"
MARK='<!-- graphify-maintenance-contract -->'
[ -f "$F" ] || { echo "no CLAUDE.md at $F (skipping)"; exit 0; }
if grep -qF "$MARK" "$F" 2>/dev/null; then echo "contract already present: $F"; exit 0; fi
cat >> "$F" <<EOF

$MARK
## Graphify graph maintenance

This repo has a Graphify code graph (\`graphify-out/\`, git-ignored). Freshness:
- **On commit / pull / rebase** via global git hooks in \`~/.config/git/hooks\`.
- **Weekly** via a launchd agent that also fast-forwards \`master\`/\`main\` from
  \`upstream\` and rebases \`agents-workbench\` onto it **only when the tree is clean
  and the rebase is conflict-free** (otherwise it aborts and logs — no history is
  rewritten).

Manual refresh: \`graphify update .\`. Conflicts and diverged branches are reported in
\`~/.claude/logs/graphify-sync-LATEST.md\`. Worktrees see the graph via a
\`graphify-out\` symlink to the main checkout.
EOF
echo "appended contract to $F"
