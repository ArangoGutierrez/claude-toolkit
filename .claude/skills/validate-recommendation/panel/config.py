"""Load and validate ~/.claude/panel/config.yml.

YAML-based config (NAT-compatible). Enforces the odd-N invariant on the
COUNT OF ENABLED PANELISTS (not total). Whitelists backend strings so
typos surface at load time, not dispatch time. nat-* backends require
'model'; claude-subagent backend requires 'subagent_type'.
"""
from __future__ import annotations
from dataclasses import dataclass, field
from pathlib import Path
from typing import Literal

import yaml

VALID_BACKENDS = {"nat-nim", "nat-anthropic", "nat-openai", "claude-subagent"}
VALID_HARD_THRESHOLDS = {"majority", "supermajority"}
VALID_FAILURE_MODES = {"strict", "graceful", "auto"}


class ConfigError(Exception):
    pass


@dataclass
class Panelist:
    id: str
    role: str
    enabled: bool
    backend: str
    model: str = ""           # required for nat-* backends
    subagent_type: str = ""   # required for claude-subagent backend
    max_tokens: int = 32768
    temperature: float = 0.3
    timeout_seconds: int = 60


@dataclass
class RationaleGate:
    requires_principle_or_alternative: bool = True
    principle_patterns: list[str] = field(default_factory=lambda: [
        r"\b(YAGNI|atomicity|TDD|priority order|conventions?)\b",
        r"\bviolates? (the )?(principle|convention|rule)\b",
        r"\bbreaks?\b.*\b(rule|convention|invariant)\b",
    ])


@dataclass
class Severity:
    hard_threshold: Literal["majority", "supermajority"] = "majority"
    rationale_gate: RationaleGate = field(default_factory=RationaleGate)


@dataclass
class FailureMode:
    on_panelist_error: Literal["strict", "graceful", "auto"] = "auto"


@dataclass
class ReBrainstorm:
    enabled: bool = True
    max_cycles: int = 2


@dataclass
class Telemetry:
    jsonl: str = "~/.claude/panel/decisions.jsonl"
    otel_endpoint: str | None = None


@dataclass
class Config:
    version: str
    panelists: list[Panelist]
    severity: Severity = field(default_factory=Severity)
    failure_mode: FailureMode = field(default_factory=FailureMode)
    re_brainstorm: ReBrainstorm = field(default_factory=ReBrainstorm)
    telemetry: Telemetry = field(default_factory=Telemetry)


def load_config(path: str | Path) -> Config:
    path = Path(path).expanduser()
    if not path.is_file():
        raise ConfigError(f"config file missing: {path}")
    try:
        raw = yaml.safe_load(path.read_text(encoding="utf-8")) or {}
    except yaml.YAMLError as e:
        raise ConfigError(f"config YAML parse error: {e}") from e

    panelists_raw = raw.get("panelists") or []
    if not panelists_raw:
        raise ConfigError("config: panelists must be non-empty")

    panelists: list[Panelist] = []
    for i, p in enumerate(panelists_raw):
        pid = p.get("id")
        if not pid:
            raise ConfigError(f"config: panelists[{i}] missing 'id'")
        backend = p.get("backend")
        if backend not in VALID_BACKENDS:
            raise ConfigError(
                f"config: panelists[{i}].backend must be one of "
                f"{sorted(VALID_BACKENDS)}, got '{backend}'"
            )
        model = p.get("model", "")
        subagent_type = p.get("subagent_type", "")
        if backend.startswith("nat-") and not model:
            raise ConfigError(
                f"config: panelists[{i}].model is required for backend '{backend}'"
            )
        if backend == "claude-subagent" and not subagent_type:
            raise ConfigError(
                f"config: panelists[{i}].subagent_type is required for "
                f"backend 'claude-subagent'"
            )
        panelists.append(Panelist(
            id=pid,
            role=p.get("role", ""),
            enabled=bool(p.get("enabled", False)),
            backend=backend,
            model=model,
            subagent_type=subagent_type,
            max_tokens=int(p.get("max_tokens", 32768)),
            temperature=float(p.get("temperature", 0.3)),
            timeout_seconds=int(p.get("timeout_seconds", 60)),
        ))

    enabled_count = sum(1 for p in panelists if p.enabled)
    if enabled_count == 0:
        raise ConfigError("config: at least one panelist must be enabled")
    if enabled_count % 2 == 0:
        raise ConfigError(
            f"config: enabled-panelist count must be odd (got {enabled_count}). "
            "Even N produces tie-prone votes; the odd-N invariant is required."
        )

    severity_raw = raw.get("severity") or {}
    rg_raw = severity_raw.get("rationale_gate") or {}
    severity = Severity(
        hard_threshold=severity_raw.get("hard_threshold", "majority"),
        rationale_gate=RationaleGate(
            requires_principle_or_alternative=rg_raw.get(
                "requires_principle_or_alternative", True
            ),
            principle_patterns=rg_raw.get(
                "principle_patterns", RationaleGate().principle_patterns
            ),
        ),
    )
    if severity.hard_threshold not in VALID_HARD_THRESHOLDS:
        raise ConfigError(
            f"severity.hard_threshold must be one of "
            f"{sorted(VALID_HARD_THRESHOLDS)}, got '{severity.hard_threshold}'"
        )

    fm_raw = raw.get("failure_mode") or {}
    failure_mode = FailureMode(
        on_panelist_error=fm_raw.get("on_panelist_error", "auto")
    )
    if failure_mode.on_panelist_error not in VALID_FAILURE_MODES:
        raise ConfigError(
            f"failure_mode.on_panelist_error must be one of "
            f"{sorted(VALID_FAILURE_MODES)}, got '{failure_mode.on_panelist_error}'"
        )

    rb_raw = raw.get("re_brainstorm") or {}
    re_brainstorm = ReBrainstorm(
        enabled=bool(rb_raw.get("enabled", True)),
        max_cycles=int(rb_raw.get("max_cycles", 2)),
    )
    if not (0 <= re_brainstorm.max_cycles <= 5):
        raise ConfigError(
            f"re_brainstorm.max_cycles must be in [0, 5], got {re_brainstorm.max_cycles}"
        )

    tel_raw = raw.get("telemetry") or {}
    telemetry = Telemetry(
        jsonl=tel_raw.get("jsonl", "~/.claude/panel/decisions.jsonl"),
        otel_endpoint=tel_raw.get("otel_endpoint"),
    )

    return Config(
        version=str(raw.get("version", "1")),
        panelists=panelists,
        severity=severity,
        failure_mode=failure_mode,
        re_brainstorm=re_brainstorm,
        telemetry=telemetry,
    )
