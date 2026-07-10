# Agents

This page is for an AI agent (or a human scripting one) that wants to pull
this repo's documentation into context programmatically, without cloning the
repo or rendering the MkDocs site.

## Raw-md URL scheme

Every page in this repo is plain Markdown, fetchable directly from GitHub's
raw-content host at a predictable URL:

```
https://raw.githubusercontent.com/ArangoGutierrez/claude-toolkit/main/<path>
```

For example, this page itself is:

```
https://raw.githubusercontent.com/ArangoGutierrez/claude-toolkit/main/docs/agents.md
```

No authentication, no rate-limit surprises beyond GitHub's normal
unauthenticated raw-content limits, and no HTML to strip — just the source
Markdown, exactly as it renders in the MkDocs site.

## `llms.txt` — the root index

[`llms.txt`](https://raw.githubusercontent.com/ArangoGutierrez/claude-toolkit/main/llms.txt)
is a hand-curated index in the [llmstxt.org](https://llmstxt.org) format: an
H1 title, a one-line summary, and grouped link lists (`## Docs`,
`## Patterns`, `## Examples`, `## Engine source`), one link per line. Start
here if you want to decide which pages are relevant before fetching them —
it is small enough to fit in a single context window alongside your own
task.

## `llms-full.txt` — the single-fetch corpus

[`llms-full.txt`](https://raw.githubusercontent.com/ArangoGutierrez/claude-toolkit/main/llms-full.txt)
concatenates every page linked from `llms.txt`, in the order `llms.txt`
lists them, each preceded by a `===== <path> =====` header. Fetch this one
file to get the entire documentation corpus in a single request — useful
when you'd rather pay one fetch than N, or when your fetch tool doesn't
handle a fan-out well.

It is generated, not hand-written: `scripts/gen-llms-full.sh` reads
`llms.txt`, resolves every linked `.md` file back to its path in this repo,
and concatenates them. Regenerate it whenever `llms.txt` changes, or
whenever any page it links changes:

```bash
scripts/gen-llms-full.sh
```

The script fails loudly (non-zero exit, `MISSING: <path>` on stderr) if
`llms.txt` ever links a path that doesn't exist in the tree, so a stale
link can't silently ship in the generated corpus.

## The stable-heading promise

Every page under [`docs/patterns/`](patterns/openrouter-free-tier.md) uses
the same four H2 headings, in the same order: `## What`, `## How`, `## Env`,
`## Pitfalls`. An agent that has parsed one pattern page can jump straight
to the section it needs on any other pattern page without re-parsing the
whole document — `## Pitfalls` always answers "what breaks and why," `## Env`
always answers "what variables does this read." This structure is a
contract: new pattern pages are expected to follow it, and a page that
doesn't should be treated as a bug.
