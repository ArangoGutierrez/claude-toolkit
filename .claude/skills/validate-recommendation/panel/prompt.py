"""Prompt body construction for panel dispatch, including authorship blinding.

A blinded panelist must not be able to tell which option the assistant
recommended. That is a correctness property, so it lives here in testable
code rather than as an instruction in SKILL.md: an instruction not to
mention the recommendation cannot be verified and fails silently.

Blinding does three things:
  1. omits the recommendation and its stated reasoning entirely,
  2. strips the "(Recommended)" / "(Recommended; Panel-flagged)" markers
     from every displayed label,
  3. rotates option order deterministically, so the recommended option is
     not always first.

Rotation uses hashlib, never the builtin hash(), which is salted per
process via PYTHONHASHSEED and would not be reproducible across runs.
"""
from __future__ import annotations

import hashlib
import re

_MARKER_RE = re.compile(r"\s*\((?:Recommended(?:;\s*Panel-flagged)?)\)\s*$")


def strip_marker(label: str) -> str:
    """Remove a trailing (Recommended) / (Recommended; Panel-flagged) marker."""
    return _MARKER_RE.sub("", label).strip()


def _rotation_offset(question: str, n: int) -> int:
    """Deterministic rotation offset in [0, n) derived from the question text."""
    if n <= 1:
        return 0
    digest = hashlib.sha256(question.encode("utf-8")).hexdigest()
    return int(digest, 16) % n


def build_prompt_body(
    question: str,
    options: list[tuple[str, str]],
    recommended_label: str,
    reasoning: str,
    *,
    blind: bool,
) -> str:
    """Build the user prompt body sent to one panelist.

    options is a list of (label, description) in their original order.
    """
    lines = [f"Question: {question}", "Options (verbatim labels and descriptions):"]

    if not blind:
        for label, desc in options:
            lines.append(f"  {label} - {desc}")
        lines.append(f"Assistant's recommended option: {recommended_label}")
        lines.append(f"Assistant's stated reasoning: {reasoning}")
        return "\n".join(lines) + "\n"

    offset = _rotation_offset(question, len(options))
    rotated = options[offset:] + options[:offset]
    for label, desc in rotated:
        lines.append(f"  {strip_marker(label)} - {desc}")
    lines.append("")
    lines.append(
        "Choose the single best option on its merits. Reply with exactly "
        "two lines, no preamble and no markdown fencing:"
    )
    lines.append("CHOICE: <verbatim option label copied from the list above>")
    lines.append("RATIONALE: <one paragraph, 3-5 sentences>")
    return "\n".join(lines) + "\n"
