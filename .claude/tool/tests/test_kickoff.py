import time

import tool.kickoff as kk
from tool import kickoff
from tool.kickoff import DispatchTask, KickoffResult, _SYSTEM, make_validator


def _skill(dir_, name, desc, folded=False):
    d = dir_ / name
    d.mkdir()
    if folded:
        body = f"---\nname: {name}\ndescription: >\n  {desc}\n---\n# {name}\nSENTINEL_BODY\n"
    else:
        body = f"---\nname: {name}\ndescription: {desc}\n---\n# {name}\nSENTINEL_BODY\n"
    (d / "SKILL.md").write_text(body)


def test_build_manifest_single_and_folded(tmp_path):
    _skill(tmp_path, "alpha", "does alpha things")
    _skill(tmp_path, "beta", "does beta things across lines", folded=True)
    man = kk.build_manifest(tmp_path)
    assert "alpha: does alpha things" in man
    assert "beta: does beta things across lines" in man
    assert "SENTINEL_BODY" not in man  # body excluded


def test_render_interactive_shows_verdicts_and_acceptance(tmp_path):
    _skill(tmp_path, "alpha", "a")
    man = kk.build_manifest(tmp_path)
    result = {
        "enriched_prompt": "Do the thing precisely",
        "applicable_skills": ["alpha", "ghost-skill"],
        "verification_checklist": [
            {"description": "unit tests run", "command": "go test ./...",
             "status": "runnable", "detail": "fails (exit 1)"},
            {"description": "bad", "command": "frobnicate",
             "status": "broken", "detail": "command not found / not executable"},
            {"description": "danger", "command": "rm -rf x", "status": "rejected", "detail": "denied binary 'rm'"},
        ],
        "execution_hint": "solo",
        "cited_paths": ["go.mod"],
    }
    out = kk.render(result, man, mode="interactive")
    assert "alpha" in out and "ghost-skill" not in out      # hallucinated skill dropped
    assert "go test ./..." in out
    assert "BROKEN" in out                                  # broken check surfaced, not hidden
    assert "REJECTED" in out                               # rejected check surfaced with its label
    assert "**Grounded in:** go.mod" in out
    accept = out.split("Acceptance (runnable):", 1)[1]
    assert "go test ./..." in accept                        # runnable -> acceptance
    assert "frobnicate" not in accept                       # broken -> NOT acceptance
    assert "rm -rf x" not in accept                        # rejected command excluded from acceptance


def test_render_worker_shows_commands_not_goal(tmp_path):
    _skill(tmp_path, "alpha", "a")
    man = kk.build_manifest(tmp_path)
    result = {"enriched_prompt": "x", "applicable_skills": ["alpha"],
              "verification_checklist": [{"description": "d", "command": "make test",
                                          "status": "runnable", "detail": "passes"}],
              "execution_hint": "solo", "cited_paths": []}
    out = kk.render(result, man, mode="worker")
    assert "Goal:" not in out and "ORCH_TASK_UUID" not in out
    assert "make test" in out
    assert "## Kickoff" not in out
    assert "Acceptance (runnable):" not in out
    assert "Grounded in: (no files read)" in out


def test_make_validator_flags_broken_and_requests_revision(tmp_path, monkeypatch):
    from tool.verify import CheckVerdict
    monkeypatch.setattr(kk, "validate_checklist", lambda cmds, root, **kw: [
        CheckVerdict(status="runnable", detail="passes", exit_code=0),
        CheckVerdict(status="broken", detail="command not found / not executable", exit_code=127),
    ])
    validator = kk.make_validator(tmp_path)
    outcome = validator({"verification_checklist": [
        {"description": "a", "command": "true"},
        {"description": "b", "command": "frob"},
    ]})
    assert outcome.accept is False
    assert "frob" in outcome.feedback                       # the broken command is named
    annotated = outcome.result["verification_checklist"]
    assert annotated[0]["status"] == "runnable"
    assert annotated[1]["status"] == "broken"


def test_make_validator_accepts_when_all_runnable(tmp_path, monkeypatch):
    from tool.verify import CheckVerdict
    monkeypatch.setattr(kk, "validate_checklist", lambda cmds, root, **kw: [
        CheckVerdict(status="runnable", detail="passes", exit_code=0)])
    validator = kk.make_validator(tmp_path)
    outcome = validator({"verification_checklist": [{"description": "a", "command": "true"}],
                         "intent": "why it matters", "boundaries": ["scope limit"]})
    assert outcome.accept is True


