from __future__ import annotations

import os
import shlex
import shutil
import subprocess
import tempfile
import time
from pathlib import Path
from typing import Callable, Literal

from pydantic import BaseModel

_DENY_BINARIES = {
    "rm", "rmdir", "sudo", "curl", "wget", "nc", "ncat", "telnet", "dd",
    "chmod", "chown", "mkfs", "shutdown", "reboot", "mv", "scp", "ssh",
    "rsync", "kill", "pkill", "killall",
}
_DENY_GIT_SUBCMDS = {
    "push", "commit", "reset", "clean", "rebase",
    # the restore/checkout family silently overwrites uncommitted work
    "restore", "checkout", "switch", "stash", "branch", "worktree",
    "gc", "prune", "rm", "mv", "am", "cherry-pick", "revert", "merge",
    "pull", "fetch", "apply", "update-ref", "filter-branch", "submodule",
    "remote", "tag", "notes", "config", "init", "clone",
}
# git global options that consume the NEXT token, so it is a value and not the
# subcommand. Needed to read `git -C <dir> clean -fdx` correctly.
_GIT_VALUE_OPTS = {"-C", "-c", "--git-dir", "--work-tree", "--namespace",
                   "--exec-path", "--super-prefix", "--attr-source"}
# Shell operators treated as standalone tokens when UNQUOTED. A metacharacter
# inside a quoted argument (e.g. the ';' in `python3 -c "import x; y"`) stays
# part of its token and is NOT flagged.
_PUNCT = ";()<>|&"
# Operators an acceptance check legitimately needs. Allowed as SEPARATORS only:
# every other all-punctuation token stays denied, and the denylist below runs
# once per segment, so `echo ok && rm -rf x` is still rejected.
_ALLOWED_OPS = {"&&", "||", "|"}
# Cache dirs outside the repo that real toolchains must write to. Everything
# else outside the repo + TMPDIR is denied, so a model-authored check cannot
# damage files outside the working tree.
_CACHE_WRITE_DIRS = ("Library/Caches", ".cache", "go", "Library/Developer", ".cargo", ".npm")
_OUTPUT_TAIL = 500


class CheckVerdict(BaseModel):
    status: Literal["runnable", "broken", "rejected", "unvalidated"]
    detail: str
    exit_code: int | None = None
    output_tail: str = ""


def _drop_stderr_merge(tokens: list[str]) -> list[str]:
    """Drop the exact `2>&1` form, which shlex tokenizes as '2', '>&', '1'. It
    merges two file descriptors and writes nothing, so it is safe. Any OTHER
    '>&' (e.g. `cmd >& file`, `cmd 1>&2`) is left in place, so the
    all-punctuation check below still rejects it."""
    out: list[str] = []
    i = 0
    while i < len(tokens):
        if (tokens[i] == ">&" and out and out[-1] == "2"
                and i + 1 < len(tokens) and tokens[i + 1] == "1"):
            out.pop()          # the '2'
            i += 2             # the '>&' and the '1'
            continue
        out.append(tokens[i])
        i += 1
    return out


def _git_violation(seg: list[str], i: int) -> str | None:
    """`seg[i]` is a git token. Return a reason, or None.

    An alias is checked first and across every following token: `-c` consumes
    its value, so the walk below would step straight over
    `alias.z=clean -fdx`, and the subcommand is inside a quoted token where no
    token scan can see it."""
    rest = seg[i + 1:]
    j = 0
    while j < len(rest):
        tok = rest[j]
        if not tok.startswith("-"):
            # the first NON-option token is the subcommand; a denied word later
            # is a search term or a ref, not an invocation
            return f"denied git subcommand {tok!r}" if tok in _DENY_GIT_SUBCMDS else None
        # Everything from here to the subcommand is a GIT option. Deny the
        # whole config-override mechanism rather than one key name: config keys
        # are case-INSENSITIVE, and several of them run their value as a
        # command (core.pager, core.fsmonitor, diff.external, core.sshCommand),
        # so `-c alias.` is only one route of many.
        if tok == "-c" or tok.lower().startswith("--config-env"):
            return "git config override"
        j += 2 if tok in _GIT_VALUE_OPTS else 1
    return None


