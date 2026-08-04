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
    # '&&' is now an allowed operator, so this input must still be rejected for a
    # STRONGER reason: the denylist runs per segment, and segment 2 invokes rm.
    assert denylisted_reason("go test ./... && rm x") == "denied binary 'rm'"

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


# --- substitution / background forms that were never covered before ---

def test_denylist_rejects_process_substitution():
    assert denylisted_reason("cat <(cmd)") == "shell metacharacter '<('"

def test_denylist_rejects_arithmetic_expansion():
    assert denylisted_reason("echo $((1+1))") == "shell metacharacter '(('"

def test_denylist_rejects_background_operator():
    assert denylisted_reason("cmd &") == "shell metacharacter '&'"


# --- the 2>&1 allowance is EXACT: any other '>&' stays denied ---

def test_denylist_allows_exact_stderr_redirect():
    assert denylisted_reason("bash tests/run-tests.sh 2>&1 | tail -1") is None

def test_denylist_rejects_other_fd_redirect():
    # a '>&' whose neighbours are not exactly 2 and 1 is a file write, not a merge
    assert denylisted_reason("cmd >& f") == "shell metacharacter '>&'"
    assert denylisted_reason("cmd 1>&2") == "shell metacharacter '>&'"


# --- allowed operators: the split is TOKEN-level, so quoted ops stay inert ---

def test_denylist_allows_chained_acceptance_checks():
    assert denylisted_reason("test -x f && echo OK") is None
    assert denylisted_reason("make test || true") is None

def test_denylist_allows_quoted_operator_inside_argument():
    # the '&&' lives inside a quoted arg -> one token -> never an operator
    assert denylisted_reason('grep -q "a && b" file') is None


# --- the denylist now runs PER SEGMENT (this is what allowing '&&' costs) ---

def test_denylist_rejects_denied_binary_in_later_segment():
    assert denylisted_reason("echo ok && rm -rf x") == "denied binary 'rm'"

def test_denylist_rejects_git_subcommand_in_later_segment():
    assert denylisted_reason("echo ok && git push") == "denied git subcommand 'push'"


# --- the git check is NON-POSITIONAL (closes a hole that predates chaining) ---

def test_denylist_rejects_git_behind_a_wrapper():
    # both of these returned None before: the check read only tokens[0]/tokens[1]
    assert denylisted_reason("env git push") == "denied git subcommand 'push'"
    assert denylisted_reason("nice git reset") == "denied git subcommand 'reset'"


# --- an operator with nothing on one side is not a command ---

def test_denylist_rejects_attached_comment():
    # shlex starts a comment at an attached '#'; /bin/sh does NOT -- it runs the
    # rest. Without commenters disabled the whole filter is bypassed:
    # `/bin/sh -c 'echo x#; rm -rf y'` deletes y.
    assert denylisted_reason("echo x#; rm -rf y") == "shell metacharacter ';'"
    assert denylisted_reason("ls#&& rm -rf y") == "denied binary 'rm'"

def test_denylist_allows_hash_inside_argument():
    assert denylisted_reason("grep -q '#include' f") is None

def test_denylist_rejects_comment_only_command():
    # disabling shlex comments made these parse to real tokens, so they stopped
    # being "empty command" and validated as runnable/passes -- a definition of
    # done that can NEVER fail, which is the exact bug this module exists to stop
    assert denylisted_reason("# just a comment") == "empty command"
    assert denylisted_reason("#") == "empty command"
    assert denylisted_reason("#!/bin/sh") == "empty command"


def test_denylist_rejects_git_subcommand_behind_an_option():
    # the check must scan the whole segment: a git OPTION may precede the
    # subcommand, and `git -C <dir> clean -fdx` deletes files inside the root,
    # which the Seatbelt profile permits
    assert denylisted_reason("git -C /tmp/x clean -fdx") == "denied git subcommand 'clean'"
    assert denylisted_reason("git --git-dir=x push") == "denied git subcommand 'push'"
    assert denylisted_reason("git --no-pager reset --hard") == "denied git subcommand 'reset'"
    # '-c' is now denied as a mechanism, BEFORE the subcommand is even read,
    # so this input is still rejected and for a broader reason
    assert denylisted_reason("git -c a=b commit -m z") == "git config override"
    assert denylisted_reason("git.exe push") == "denied git subcommand 'push'"

def test_denylist_rejects_config_override_through_the_environment():
    # git reads GIT_CONFIG_COUNT/KEY_n/VALUE_n, so the override needs no '-c'
    # at all. This form deleted a worktree while reporting 'passes'.
    assert denylisted_reason(
        "GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=alias.z GIT_CONFIG_VALUE_0='clean -fdx' git z"
    ) == "git config override through the environment"
    assert denylisted_reason(
        "GIT_CONFIG_KEY_0=core.fsmonitor GIT_CONFIG_VALUE_0='rm -rf w' git status"
    ) == "git config override through the environment"

def test_denylist_rejects_environment_that_redirects_code_resolution():
    assert denylisted_reason("PATH=/tmp/evil:$PATH git zzz") == "environment redirects code resolution"
    assert denylisted_reason("DYLD_INSERT_LIBRARIES=/tmp/x.dylib make test") == "environment redirects code resolution"

def test_denylist_rejects_git_exec_path():
    # --exec-path relocates where git finds its subcommand binaries
    assert denylisted_reason("git --exec-path=/tmp/evil zzz") == "git exec-path override"
    assert denylisted_reason("git --exec-path /tmp/evil zzz") == "git exec-path override"