def test_main_attaches_cited_paths(tmp_path, monkeypatch, capsys):
    _skill(tmp_path, "alpha", "a")
    monkeypatch.setenv("KICKOFF_SKILLS_DIR", str(tmp_path))
    captured = {}

    def fake_readonly(root, sink=None):
        captured["sink"] = sink
        return []

    def fake_agentic(**kw):
        captured["sink"].extend(["b.go", "a.go", "a.go"])   # simulate reads: unsorted + dupe
        return {"enriched_prompt": "x", "applicable_skills": ["alpha"],
                "verification_checklist": [], "execution_hint": "solo"}

    monkeypatch.setattr(kk, "readonly_tools", fake_readonly)
    monkeypatch.setattr(kk, "make_validator", lambda root, profile="standard": None)
    monkeypatch.setattr(kk, "agentic_run", fake_agentic)
    rc = kk.main(["--mode", "interactive", "do x"])
    out = capsys.readouterr().out
    assert rc == 0
    assert "**Grounded in:** a.go, b.go" in out             # sorted + deduped


def test_main_passthrough_on_engine_error(tmp_path, monkeypatch, capsys):
    _skill(tmp_path, "alpha", "a")
    monkeypatch.setenv("KICKOFF_SKILLS_DIR", str(tmp_path))

    def boom(**kw):
        from tool.errors import LoopBudgetError
        raise LoopBudgetError("hub down")

    monkeypatch.setattr(kk, "agentic_run", boom)
    rc = kk.main(["--mode", "interactive", "do something"])
    out = capsys.readouterr().out
    assert rc == 0
    assert out.startswith(kk.PASSTHROUGH_PREFIX)


def test_main_passthrough_on_generic_exception(tmp_path, monkeypatch, capsys):
    _skill(tmp_path, "alpha", "a")
    monkeypatch.setenv("KICKOFF_SKILLS_DIR", str(tmp_path))

    def boom(**kw):
        raise RuntimeError("non-engine failure")

    monkeypatch.setattr(kk, "agentic_run", boom)
    rc = kk.main(["--mode", "interactive", "do something"])
    out = capsys.readouterr().out
    assert rc == 0
    assert out.startswith(kk.PASSTHROUGH_PREFIX)


def test_make_validator_accepts_when_unvalidated(tmp_path, monkeypatch):
    from tool.verify import CheckVerdict
    monkeypatch.setattr(kk, "validate_checklist", lambda cmds, root, **kw: [
        CheckVerdict(status="unvalidated", detail="validation budget exhausted")])
    validator = kk.make_validator(tmp_path)
    outcome = validator({"verification_checklist": [{"description": "a", "command": "go test ./..."}],
                         "intent": "why it matters", "boundaries": ["scope limit"]})
    assert outcome.accept is True   # unvalidated must NOT trigger a revision


def test_make_validator_rejected_triggers_revision(tmp_path, monkeypatch):
    from tool.verify import CheckVerdict
    monkeypatch.setattr(kk, "validate_checklist", lambda cmds, root, **kw: [
        CheckVerdict(status="rejected", detail="denied binary 'rm'")])
    validator = kk.make_validator(tmp_path)
    outcome = validator({"verification_checklist": [{"description": "b", "command": "rm -rf x"}]})
    assert outcome.accept is False                 # rejected triggers revision
    assert "rm -rf x" in outcome.feedback          # the offending command is named
    assert outcome.result["verification_checklist"][0]["status"] == "rejected"


def test_main_wall_clock_deadline_interrupts_hung_engine(tmp_path, monkeypatch, capsys):
    """2026-07-03 hang: an LLM POST with no timeout blocks inside agentic_run,
    past every between-rounds timeout check, so KICKOFF_TIMEOUT never fires and
    enrich.sh's fail-open never triggers. A hard wall-clock deadline must
    convert that block into a passthrough."""
    _skill(tmp_path, "alpha", "a")
    monkeypatch.setenv("KICKOFF_SKILLS_DIR", str(tmp_path))
    monkeypatch.setenv("KICKOFF_TIMEOUT", "1")
    monkeypatch.setenv("KICKOFF_DEADLINE_MARGIN", "1")

    def hung_engine(**kw):
        time.sleep(15)  # a stalled POST: blocks, never raises on its own
        return {"enriched_prompt": "late", "applicable_skills": [],
                "verification_checklist": [], "execution_hint": "solo"}

    monkeypatch.setattr(kk, "agentic_run", hung_engine)
    monkeypatch.setattr(kk, "readonly_tools", lambda root, sink=None: [])
    monkeypatch.setattr(kk, "make_validator", lambda root, profile="standard": None)
    start = time.monotonic()
    rc = kk.main(["--mode", "interactive", "do something"])
    elapsed = time.monotonic() - start
    out = capsys.readouterr().out
    assert rc == 0
    assert out.startswith(kk.PASSTHROUGH_PREFIX)
    assert "deadline" in out            # the discriminating reason, not any passthrough
    assert elapsed < 8                  # interrupted at ~2s, not after the full 15s sleep


