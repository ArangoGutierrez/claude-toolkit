from __future__ import annotations

import argparse
import contextlib
import json
import os
import re
import signal
import sys
import threading
from pathlib import Path
from typing import Literal

from pydantic import BaseModel, Field

from tool.agentic import agentic_run, ValidationOutcome
from tool.tools import readonly_tools
from tool.routing import rank_manifest
from tool.verify import validate_checklist
from tool.errors import EngineError

PASSTHROUGH_PREFIX = "KICKOFF_PASSTHROUGH:"
_DEFAULT_SKILLS_DIR = "~/.claude/skills"
# Public catalog form (OpenRouter ID); private deploys override via the
# KICKOFF_MODEL env (settings.json env block).
_DEFAULT_MODEL = "nvidia/nemotron-3-ultra-550b-a55b:free"

_SYSTEM = (
    "You are a prompt compiler. Inspect the repository with the read-only tools, "
    "then call submit_result. enriched_prompt: a tightened, scoped restatement of "
    "the task (clarify scope and implicit requirements; do NOT invent features). "
    "intent: 1-2 sentences on why this task exists, who or what consumes the result, "
    "and what it enables — derive it from the task text and the files you read; if no "
    "motivation is stated, say what the change mechanically enables (which component "
    "consumes the output), never an invented business reason. "
    "boundaries: explicit out-of-scope items or don't-dos implied by the task and the "
    "repo, each concrete and checkable (e.g. 'do not modify the public API in pkg/x'), "
    "never vague scoping prose. "
    "Keep every field task-specific: no generic behavioral advice such as 'be concise', "
    "'verify your work', or 'act autonomously' — the agent consuming this prompt already "
    "has standing instructions, and repeating them degrades its output. "
    "applicable_skills: names drawn ONLY from the supplied skill list. "
    "verification_checklist: a list of checks, each with a 'description' and a single "
    "runnable shell 'command' (ONE command only — no pipes, redirects, '&&' or ';', no "
    "inline 'python -c' scripts). Use 'python3' (never bare 'python') and prefer direct "
    "runners like 'pytest', 'go test', 'go build', 'golangci-lint run'. Each command must "
    "run from the repo root using tooling actually present (call detect_build_tooling). "
    "execution_hint: 'orchestrate' if "
    "the task is multi-task and parallelizable across disjoint paths, else 'solo'."
)

_SYSTEM_CHIEF_SUFFIX = (
    " You are compiling for an orchestrator that dispatches parallel subagents. "
    "When the task decomposes into independent pieces, also fill dispatch_plan: 2-6 tasks, "
    "each with a unique title, a type, owns (>=1 glob naming that task's exclusive write "
    "paths; owns sets must be pairwise disjoint across tasks — put read-shared paths such "
    "as go.mod in shared, never in owns), deps (titles of tasks that must land first), "
    "brief (2-4 task-specific sentences: what and why), and acceptance (checks obeying the "
    "same single-command rules as verification_checklist, runnable from the repo root). "
    "Set execution_hint='orchestrate' if and only if dispatch_plan has 2 or more tasks; a "
    "task too small to decompose keeps an empty dispatch_plan and execution_hint='solo'."
)


class Check(BaseModel):
    description: str = Field(description="What this check verifies")
    command: str = Field(description="A single runnable shell command — ONE command, no pipes, redirects, '&&', ';', or inline 'python -c'. Use python3 (not bare python) and direct runners like pytest, go test, go build.")


class DispatchTask(BaseModel):
    title: str = Field(description="Short imperative task title; unique within the plan")
    type: Literal["feat", "fix", "chore", "docs", "test", "refactor"] = "feat"
    owns: list[str] = Field(description="Exclusive write globs; >=1; pairwise-disjoint across tasks")
    deps: list[str] = Field(default_factory=list, description="Titles of tasks that must land first")
    brief: str = Field(default="", description="2-4 task-specific sentences: what to build and why")
    acceptance: list[Check] = Field(default_factory=list)


