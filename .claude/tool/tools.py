from __future__ import annotations

import subprocess
from dataclasses import dataclass
from pathlib import Path
from typing import Callable

from pydantic import BaseModel, Field

from tool.security import jail_path, read_capped
from tool.errors import ToolError

_GREP_MAX_LINES = 50
_LIST_MAX_ENTRIES = 200
_GIT_LOG_N = 20
_BUILD_FILES = {
    "go.mod": "go", "Makefile": "make", "package.json": "node",
    "pyproject.toml": "python", "Cargo.toml": "rust", "Dockerfile": "docker",
    "pom.xml": "maven", "build.gradle": "gradle",
}


@dataclass
class Tool:
    name: str
    description: str
    args_model: type[BaseModel]
    run: Callable[..., str]

    def openai_schema(self) -> dict:
        params = self.args_model.model_json_schema()
        params.pop("title", None)
        return {"type": "function", "function": {
            "name": self.name, "description": self.description, "parameters": params}}


class _ReadFileArgs(BaseModel):
    path: str = Field(description="Repo-relative path to a text file")


class _GrepArgs(BaseModel):
    pattern: str = Field(description="Literal/regex pattern to search for")
    glob: str | None = Field(default=None, description="Optional pathspec, e.g. '*.go'")


class _ListDirArgs(BaseModel):
    path: str = Field(default=".", description="Repo-relative directory")


class _NoArgs(BaseModel):
    pass


def readonly_tools(root: Path, sink: list[str] | None = None) -> list[Tool]:
    root = Path(root)
    rroot = root.resolve()
    seen = sink if sink is not None else []

    def read_file(path: str) -> str:
        p = jail_path(root, path)
        if not p.exists():
            raise ToolError(f"no such file: {path!r}")
        if p.is_dir():
            raise ToolError(f"{path!r} is a directory; use list_dir")
        seen.append(str(p.relative_to(rroot)))   # cite only after jail + existence checks
        return read_capped(p)

    def grep(pattern: str, glob: str | None = None) -> str:
        argv = ["git", "-C", str(root), "grep", "-nI", "--no-color", "-e", pattern]
        if glob:
            argv += ["--", glob]
        proc = subprocess.run(argv, capture_output=True, text=True, timeout=10)
        lines = proc.stdout.splitlines()[:_GREP_MAX_LINES]
        for ln in lines:
            fname = ln.split(":", 1)[0]
            if fname:
                seen.append(fname)
        return "\n".join(line[:300] for line in lines) or "(no matches)"

    def list_dir(path: str = ".") -> str:
        p = jail_path(root, path)
        if not p.is_dir():
            raise ToolError(f"{path!r} is not a directory")
        entries = sorted(p.iterdir())[:_LIST_MAX_ENTRIES]
        return "\n".join(e.name + ("/" if e.is_dir() else "") for e in entries) or "(empty)"

    def git_log() -> str:
        proc = subprocess.run(
            ["git", "-C", str(root), "log", "--oneline", "--no-color", "-n", str(_GIT_LOG_N)],
            capture_output=True, text=True, timeout=10)
        return proc.stdout.strip() or "(no git history)"

    def detect_build_tooling() -> str:
        found = sorted({tok for fn, tok in _BUILD_FILES.items() if (root / fn).exists()})
        return ", ".join(found) if found else "(none detected)"

    return [
        Tool("read_file", "Read a text file in the repo (head, capped).", _ReadFileArgs, read_file),
        Tool("grep", "Search tracked files for a pattern (capped).", _GrepArgs, grep),
        Tool("list_dir", "List entry names in a repo directory (capped).", _ListDirArgs, list_dir),
        Tool("git_log", "Recent commit subject lines.", _NoArgs, git_log),
        Tool("detect_build_tooling", "Detect build/test tooling present in the repo.", _NoArgs, detect_build_tooling),
    ]
