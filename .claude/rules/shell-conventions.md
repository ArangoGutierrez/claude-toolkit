# Shell Conventions

Discipline rules for shell commands run via Bash, scripts under `scripts/`,
and `make` targets. Append patterns here as they emerge; this file is a
sibling to the other `rules/*.md` and is auto-loaded by Claude Code.

## File operations — never trust exit 0

`cp`, `mv`, `rsync`, and `install` can return success while doing nothing
useful. Common traps:

- **Interactive aliases** (`mv -i`, `cp -i`) decline overwrite and return 0.
  In a non-interactive script the `-i` prompt blocks on stdin and **hangs**
  the task.
- **`cp -R src dst` nesting**: when `dst` exists as a directory, the source
  is copied *into* it (`dst/src/…`) instead of replacing its contents.
  Exit code is 0.
- **`rsync` with `--ignore-existing`** silently keeps stale targets when
  source and destination both exist.

**Always verify after-state.** Diff, `ls`, or `stat` the destination after
the operation; never declare success on exit code alone.

Bypass `-i` aliases with the explicit binary (`command cp -f`,
`command mv -f`) or a redirect (`cat src > dst`). For directory mirror,
either `rm -rf dst && cp -R src dst` or `cp -R src/. dst/` (trailing
`/.` copies contents, not the directory itself).

## Working directory does not persist between Bash calls

Despite tool docs implying otherwise, `cd` in one Bash call may not be
visible to the next. A stale `cd` can cause `git add` pathspec misses,
wrong-venv installs, and snapshot artifacts written to the wrong tree.

**Use absolute paths.** For `git`, prefer `git -C <dir> <subcommand>` over
`cd <dir> && git <subcommand>`. For scripts that need a working tree,
`cd "$(dirname "$0")"` at the top.

## Sandboxed Bash diverges from unsandboxed in non-obvious ways

- `$TMPDIR` is `/tmp/claude-NNN/...` sandboxed, `/var/folders/.../T/...`
  unsandboxed. Files scaffolded in one mode are invisible in the other.
  For cross-mode workflows, use a fixed `/tmp/<name>` path.
- `**/secret*`, `**/credential*`, `**/*token*` reads are blocked sandboxed.
  A dep with a `secrets.py` module breaks `import` chains with a
  misleading `ModuleNotFoundError`.
- `git worktree add/remove` and writes under `~/.claude/`, `.worktrees/`,
  `.claude/worktrees/` are denied → exit 128. Run sandbox-disabled from
  the start; do not retry sandboxed-first.
- Process enumeration and signaling are denied sandboxed: `ps -axo`,
  `lsof` against other processes, and `kill` fail with "operation not
  permitted". Leak hunts, orphan-process cleanup, and any cross-process
  diagnosis need sandbox-disabled from the start.

## Pipes eat exit codes

`make test 2>&1 | tail -1 && git commit …` commits on a RED suite: the
chain sees tail's rc, not make's. The same trap masked a failed
`git pull --ff-only` (a worktree was then cut from the wrong base) and
a glab 422 during merge mechanics.

Gate on the command, not its pipe: `cmd > /tmp/out 2>&1; rc=$?`, then
inspect the file — or `set -o pipefail` when a pipe is unavoidable.
Never put `&&` after a piped verification.

Related macOS gap: GNU `timeout` does not exist on stock macOS — bound
long-running commands with a background run + `pkill -TERM -f <child>`
(targeting the actual child process, not the make/uv wrapper).

When a shell command fails with "Operation not permitted" or unexpected
network/cert errors, re-run sandbox-disabled before assuming a real bug.
