from __future__ import annotations

import fnmatch
from pathlib import Path

from tool.errors import ToolError

# Mirrors the Bash sandbox read-deny set; these never reach the model.
_DENY_GLOBS = (
    ".env", ".env.*", "*secret*", "*credential*", "*token*",
    "*.pem", "*.key", "*id_rsa*", "*password*",
)
_DENY_DIR_COMPONENTS = {".ssh", ".aws"}


def is_denylisted(path: Path) -> bool:
    if _DENY_DIR_COMPONENTS & set(path.parts):
        return True
    name = path.name.lower()
    return any(fnmatch.fnmatch(name, g) for g in _DENY_GLOBS)


def jail_path(root: Path, rel: str) -> Path:
    """Resolve `rel` strictly within `root`. Raise ToolError on escape or denylist hit."""
    root = Path(root).resolve()
    candidate = (root / rel).resolve()  # collapses .. and follows symlinks
    if root != candidate and root not in candidate.parents:
        raise ToolError(f"path {rel!r} resolves outside repository root")
    rel_candidate = candidate.relative_to(root)  # safe: candidate is inside root here
    if is_denylisted(rel_candidate) or is_denylisted(Path(rel)):
        raise ToolError(f"path {rel!r} is denylisted (secret/credential material)")
    return candidate


def read_capped(path: Path, cap: int = 8192) -> str:
    data = Path(path).read_bytes()[: cap + 1]
    if b"\x00" in data:
        raise ToolError(f"refusing to read binary file: {path.name}")
    return data[:cap].decode("utf-8", errors="replace")
