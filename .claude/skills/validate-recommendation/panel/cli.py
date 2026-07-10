"""Top-level CLI dispatch for the panel package.

Subcommands shipped so far:
- aggregate         (Phase 3c — N-panelist JSON directive)
- lint-config       (Phase 3a — config validation)
- dispatch          (Phase 3b — langchain-provider-backed panelist dispatch)

Subcommands planned for later phases:
- record-userpick   (Phase 6)
- ls, show, label, stats, replay, gc   (Phase 6)
- tune              (Phase 7 — NAT Eval-backed)
"""
import argparse
import sys
from pathlib import Path


def _default_config_path() -> Path:
    return Path.home() / ".claude" / "panel" / "config.yml"


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        prog="panel", description="validate-recommendation panel CLI"
    )
    sub = parser.add_subparsers(dest="cmd", required=True)

    agg = sub.add_parser(
        "aggregate", help="Aggregate N-panelist verdicts into a JSON directive"
    )
    agg.add_argument(
        "--config", default=None,
        help="Path to config.yml (default: ~/.claude/panel/config.yml)",
    )
    agg.add_argument(
        "--verdicts-dir", required=True,
        help="Directory containing <panelist-id>.verdict files",
    )
    agg.add_argument(
        "--recommended-label", required=True,
        help="Label identifying the recommended option; threaded to severity layer (token interpolation into summary text is reserved for a future phase)",
    )
    agg.add_argument(
        "--question-id", default=None,
        help="Optional canonical id for this question; recorded in the decisions.jsonl telemetry row for later join",
    )

    lint = sub.add_parser("lint-config", help="Validate panel config.yml")
    lint.add_argument(
        "--config", default=None,
        help="Path to config.yml (default: ~/.claude/panel/config.yml)",
    )

    disp = sub.add_parser(
        "dispatch",
        help="Run one panelist via its configured backend (stub in Phase 3a)",
    )
    disp.add_argument("--panelist", required=True, help="Panelist id from config.yml")
    disp.add_argument(
        "--config", default=None,
        help="Path to config.yml (default: ~/.claude/panel/config.yml)",
    )
    disp.add_argument("--persona", required=True, help="Path to persona file")
    disp.add_argument(
        "--prompt-file", required=True, help="Templated user prompt body"
    )
    disp.add_argument("--output", required=True, help="Verdict file output path")

    args = parser.parse_args(argv)

    if args.cmd == "aggregate":
        from panel.aggregate import aggregate
        cfg_path = args.config or _default_config_path()
        print(aggregate(
            str(cfg_path), args.verdicts_dir, args.recommended_label,
            question_id=args.question_id,
        ))
        return 0

    if args.cmd == "lint-config":
        from panel.config import load_config, ConfigError
        cfg_path = args.config or _default_config_path()
        try:
            cfg = load_config(cfg_path)
        except ConfigError as e:
            print(f"CONFIG ERROR: {e}", file=sys.stderr)
            return 1
        enabled = [p for p in cfg.panelists if p.enabled]
        print(
            f"OK: {len(enabled)} enabled panelist(s) "
            f"(of {len(cfg.panelists)} configured)"
        )
        for p in enabled:
            extra = f"model={p.model}" if p.model else f"subagent={p.subagent_type}"
            print(f"  - {p.id} (role={p.role}, backend={p.backend}, {extra})")
        return 0

    if args.cmd == "dispatch":
        from panel.dispatch import dispatch
        return dispatch(
            panelist_id=args.panelist,
            config_path=args.config or _default_config_path(),
            persona_path=args.persona,
            prompt_file=args.prompt_file,
            output=args.output,
        )

    parser.error(f"unknown command: {args.cmd}")
    return 2
