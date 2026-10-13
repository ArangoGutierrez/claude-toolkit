"""Stakes of a paneled question, and what the session does with a verdict.

A marked fork is high stakes unless its question text starts with the
[reversible] tag and nothing in the question or its options names an
outward or irreversible verb, including inside identifiers such as
allow_auto_merge or deployProd. While the user is away, a reversible fork
proceeds unless the panel hard-dissents, and a high-stakes fork always
waits for the user with the panel's review attached. Every unclear input
resolves toward asking the user.
"""
from __future__ import annotations

import re
from dataclasses import dataclass

REVERSIBLE_TAG = "[reversible]"

_KEYWORDS = re.compile(
    r"\b(push(es|ed|ing)?|merg(e|es|ed|ing)|publish(es|ed|ing)?|post(s|ed|ing)?|"
    r"send(s|ing)?|sent|delet(e|es|ed|ing)|deploy(s|ed|ing|ment|ments)?|"
    r"releas(e|es|ed|ing)|forc(e|es|ed|ing))\b",
    re.IGNORECASE,
)

# Identifier joints become word breaks before matching: lower-to-upper case
# changes (autoMerge), underscores (allow_auto_merge) and digit runs (deploy2prod).
_CAMEL = re.compile(r"(?<=[a-z])(?=[A-Z])")
_JOINERS = re.compile(r"[_0-9]+")

_VOTED = ("HOLD", "SOFT-DISSENT", "HARD-DISSENT")

_TABLE = {
    ("HOLD", "reversible"): "proceed",
    ("SOFT-DISSENT", "reversible"): "proceed_noted",
    ("HARD-DISSENT", "reversible"): "ask_with_review",
    ("HOLD", "high"): "ask_with_review",
    ("SOFT-DISSENT", "high"): "ask_with_review",
    ("HARD-DISSENT", "high"): "ask_with_review",
}


@dataclass(frozen=True)
class Stakes:
    level: str   # "reversible" | "high"
    reason: str  # "tagged" | "untagged" | "keyword:<word>" | "no_question"


def classify(question: object) -> Stakes:
    """Stakes of a build-prompt question payload."""
    if not isinstance(question, dict):
        return Stakes("high", "no_question")
    text = question.get("question")
    if not isinstance(text, str) or not text.strip():
        return Stakes("high", "no_question")
    options = question.get("options")
    fields = [text]
    for option in options if isinstance(options, list) else []:
        if isinstance(option, dict):
            fields.append(str(option.get("label") or ""))
            fields.append(str(option.get("description") or ""))
    for field in fields:
        match = _KEYWORDS.search(_words(field))
        if match:
            return Stakes("high", f"keyword:{match.group(0).lower()}")
    if text.lstrip().lower().startswith(REVERSIBLE_TAG):
        return Stakes("reversible", "tagged")
    return Stakes("high", "untagged")


def _words(text: str) -> str:
    """Split identifiers so a keyword inside one still matches on its own."""
    return _JOINERS.sub(" ", _CAMEL.sub(" ", text))


def action(verdict: str, level: str, mode: str = "on") -> str:
    """What the session does: proceed, proceed_noted, ask_with_review or ask."""
    if verdict not in _VOTED:
        return "ask"
    if (mode or "").strip().lower() == "advise":
        return "ask_with_review"
    return _TABLE.get((verdict, level), "ask_with_review")
