import tool.routing as routing


def _manifest(*pairs):
    return "\n".join(f"{name}: {desc}" for name, desc in pairs)


def test_drops_irrelevant_skills_for_go_task():
    # 1 relevant Go skill + 12 finance skills sharing no Go terms.
    pairs = [("go-review", "review go code errors concurrency goroutines idioms")]
    pairs += [(f"cfo{i}", "portfolio tax rebalance finance abgeltungsteuer") for i in range(12)]
    man = _manifest(*pairs)
    out = routing.rank_manifest("refactor go errors and concurrency in goroutines", man, top_k=5)
    names = [ln.split(":", 1)[0] for ln in out.splitlines() if ln.strip()]
    assert "go-review" in names                          # relevant skill kept
    assert not any(n.startswith("cfo") for n in names)   # zero-scoring noise dropped


def test_idf_prefers_rare_discriminative_term_over_common_terms():
    # 'narrow' shares 1 RARE term (kubernetes) with the task; 'broad' + 8 pads share
    # 2 COMMON terms (alpha, beta). Plain overlap -> broad/pads win (RED).
    # IDF -> the rare term dominates -> 'narrow' ranks first (GREEN).
    pairs = [("narrow", "kubernetes"), ("broad", "alpha beta gamma")]
    pairs += [(f"pad{i}", "alpha beta") for i in range(8)]   # raise df(alpha), df(beta)
    man = _manifest(*pairs)                                  # 10 skills
    out = routing.rank_manifest("alpha beta kubernetes", man, top_k=5)
    names = [ln.split(":", 1)[0] for ln in out.splitlines() if ln.strip()]
    assert names[0] == "narrow"                             # rare term beats 2 common matches
    assert "broad" in names and names.index("narrow") < names.index("broad")


def test_caps_result_at_top_k():
    # 20 matching skills + 4 disjoint (so the shared term's df < N, idf > 0).
    pairs = [(f"s{i}", "kubernetes operator reconcile") for i in range(20)]
    pairs += [(f"x{i}", "finance tax portfolio") for i in range(4)]
    man = _manifest(*pairs)
    out = routing.rank_manifest("kubernetes operator", man, top_k=6)
    assert len([ln for ln in out.splitlines() if ln.strip()]) == 6


def test_fail_open_when_no_overlap_returns_full_manifest():
    pairs = [(f"s{i}", "kubernetes operator reconcile") for i in range(12)]
    man = _manifest(*pairs)
    out = routing.rank_manifest("completely unrelated zzzqqq vocabulary", man, top_k=5)
    assert out == man            # disjoint vocab -> unchanged (never starve the model)


def test_fail_open_when_manifest_at_or_below_top_k_returns_unchanged():
    man = _manifest(("go-review", "go code"), ("k8s-debug", "kubernetes pods"))
    out = routing.rank_manifest("kubernetes", man, top_k=10)
    assert out == man            # nothing to trim
