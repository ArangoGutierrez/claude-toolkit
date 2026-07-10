import pytest
from pathlib import Path
from tool.security import jail_path, read_capped, is_denylisted
from tool.errors import ToolError


def test_jail_path_allows_inside_root(tmp_path):
    (tmp_path / "go.mod").write_text("module x\n")
    p = jail_path(tmp_path, "go.mod")
    assert p == (tmp_path / "go.mod").resolve()


def test_jail_path_rejects_parent_escape(tmp_path):
    with pytest.raises(ToolError, match="outside repository root"):
        jail_path(tmp_path, "../../etc/passwd")


def test_jail_path_rejects_symlink_escape(tmp_path):
    outside = tmp_path.parent / "outside_secret.txt"
    outside.write_text("top secret")
    link = tmp_path / "link"
    link.symlink_to(outside)
    with pytest.raises(ToolError, match="outside repository root"):
        jail_path(tmp_path, "link")


@pytest.mark.parametrize("name", [".env", ".env.local", "api_token.txt",
                                  "my_secret.yaml", "server.pem", "tls.key", "id_rsa",
                                  "db_password.yaml", "My_Secret.YAML"])
def test_jail_path_rejects_secret_names(tmp_path, name):
    (tmp_path / name).write_text("x")
    with pytest.raises(ToolError, match="denylisted"):
        jail_path(tmp_path, name)


def test_jail_path_rejects_ssh_dir_component(tmp_path):
    (tmp_path / ".ssh").mkdir()
    (tmp_path / ".ssh" / "config").write_text("x")
    with pytest.raises(ToolError, match="denylisted"):
        jail_path(tmp_path, ".ssh/config")


def test_jail_path_rejects_aws_dir_component(tmp_path):
    # Use "config" as the filename — it matches no glob, so the ToolError can only
    # come from the .aws dir-component check. This ensures the guard is exercised.
    (tmp_path / ".aws").mkdir()
    (tmp_path / ".aws" / "config").write_text("x")
    with pytest.raises(ToolError, match="denylisted"):
        jail_path(tmp_path, ".aws/config")


def test_read_capped_truncates(tmp_path):
    f = tmp_path / "big.txt"
    f.write_text("A" * 10000)
    out = read_capped(f, cap=8192)
    assert len(out.encode("utf-8")) == 8192


def test_read_capped_rejects_binary(tmp_path):
    f = tmp_path / "bin"
    f.write_bytes(b"\x00\x01\x02\x03")
    with pytest.raises(ToolError, match="binary"):
        read_capped(f, cap=8192)


def test_is_denylisted_true_for_credentials():
    assert is_denylisted(Path("config/credentials.json")) is True
    assert is_denylisted(Path("src/main.go")) is False
