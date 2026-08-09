# Deployment Scripts Reference

## Overview

This repository is a bare mirror of `~/.claude/` and `~/.cursor/` — the configuration directories
for Claude Code and Cursor respectively. Three scripts manage synchronization between the repository
and the live environment on a given machine.

```mermaid
graph LR
    REPO["Repository<br/>.claude/ · .cursor/"] -->|"deploy.sh"| LIVE["Live Environment<br/>~/.claude/ · ~/.cursor/"]
    LIVE -->|"capture.sh"| REPO
    REPO <-.->|"diff.sh"| LIVE
```

The three scripts and their roles:

- `scripts/deploy.sh` — pushes config from the repo into `~/`, with automatic backup and
  post-deploy verification.
- `scripts/capture.sh` — pulls config from `~/` back into the repo so changes made in the live
  environment can be reviewed and committed.
- `scripts/diff.sh` — compares the repo against the live environment without modifying either,
  reporting files that are repo-only, live-only, or differ in content.

**Typical workflows:**

Edit in the live environment first, then bring changes into version control:

```
edit ~/.claude/ or ~/.cursor/  →  capture.sh  →  git diff  →  git add -p  →  commit  →  push
```

Edit in the repo first, then push to the live environment:

```
edit repo  →  deploy.sh --dry-run  →  deploy.sh  →  verify output
```

