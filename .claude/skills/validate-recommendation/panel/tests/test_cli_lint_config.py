"""Tests for panel.cli lint-config and dispatch subcommand registration.

dispatch is a stub here (real NAT integration ships in Phase 3b). The
test verifies the subparser is registered and returns a clear
'not-implemented-here' exit code so an accidental dispatch call doesn't
fail silently.
"""
import textwrap

import pytest


def _write_config(tmp_path, content):
    p = tmp_path / "config.yml"
    p.write_text(textwrap.dedent(content).strip() + "\n")
    return p


def test_lint_config_ok_for_valid_single_panelist(tmp_path, capsys):
    from panel.cli import main
    cfg = _write_config(tmp_path, """
        version: 1
        panelists:
          - id: da-nemotron
            role: DA
            enabled: true
            backend: nat-nim
            model: example-org/example-model
    """)
    rc = main(["lint-config", "--config", str(cfg)])
    out = capsys.readouterr().out
    assert rc == 0
    assert "OK" in out
    assert "da-nemotron" in out


def test_lint_config_reports_error_on_even_enabled(tmp_path, capsys):
    from panel.cli import main
    cfg = _write_config(tmp_path, """
        version: 1
        panelists:
          - id: a
            role: DA
            enabled: true
            backend: nat-nim
            model: x
          - id: b
            role: PE
            enabled: true
            backend: claude-subagent
            subagent_type: principal-engineer
    """)
    rc = main(["lint-config", "--config", str(cfg)])
    captured = capsys.readouterr()
    assert rc != 0
    combined = captured.out + captured.err
    assert "CONFIG ERROR" in combined or "ConfigError" in combined or "odd" in combined.lower()


def test_lint_config_reports_error_on_missing_file(tmp_path, capsys):
    from panel.cli import main
    rc = main(["lint-config", "--config", str(tmp_path / "nope.yml")])
    captured = capsys.readouterr()
    assert rc != 0
    combined = captured.out + captured.err
    assert "CONFIG ERROR" in combined or "missing" in combined.lower()


# --- persona/blind cross-check -------------------------------------------
#
# A seat's `blind` flag and its persona's output contract are two halves of
# one decision, written in two files. When they disagree the failure is
# silent and total: dispatch.py rewrites any reply lacking a VERDICT line to
# `VERDICT: ERROR`, so an unblinded seat whose persona demands CHOICE dies on
# every question while the config still lints clean. lint-config is the only
# place both halves are visible at once.
#
# The check reads the REAL personas/ directory shipped next to panel/, so
# these configs use the real roles: DA's persona demands `VERDICT:`, PE's and
# QA's demand `CHOICE:`.


def test_lint_config_rejects_choice_persona_without_blind(tmp_path, capsys):
    from panel.cli import main
    cfg = _write_config(tmp_path, """
        version: 1
        panelists:
          - id: da
            role: DA
            enabled: true
            backend: nat-nim
            model: x
          - id: pe
            role: PE
            enabled: true
            backend: claude-subagent
            subagent_type: principal-engineer
          - id: qa
            role: QA
            enabled: true
            blind: true
            backend: claude-subagent
            subagent_type: qa-engineer
    """)
    rc = main(["lint-config", "--config", str(cfg)])
    captured = capsys.readouterr()
    assert rc == 1
    assert (
        "PERSONA/BLIND ERROR: panelist 'pe' (role PE) has a persona that "
        "demands a CHOICE: reply, so it must set blind: true"
    ) in captured.err
    # qa is correctly blinded; naming it too would make the report useless.
    assert "panelist 'qa'" not in captured.err
    # No green light on a rejected config.
    assert "OK:" not in captured.out


def test_lint_config_accepts_choice_persona_with_blind(tmp_path, capsys):
    from panel.cli import main
    cfg = _write_config(tmp_path, """
        version: 1
        panelists:
          - id: da
            role: DA
            enabled: true
            backend: nat-nim
            model: x
          - id: pe
            role: PE
            enabled: true
            blind: true
            backend: claude-subagent
            subagent_type: principal-engineer
          - id: qa
            role: QA
            enabled: true
            blind: true
            backend: claude-subagent
            subagent_type: qa-engineer
    """)
    rc = main(["lint-config", "--config", str(cfg)])
    captured = capsys.readouterr()
    assert rc == 0, f"stderr={captured.err!r}"
    assert "OK: 3 enabled panelist(s) (of 3 configured)" in captured.out
    assert (
        "  - pe (role=PE, backend=claude-subagent, "
        "subagent=principal-engineer, blind)"
    ) in captured.out


def test_lint_config_rejects_verdict_persona_marked_blind(tmp_path, capsys):
    """The mirror case: blinding a seat whose persona replies with VERDICT.

    Such a seat gets no recommendation to hold or overturn, so its verdict is
    an opinion on a question it was never asked.
    """
    from panel.cli import main
    cfg = _write_config(tmp_path, """
        version: 1
        panelists:
          - id: da
            role: DA
            enabled: true
            blind: true
            backend: claude-subagent
            subagent_type: adversarial-critic
    """)
    rc = main(["lint-config", "--config", str(cfg)])
    captured = capsys.readouterr()
    assert rc == 1
    assert (
        "PERSONA/BLIND ERROR: panelist 'da' (role DA) has a persona that "
        "demands a VERDICT: reply, so it must not set blind: true"
    ) in captured.err


def test_lint_config_reports_missing_persona_without_traceback(
    tmp_path, capsys, personas_dir
):
    from panel.cli import main
    cfg = _write_config(tmp_path, """
        version: 1
        panelists:
          - id: ghost
            role: GHOST
            enabled: true
            backend: claude-subagent
            subagent_type: general-purpose
    """)
    rc = main(["lint-config", "--config", str(cfg)])
    captured = capsys.readouterr()
    assert rc == 1
    assert (
        f"PERSONA/BLIND ERROR: panelist 'ghost' (role GHOST) has no usable "
        f"persona: persona file missing: {personas_dir / 'ghost.md'}"
    ) in captured.err
    assert "Traceback" not in captured.err


def test_lint_config_ignores_a_disabled_panelists_persona(tmp_path, capsys):
    """A disabled seat is never dispatched, so its persona cannot mismatch.

    Checking every configured panelist instead of every ENABLED one would
    make the shipped opt-in rows unlintable.
    """
    from panel.cli import main
    cfg = _write_config(tmp_path, """
        version: 1
        panelists:
          - id: da
            role: DA
            enabled: true
            backend: nat-nim
            model: x
          - id: pe
            role: PE
            enabled: false
            backend: claude-subagent
            subagent_type: principal-engineer
    """)
    rc = main(["lint-config", "--config", str(cfg)])
    captured = capsys.readouterr()
    assert rc == 0, f"stderr={captured.err!r}"
    assert "panelist 'pe'" not in captured.err
    assert "OK: 1 enabled panelist(s) (of 2 configured)" in captured.out


def test_dispatch_subparser_registered(capsys):
    """dispatch --help works (subparser registration check)."""
    from panel.cli import main
    with pytest.raises(SystemExit) as excinfo:
        main(["dispatch", "--help"])
    # argparse exits 0 on --help
    assert excinfo.value.code == 0
    out = capsys.readouterr().out
    assert "--panelist" in out
    assert "--output" in out
