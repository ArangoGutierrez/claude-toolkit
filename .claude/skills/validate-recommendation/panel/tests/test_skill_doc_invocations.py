"""SKILL.md's runnable blocks must invoke the panel package, not shadow it.

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
behaviour is to fall back to asking the original question, so a block that
lost its `cd` makes the panel silently stop working while looking normal.
This test is the guard: every `-m panel` call inside a ```bash block must be
preceded, in that same block, by the cd into the skill directory.
"""
from pathlib import Path

SKILL_DIR = Path(__file__).resolve().parent.parent.parent
SKILL_MD = SKILL_DIR / "SKILL.md"
CD_LINE = 'cd "${HOME}/.claude/skills/validate-recommendation"'


def _bash_blocks(text: str) -> list[tuple[int, list[str]]]:
    """Return (1-based start line, lines) for every ```bash fenced block."""
    blocks: list[tuple[int, list[str]]] = []
    current: list[str] | None = None
    start = 0
    for n, line in enumerate(text.splitlines(), start=1):
        if current is None:
            if line.strip() == "```bash":
                current, start = [], n
        elif line.strip() == "```":
            blocks.append((start, current))
            current = None
        else:
            current.append(line)
    return blocks


def test_every_module_panel_call_in_a_bash_block_cds_to_the_skill_dir():
    blocks = _bash_blocks(SKILL_MD.read_text(encoding="utf-8"))
    offenders: list[str] = []
    found = 0
    for start, lines in blocks:
        for i, line in enumerate(lines):
            # A shell comment explaining the trap is not an invocation of it.
            if "-m panel" not in line or line.lstrip().startswith("#"):
                continue
            found += 1
            if not any(CD_LINE in earlier for earlier in lines[:i]):
                offenders.append(f"SKILL.md:{start + 1 + i}: {line.strip()}")
    # Guard the guard: a parser that finds nothing would pass vacuously.
    assert found >= 4, f"expected >=4 `-m panel` calls in bash blocks, found {found}"
    assert not offenders, (
        "these `python -m panel` calls run from an unknown cwd and would load "
        "the ~/.claude/panel CONFIG directory as a namespace package:\n  "
        + "\n  ".join(offenders)
    )