def denylisted_reason(command: str) -> str | None:
    """Return a reason string if `command` is denied, else None. Shell/quote-aware:
    a metacharacter inside a quoted argument is part of its token, not flagged.

    `&&`, `||`, `|` and the exact `2>&1` are permitted, because an acceptance
    check needs them. They are permitted as SEPARATORS only: the command is cut
    into segments on them and every segment is denylisted independently, so no
    segment can smuggle a denied binary or git subcommand past the first one."""
    if "`" in command:
        return "backtick command substitution"
    try:
        lexer = shlex.shlex(command, posix=True, punctuation_chars=_PUNCT)
        # shlex opens a comment at an ATTACHED '#' and silently drops the rest
        # of the line; /bin/sh treats it as a literal and executes it. Leaving
        # this on bypasses the whole filter: `echo x#; rm -rf y` reads as
        # ['echo','x'] here but deletes y when run.
        lexer.commenters = ""
        tokens = list(lexer)
    except ValueError:
        return "unparseable command"
    if not tokens:
        return "empty command"
    # With comments disabled a comment-only string parses to real tokens, so it
    # stops looking empty and validates as "passes" -- a check that can never
    # fail. Only a token STARTING with '#' opens a comment in bash, so this
    # cannot be a real command. Trailing tokens are NOT dropped: shlex strips
    # quotes, so a quoted '#x' is indistinguishable from a comment here, and
    # dropping the remainder would hide `foo '#x' && rm -rf y` from the scan.
    if tokens[0].startswith("#"):
        return "empty command"
    tokens = _drop_stderr_merge(tokens)
    for t in tokens:
        if t and t not in _ALLOWED_OPS and all(c in _PUNCT for c in t):
            return f"shell metacharacter {t!r}"
    segments: list[list[str]] = [[]]
    for t in tokens:
        if t in _ALLOWED_OPS:
            segments.append([])
        else:
            segments[-1].append(t)
    for seg in segments:
        if not seg:
            return "empty command segment"
        for i, tok in enumerate(seg):
            base = tok.rsplit("/", 1)[-1]
            if base in _DENY_BINARIES:
                return f"denied binary {base!r}"
            # The invocation may be wrapped (`env git push`) and the subcommand
            # may sit behind a git option (`git -C dir clean -fdx`, which
            # deletes files inside the root that Seatbelt permits).
            if base in ("git", "git.exe"):
                reason = _git_violation(seg, i)
                if reason is not None:
                    return reason
    return None


def _sandbox_profile(root: Path) -> str:
    """macOS Seatbelt: allow all but network; deny file writes outside the repo
    root, TMPDIR, /dev, and toolchain cache dirs. Every path is realpath-resolved
    because Seatbelt matches the canonical path (/var -> /private/var); an
    unresolved subpath silently never matches."""
    allow = [str(Path(root).resolve()), os.path.realpath(tempfile.gettempdir()), "/dev"]
    home = Path.home().resolve()
    allow += [str(home / rel) for rel in _CACHE_WRITE_DIRS]
    subpaths = " ".join(f'(subpath "{p}")' for p in allow)
    return ("(version 1)(allow default)(deny network*)(deny file-write*)"
            f"(allow file-write* {subpaths})")


def validate_check(command: str, root: Path, *, timeout: float = 15.0) -> CheckVerdict:
    """Prove a command is RUNNABLE (executes to a clear verdict). Reject only
    structurally broken commands; a non-zero exit means 'runs, fails now'."""
    reason = denylisted_reason(command)
    if reason is not None:
        return CheckVerdict(status="rejected", detail=reason)
    if shutil.which("sandbox-exec") is None:
        return CheckVerdict(status="unvalidated", detail="sandbox-exec unavailable")
    # pipefail: a pipeline otherwise reports its LAST command's status, so
    # `make test 2>&1 | tail -1` would be classified "runs; passes" on a RED
    # suite. macOS /bin/sh is bash and supports it.
    argv = ["sandbox-exec", "-p", _sandbox_profile(root), "/bin/sh", "-c",
            f"set -o pipefail; {command}"]
    try:
        proc = subprocess.run(argv, cwd=str(root), capture_output=True,
                              text=True, timeout=timeout)
    except subprocess.TimeoutExpired:
        return CheckVerdict(status="broken", detail="timeout")
    except OSError as e:
        return CheckVerdict(status="unvalidated", detail=f"could not launch sandbox: {e}")
    tail = (proc.stdout + proc.stderr)[-_OUTPUT_TAIL:]
    rc = proc.returncode
    if rc in (126, 127):
        return CheckVerdict(status="broken", detail="command not found / not executable",
                            exit_code=rc, output_tail=tail)
    if rc == 0:
        detail = "passes"
    elif rc == 141 and "|" in command:
        # 128+SIGPIPE. pipefail surfaces this when a consumer closes early
        # (`yes | head -1`); the check itself did not fail. Name it, so the
        # verdict is not read as an ordinary failure.
        detail = "fails (exit 141; SIGPIPE, a pipeline consumer closed early)"
    else:
        detail = f"fails (exit {rc})"
    return CheckVerdict(status="runnable", detail=detail, exit_code=rc, output_tail=tail)


def validate_checklist(commands: list[str], root: Path, *,
                       per_cmd_timeout: float = 15.0,
                       total_timeout: float = 60.0,
                       max_checks: int = 8,
                       clock: Callable[[], float] = time.monotonic) -> list[CheckVerdict]:
    """Validate each command, 1:1. Commands beyond the count/time budget are
    surfaced as `unvalidated` (never silently dropped)."""
    verdicts: list[CheckVerdict] = []
    start = clock()
    for i, cmd in enumerate(commands):
        if i >= max_checks or (clock() - start) > total_timeout:
            verdicts.append(CheckVerdict(status="unvalidated", detail="validation budget exhausted"))
            continue
        verdicts.append(validate_check(cmd, root, timeout=per_cmd_timeout))
    return verdicts
