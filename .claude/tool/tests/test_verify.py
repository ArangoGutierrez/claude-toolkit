import os
import shutil
import pytest

from tool.verify import (
    denylisted_reason, validate_check, validate_checklist,
    CheckVerdict, _sandbox_profile,
)

_HAS_SANDBOX = shutil.which("sandbox-exec") is not None
needs_sandbox = pytest.mark.skipif(not _HAS_SANDBOX, reason="sandbox-exec only on macOS")


# --- denylist pre-gate (each input flips the guard; assert exact reason) ---

def test_denylist_rejects_rm():
    assert denylisted_reason("rm -rf /tmp/x") == "denied binary 'rm'"

def test_denylist_rejects_redirection():
    assert denylisted_reason("echo hi > out.txt") == "shell metacharacter '>'"

def test_denylist_rejects_chaining():
    assert denylisted_reason("go test ./... && rm x") == "shell metacharacter '&&'"

def test_denylist_rejects_git_push():
    assert denylisted_reason("git push origin main") == "denied git subcommand 'push'"

def test_denylist_rejects_curl():
    assert denylisted_reason("curl http://example.com") == "denied binary 'curl'"

def test_denylist_allows_plain_checks():
    assert denylisted_reason("go test ./...") is None
    assert denylisted_reason("golangci-lint run") is None
    assert denylisted_reason("pytest -q") is None

def test_denylist_allows_quoted_semicolon():
    # the ';' is inside a quoted arg -> a single safe command -> allowed
    assert denylisted_reason('python3 -c "import x; print(1)"') is None

def test_denylist_allows_quoted_parens():
    assert denylisted_reason('pytest -k "test_foo and bar(baz)"') is None

def test_denylist_rejects_bare_semicolon():
    assert denylisted_reason("a; b") == "shell metacharacter ';'"
    assert denylisted_reason("a;b") == "shell metacharacter ';'"

def test_denylist_rejects_command_substitution():
    assert denylisted_reason("echo $(whoami)") == "shell metacharacter '('"

def test_denylist_rejects_backtick():
    assert denylisted_reason("echo `whoami`") == "backtick command substitution"


# --- sandbox profile must deny network and jail writes (regression guard) ---

def test_profile_denies_network_and_jails_writes(tmp_path):
    prof = _sandbox_profile(tmp_path)
    assert "(deny network*)" in prof
    assert "(deny file-write*)" in prof
    # repo root is realpath-resolved into an allow rule
    assert f'(subpath "{os.path.realpath(tmp_path)}")' in prof

def test_validate_passes_profile_to_sandbox_exec(tmp_path, monkeypatch):
    captured = {}
    class _CP:
        returncode = 0; stdout = ""; stderr = ""
    monkeypatch.setattr("tool.verify.shutil.which", lambda name: "/usr/bin/sandbox-exec")
    monkeypatch.setattr("tool.verify.subprocess.run", lambda argv, **kw: captured.update(argv=argv) or _CP())
    validate_check("true", tmp_path)
    assert captured["argv"][0] == "sandbox-exec" and captured["argv"][1] == "-p"
    assert "(deny network*)" in captured["argv"][2] and "(deny file-write*)" in captured["argv"][2]


# --- classification (real sandbox exec on macOS) ---

@needs_sandbox
def test_validate_runnable_passes(tmp_path):
    v = validate_check("true", tmp_path)
    assert v.status == "runnable" and v.detail == "passes" and v.exit_code == 0

@needs_sandbox
def test_validate_runnable_fails(tmp_path):
    v = validate_check("false", tmp_path)
    assert v.status == "runnable" and v.detail == "fails (exit 1)" and v.exit_code == 1

@needs_sandbox
def test_validate_broken_command_not_found(tmp_path):
    v = validate_check("nonexistent-bin-xyz-123", tmp_path)
    assert v.status == "broken" and v.exit_code == 127 and v.detail == "command not found / not executable"

@needs_sandbox
def test_validate_timeout_is_broken(tmp_path):
    v = validate_check("sleep 5", tmp_path, timeout=0.5)
    assert v.status == "broken" and v.detail == "timeout"


# --- behavioral write-jail tests (security discriminators) ---

@needs_sandbox
def test_sandbox_allows_write_inside_root(tmp_path):
    v = validate_check("touch jail_probe", tmp_path)
    assert v.status == "runnable" and v.exit_code == 0
    assert (tmp_path / "jail_probe").exists()   # fails if the realpath resolution is wrong

@needs_sandbox
def test_sandbox_denies_write_outside_root(tmp_path):
    sentinel = f"/tmp/kjail_denied_{os.getpid()}"   # /tmp -> /private/tmp: outside repo/TMPDIR/cache allowlist
    try:
        v = validate_check(f"touch {sentinel}", tmp_path)
        assert v.status == "runnable" and v.exit_code != 0   # ran, but the write was blocked
        assert not os.path.exists(sentinel)                  # jail actually prevented the write
    finally:
        try:
            os.remove(sentinel)
        except OSError:
            pass


# --- fail-open when sandbox-exec is absent ---

def test_validate_unvalidated_when_no_sandbox(tmp_path, monkeypatch):
    monkeypatch.setattr("tool.verify.shutil.which", lambda name: None)
    v = validate_check("true", tmp_path)
    assert v.status == "unvalidated" and "sandbox-exec" in v.detail


# --- checklist budgets (overflow is surfaced as unvalidated, never dropped) ---

def test_validate_checklist_max_checks_caps(tmp_path, monkeypatch):
    monkeypatch.setattr("tool.verify.validate_check",
                        lambda cmd, root, timeout=15.0: CheckVerdict(status="runnable", detail="passes", exit_code=0))
    cmds = [f"true {i}" for i in range(9)]
    verdicts = validate_checklist(cmds, tmp_path, max_checks=8)
    assert len(verdicts) == 9                 # 1:1 with inputs, nothing dropped
    assert verdicts[8].status == "unvalidated"
    assert sum(1 for v in verdicts if v.status == "runnable") == 8

def test_validate_checklist_total_timeout_caps(tmp_path, monkeypatch):
    monkeypatch.setattr("tool.verify.validate_check",
                        lambda cmd, root, timeout=15.0: CheckVerdict(status="runnable", detail="passes"))
    ticks = iter([0.0, 0.0, 100.0, 100.0])    # start, i0 (ok), i1 (>60 -> unvalidated), i2
    verdicts = validate_checklist(["true", "true", "true"], tmp_path,
                                  total_timeout=60.0, clock=lambda: next(ticks))
    assert verdicts[0].status == "runnable"
    assert verdicts[1].status == "unvalidated"
    assert verdicts[2].status == "unvalidated"