class KickoffResult(BaseModel):
    enriched_prompt: str = Field(description="Scoped restatement of the task")
    intent: str = Field(default="", description="Why this task exists, who/what consumes the result, what it enables — from the task text and files read only")
    boundaries: list[str] = Field(default_factory=list, description="Explicit out-of-scope items / don't-dos; each concrete and checkable")
    applicable_skills: list[str] = Field(default_factory=list)
    verification_checklist: list[Check] = Field(default_factory=list)
    execution_hint: Literal["solo", "orchestrate"] = "solo"
    dispatch_plan: list[DispatchTask] = Field(default_factory=list)
    shared: list[str] = Field(default_factory=list)


def build_manifest(skills_dir: Path) -> str:
    skills_dir = Path(skills_dir).expanduser()
    lines: list[str] = []
    for skill_md in sorted(skills_dir.glob("*/SKILL.md")):
        name, desc = _parse_frontmatter(skill_md.read_text(encoding="utf-8"))
        if name:
            lines.append(f"{name}: {desc}".rstrip())
    return "\n".join(lines)


def _parse_frontmatter(text: str) -> tuple[str, str]:
    if not text.startswith("---"):
        return "", ""
    end = text.find("\n---", 3)
    fm = text[3:end] if end != -1 else ""
    name = ""
    desc = ""
    m = re.search(r"^name:\s*(.+)$", fm, re.MULTILINE)
    if m:
        name = m.group(1).strip()
    m = re.search(r"^description:\s*(.*)$", fm, re.MULTILINE)
    if m:
        first = m.group(1).strip()
        if first in (">", "|", ">-", "|-"):  # folded/literal block
            block = fm[m.end():].splitlines()
            folded = []
            for ln in block:
                if ln.strip() and (ln.startswith(" ") or ln.startswith("\t")):
                    folded.append(ln.strip())
                elif ln.strip() == "":
                    continue
                else:
                    break
            desc = " ".join(folded)
        else:
            desc = first
    return name, desc


def _glob_root(g: str) -> str:
    out: list[str] = []
    for seg in g.split("/"):
        if "*" in seg:
            break
        if seg:
            out.append(seg)
    return "/".join(out)


def _plan_problems(result: dict) -> list[str]:
    plan = result.get("dispatch_plan") or []
    problems: list[str] = []
    titles = [t.get("title", "") for t in plan]
    if len(set(titles)) != len(titles):
        problems.append("dispatch_plan titles must be unique")
    for t in plan:
        if not t.get("owns"):
            problems.append(f"task {t.get('title', '?')!r}: owns must contain at least one glob")
    pairs = [(t.get("title", "?"), _glob_root(g)) for t in plan for g in t.get("owns", [])]
    for i in range(len(pairs)):
        for j in range(i + 1, len(pairs)):
            (ta, ra), (tb, rb) = pairs[i], pairs[j]
            if ta == tb:
                continue
            if ra == rb or not ra or not rb or ra.startswith(rb + "/") or rb.startswith(ra + "/"):
                problems.append(f"owns overlap between {ta!r} and {tb!r}: {ra or '**'!r} vs {rb or '**'!r}")
    known = set(titles)
    for t in plan:
        for d in t.get("deps", []):
            if d not in known:
                problems.append(f"task {t.get('title', '?')!r}: dep {d!r} is not a task title")
    graph = {t.get("title", ""): [d for d in t.get("deps", []) if d in known] for t in plan}
    state: dict[str, int] = {}

    def _visit(n: str) -> bool:
        if state.get(n) == 1:
            return True
        if state.get(n) == 2:
            return False
        state[n] = 1
        cyc = any(_visit(d) for d in graph.get(n, []))
        state[n] = 2
        return cyc

    if any(_visit(n) for n in graph):
        problems.append("dispatch_plan deps contain a cycle")
    hint = result.get("execution_hint", "solo")
    if len(plan) >= 2 and hint != "orchestrate":
        problems.append("execution_hint must be 'orchestrate' when dispatch_plan has >=2 tasks")
    if len(plan) == 1 and hint == "orchestrate":
        problems.append("a 1-task dispatch_plan is not orchestration: empty the plan (solo) or split further")
    return problems


