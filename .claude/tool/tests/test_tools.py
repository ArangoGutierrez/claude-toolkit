import subprocess
import pytest
from tool.tools import readonly_tools
from tool.errors import ToolError


def _by_name(root):
    return {t.name: t for t in readonly_tools(root)}


def _git_repo(tmp_path):
    subprocess.run(["git", "init", "-q"], cwd=tmp_path, check=True)
    subprocess.run(["git", "-C", str(tmp_path), "config", "user.email", "t@t"], check=True)
    subprocess.run(["git", "-C", str(tmp_path), "config", "user.name", "t"], check=True)
    return tmp_path


def test_read_file_returns_contents(tmp_path):
    (tmp_path / "go.mod").write_text("module example.com/x\n")
    t = _by_name(tmp_path)["read_file"]
    assert "module example.com/x" in t.run(path="go.mod")


def test_read_file_rejects_escape(tmp_path):
    t = _by_name(tmp_path)["read_file"]
    with pytest.raises(ToolError, match="outside repository root"):
        t.run(path="../../etc/passwd")


def test_read_file_rejects_secret(tmp_path):
    (tmp_path / ".env").write_text("API_KEY=zzz")
    t = _by_name(tmp_path)["read_file"]
    with pytest.raises(ToolError, match="denylisted"):
        t.run(path=".env")


def test_list_dir_caps_entries(tmp_path):
    for i in range(500):
        (tmp_path / f"f{i}.txt").write_text("x")
    t = _by_name(tmp_path)["list_dir"]
    out = t.run(path=".")
    assert len(out.splitlines()) == 200   # 500 files -> capped to exactly 200 entries


def test_grep_finds_match_and_caps(tmp_path):
    _git_repo(tmp_path)
    (tmp_path / "a.go").write_text("func TestFoo() {}\nfunc TestBar() {}\n")
    subprocess.run(["git", "-C", str(tmp_path), "add", "-A"], check=True)
    t = _by_name(tmp_path)["grep"]
    out = t.run(pattern="func Test")
    assert "TestFoo" in out


def test_grep_caps_matches(tmp_path):
    _git_repo(tmp_path)
    body = "\n".join(f"func Test{i}() {{}}" for i in range(100))
    (tmp_path / "many.go").write_text(body + "\n")
    subprocess.run(["git", "-C", str(tmp_path), "add", "-A"], check=True)
    t = _by_name(tmp_path)["grep"]
    out = t.run(pattern="func Test")
    assert len(out.splitlines()) == 50   # capped at _GREP_MAX_LINES; uncapped would be 100


def test_detect_build_tooling_reports_go_and_make(tmp_path):
    (tmp_path / "go.mod").write_text("module x\n")
    (tmp_path / "Makefile").write_text("all:\n\techo hi\n")
    t = _by_name(tmp_path)["detect_build_tooling"]
    out = t.run()
    assert "go" in out and "make" in out


def test_openai_schema_shape(tmp_path):
    t = _by_name(tmp_path)["read_file"]
    s = t.openai_schema()
    assert s["type"] == "function"
    assert s["function"]["name"] == "read_file"
    assert "path" in s["function"]["parameters"]["properties"]
    assert "title" not in s["function"]["parameters"]


def test_read_file_missing_path_raises_toolerror(tmp_path):
    # A model probing a non-existent path must get a ToolError (fed back), not a raw
    # FileNotFoundError that crashes the agentic loop. Removing the existence check
    # in read_file lets read_capped raise FileNotFoundError -> this test goes red.
    t = _by_name(tmp_path)["read_file"]
    with pytest.raises(ToolError, match="no such file"):
        t.run(path="does_not_exist.txt")


def test_read_file_records_citation(tmp_path):
    (tmp_path / "go.mod").write_text("module x\n")
    sink = []
    tools = {t.name: t for t in readonly_tools(tmp_path, sink=sink)}
    tools["read_file"].run(path="go.mod")
    assert sink == ["go.mod"]            # the read file is cited


def test_rejected_read_is_not_cited(tmp_path):
    sink = []
    tools = {t.name: t for t in readonly_tools(tmp_path, sink=sink)}
    with pytest.raises(ToolError):
        tools["read_file"].run(path="../../etc/passwd")
    assert sink == []                    # jail_path raises BEFORE the sink append


def test_grep_records_matched_files(tmp_path):
    _git_repo(tmp_path)
    (tmp_path / "a.go").write_text("func TestFoo() {}\n")
    subprocess.run(["git", "-C", str(tmp_path), "add", "-A"], check=True)
    sink = []
    tools = {t.name: t for t in readonly_tools(tmp_path, sink=sink)}
    tools["grep"].run(pattern="func Test")
    assert "a.go" in sink
