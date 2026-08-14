"""Top-level CLI dispatch for the panel package.

Subcommands shipped so far:
- aggregate         (Phase 3c — N-panelist JSON directive)
- lint-config       (Phase 3a — config validation)
- dispatch          (Phase 3b — langchain-provider-backed panelist dispatch)
- build-prompt      (blinded panelist prompt body)
- stats             (per-panelist dissent-rate health metric)

Subcommands planned for later phases:
- record-userpick   (Phase 6)
- ls, show, label, replay, gc   (Phase 6)
- tune              (Phase 7 — NAT Eval-backed)
"""
import argparse
import sys
from pathlib import Path


def _default_config_path() -> Path:
    return Path.home() / ".claude" / "panel" / "config.yml"


def _persona_blind_problems(panelists) -> list[str]:
    """Report enabled seats whose `blind` flag contradicts their persona.

    A persona that asks for `CHOICE:` is a blinded persona — it is never told
    which option was recommended — so its seat must set `blind: true`. A
    persona that asks for `VERDICT:` judges a named recommendation, so its
    seat must not be blinded. A mismatch fails silently and totally at
    runtime: a claude-subagent reply is written to its verdict file verbatim,
    and `aggregate()` scores a file carrying no `VERDICT:` line as ERROR for
    that panelist, so the seat dies on every question. (On a nat-* backend
    `dispatch.py` performs the equivalent rewrite before the file is written.)

    This lives here rather than in `load_config` because it is a property of
    the persona files, not of the config document: `load_config` stays a pure
    parser, and an unblinded claude-subagent seat remains legal on its own.
    """
    from panel.personas import PersonaError, load_persona_by_role

    problems: list[str] = []
    for p in panelists:
        if not p.enabled:
            continue
        who = f"panelist '{p.id}' (role {p.role})"
        try:
            persona = load_persona_by_role(p.role)
        except PersonaError as e:
            problems.append(f"PERSONA/BLIND ERROR: {who} has no usable persona: {e}")
            continue
        wants_choice = "CHOICE:" in persona.system_prompt
        wants_verdict = "VERDICT:" in persona.system_prompt
        if wants_choice and not wants_verdict:
            if not p.blind:
                problems.append(
                    f"PERSONA/BLIND ERROR: {who} has a persona that demands a "
                    f"CHOICE: reply, so it must set blind: true"
                )
        elif wants_verdict and not wants_choice:
            if p.blind:
                problems.append(
                    f"PERSONA/BLIND ERROR: {who} has a persona that demands a "
                    f"VERDICT: reply, so it must not set blind: true"
                )
        else:
            problems.append(
                f"PERSONA/BLIND ERROR: {who} has a persona with no single output "
                f"contract: its system prompt must ask for exactly one of "
                f"CHOICE: or VERDICT:"
            )
    return problems


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

    bp = sub.add_parser(
        "build-prompt", help="Build a panelist prompt body (blinded per config)"
    )
    bp.add_argument("--panelist", required=True, help="Panelist id from config.yml")
    bp.add_argument(
        "--config", default=None,
        help="Path to config.yml (default: ~/.claude/panel/config.yml)",
    )
    bp.add_argument(
        "--question-file", required=True,
        help="JSON file: {question, options:[{label,description}], recommended_label, reasoning}",
    )
    bp.add_argument("--output", required=True, help="Prompt body output path")

    st = sub.add_parser("stats", help="Per-panelist dissent-rate health metric")
    st.add_argument(
        "--jsonl", default=None,
        help="Path to decisions.jsonl (default: ~/.claude/panel/decisions.jsonl)",
    )
    st.add_argument("--min-n", type=int, default=20, help="Minimum votes before flagging")

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
        problems = _persona_blind_problems(cfg.panelists)
        if problems:
            for line in problems:
                print(line, file=sys.stderr)
            return 1
        enabled = [p for p in cfg.panelists if p.enabled]
        print(
            f"OK: {len(enabled)} enabled panelist(s) "
            f"(of {len(cfg.panelists)} configured)"
        )
        for p in enabled:
            extra = f"model={p.model}" if p.model else f"subagent={p.subagent_type}"
            blind = ", blind" if p.blind else ""
            print(f"  - {p.id} (role={p.role}, backend={p.backend}, {extra}{blind})")
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

    if args.cmd == "build-prompt":
        import json as _json
        from panel.config import load_config
        from panel.prompt import build_prompt_body
        cfg = load_config(args.config or _default_config_path())
        match = [p for p in cfg.panelists if p.id == args.panelist]
        if not match:
            print(f"panel: no such panelist: {args.panelist}", file=sys.stderr)
            return 1
        payload = _json.loads(Path(args.question_file).read_text(encoding="utf-8"))
        blinded = match[0].blind
        body = build_prompt_body(
            payload["question"],
            [(o["label"], o["description"]) for o in payload["options"]],
            payload.get("recommended_label", ""),
            # A blinded panelist must never receive the reasoning. Drop it here;
            # build_prompt_body refuses the build outright if it arrives anyway.
            "" if blinded else payload.get("reasoning", "(no reasoning supplied)"),
            blind=blinded,
        )
        Path(args.output).write_text(body, encoding="utf-8")
        return 0

    if args.cmd == "stats":
        from panel.stats import load_rows, panelist_dissent_rates, health_flags
        jsonl = args.jsonl or (Path.home() / ".claude" / "panel" / "decisions.jsonl")
        rates = panelist_dissent_rates(load_rows(jsonl))
        flags = health_flags(rates, min_n=args.min_n)
        if not rates:
            print("no decisions recorded yet")
            return 0
        for pid in sorted(rates):
            s = rates[pid]
            print(
                f"  {pid:<14} n={s['n']:<5} overturns={s['overturns']:<5} "
                f"dissent-rate={s['dissent_rate'] * 100:5.1f}%  {flags[pid]}"
            )
        return 0

    parser.error(f"unknown command: {args.cmd}")
    return 2
