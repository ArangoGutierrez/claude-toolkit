from __future__ import annotations

import math
import re

_TOKEN = re.compile(r"[a-z0-9]+")
_STOPWORDS = frozenset({
    "use", "when", "the", "a", "an", "or", "and", "to", "of", "for", "in",
    "on", "with", "is", "are", "this", "that", "it", "as", "by", "from",
    "triggered", "trigger", "triggers", "claude", "skill", "your", "you",
    "do", "not", "via", "any",
})


def _tokens(text: str) -> set[str]:
    return {t for t in _TOKEN.findall(text.lower())
            if len(t) > 1 and t not in _STOPWORDS}


def rank_manifest(task_text: str, manifest: str, top_k: int = 10) -> str:
    """Reduce a `name: description` manifest to a relevance-ranked shortlist.

    Scores each skill line against ``task_text`` with IDF-weighted token
    overlap and returns the ``top_k`` highest-scoring lines (score > 0),
    best-first, ties broken by original manifest order.

    Fail-open: returns ``manifest`` unchanged when there is nothing to trim
    (<= top_k lines), when no skill shares a discriminative term, or on any
    internal error. It must never raise and never shrink to an empty list.
    """
    try:
        lines = [ln for ln in manifest.splitlines() if ":" in ln]
        if len(lines) <= top_k:
            return manifest
        skill_tokens = [_tokens(ln) for ln in lines]
        n = len(lines)
        df: dict[str, int] = {}
        for toks in skill_tokens:
            for t in toks:
                df[t] = df.get(t, 0) + 1
        task_tokens = _tokens(task_text)
        scored: list[tuple[float, int, str]] = []
        for idx, (ln, toks) in enumerate(zip(lines, skill_tokens)):
            shared = task_tokens & toks
            score = sum(math.log(n / df[t]) for t in shared)  # df[t] >= 1 for shared
            scored.append((score, idx, ln))
        scored.sort(key=lambda s: (-s[0], s[1]))  # score desc, stable by original order
        kept = [ln for score, _idx, ln in scored if score > 0][:top_k]
        if not kept:
            return manifest
        return "\n".join(kept)
    except Exception:
        return manifest