def test_denylist_only_treats_git_as_git_in_command_position():
    # 'git' as an ARGUMENT to another command is not a git invocation;
    # `grep git -c README.md` was wrongly rejected as a config override
    assert denylisted_reason("grep git -c README.md") is None
    assert denylisted_reason("echo git -c foo") is None
    # ...but a wrapper still resolves through to the real command word
    assert denylisted_reason("env git push") == "denied git subcommand 'push'"
    assert denylisted_reason("nice git reset") == "denied git subcommand 'reset'"


def test_denylist_rejects_the_whole_config_override_mechanism():
    # INVARIANT: '-c'/'--config-env' BEFORE the subcommand is denied outright.
    # Guarding the key name 'alias.' is not enough -- git config keys are
    # case-INSENSITIVE, and several non-alias keys run their value as a
    # command (core.pager, core.fsmonitor, diff.external, core.sshCommand).
    assert denylisted_reason("git -c ALIAS.z='clean -fdx' z") == "git config override"
    assert denylisted_reason("git -c Alias.z=clean z") == "git config override"
    assert denylisted_reason("git -c core.fsmonitor='rm -rf work.txt' status") == "git config override"
    assert denylisted_reason("git -c alias.z='clean -fdx' z") == "git config override"
    assert denylisted_reason("git --config-env=alias.z=ZV z") == "git config override"
    assert denylisted_reason("ZV='clean -fdx' git --config-env=alias.z=ZV z") == "git config override"

def test_denylist_allows_dash_c_belonging_to_a_subcommand():
    # after the subcommand, '-c' is the SUBCOMMAND's flag, not git's config
    # override, so denying it there would break a read-only check
    assert denylisted_reason("git grep -c foo") is None
    assert denylisted_reason("git shortlog -c") is None

def test_denylist_skips_the_value_of_attr_source():
    # --attr-source consumes the NEXT token, so without it in the skip set the
    # subcommand is misread and 'clean -fdx' runs
    assert denylisted_reason("git --attr-source HEAD clean -fdx") == "denied git subcommand 'clean'"


def test_denylist_rejects_git_alias_smuggling():
    # the subcommand hides inside a QUOTED token, so scanning tokens never sees
    # it; `git -c alias.z='clean -fdx' z` really does delete files. The whole
    # -c mechanism is denied, so the reason names the mechanism.
    assert denylisted_reason("git -c alias.p=push p") == "git config override"
    # reached as a subcommand instead, `config` is itself denied
    assert denylisted_reason("git config --get alias.push") == "denied git subcommand 'config'"

def test_denylist_rejects_destructive_read_family():
    # a five-word denylist missed the whole restore/checkout family;
    # `git restore work.txt` silently overwrites uncommitted work
    assert denylisted_reason("git restore work.txt") == "denied git subcommand 'restore'"
    assert denylisted_reason("git checkout .") == "denied git subcommand 'checkout'"
    assert denylisted_reason("git stash") == "denied git subcommand 'stash'"
    assert denylisted_reason("git branch -D main") == "denied git subcommand 'branch'"
    assert denylisted_reason("git worktree remove x") == "denied git subcommand 'worktree'"
    assert denylisted_reason("git gc --prune=now") == "denied git subcommand 'gc'"

def test_denylist_allows_git_read_subcommands():
    assert denylisted_reason("git -C /tmp/x status") is None
    assert denylisted_reason("git log --oneline -1") is None

def test_denylist_does_not_confuse_an_argument_for_a_subcommand():
    # only the first NON-OPTION token after git is the subcommand. A denied word
    # appearing as a search term or a ref is not an invocation of it.
    assert denylisted_reason("git grep -q push -- .") is None
    assert denylisted_reason("git log --grep=push") is None
    assert denylisted_reason("git diff main..push") is None
    assert denylisted_reason("git show HEAD:reset.txt") is None


def test_denylist_rejects_empty_segment():
    assert denylisted_reason("&& echo hi") == "empty command segment"
    assert denylisted_reason("echo hi &&") == "empty command segment"
    assert denylisted_reason("a && && b") == "empty command segment"


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
def test_pipeline_reports_left_side_failure(tmp_path):
    # a pipeline returns its LAST command's status, so without `set -o pipefail`
    # `make test 2>&1 | tail -1` would be labelled "runs; passes" on a RED suite
    v = validate_check("false | true", tmp_path)
    assert v.status == "runnable" and v.exit_code == 1 and v.detail == "fails (exit 1)"


@needs_sandbox
def test_sigpipe_is_labelled_distinctly(tmp_path):
    # pipefail makes a consumer that closes early (`| head`) surface as 141.
    # The check actually PASSED, so the detail must say so rather than read as
    # an ordinary failure. A finite producer is unaffected (test below).
    v = validate_check("yes | head -1", tmp_path)
    assert v.detail == "fails (exit 141; SIGPIPE, a pipeline consumer closed early)"

@needs_sandbox
def test_141_without_a_pipeline_is_not_called_sigpipe(tmp_path):
    # exit 141 from a command with no pipe is an ordinary failure; naming a
    # cause that cannot apply states something false
    v = validate_check("exit 141", tmp_path)
    assert v.detail == "fails (exit 141)"

@needs_sandbox
def test_finite_producer_into_head_still_passes(tmp_path):
    v = validate_check("grep -c . /etc/hosts | head -1", tmp_path)
    assert v.status == "runnable" and v.exit_code == 0 and v.detail == "passes"


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