def make_validator(root: Path, profile: str = "standard"):
    def validator(result: dict) -> ValidationOutcome:
        checks = result.get("verification_checklist", [])
        commands = [c.get("command", "") for c in checks]
        verdicts = validate_checklist(commands, root)
        annotated = []
        problems = []
        for chk, verdict in zip(checks, verdicts):
            annotated.append({**chk, "status": verdict.status, "detail": verdict.detail})
            if verdict.status in ("broken", "rejected"):
                problems.append(f"- {chk.get('command', '')!r}: {verdict.status} ({verdict.detail})")
        result = {**result, "verification_checklist": annotated}
        plan_problems: list[str] = []
        if profile == "chief":
            annotated_plan = []
            for t in result.get("dispatch_plan") or []:
                acc = t.get("acceptance", [])
                cmds = [c.get("command", "") for c in acc]
                vs = validate_checklist(cmds, root) if cmds else []
                t = {**t, "acceptance": [
                    {**c, "status": v.status, "detail": v.detail} for c, v in zip(acc, vs)]}
                annotated_plan.append(t)
                for c in t["acceptance"]:
                    if c.get("status") in ("broken", "rejected"):
                        plan_problems.append(
                            f"- task {t.get('title', '?')!r} acceptance {c.get('command', '')!r}: "
                            f"{c['status']} ({c.get('detail', '')})")
            result = {**result, "dispatch_plan": annotated_plan}
            plan_problems.extend(_plan_problems(result))
        missing = []
        if not str(result.get("intent") or "").strip():
            missing.append("intent")
        if not result.get("boundaries"):
            missing.append("boundaries")
        if not problems and not missing and not plan_problems:
            return ValidationOutcome(accept=True, feedback="", result=result)
        parts = []
        if problems:
            parts.append(
                "These verification checks did not run cleanly. Replace each with a single "
                "runnable shell command (no pipes, redirects, '&&' or ';') that uses tooling "
                "present in the repo; keep the descriptions you can keep:\n" + "\n".join(problems))
        if missing:
            desc_parts = []
            if "intent" in missing:
                desc_parts.append("intent: 1-2 sentences on why this task exists and what consumes its result.")
            if "boundaries" in missing:
                desc_parts.append("boundaries: concrete out-of-scope items / don't-dos drawn from the task and repo.")
            parts.append(
                "Also supply the missing field(s): " + ", ".join(missing) + ". " + " ".join(desc_parts))
        if plan_problems:
            parts.append(
                "The dispatch plan has structural problems; fix them while keeping the valid "
                "tasks (owns must be pairwise disjoint, deps must name other tasks, acceptance "
                "commands must run from the repo root):\n" + "\n".join(plan_problems))
        return ValidationOutcome(accept=False, feedback="\n\n".join(parts), result=result)
    return validator


def _format_budget(k: int) -> str:
    """Render a thousands-of-tokens budget as the compact string the
    budget-governor Stop hook expects on its `^Budget: <N|N.Nk|N.Nm>` grep."""
    if k % 1000 == 0:
        return f"{k // 1000}m"
    if k > 1000:
        return f"{k / 1000:.1f}m"
    return f"{k}k"


def _budget_for_plan(plan: list) -> str:
    """Deterministic token budget for a kickoff: scales with dispatch_plan size
    (200k base + 200k/task, capped at 2m) for a compiled orchestration plan;
    a flat 300k for solo/standard kickoffs (empty plan)."""
    n = len(plan)
    if n >= 2:
        return _format_budget(min(200 + 200 * n, 2000))
    return _format_budget(300)