def test_main_passes_ranked_manifest_to_model(tmp_path, monkeypatch):
    _skill(tmp_path, "go-review", "review go code errors concurrency goroutines")
    for i in range(12):
        _skill(tmp_path, f"cfo{i}", "portfolio tax rebalance finance abgeltungsteuer")
    monkeypatch.setenv("KICKOFF_SKILLS_DIR", str(tmp_path))
    monkeypatch.setenv("KICKOFF_SKILL_TOPK", "5")
    captured = {}

    def fake_agentic(**kw):
        captured["user"] = kw["user"]
        return {"enriched_prompt": "x", "applicable_skills": ["go-review"],
                "verification_checklist": [], "execution_hint": "solo"}

    monkeypatch.setattr(kk, "readonly_tools", lambda root, sink=None: [])
    monkeypatch.setattr(kk, "make_validator", lambda root, profile="standard": None)
    monkeypatch.setattr(kk, "agentic_run", fake_agentic)
    rc = kk.main(["--mode", "interactive", "refactor go errors and concurrency"])
    assert rc == 0
    user = captured["user"]
    section = user.split("Available skills:\n", 1)[1].split("\n\nTask:", 1)[0]
    names = [ln.split(":", 1)[0] for ln in section.splitlines() if ln.strip()]
    assert "go-review" in names                          # relevant skill survived ranking
    assert not any(n.startswith("cfo") for n in names)   # 12 finance skills trimmed away
    assert len(names) <= 5                               # honored KICKOFF_SKILL_TOPK


def test_main_passes_transcript_path_from_env(tmp_path, monkeypatch):
    _skill(tmp_path, "alpha", "a")
    monkeypatch.setenv("KICKOFF_SKILLS_DIR", str(tmp_path))
    monkeypatch.setenv("KICKOFF_DEBUG_TRANSCRIPT", str(tmp_path / "t.jsonl"))
    captured = {}

    def fake_agentic(**kw):
        captured.update(kw)
        return {"enriched_prompt": "x", "applicable_skills": [],
                "verification_checklist": [], "execution_hint": "solo"}

    monkeypatch.setattr(kk, "readonly_tools", lambda root, sink=None: [])
    monkeypatch.setattr(kk, "make_validator", lambda root, profile="standard": None)
    monkeypatch.setattr(kk, "agentic_run", fake_agentic)
    assert kk.main(["--mode", "interactive", "do x"]) == 0
    assert captured["transcript_path"] == str(tmp_path / "t.jsonl")


def test_main_transcript_path_none_when_env_unset(tmp_path, monkeypatch):
    _skill(tmp_path, "alpha", "a")
    monkeypatch.setenv("KICKOFF_SKILLS_DIR", str(tmp_path))
    monkeypatch.delenv("KICKOFF_DEBUG_TRANSCRIPT", raising=False)
    captured = {}

    def fake_agentic(**kw):
        captured.update(kw)
        return {"enriched_prompt": "x", "applicable_skills": [],
                "verification_checklist": [], "execution_hint": "solo"}

    monkeypatch.setattr(kk, "readonly_tools", lambda root, sink=None: [])
    monkeypatch.setattr(kk, "make_validator", lambda root, profile="standard": None)
    monkeypatch.setattr(kk, "agentic_run", fake_agentic)
    assert kk.main(["--mode", "interactive", "do x"]) == 0
    assert captured["transcript_path"] is None


def test_kickoff_result_defaults_for_intent_and_boundaries():
    # Missing keys must never hard-fail validation (fail-open contract).
    r = kk.KickoffResult(enriched_prompt="x")
    assert r.intent == ""
    assert r.boundaries == []


