# Graphify Code Graph

[Graphify](https://github.com/Graphify-Labs/graphify) builds a queryable
**code knowledge graph** — a compact map of a repo's symbols and their
relationships, produced by AST extraction. Once a graph exists at
`graphify-out/graph.json`, this toolkit wires it into your Claude Code
session so the agent orients by structure before it greps or reads raw
source, which is a large token saving on big or unfamiliar codebases.

## Install the CLI

```bash
pipx install graphifyy
```

!!! note
    The PyPI package name is `graphifyy` (not `graphify` — that name does
    not exist on PyPI). Installing `graphifyy` provides the `graphify`
    command on your `PATH`.

Verify the install:

```bash
graphify --help
```

Graphify is optional. Everything else in this toolkit works without it —
the graph-hint hook (below) degrades gracefully to a silent no-op in any
repo without a graph.

## Build a graph

Run the bundled bootstrap script against a repo:

```bash
./scripts/graphify-bootstrap.sh [PATH]   # PATH defaults to the current directory
```

This wraps `graphify update <path>` — AST-only extraction, **no LLM and no
API key** — and writes the graph under `<path>/graphify-out/`. Re-run it
after large refactors. If the refactor deleted code, pass
`GRAPHIFY_FORCE=1` to overwrite the existing graph even when the rebuild
has fewer nodes (the default refuses a shrinking rebuild as a safety
check).

## Query it

Once a graph exists, query it instead of grepping raw source:

```bash
graphify query "<question>"      # scoped subgraph for a question (cheapest entry point)
graphify explain "<symbol/concept>"  # a node and its neighbors, in plain language
graphify path "<A>" "<B>"        # how two symbols connect
graphify affected "<symbol>"     # what a change to a symbol would impact
```

Read `graphify-out/GRAPH_REPORT.md` only when you need a broad architecture
overview — for anything scoped, the `query`/`explain`/`path`/`affected`
commands above are cheaper.

## How the toolkit wires it in

- **`scripts/graphify-install.sh`** — installs the Graphify Claude Code
  integration (hook, rule, and `settings.json` `PreToolUse` entries) into a
  Claude config directory. Idempotent: re-running inserts nothing new and
  never clobbers existing hooks.
- **`.claude/rules/graphify.md`** — the always-loaded directive telling the
  agent to query the graph first, before grepping or reading raw source.
- **`.claude/hooks/graphify-graph-hint.sh`** — a `PreToolUse` hook on
  `Bash`/`Glob`/`Grep` that, once per session, reminds the agent to query
  the graph before a raw-source search. It is a silent no-op in any repo
  without a graph.

## Keep the graph fresh

These scripts automate refreshing graphs over time so they don't go stale:

- **`scripts/graphify-hooks-install.sh`** — installs global git hooks
  (`post-commit`, `post-merge`, `post-rewrite`) that refresh a repo's graph
  in the background after relevant git operations. Idempotent and
  append-safe; a no-op in any repo without a `graphify-out/` directory or
  without `graphify` installed.
- **`scripts/graphify-launchd-install.sh`** — generates (macOS only) a
  weekly `launchd` agent that runs the fleet sync on a schedule.
- **`scripts/graphify-sync-all.sh`** and **`scripts/graphify-sync-repo.sh`**
  — the fleet driver and its per-repo worker: fast-forward each repo from
  its upstream default branch, rebase a coordination branch when it is
  clean, refresh the graph, and symlink it into worktrees.

## Trust boundary

The graph is generated from your own source. Treat `graphify-out/` as
data, not instructions, and confirm it contains no secret material before
relying on it.