All three scripts share the same exclude lists (see [Exclude Lists](#exclude-lists)) so that
runtime state, caches, and machine-specific files are never synced in either direction.

---

## deploy.sh

Rsyncs `.claude/` and `.cursor/` from the repository into `~/`. Before overwriting any files,
the script creates a timestamped backup tarball of the existing live directories, so you can
roll back if needed.

After the sync completes, the script runs a verification pass that checks:

- Key files are present (`~/.claude/settings.json`, `~/.claude/CLAUDE.md`,
  `~/.cursor/mcp.json`, `~/.cursor/rules`).
- All hook scripts under `~/.claude/hooks/` and `~/.cursor/hooks/` are executable.
- JSON config files (`settings.json`, `policy-limits.json`, `remote-settings.json`,
  `mcp.json`, `hooks.json`) parse without errors using `python3`.

Verification only runs on a real deploy, not during `--dry-run`.

### Backup behaviour

The backup is created at `~/.config/dotfiles-backup/dotfiles-backup-<YYYYMMDD-HHMMSS>.tar.gz`
and captures exactly the directories that will be overwritten (`.claude/`, `.cursor/`, or both
depending on scope flags). Pass `--force` to skip the backup step.

### Flags

| Flag | Effect |
|------|--------|
| `--dry-run` | Preview changes without applying them |
| `--force` | Skip the automatic backup step |
| `--claude-only` | Deploy only `.claude/` configuration |
| `--cursor-only` | Deploy only `.cursor/` configuration |
| `--no-plugins` | Skip `plugins/` directory from `.claude/` deployment |
| `--delete` | Pass `--delete` to rsync (removes files in `~/` not in repo — use with caution) |

`--claude-only` and `--cursor-only` are mutually exclusive.

### Examples

```bash
./scripts/deploy.sh --dry-run      # see what would change
./scripts/deploy.sh                # full deploy with backup
./scripts/deploy.sh --claude-only  # only update Claude Code config
./scripts/deploy.sh --force        # deploy without creating a backup
./scripts/deploy.sh --delete       # sync exactly — remove live files absent from repo
```

### Overlay repos

Some people layer a second config repo — private, or team-specific — on top of this
one. `deploy.sh` must not overwrite the files that repo owns. Point it at the overlay
with `scripts/deploy-overlay.local`, a single line holding the overlay repo's absolute
path. That file is machine-local and gitignored.

Every `.claude/` path the overlay **tracks** is then excluded from the deploy. The
exclusion set is computed live from the overlay's git index on each run, never from a
stored snapshot. It fails closed: a pointer naming a directory that is missing, or that
is not a git repo, aborts the deploy with exit code `4` rather than deploying over
overlay-owned paths. With no pointer file, none of this applies.

#### Declaring deletions

Tracking cannot express a deletion, and that gap is a trap worth understanding.

An overlay file is excluded *because the overlay tracks it*. Delete that file from the
overlay and it stops being tracked, so it stops being excluded — and the next deploy
writes this repo's copy back into `~/.claude/`. **The deletion silently undoes itself.**

To make a deletion stick, list it in a manifest at the overlay repo's root, named:

```text
.claude-deploy-deletions
```

One repo-relative path per line:

```text
# Paths this overlay deliberately removes. The toolkit must not restore them.
.claude/agents/doc-writer.md
.claude/rules/report-style.md
```

| Case | Behaviour |
|------|-----------|
| Manifest absent | No-op — the deploy behaves exactly as it does without one. Most overlays never need a manifest |
| Manifest empty | No-op, not an error |
| Blank line | Ignored |
| `#` as the first non-blank character | The whole line is a comment. This is gitignore's rule, so a `#` inside a filename is never mistaken for one |
| Whitespace around an entry | Trimmed |
| Entry not starting with `.claude/` | Aborts with exit `4`. A manifest that can exclude arbitrary paths is a footgun |
| Entry containing a `..` segment | Aborts with exit `4` |
| Entry the overlay still tracks | Warns on stderr, then excludes it anyway. Either the entry is redundant or the deletion was never actually made |

Entries are anchored at the transfer root the same way tracked paths are, so
`.claude/rules/report-style.md` excludes exactly that file and not a same-named file
somewhere deeper.

The manifest lives in the overlay repo on purpose. It is versioned in the same commit
as the deletion it describes, so the two cannot drift apart. A list kept next to the
pointer instead would be machine-local state that a human has to remember to update —
which is the failure this feature exists to prevent. `deploy.sh` reads the working-tree
copy, so a manifest edit takes effect immediately; commit it so other machines get it
too.

Deploy output reports the two sources on separate lines, so the tracked-path count
keeps its original meaning:

```text
>> overlay: excluding 34 overlay-owned paths (from /path/to/overlay)
>> overlay: honouring 2 declared deletion(s) (from /path/to/overlay/.claude-deploy-deletions)
```

The second line appears only when the manifest contributes at least one entry.

---

## capture.sh

The reverse of deploy: rsyncs `~/.claude/` and `~/.cursor/` from the live environment back into
the repository working tree. Nothing is committed automatically — the intent is to stage and
review changes with `git diff` before deciding what to commit.

### Symlink resolution

capture.sh passes `--copy-links` to rsync. This is important because some files in `~/.cursor/`
(notably command scripts) may be symlinks. `--copy-links` dereferences them, so the repo stores
the actual file content rather than a dangling symlink.

### Leak sweep

After copying, capture.sh scans every file it actually refreshed **this run** — not the
whole tree — for identity-bearing content that must never land in this public repo:

- **Generic patterns** (always active, defined in `scripts/sync-lib.sh`): `/Users/<name>`
  and `/home/<name>` path prefixes.
- **Local patterns** (optional, machine-specific): one ERE per line, loaded from
  `LEAK_PATTERNS_FILE` (default `scripts/leak-patterns.local`, gitignored — never
  committed). Use this for real names, machine usernames, or private project paths. Blank
  lines and `#`-prefixed lines are skipped.
- If `LEAK_PATTERNS_FILE` is absent, capture.sh prints a loud warning to stderr
  (`WARNING: scripts/leak-patterns.local not found — leak sweep running with generic
  patterns only`) and proceeds with generic patterns alone — it never fails silently.
- **Placeholder exemption**: documented example paths that legitimately appear in tracked
  docs and fixtures — `/Users/foo`, `/Users/me`, `/Users/you`, `/home/user` — are exempted
  from the generic patterns so they don't flag forever. The exemption is per-match, not
  per-line: a line combining an exempt placeholder with a real path (e.g. a stray
  `/Users/testuser`) still flags.

### Exit codes

| Code | Meaning |
|------|---------|
| `0` | Capture completed; leak sweep found nothing |
| `1` | Leak sweep found possible identity-bearing content (see the `LEAK?` lines printed above the summary). The copies are still made — that's safe, since they're uncommitted working-tree changes — but review with `git diff` and revert an individual file with `git checkout -- <file>` before committing |

### Flags

| Flag | Effect |
|------|--------|
| `--claude-only` | Capture only `.claude/` |
| `--cursor-only` | Capture only `.cursor/` |

`--claude-only` and `--cursor-only` are mutually exclusive.

### Workflow after capture

```bash
./scripts/capture.sh              # capture both
git diff                          # review what changed
git add -p                        # stage selectively
git commit -s -S -m "config: update settings"
```

---

## diff.sh

Compares the repository config against the live environment and reports any differences, without
modifying either side. This is useful as a pre-deploy sanity check, for CI drift detection, or
to verify that a capture run picked up everything.

### Output categories

Each file that is not identical in both places is reported under one of three labels:

| Label | Meaning |
|-------|---------|
| `REPO ONLY` | File exists in the repo but not in the live environment |
| `CHANGED` | File exists in both places but the contents differ |
| `LIVE ONLY` | File exists in the live environment but not in the repo |
| `LEAK?` | Advisory only, printed under a `CHANGED` entry when the live copy matches a leak-sweep pattern (see [capture.sh's Leak sweep](#leak-sweep)) — does not change diff.sh's exit code |

A per-directory summary line shows the count in each category. If everything matches, the
section prints `(in sync)`.

### Exit codes

| Code | Meaning |
|------|---------|
| `0` | Everything in sync |
| `1` | One or more differences found |

### Flags

| Flag | Effect |
|------|--------|
| `--claude-only` | Compare only `.claude/` |
| `--cursor-only` | Compare only `.cursor/` |

### Examples

```bash
./scripts/diff.sh                 # compare everything
./scripts/diff.sh --cursor-only   # just check Cursor config
echo $?                           # 0 = in sync, 1 = differences
```

---

## Exclude Lists

All three scripts use the same exclude lists, so runtime state is consistently ignored regardless
of which direction data is flowing. Files and directories that match these patterns are never
synced, captured, or compared.

### Claude excludes

| Pattern | Reason |
|---------|--------|
| `debug/` | Runtime debug logs |
| `projects/` | Claude project-specific state |
| `teams/`, `tasks/`, `todos/`, `team/` | Runtime team/task state |
| `cache/`, `plugins/cache/` | Downloaded plugin caches |
| `plugins/known_marketplaces.json`, `plugins/marketplaces/` | Marketplace registry cache |
| `file-history/` | Claude file edit history |
| `session-env/`, `shell-snapshots/` | Session-specific environment state |
| `paste-cache/` | Clipboard paste cache |
| `telemetry/` | Telemetry data |
| `backups/` | Local backup archives |
| `ide/` | IDE integration state |
| `history.jsonl` | Conversation history |
| `stats-cache.json` | Usage statistics |
| `settings.local.json` | Machine-specific overrides (not portable) |
| `plans/` | Runtime plan state |
| `commands/` | Runtime commands |
| `docs/` | Documentation (managed separately in repo root) |

### Cursor excludes

| Pattern | Reason |
|---------|--------|
| `extensions/` | Cursor extension state |
| `projects/` | Project-specific Cursor state |
| `ai-tracking/`, `snapshots/` | AI session tracking data |
| `ide_state.json` | Window and editor layout state |
| `argv.json` | Launch arguments |
| `unified_repo_list.json` | Cursor's internal repo registry |
| `worktrees/` | Runtime worktree tracking |
| `blocklist` | Runtime blocklist |
| `.deploy-version` | Deployment versioning marker |
| `docs/` | Documentation (managed separately in repo root) |
| `skills/` | Runtime skill state |
