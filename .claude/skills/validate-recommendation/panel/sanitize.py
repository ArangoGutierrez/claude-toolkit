"""Sanitize markdown injection vectors from panelist text.

Parity with aggregate.sh's sanitize() function:
    sed -e 's/!\\[[^]]*\\]([^)]*)//g' \\
        -e 's/\\[[^]]*\\]([^)]*)//g' \\
        -e 's/`//g'

Applied to rationale + alternative text before embedding in the
user-visible Panel review summary. Defense in depth — format
compliance is the first line of defense; a prompt-injected DA backend
that does pass format validation might still try to inject HTML-ish
markdown.
"""
import re

# Image first (longest match) — !\[alt](url)
_IMAGE_RE = re.compile(r"!\[[^\]]*\]\([^)]*\)")
# Then link — [text](url)
_LINK_RE = re.compile(r"\[[^\]]*\]\([^)]*\)")
# Then backticks (any backtick character)
_BACKTICK_RE = re.compile(r"`")


def strip_markdown(text: str) -> str:
    """Remove image syntax, link syntax, and backticks from `text`."""
    text = _IMAGE_RE.sub("", text)
    text = _LINK_RE.sub("", text)
    text = _BACKTICK_RE.sub("", text)
    return text