def render(result: dict, manifest: str, mode: str) -> str:
    valid = {ln.split(":", 1)[0] for ln in manifest.splitlines() if ":" in ln}
    skills = [s for s in result.get("applicable_skills", []) if s in valid]
    lines: list[str] = []
    runnable: list[str] = []
    for chk in result.get("verification_checklist", []):
        if isinstance(chk, str):           # tolerate un-annotated string form
            chk = {"command": chk}
        desc = chk.get("description", "")
        cmd = chk.get("command", "")
        status = chk.get("status")
        detail = chk.get("detail", "")
        if status == "runnable":
            label = f"runs; {detail}"
            runnable.append(cmd)
        elif status == "broken":
            label = f"BROKEN: {detail}"
        elif status == "rejected":
            label = f"REJECTED: {detail}"
        elif status == "unvalidated":
            label = f"unvalidated: {detail}"
        else:
            label = "unchecked"
        lines.append(f"- [{label}] {desc} — `{cmd}`")
    checklist = "\n".join(lines)
    enriched = result.get("enriched_prompt", "")
    cited = result.get("cited_paths", [])
    grounded = ", ".join(cited) if cited else "(no files read)"
    acceptance = "\n".join(runnable) if runnable else "(none proven runnable)"
    intent = result.get("intent", "")
    bounds = [b for b in result.get("boundaries", []) if b]
    if mode == "worker":
        intent_para = f"Intent: {intent}\n\n" if intent else ""
        bounds_para = ("Out of scope:\n" + "\n".join(f"- {b}" for b in bounds) + "\n\n") if bounds else ""
        return (f"Task focus: {enriched}\n\n"
                f"{intent_para}{bounds_para}"
                f"Apply these skills as relevant: {', '.join(skills) or 'none'}\n\n"
                f"Grounded in: {grounded}\n\n"
                f"Before you consider this done, verify:\n{checklist}\n")
    intent_line = f"**Intent:** {intent}\n" if intent else ""
    bounds_block = ("**Out of scope:**\n" + "\n".join(f"- {b}" for b in bounds) + "\n") if bounds else ""
    plan = result.get("dispatch_plan") or []
    plan_block = ""
    if plan:
        rows: list[str] = []
        seed_tasks: list[dict] = []
        for i, t in enumerate(plan, 1):
            deps = ", ".join(t.get("deps", [])) or "none"
            rows.append(f"{i}. {t.get('title', '')} [{t.get('type', 'feat')}] — "
                        f"owns: {', '.join(t.get('owns', []))} — deps: {deps}")
            if t.get("brief"):
                rows.append(f"   {t['brief']}")
            for c in t.get("acceptance", []):
                status = c.get("status")
                detail = c.get("detail", "")
                label = {"runnable": f"runs; {detail}", "broken": f"BROKEN: {detail}",
                         "rejected": f"REJECTED: {detail}",
                         "unvalidated": f"unvalidated: {detail}"}.get(status, "unchecked")
                rows.append(f"   - [{label}] {c.get('description', '')} — `{c.get('command', '')}`")
            seed_tasks.append({"title": t.get("title", ""), "type": t.get("type", "feat"),
                               "owns": t.get("owns", []), "deps": t.get("deps", [])})
        seed = json.dumps({"shared": result.get("shared", []), "tasks": seed_tasks}, indent=1)
        plan_block = (
            "\n**Dispatch plan:**\n" + "\n".join(rows) + "\n\n"
            "```json\n" + seed + "\n```\n\n"
            "Dispatch contract (constant): per-task brief at .superpowers/sdd/task-N-brief.md and "
            "report at .superpowers/sdd/task-N-report.md; report status vocabulary DONE | "
            "DONE_WITH_CONCERNS | BLOCKED | NEEDS_CONTEXT; every report carries "
            "verification-command output (evidence, not claims); every dispatch sets an "
            "explicit model:.\n")
    budget = _budget_for_plan(plan)
    return (f"## Kickoff\n"
            f"**Scoped prompt:** {enriched}\n"
            f"{intent_line}"
            f"{bounds_block}"
            f"**Skills:** {', '.join(skills) or 'none'}\n"
            f"**Execution:** {result.get('execution_hint', 'solo')}\n"
            f"**Budget:** {budget}\n"
            f"**Grounded in:** {grounded}\n"
            f"**Verification checklist:**\n{checklist}\n\n"
            f"Acceptance (runnable):\n{acceptance}\n{plan_block}")