def test_render_interactive_includes_intent_and_out_of_scope(tmp_path):
    _skill(tmp_path, "alpha", "a")
    man = kk.build_manifest(tmp_path)
    result = {"enriched_prompt": "Do the thing", "applicable_skills": ["alpha"],
              "verification_checklist": [], "execution_hint": "solo",
              "cited_paths": ["go.mod"],
              "intent": "Feeds the deploy pipeline for the ops team",
              "boundaries": ["do not modify the public repo", "no new dependencies"]}
    out = kk.render(result, man, mode="interactive")
    assert "**Intent:** Feeds the deploy pipeline for the ops team" in out
    assert "**Out of scope:**" in out
    assert "- do not modify the public repo" in out
    assert "- no new dependencies" in out
    # ordering: scoped prompt, then intent/boundaries, then skills
    assert out.index("**Scoped prompt:**") < out.index("**Intent:**") < out.index("**Skills:**")


def test_render_interactive_omits_empty_intent_and_boundaries(tmp_path):
    _skill(tmp_path, "alpha", "a")
    man = kk.build_manifest(tmp_path)
    result = {"enriched_prompt": "x", "applicable_skills": [],
              "verification_checklist": [], "execution_hint": "solo", "cited_paths": []}
    out = kk.render(result, man, mode="interactive")
    assert "**Intent:**" not in out          # no empty headers
    assert "**Out of scope:**" not in out


def test_render_worker_includes_intent_and_out_of_scope(tmp_path):
    _skill(tmp_path, "alpha", "a")
    man = kk.build_manifest(tmp_path)
    result = {"enriched_prompt": "x", "applicable_skills": ["alpha"],
              "verification_checklist": [], "execution_hint": "solo", "cited_paths": [],
              "intent": "Unblocks task T4", "boundaries": ["touch only tool/**"]}
    out = kk.render(result, man, mode="worker")
    assert "Intent: Unblocks task T4" in out
    assert "Out of scope:" in out
    assert "- touch only tool/**" in out
    assert "## Kickoff" not in out           # worker format unchanged otherwise


def test_make_validator_requests_missing_intent_and_boundaries(tmp_path, monkeypatch):
    from tool.verify import CheckVerdict
    monkeypatch.setattr(kk, "validate_checklist", lambda cmds, root, **kw: [
        CheckVerdict(status="runnable", detail="passes", exit_code=0)])
    validator = kk.make_validator(tmp_path)
    outcome = validator({"verification_checklist": [{"description": "a", "command": "true"}],
                         "intent": "", "boundaries": []})
    assert outcome.accept is False
    assert "intent" in outcome.feedback
    assert "boundaries" in outcome.feedback


def test_make_validator_combines_broken_check_and_missing_intent(tmp_path, monkeypatch):
    from tool.verify import CheckVerdict
    monkeypatch.setattr(kk, "validate_checklist", lambda cmds, root, **kw: [
        CheckVerdict(status="broken", detail="command not found / not executable", exit_code=127)])
    validator = kk.make_validator(tmp_path)
    outcome = validator({"verification_checklist": [{"description": "b", "command": "frob"}],
                         "intent": "", "boundaries": ["x"]})
    assert outcome.accept is False
    assert "frob" in outcome.feedback        # broken check still named
    assert "intent" in outcome.feedback      # missing field also named
    assert "boundaries" not in outcome.feedback.split("missing", 1)[-1]  # present field not requested


def test_make_validator_treats_none_intent_as_missing(tmp_path, monkeypatch):
    from tool.verify import CheckVerdict
    monkeypatch.setattr(kk, "validate_checklist", lambda cmds, root, **kw: [
        CheckVerdict(status="runnable", detail="passes", exit_code=0)])
    validator = kk.make_validator(tmp_path)
    outcome = validator({"verification_checklist": [{"description": "a", "command": "true"}],
                         "intent": None, "boundaries": ["x"]})
    assert outcome.accept is False
    assert "intent" in outcome.feedback


def test_make_validator_whitespace_intent_and_absent_boundaries_are_missing(tmp_path, monkeypatch):
    from tool.verify import CheckVerdict
    monkeypatch.setattr(kk, "validate_checklist", lambda cmds, root, **kw: [
        CheckVerdict(status="runnable", detail="passes", exit_code=0)])
    validator = kk.make_validator(tmp_path)
    outcome = validator({"verification_checklist": [{"description": "a", "command": "true"}],
                         "intent": "   "})
    assert outcome.accept is False
    assert "intent" in outcome.feedback
    assert "boundaries" in outcome.feedback


