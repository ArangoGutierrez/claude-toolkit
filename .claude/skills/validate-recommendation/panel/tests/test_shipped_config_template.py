"""The shipped config template IS the default panel — pin its composition.

`.claude/panel/config.yml.template` is what an operator copies to
`~/.claude/panel/config.yml`, so its contents are the shipped default, not
documentation. A template that parses fine but ships a composition nobody
intended stays invisible until a live dispatch, and by then the wrong
panelists have already voted.

These tests read the template in THIS worktree, never the deployed copy at
~/.claude/panel/config.yml — grading the deployed file would grade an
artifact the branch does not contain.
"""
from pathlib import Path

SKILL_DIR = Path(__file__).resolve().parent.parent.parent
TEMPLATE = SKILL_DIR.parent.parent / "panel" / "config.yml.template"


def test_template_exists_at_the_documented_path():
    assert TEMPLATE.is_file(), f"shipped template missing: {TEMPLATE}"


def test_template_ships_three_enabled_panelists_da_pe_qa():
    from panel.config import load_config
    cfg = load_config(TEMPLATE)
    enabled = [p.id for p in cfg.panelists if p.enabled]
    assert enabled == ["da", "pe", "qa"]
    # Odd N is what makes a lone dissent a SOFT-DISSENT instead of a hard
    # interrupt; an even panel is rejected by load_config, but a silent drop
    # back to N=1 would still lint clean.
    assert len(enabled) % 2 == 1


def test_template_blinds_exactly_pe_and_qa():
    from panel.config import load_config
    cfg = load_config(TEMPLATE)
    by_id = {p.id: p for p in cfg.panelists}
    assert [p.id for p in cfg.panelists if p.enabled and p.blind] == ["pe", "qa"]
    # The DA argues against a named recommendation, so it must keep seeing it.
    assert by_id["da"].blind is False


def test_template_passes_lint_config(capsys):
    """The shipped template must satisfy the persona/blind cross-check.

    Enabling a claude-subagent seat without `blind: true` gives it the
    unblinded prompt body while its persona demands `CHOICE:`. Its reply
    carries no `VERDICT:` line, and `aggregate()` scores that as ERROR for
    the panelist on every question.
    """
    from panel.cli import main
    rc = main(["lint-config", "--config", str(TEMPLATE)])
    captured = capsys.readouterr()
    assert rc == 0, f"stderr={captured.err!r}"
    assert "OK: 3 enabled panelist(s) (of 3 configured)" in captured.out