def _repo_root() -> Path:
    import subprocess  # noqa: PLC0415
    try:
        out = subprocess.run(["git", "rev-parse", "--show-toplevel"],
                             capture_output=True, text=True, timeout=5)
        if out.returncode == 0 and out.stdout.strip():
            return Path(out.stdout.strip())
    except Exception:
        pass
    return Path.cwd()


def _passthrough(reason: str) -> int:
    print(f"{PASSTHROUGH_PREFIX} enrichment unavailable ({reason})")
    return 0


@contextlib.contextmanager
def _wall_clock_deadline(seconds: int):
    """Hard fail-open guard around the engine call. agentic_run checks its
    timeout only between rounds, so an LLM POST on a stalled connection blocks
    forever and enrich.sh's fail-open (which needs the process to exit) never
    fires. SIGALRM converts that block into an EngineError. No-op off the main
    thread, where SIGALRM cannot be armed."""
    if threading.current_thread() is not threading.main_thread():
        yield
        return

    def _on_alarm(signum, frame):
        raise EngineError(f"wall-clock deadline exceeded ({seconds}s)")

    previous = signal.signal(signal.SIGALRM, _on_alarm)
    signal.alarm(seconds)
    try:
        yield
    finally:
        signal.alarm(0)
        signal.signal(signal.SIGALRM, previous)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(prog="tool.kickoff")
    parser.add_argument("--mode", choices=["interactive", "worker"], default="interactive")
    parser.add_argument("--title", default="")
    parser.add_argument("--owns", default="")
    parser.add_argument("--profile", choices=["standard", "chief"], default="standard")
    parser.add_argument("idea", nargs="*")
    args = parser.parse_args(argv)

    if args.mode == "worker":
        content = f"Title: {args.title}\nOwns (modify only these globs): {args.owns}"
    else:
        content = " ".join(args.idea).strip()
    if not content:
        return _passthrough("empty input")

    skills_dir = Path(os.environ.get("KICKOFF_SKILLS_DIR", _DEFAULT_SKILLS_DIR))
    model = os.environ.get("KICKOFF_MODEL", _DEFAULT_MODEL)
    try:
        manifest = build_manifest(skills_dir)
        manifest = rank_manifest(
            content, manifest, top_k=int(os.environ.get("KICKOFF_SKILL_TOPK", "10")))
        root = _repo_root()
        cited: list[str] = []
        timeout = float(os.environ.get("KICKOFF_TIMEOUT", "300"))
        deadline = max(1, int(timeout) + int(os.environ.get("KICKOFF_DEADLINE_MARGIN", "30")))
        with _wall_clock_deadline(deadline):
            result = agentic_run(
                backend=os.environ.get("KICKOFF_BACKEND", "nat-nim"), model=model,
                system=_SYSTEM + (_SYSTEM_CHIEF_SUFFIX if args.profile == "chief" else ""),
                user=f"Available skills:\n{manifest}\n\nTask:\n{content}",
                tools=readonly_tools(root, sink=cited),
                result_schema=KickoffResult,
                validator=make_validator(root, args.profile),
                max_rounds=int(os.environ.get("KICKOFF_MAX_ROUNDS", "32")),
                timeout=timeout,
                transcript_path=os.environ.get("KICKOFF_DEBUG_TRANSCRIPT"),
            )
        result["cited_paths"] = sorted(set(cited))
        print(render(result, manifest, args.mode))
        return 0
    except EngineError as e:
        return _passthrough(str(e).split("\n")[0][:80])
    except Exception as e:  # never block the kickoff
        return _passthrough(f"{type(e).__name__}: {str(e).split(chr(10))[0][:60]}")


if __name__ == "__main__":
    sys.exit(main())
