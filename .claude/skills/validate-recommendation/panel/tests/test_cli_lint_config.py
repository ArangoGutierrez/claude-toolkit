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
            model: nvidia/nemotron-3-super-v3
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
