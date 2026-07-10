"""Subprocess-level tests for `python -m panel` exit-code propagation.

The CLI's main() returns int exit codes (0 / 1 / 2). Phase 2's __main__.py
called main() without sys.exit(), so process exit was always 0 even when
main() returned non-zero. These tests run the CLI as a subprocess and
assert the actual process exit code.
"""
import os
import subprocess
import sys
import textwrap
from pathlib import Path


SKILL_DIR = Path(__file__).resolve().parent.parent.parent
PYTHON = "/opt/homebrew/bin/python3.12"


def _run(args, cwd=SKILL_DIR):
    """Run `python -m panel <args>` as a subprocess. Returns (rc, stdout, stderr)."""
    proc = subprocess.run(
        [PYTHON, "-m", "panel", *args],
        cwd=str(cwd),
        capture_output=True,
        text=True,
    )
    return proc.returncode, proc.stdout, proc.stderr


def test_subprocess_exits_zero_on_valid_lint_config(tmp_path):
    cfg = tmp_path / "config.yml"
    cfg.write_text(textwrap.dedent("""
        version: 1
        panelists:
          - id: da
            role: DA
            enabled: true
            backend: nat-nim
            model: x
    """).strip() + "\n")
    rc, out, err = _run(["lint-config", "--config", str(cfg)])
    assert rc == 0, f"expected 0, got {rc}; stdout={out!r}; stderr={err!r}"
    assert "OK" in out


def test_subprocess_exits_one_on_missing_config(tmp_path):
    rc, out, err = _run(["lint-config", "--config", str(tmp_path / "no.yml")])
    assert rc == 1, f"expected 1, got {rc}; stdout={out!r}; stderr={err!r}"
    assert "CONFIG ERROR" in err


def test_subprocess_exits_one_on_invalid_config(tmp_path):
    cfg = tmp_path / "config.yml"
    cfg.write_text("panelists:\n  - id: x\n    enabled: true\n    backend: bogus\n")
    rc, out, err = _run(["lint-config", "--config", str(cfg)])
    assert rc == 1, f"expected 1, got {rc}; stdout={out!r}; stderr={err!r}"
    assert "CONFIG ERROR" in err


def test_subprocess_exits_one_on_dispatch_missing_persona(tmp_path):
    """Phase 3b: dispatch is real; missing persona is a caller-bug → exit 1."""
    cfg = tmp_path / "config.yml"
    cfg.write_text(textwrap.dedent("""
        version: 1
        panelists:
          - id: da
            role: DA
            enabled: true
            backend: nat-nim
            model: test-model
    """).strip() + "\n")
    rc, out, err = _run([
        "dispatch",
        "--panelist", "da",
        "--config", str(cfg),
        "--persona", str(tmp_path / "no-persona.md"),
        "--prompt-file", str(tmp_path / "no-prompt.txt"),
        "--output", str(tmp_path / "verdict.txt"),
    ])
    assert rc == 1, f"expected 1, got {rc}; stdout={out!r}; stderr={err!r}"
    assert "persona" in err.lower() or "missing" in err.lower()
