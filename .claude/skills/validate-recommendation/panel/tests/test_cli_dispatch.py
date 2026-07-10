"""CLI tests for `panel dispatch` after Phase 3b wiring.

The CLI's only job for dispatch is argparse → call dispatch(). We mock
panel.dispatch.dispatch and confirm the args land correctly. The dispatch
function itself is exercised by test_dispatch.py.
"""
import textwrap
from unittest.mock import patch


def _write_minimal_config(tmp_path):
    p = tmp_path / "config.yml"
    p.write_text(textwrap.dedent("""
        version: 1
        panelists:
          - id: da
            role: DA
            enabled: true
            backend: nat-nim
            model: test-model
    """).strip() + "\n")
    return p


def test_cli_dispatch_calls_dispatch_with_threaded_args(tmp_path):
    from panel.cli import main
    cfg = _write_minimal_config(tmp_path)
    persona = tmp_path / "p.md"
    persona.write_text("---\nrole: DA\n---\n# System prompt\nx\n# User prompt template\nq\n")
    prompt = tmp_path / "u.txt"
    prompt.write_text("Question: x?\n")
    out = tmp_path / "v.txt"

    with patch("panel.dispatch.dispatch", return_value=0) as mock_dispatch:
        rc = main([
            "dispatch",
            "--panelist", "da",
            "--config", str(cfg),
            "--persona", str(persona),
            "--prompt-file", str(prompt),
            "--output", str(out),
        ])
    assert rc == 0
    mock_dispatch.assert_called_once()
    kwargs = mock_dispatch.call_args.kwargs
    if not kwargs:
        args = mock_dispatch.call_args.args
        assert args[0] == "da"
        assert str(args[1]) == str(cfg)
        assert str(args[2]) == str(persona)
        assert str(args[3]) == str(prompt)
        assert str(args[4]) == str(out)
    else:
        assert kwargs["panelist_id"] == "da"
        assert str(kwargs["config_path"]) == str(cfg)
        assert str(kwargs["persona_path"]) == str(persona)
        assert str(kwargs["prompt_file"]) == str(prompt)
        assert str(kwargs["output"]) == str(out)


def test_cli_dispatch_returns_dispatch_exit_code(tmp_path):
    from panel.cli import main
    cfg = _write_minimal_config(tmp_path)
    persona = tmp_path / "p.md"
    persona.write_text("---\nrole: DA\n---\n# System prompt\nx\n# User prompt template\nq\n")
    prompt = tmp_path / "u.txt"
    prompt.write_text("q\n")
    out = tmp_path / "v.txt"

    with patch("panel.dispatch.dispatch", return_value=1):
        rc = main([
            "dispatch", "--panelist", "da", "--config", str(cfg),
            "--persona", str(persona), "--prompt-file", str(prompt),
            "--output", str(out),
        ])
    assert rc == 1


def test_cli_dispatch_uses_default_config_when_omitted(tmp_path):
    from panel.cli import main
    persona = tmp_path / "p.md"
    persona.write_text("---\nrole: DA\n---\n# System prompt\nx\n# User prompt template\nq\n")
    prompt = tmp_path / "u.txt"
    prompt.write_text("q\n")
    out = tmp_path / "v.txt"

    with patch("panel.dispatch.dispatch", return_value=0) as mock_dispatch:
        main([
            "dispatch", "--panelist", "da",
            "--persona", str(persona), "--prompt-file", str(prompt),
            "--output", str(out),
        ])
    kwargs = mock_dispatch.call_args.kwargs
    config_arg = kwargs.get("config_path") if kwargs else mock_dispatch.call_args.args[1]
    assert ".claude/panel/config.yml" in str(config_arg)
