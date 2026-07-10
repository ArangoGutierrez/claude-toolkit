"""Per-role persona file loader.

A persona file has YAML front-matter and three known markdown sections:
  # System prompt
  # One-shot example   (optional — empty allowed)
  # User prompt template

The loader splits these into a Persona dataclass. `load_persona_by_role`
finds the file by role name (case-insensitive: 'DA' → personas/da.md).
"""
from __future__ import annotations
import re
from dataclasses import dataclass, field
from pathlib import Path

import yaml


_FRONTMATTER_RE = re.compile(r"^---\n(.*?)\n---\n(.*)$", re.DOTALL)


class PersonaError(Exception):
    pass


@dataclass
class Persona:
    role: str
    description: str = ""
    intended_backends: list[str] = field(default_factory=list)
    system_prompt: str = ""
    one_shot_example: str = ""
    user_prompt_template: str = ""


def _split_sections(body: str) -> dict[str, str]:
    """Split markdown body on `# Heading` lines into a dict keyed by heading."""
    sections: dict[str, list[str]] = {}
    current: str | None = None
    for line in body.splitlines():
        if line.startswith("# "):
            current = line[2:].strip()
            sections[current] = []
        elif current is not None:
            sections[current].append(line)
    return {k: "\n".join(v).strip() for k, v in sections.items()}


def load_persona(path: str | Path) -> Persona:
    path = Path(path).expanduser()
    if not path.is_file():
        raise PersonaError(f"persona file missing: {path}")

    text = path.read_text(encoding="utf-8")
    m = _FRONTMATTER_RE.match(text)
    if not m:
        raise PersonaError(f"{path}: missing or malformed YAML front-matter")

    frontmatter_raw, body = m.group(1), m.group(2)
    try:
        meta = yaml.safe_load(frontmatter_raw) or {}
    except yaml.YAMLError as e:
        raise PersonaError(f"{path}: front-matter parse error: {e}") from e
    if not isinstance(meta, dict):
        raise PersonaError(
            f"{path}: front-matter must be a YAML mapping (got {type(meta).__name__})"
        )

    role = meta.get("role")
    if not role:
        raise PersonaError(f"{path}: front-matter missing 'role'")

    sections = _split_sections(body)
    sp = sections.get("System prompt", "")
    upt = sections.get("User prompt template", "")
    if not sp:
        raise PersonaError(f"{path}: '# System prompt' section is empty or missing")
    if not upt:
        raise PersonaError(f"{path}: '# User prompt template' section is empty or missing")

    return Persona(
        role=role,
        description=meta.get("description", ""),
        intended_backends=list(meta.get("intended_backends", [])),
        system_prompt=sp,
        one_shot_example=sections.get("One-shot example", ""),
        user_prompt_template=upt,
    )


def load_persona_by_role(role: str, personas_dir: str | Path | None = None) -> Persona:
    """Load persona by role name. Looks for `<personas_dir>/<role.lower()>.md`.

    Default personas_dir is the `personas/` directory next to this panel package.
    """
    if personas_dir is None:
        personas_dir = Path(__file__).resolve().parent.parent / "personas"
    return load_persona(Path(personas_dir) / f"{role.lower()}.md")
