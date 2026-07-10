"""Tests for panel.sanitize — strips markdown injection vectors from
panelist rationale text before embedding in user-visible summary.

Parity with aggregate.sh's sanitize() function: strips image syntax,
link syntax, and backticks. These vectors could otherwise let a
prompt-injected DA backend inject clickable links or inline code into
the augmented AskUserQuestion text the user sees.
"""


def test_strips_image_syntax():
    from panel.sanitize import strip_markdown
    assert strip_markdown("see ![alt](http://evil.example.com/track.png) pixel") == "see  pixel"


def test_strips_link_syntax():
    from panel.sanitize import strip_markdown
    assert strip_markdown("[click](http://evil.example.com) here") == " here"


def test_strips_backticks():
    from panel.sanitize import strip_markdown
    assert strip_markdown("run `rm -rf /` now") == "run rm -rf / now"


def test_preserves_plain_text():
    from panel.sanitize import strip_markdown
    assert strip_markdown("a perfectly normal rationale.") == "a perfectly normal rationale."


def test_strips_combination():
    from panel.sanitize import strip_markdown
    src = "Check [docs](http://x) for `cmd` and ![pic](http://y) details"
    assert strip_markdown(src) == "Check  for cmd and  details"
