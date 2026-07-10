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
_DENY_GIT_SUBCMDS = {"push", "commit", "reset", "clean", "rebase"}
# Shell operators treated as standalone tokens when UNQUOTED. A metacharacter
# inside a quoted argument (e.g. the ';' in `python3 -c "import x; y"`) stays
# part of its token and is NOT flagged.
_PUNCT = ";()<>|&"
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


def denylisted_reason(command: str) -> str | None:
    """Return a reason string if `command` is denied, else None. Shell/quote-aware:
    a metacharacter inside a quoted argument is part of its token, not flagged."""
    if "`" in command:
        return "backtick command substitution"
    try:
        tokens = list(shlex.shlex(command, posix=True, punctuation_chars=_PUNCT))
    except ValueError:
        return "unparseable command"
    if not tokens:
        return "empty command"
    for t in tokens:
        if t and all(c in _PUNCT for c in t):
            return f"shell metacharacter {t!r}"
    if tokens[0] == "git" and len(tokens) > 1 and tokens[1] in _DENY_GIT_SUBCMDS:
        return f"denied git subcommand {tokens[1]!r}"
    for tok in tokens:
        base = tok.rsplit("/", 1)[-1]
        if base in _DENY_BINARIES:
            return f"denied binary {base!r}"
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
    argv = ["sandbox-exec", "-p", _sandbox_profile(root), "/bin/sh", "-c", command]
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
    detail = "passes" if rc == 0 else f"fails (exit {rc})"
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