def test_main_budget_defaults_raised(tmp_path, monkeypatch):
    _skill(tmp_path, "alpha", "a")
    monkeypatch.setenv("KICKOFF_SKILLS_DIR", str(tmp_path))
    monkeypatch.delenv("KICKOFF_MAX_ROUNDS", raising=False)
    monkeypatch.delenv("KICKOFF_TIMEOUT", raising=False)
    captured = {}

    def fake_agentic(**kw):
        captured.update(kw)
        return {"enriched_prompt": "x", "applicable_skills": [],
                "verification_checklist": [], "execution_hint": "solo"}

    monkeypatch.setattr(kk, "readonly_tools", lambda root, sink=None: [])
    monkeypatch.setattr(kk, "make_validator", lambda root, profile="standard": None)
    monkeypatch.setattr(kk, "agentic_run", fake_agentic)
    assert kk.main(["--mode", "interactive", "do x"]) == 0
    assert captured["max_rounds"] == 32
    assert captured["timeout"] == 300.0


# --- chief-mode: schema back-compat -----------------------------------------

def test_kickoff_result_defaults_for_dispatch_plan_and_shared():
    r = KickoffResult(enriched_prompt="x")
    assert r.dispatch_plan == []
    assert r.shared == []


def test_dispatch_task_defaults():
    t = DispatchTask(title="API layer", owns=["pkg/api/**"])
    assert t.type == "feat" and t.deps == [] and t.brief == "" and t.acceptance == []


# --- chief-mode: profile prompt selection ------------------------------------

def test_main_chief_profile_appends_suffix(tmp_path, monkeypatch):
    captured = {}
    def fake_run(**kw):
        captured.update(kw)
        return {"enriched_prompt": "p", "intent": "i", "boundaries": ["b"]}
    monkeypatch.setattr("tool.kickoff.agentic_run", fake_run)
    monkeypatch.setenv("KICKOFF_SKILLS_DIR", str(tmp_path))
    kickoff.main(["--profile", "chief", "idea"])
    assert captured["system"].startswith(_SYSTEM)
    assert "dispatch_plan" in captured["system"]
    assert "pairwise disjoint" in captured["system"]


def test_main_standard_profile_system_prompt_unchanged(tmp_path, monkeypatch):
    captured = {}
    def fake_run(**kw):
        captured.update(kw)
        return {"enriched_prompt": "p", "intent": "i", "boundaries": ["b"]}
    monkeypatch.setattr("tool.kickoff.agentic_run", fake_run)
    monkeypatch.setenv("KICKOFF_SKILLS_DIR", str(tmp_path))
    kickoff.main(["idea"])
    assert captured["system"] == _SYSTEM


# --- chief-mode: validator ----------------------------------------------------

def _plan_result(tasks, hint="orchestrate"):
    return {"enriched_prompt": "p", "intent": "i", "boundaries": ["b"],
            "verification_checklist": [], "dispatch_plan": tasks,
            "shared": [], "execution_hint": hint}


def test_validator_chief_accepts_disjoint_plan(tmp_path, monkeypatch):
    monkeypatch.setattr("tool.kickoff.validate_checklist", lambda cmds, root: [])
    v = make_validator(tmp_path, profile="chief")
    out = v(_plan_result([
        {"title": "A", "owns": ["pkg/api/**"], "deps": [], "acceptance": []},
        {"title": "B", "owns": ["cmd/cli/**"], "deps": ["A"], "acceptance": []},
    ]))
    assert out.accept


def test_validator_chief_rejects_owns_overlap(tmp_path, monkeypatch):
    monkeypatch.setattr("tool.kickoff.validate_checklist", lambda cmds, root: [])
    v = make_validator(tmp_path, profile="chief")
    out = v(_plan_result([
        {"title": "A", "owns": ["pkg/api/**"], "deps": [], "acceptance": []},
        {"title": "B", "owns": ["pkg/api/handlers/**"], "deps": [], "acceptance": []},
    ]))
    assert not out.accept and "overlap" in out.feedback


