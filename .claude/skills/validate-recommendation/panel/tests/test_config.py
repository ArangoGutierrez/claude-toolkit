"""Tests for panel.config — YAML config loader.

Covers:
- Default config (DA enabled, PE/QA opt-in) parses correctly.
- Odd-N invariant rejects 0 or 2 enabled panelists.
- 1 and 3 enabled panelists accepted.
- Unknown backend rejected at load time.
- Optional sections default to spec-defined values when omitted.
- nat-* backend requires 'model'; claude-subagent backend requires 'subagent_type'.
- severity.hard_threshold whitelist, failure_mode whitelist, max_cycles bounds.
- Missing file raises ConfigError with a clear message.
"""
import textwrap

import pytest


def _write_yaml(tmp_path, content):
    p = tmp_path / "config.yml"
    p.write_text(textwrap.dedent(content).strip() + "\n")
    return p


def test_load_default_config_only_da_enabled(tmp_path):
    from panel.config import load_config
    cfg = _write_yaml(tmp_path, """
        version: 1
        panelists:
          - id: da-nemotron
            role: DA
            enabled: true
            backend: nat-nim
            model: example-org/example-model
          - id: pe
            role: PE
            enabled: false
            backend: claude-subagent
            subagent_type: principal-engineer
          - id: qa
            role: QA
            enabled: false
            backend: claude-subagent
            subagent_type: qa-engineer
    """)
    c = load_config(cfg)
    enabled = [p for p in c.panelists if p.enabled]
    assert len(enabled) == 1
    assert enabled[0].id == "da-nemotron"
    assert enabled[0].backend == "nat-nim"
    assert enabled[0].model == "example-org/example-model"


def test_reject_even_enabled_count(tmp_path):
    from panel.config import load_config, ConfigError
    cfg = _write_yaml(tmp_path, """
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
    """)
    with pytest.raises(ConfigError, match=r"odd"):
        load_config(cfg)


def test_accept_three_enabled(tmp_path):
    from panel.config import load_config
    cfg = _write_yaml(tmp_path, """
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
            backend: claude-subagent
            subagent_type: qa-engineer
    """)
    c = load_config(cfg)
    assert sum(1 for p in c.panelists if p.enabled) == 3


def test_reject_zero_enabled(tmp_path):
    from panel.config import load_config, ConfigError
    cfg = _write_yaml(tmp_path, """
        version: 1
        panelists:
          - id: da
            role: DA
            enabled: false
            backend: nat-nim
            model: x
    """)
    with pytest.raises(ConfigError, match=r"at least one"):
        load_config(cfg)


def test_reject_empty_panelists_list(tmp_path):
    """An empty 'panelists: []' list is rejected at load time (separate branch from zero-enabled)."""
    from panel.config import load_config, ConfigError
    cfg = _write_yaml(tmp_path, """
        version: 1
        panelists: []
    """)
    with pytest.raises(ConfigError, match=r"non-empty"):
        load_config(cfg)


def test_reject_missing_panelists_key(tmp_path):
    """A YAML config with no 'panelists' key is rejected (covers `raw.get('panelists') or []` fallback)."""
    from panel.config import load_config, ConfigError
    cfg = _write_yaml(tmp_path, """
        version: 1
    """)
    with pytest.raises(ConfigError, match=r"non-empty"):
        load_config(cfg)


def test_reject_unknown_backend(tmp_path):
    from panel.config import load_config, ConfigError
    cfg = _write_yaml(tmp_path, """
        version: 1
        panelists:
          - id: x
            role: DA
            enabled: true
            backend: not-a-real-backend
    """)
    with pytest.raises(ConfigError, match=r"backend must be one of"):
        load_config(cfg)


def test_nat_backend_requires_model(tmp_path):
    from panel.config import load_config, ConfigError
    cfg = _write_yaml(tmp_path, """
        version: 1
        panelists:
          - id: da
            role: DA
            enabled: true
            backend: nat-nim
    """)
    with pytest.raises(ConfigError, match=r"model"):
        load_config(cfg)


def test_subagent_backend_requires_subagent_type(tmp_path):
    from panel.config import load_config, ConfigError
    cfg = _write_yaml(tmp_path, """
        version: 1
        panelists:
          - id: pe
            role: PE
            enabled: true
            backend: claude-subagent
    """)
    with pytest.raises(ConfigError, match=r"subagent_type"):
        load_config(cfg)


def test_defaults_for_optional_sections(tmp_path):
    from panel.config import load_config
    cfg = _write_yaml(tmp_path, """
        version: 1
        panelists:
          - id: da
            role: DA
            enabled: true
            backend: nat-nim
            model: x
    """)
    c = load_config(cfg)
    assert c.severity.hard_threshold == "majority"
    assert c.severity.rationale_gate.requires_principle_or_alternative is True
    assert c.failure_mode.on_panelist_error == "auto"
    assert c.re_brainstorm.enabled is True
    assert c.re_brainstorm.max_cycles == 2
    assert c.telemetry.jsonl == "~/.claude/panel/decisions.jsonl"
    assert c.telemetry.otel_endpoint is None


def test_severity_threshold_whitelist(tmp_path):
    from panel.config import load_config, ConfigError
    cfg = _write_yaml(tmp_path, """
        version: 1
        panelists:
          - id: da
            role: DA
            enabled: true
            backend: nat-nim
            model: x
        severity:
          hard_threshold: bogus
    """)
    with pytest.raises(ConfigError, match=r"hard_threshold"):
        load_config(cfg)


def test_failure_mode_whitelist(tmp_path):
    from panel.config import load_config, ConfigError
    cfg = _write_yaml(tmp_path, """
        version: 1
        panelists:
          - id: da
            role: DA
            enabled: true
            backend: nat-nim
            model: x
        failure_mode:
          on_panelist_error: nope
    """)
    with pytest.raises(ConfigError, match=r"on_panelist_error"):
        load_config(cfg)


@pytest.mark.parametrize("max_cycles,should_raise", [
    (-1, True),
    (0, False),
    (5, False),
    (6, True),
])
def test_max_cycles_range_boundaries(tmp_path, max_cycles, should_raise):
    """max_cycles in [0, 5] inclusive. Boundary-precise to catch off-by-one mutations."""
    from panel.config import load_config, ConfigError
    cfg = _write_yaml(tmp_path, f"""
        version: 1
        panelists:
          - id: da
            role: DA
            enabled: true
            backend: nat-nim
            model: x
        re_brainstorm:
          max_cycles: {max_cycles}
    """)
    if should_raise:
        with pytest.raises(ConfigError, match=r"max_cycles"):
            load_config(cfg)
    else:
        c = load_config(cfg)
        assert c.re_brainstorm.max_cycles == max_cycles


def test_missing_config_file(tmp_path):
    from panel.config import load_config, ConfigError
    with pytest.raises(ConfigError, match=r"config file missing"):
        load_config(tmp_path / "does-not-exist.yml")


def test_malformed_yaml(tmp_path):
    from panel.config import load_config, ConfigError
    p = tmp_path / "config.yml"
    p.write_text("panelists: [oops\n  - id: x\n")
    with pytest.raises(ConfigError, match=r"YAML"):
        load_config(p)


def test_panelist_id_required(tmp_path):
    from panel.config import load_config, ConfigError
    cfg = _write_yaml(tmp_path, """
        version: 1
        panelists:
          - role: DA
            enabled: true
            backend: nat-nim
            model: x
    """)
    with pytest.raises(ConfigError, match=r"id"):
        load_config(cfg)
