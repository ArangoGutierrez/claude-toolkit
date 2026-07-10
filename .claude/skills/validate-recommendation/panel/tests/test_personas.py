"""Tests for panel.personas — per-role persona file loader.

Covers:
- Each real persona file (da/pe/qa) loads without error.
- Front-matter is parsed into role / description / intended_backends.
- Three sections are populated.
- load_persona_by_role finds the right file (case-insensitive).
- Missing file raises PersonaError.
- Malformed front-matter raises PersonaError.
- Missing required section raises PersonaError.
"""
import pytest


def test_load_da_persona(personas_dir):
    from panel.personas import load_persona
    p = load_persona(personas_dir / "da.md")
    assert p.role == "DA"
    assert "devil" in p.system_prompt.lower() or "adversari" in p.system_prompt.lower()
    assert "Question:" in p.user_prompt_template
    assert "VERDICT:" in p.one_shot_example


def test_load_pe_persona(personas_dir):
    from panel.personas import load_persona
    p = load_persona(personas_dir / "pe.md")
    assert p.role == "PE"
    assert "CLAUDE.md" in p.system_prompt
    assert "claude-subagent" in p.intended_backends


def test_load_qa_persona(personas_dir):
    from panel.personas import load_persona
    p = load_persona(personas_dir / "qa.md")
    assert p.role == "QA"
    # "theater" is QA-unique vocabulary from the persona content
    # (cf. the project constitution's "theater tests" terminology).
    assert "theater" in p.system_prompt.lower()
    assert "Question:" in p.user_prompt_template


def test_load_persona_by_role_case_insensitive(personas_dir):
    from panel.personas import load_persona_by_role
    p_upper = load_persona_by_role("DA", personas_dir=personas_dir)
    p_lower = load_persona_by_role("da", personas_dir=personas_dir)
    assert p_upper.role == p_lower.role == "DA"


def test_missing_persona_file(tmp_path):
    from panel.personas import load_persona, PersonaError
    with pytest.raises(PersonaError, match=r"missing"):
        load_persona(tmp_path / "ghost.md")


def test_missing_frontmatter(tmp_path):
    from panel.personas import load_persona, PersonaError
    p = tmp_path / "no_fm.md"
    p.write_text("# System prompt\nhi\n# User prompt template\nq\n")
    with pytest.raises(PersonaError, match=r"front-matter"):
        load_persona(p)


def test_frontmatter_not_a_mapping(tmp_path):
    """YAML scalar/list/null front-matter must raise PersonaError, not AttributeError."""
    from panel.personas import load_persona, PersonaError
    # Scalar string
    p = tmp_path / "scalar_fm.md"
    p.write_text("---\njust a string\n---\n# System prompt\nhi\n# User prompt template\nq\n")
    with pytest.raises(PersonaError, match=r"mapping"):
        load_persona(p)

    # YAML list
    p2 = tmp_path / "list_fm.md"
    p2.write_text("---\n- one\n- two\n---\n# System prompt\nhi\n# User prompt template\nq\n")
    with pytest.raises(PersonaError, match=r"mapping"):
        load_persona(p2)


def test_frontmatter_missing_role(tmp_path):
    from panel.personas import load_persona, PersonaError
    p = tmp_path / "no_role.md"
    p.write_text("---\ndescription: x\n---\n# System prompt\nhi\n# User prompt template\nq\n")
    with pytest.raises(PersonaError, match=r"role"):
        load_persona(p)


def test_missing_system_prompt_section(tmp_path):
    from panel.personas import load_persona, PersonaError
    p = tmp_path / "no_sp.md"
    p.write_text("---\nrole: DA\n---\n# User prompt template\nq\n")
    with pytest.raises(PersonaError, match=r"System prompt"):
        load_persona(p)


def test_missing_user_prompt_template_section(tmp_path):
    from panel.personas import load_persona, PersonaError
    p = tmp_path / "no_upt.md"
    p.write_text("---\nrole: DA\n---\n# System prompt\nhi\n")
    with pytest.raises(PersonaError, match=r"User prompt template"):
        load_persona(p)


def test_one_shot_example_is_optional(tmp_path):
    """One-shot example missing is allowed (some personas may not need it)."""
    from panel.personas import load_persona
    p = tmp_path / "minimal.md"
    p.write_text(
        "---\nrole: SEC\ndescription: security\nintended_backends: [nat-nim]\n---\n"
        "# System prompt\nYou check security.\n"
        "# User prompt template\nQuestion: <q>\n"
    )
    persona = load_persona(p)
    assert persona.role == "SEC"
    assert persona.one_shot_example == ""