def test_validator_chief_rejects_missing_dep_and_cycle(tmp_path, monkeypatch):
    monkeypatch.setattr("tool.kickoff.validate_checklist", lambda cmds, root: [])
    v = make_validator(tmp_path, profile="chief")
    out = v(_plan_result([
        {"title": "A", "owns": ["a/**"], "deps": ["ghost"], "acceptance": []},
        {"title": "B", "owns": ["b/**"], "deps": ["C"], "acceptance": []},
        {"title": "C", "owns": ["c/**"], "deps": ["B"], "acceptance": []},
    ]))
    assert not out.accept
    assert "not a task title" in out.feedback and "cycle" in out.feedback


def test_validator_chief_enforces_hint_consistency(tmp_path, monkeypatch):
    monkeypatch.setattr("tool.kickoff.validate_checklist", lambda cmds, root: [])
    v = make_validator(tmp_path, profile="chief")
    out = v(_plan_result([
        {"title": "A", "owns": ["a/**"], "deps": [], "acceptance": []},
        {"title": "B", "owns": ["b/**"], "deps": [], "acceptance": []},
    ], hint="solo"))
    assert not out.accept and "execution_hint" in out.feedback


def test_validator_chief_annotates_acceptance_and_flags_broken(tmp_path, monkeypatch):
    from tool.verify import CheckVerdict
    monkeypatch.setattr("tool.kickoff.validate_checklist",
                        lambda cmds, root: [CheckVerdict(status="broken", detail="command not found")])
    v = make_validator(tmp_path, profile="chief")
    out = v(_plan_result([
        {"title": "A", "owns": ["a/**"], "deps": [],
         "acceptance": [{"description": "d", "command": "gozzz test ./..."}]},
    ], hint="solo"))
    assert not out.accept
    assert out.result["dispatch_plan"][0]["acceptance"][0]["status"] == "broken"


def test_validator_standard_profile_ignores_dispatch_plan(tmp_path, monkeypatch):
    monkeypatch.setattr("tool.kickoff.validate_checklist", lambda cmds, root: [])
    v = make_validator(tmp_path)  # default profile
    out = v(_plan_result([
        {"title": "A", "owns": ["pkg/**"], "deps": [], "acceptance": []},
        {"title": "B", "owns": ["pkg/**"], "deps": [], "acceptance": []},
    ], hint="solo"))
    assert out.accept  # overlapping owns + wrong hint: not validated outside chief


# --- chief-mode: render --------------------------------------------------------

def _rendered_plan(tmp_path):
    result = {"enriched_prompt": "p", "intent": "i", "boundaries": ["b"],
              "applicable_skills": [], "verification_checklist": [], "cited_paths": [],
              "execution_hint": "orchestrate", "shared": ["go.mod"],
              "dispatch_plan": [
                  {"title": "API layer", "type": "feat", "owns": ["pkg/api/**"], "deps": [],
                   "brief": "Build the API.", "acceptance": [
                       {"description": "unit", "command": "go test ./pkg/api/...",
                        "status": "runnable", "detail": "exit 0"}]},
                  {"title": "CLI", "type": "feat", "owns": ["cmd/cli/**"], "deps": ["API layer"],
                   "brief": "Wire the CLI.", "acceptance": []},
              ]}
    return kickoff.render(result, manifest="", mode="interactive")


def test_render_dispatch_plan_block_and_json_seed(tmp_path):
    out = _rendered_plan(tmp_path)
    assert "**Dispatch plan:**" in out
    assert "1. API layer [feat] — owns: pkg/api/** — deps: none" in out
    assert "2. CLI [feat] — owns: cmd/cli/** — deps: API layer" in out
    assert "[runs; exit 0] unit — `go test ./pkg/api/...`" in out
    import json as _json
    seed = out.split("```json\n", 1)[1].split("\n```", 1)[0]
    parsed = _json.loads(seed)
    assert parsed == {"shared": ["go.mod"],
                      "tasks": [
                          {"title": "API layer", "type": "feat", "owns": ["pkg/api/**"], "deps": []},
                          {"title": "CLI", "type": "feat", "owns": ["cmd/cli/**"], "deps": ["API layer"]}]}
    assert "task-N-brief.md" in out and "DONE | DONE_WITH_CONCERNS | BLOCKED | NEEDS_CONTEXT" in out


def test_render_no_plan_is_byte_identical_to_pre_chief_output(tmp_path):
    result = {"enriched_prompt": "p", "intent": "i", "boundaries": ["b"],
              "applicable_skills": [], "verification_checklist": [], "cited_paths": [],
              "execution_hint": "solo"}
    baseline = kickoff.render(result, manifest="", mode="interactive")
    result2 = {**result, "dispatch_plan": [], "shared": []}
    assert kickoff.render(result2, manifest="", mode="interactive") == baseline
    assert "Dispatch plan" not in baseline


