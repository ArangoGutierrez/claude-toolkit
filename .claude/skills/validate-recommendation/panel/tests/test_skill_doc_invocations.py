"""SKILL.md's runnable commands must invoke the panel package, not shadow it.

The skill exports `PYTHONPATH="$HOME/.claude"` so that `import tool` resolves.
That makes cwd load-bearing for every `python -m panel` call: from any
directory other than the skill dir, `panel` resolves to `~/.claude/panel` —
the CONFIG directory (config.yml, decisions.jsonl, work/). It has no
__init__.py, so Python treats it as a namespace package and it SHADOWS the
real code package:

    $ cd /tmp && PYTHONPATH=$HOME/.claude python3.12 -m panel build-prompt ...
    No module named panel.__main__; 'panel' is a package and cannot be
    directly executed

The command exits 1 and writes nothing. SKILL.md's documented failure
behaviour is to fall back to asking the original question, so a command that
lost its `cd` makes the panel silently stop working while looking normal.

Fencing is not the boundary — a command told to a reader in prose is run just
the same, and `cd` does not persist between Bash tool calls, so an earlier
step's `cd` covers nothing. Hence two rules:

  * inside a ```bash block, the `cd` may appear earlier in that same block;
  * anywhere else, the command must carry the `cd` itself, on its own line.

A `-m panel` followed by an ellipsis (`python -m panel …`) is a reference to
the CLI, not a call, and is not checked.
"""
import re
from pathlib import Path

SKILL_DIR = Path(__file__).resolve().parent.parent.parent
SKILL_MD = SKILL_DIR / "SKILL.md"
CD_LINE = 'cd "${HOME}/.claude/skills/validate-recommendation"'

# An invocation names a subcommand. `-m panel …` and `-m panel ...` do not.
_INVOCATION_RE = re.compile(r"-m\s+panel\s+([A-Za-z][\w-]*)")


def scan_invocations(text: str) -> tuple[int, list[str]]:
    """Return (invocations seen, "line N: ..." for each one missing its cd)."""
    lines = text.splitlines()
    offenders: list[str] = []
    found = 0
    in_block = False
    block_body_start = 0
    for i, line in enumerate(lines):
        stripped = line.strip()
        if not in_block:
            if stripped == "```bash":
                in_block, block_body_start = True, i + 1
                continue
        elif stripped == "```":
            in_block = False
            continue
        if not _INVOCATION_RE.search(line):
            continue
        # A shell comment explaining the trap is not an invocation of it.
        if in_block and stripped.startswith("#"):
            continue
        found += 1
        if in_block:
            guarded = any(CD_LINE in earlier for earlier in lines[block_body_start:i])
        else:
            guarded = CD_LINE in line
        if not guarded:
            offenders.append(f"line {i + 1}: {stripped}")
    return found, offenders


def invoked_subcommands(text: str) -> set[str]:
    """Every `panel <subcommand>` the document tells a reader to run."""
    return {m.group(1) for m in _INVOCATION_RE.finditer(text)}


def test_the_python_invocation_allowlist_covers_every_subcommand_used():
    """The "what you must NOT do" allowlist must not forbid what the doc instructs.

    SKILL.md reserves `python -m panel` for a named list of subcommands. The
    list and the instructions live 300 lines apart, so a subcommand added to
    one and not the other reads as a prohibition on the skill's own happy
    path — which is exactly what happened to `build-prompt`, the call the
    entire blinding property depends on.
    """
    text = SKILL_MD.read_text(encoding="utf-8")
    m = re.search(r"Python invocation is reserved for(.*?)\n-", text, re.DOTALL)
    assert m, "the 'Python invocation is reserved for' rule moved or was reworded"
    reserved = m.group(1)
    used = invoked_subcommands(text)
    assert used, "scanner found no `-m panel <subcommand>` calls at all"
    missing = sorted(s for s in used if f"`{s}`" not in reserved)
    assert not missing, (
        f"SKILL.md invokes {missing} but its allowlist does not permit them: "
        f"the document forbids what it instructs"
    )


def test_skill_md_has_no_unguarded_panel_invocation():
    found, offenders = scan_invocations(SKILL_MD.read_text(encoding="utf-8"))
    # Guard the guard: a parser that matches nothing would pass vacuously.
    assert found, "scanner found no `-m panel` invocations in SKILL.md at all"
    assert not offenders, (
        "these `python -m panel` commands run from an unknown cwd and would "
        "load the ~/.claude/panel CONFIG directory as a namespace package:\n  "
        + "\n  ".join(offenders)
    )


def test_scanner_flags_a_missing_cd_in_prose_as_well_as_in_a_block():
    """Both code paths, pinned on a fixture so SKILL.md edits cannot rot it.

    The prose path is the one that matters here: the first version of this
    guard read fenced blocks only, and SKILL.md's documented lint-config
    fallback — a real command, in prose — was unguarded the whole time.
    """
    fixture = (
        "Prose that only mentions `python3.12 -m panel ...` in passing.\n"
        "\n"
        "```bash\n"
        "python3.12 -m panel aggregate --config x\n"
        "```\n"
        "\n"
        "```bash\n"
        'cd "${HOME}/.claude/skills/validate-recommendation" && \\\n'
        "    python3.12 -m panel dispatch --panelist da\n"
        "```\n"
        "\n"
        "Run `python3.12 -m panel stats --min-n 5` to see the metric.\n"
        "\n"
        'Or `cd "${HOME}/.claude/skills/validate-recommendation" && '
        "python3.12 -m panel lint-config`.\n"
    )
    found, offenders = scan_invocations(fixture)

    # The ellipsis mention is a reference, not a call: 4 invocations, not 5.
    assert found == 4
    joined = "\n".join(offenders)
    assert len(offenders) == 2, joined
    assert "aggregate" in joined, "missed an unguarded call inside a bash block"
    assert "stats" in joined, "missed an unguarded call in prose"
    assert "dispatch" not in joined, "flagged a block call whose cd is earlier in the block"
    assert "lint-config" not in joined, "flagged a prose call that carries its own cd"