def test_render_worker_mode_never_renders_plan(tmp_path):
    result = {"enriched_prompt": "p", "intent": "", "boundaries": [],
              "applicable_skills": [], "verification_checklist": [], "cited_paths": [],
              "dispatch_plan": [{"title": "A", "owns": ["a/**"], "deps": [], "acceptance": []}]}
    out = kickoff.render(result, manifest="", mode="worker")
    assert "Dispatch plan" not in out


# --- Task B: deterministic Budget line ---------------------------------------

def test_format_budget_sub_1000_uses_k_suffix():
    """Catches: sub-1000k values rendered with the wrong suffix/scale (e.g. '0.3m')."""
    assert kk._format_budget(300) == "300k"
    assert kk._format_budget(600) == "600k"


def test_format_budget_exact_multiples_of_1000_drop_the_decimal():
    """Catches: exact-thousand values rendered with a spurious decimal ('1.0m' instead of '1m')."""
    assert kk._format_budget(1000) == "1m"
    assert kk._format_budget(2000) == "2m"


def test_format_budget_non_multiple_above_1000_keeps_one_decimal():
    """Catches: a non-multiple-of-1000 value truncated/rounded to the wrong precision."""
    assert kk._format_budget(1400) == "1.4m"


def test_budget_for_plan_empty_plan_defaults_to_300k():
    """Catches: solo/standard-profile kickoffs (no dispatch plan) getting no budget or a
    non-default value."""
    assert kk._budget_for_plan([]) == "300k"


def test_budget_for_plan_scales_with_task_count():
    """Catches: the per-task budget formula (200 + 200*n) drifting for small plan sizes."""
    two_tasks = [{"title": "A", "owns": ["a/**"]}, {"title": "B", "owns": ["b/**"]}]
    assert kk._budget_for_plan(two_tasks) == "600k"
    four_tasks = [{"title": t, "owns": [f"{t}/**"]} for t in "ABCD"]
    assert kk._budget_for_plan(four_tasks) == "1m"


def test_budget_for_plan_caps_at_2m_for_large_plans():
    """Catches: the budget formula exceeding the deliberate 2m ceiling on large plans."""
    twelve_tasks = [{"title": f"T{i}", "owns": [f"t{i}/**"]} for i in range(12)]
    assert kk._budget_for_plan(twelve_tasks) == "2m"


def test_render_chief_plan_includes_budget_line_after_execution(tmp_path):
    """Catches: a compiled 4-task orchestration plan rendering with no Budget line, a wrong
    value, or one not immediately following Execution (where the governor's grep and the
    SKILL.md transcription step both expect it)."""
    result = {"enriched_prompt": "p", "intent": "i", "boundaries": ["b"],
              "applicable_skills": [], "verification_checklist": [], "cited_paths": [],
              "execution_hint": "orchestrate",
              "dispatch_plan": [{"title": t, "owns": [f"{t}/**"], "deps": [], "acceptance": []}
                                 for t in "ABCD"]}
    out = kk.render(result, manifest="", mode="interactive")
    assert "**Budget:** 1m" in out
    lines = out.splitlines()
    exec_idx = next(i for i, ln in enumerate(lines) if ln.startswith("**Execution:**"))
    assert lines[exec_idx + 1] == "**Budget:** 1m"


def test_render_solo_plan_includes_default_budget_line(tmp_path):
    """Catches: solo/empty-plan kickoffs silently getting no Budget line, leaving the
    budget-governor Stop hook dormant."""
    result = {"enriched_prompt": "p", "intent": "i", "boundaries": ["b"],
              "applicable_skills": [], "verification_checklist": [], "cited_paths": [],
              "execution_hint": "solo"}
    out = kk.render(result, manifest="", mode="interactive")
    assert "**Budget:** 300k" in out


def test_default_model_is_public_catalog_form():
    """Bug caught: hub-form default returning to source (T13 leak-gate class)."""
    assert kk._DEFAULT_MODEL == "nvidia/nemotron-3-ultra-550b-a55b:free"
    assert kk._DEFAULT_MODEL.count("nvidia/") == 1  # hub-form would count 2; no banned literal
