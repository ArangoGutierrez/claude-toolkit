import contextlib
import io
import json
import os
import shutil
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import fetch_ai_reviews  # noqa: E402
from fetch_ai_reviews import (  # noqa: E402
    collect, fetch, load_allowlist, main,
)

SHIPPED_ALLOWLIST = os.path.join(
    os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
    "ai-reviewers.json")

ALLOWLIST = {
    "coderabbitai[bot]": "CodeRabbit",
    "copilot-pull-request-reviewer[bot]": "Copilot",
    "greptile-apps[bot]": "Greptile",
}

# Shapes copied from live gh api responses on 2026-08-28. CodeRabbit posts its
# walkthrough on issues/{n}/comments; Copilot and Greptile post on
# pulls/{n}/reviews. codecov-commenter is a bot that reports type User, and
# github-actions[bot] is type Bot that reviews nothing: both are the reason
# detection keys on the login allowlist rather than on user.type.
ISSUE_COMMENTS = [
    {"id": 5452423076, "user": {"login": "coderabbitai[bot]", "type": "Bot"},
     "body": "## Walkthrough\nThe cfg index is unguarded.",
     "html_url": "https://github.com/o/r/pull/12#issuecomment-5452423076"},
    {"id": 5452430967, "user": {"login": "codecov-commenter", "type": "User"},
     "body": "Coverage decreased by 0.1%.",
     "html_url": "https://github.com/o/r/pull/12#issuecomment-5452430967"},
    {"id": 5452430999, "user": {"login": "github-actions[bot]", "type": "Bot"},
     "body": "Build succeeded.",
     "html_url": "https://github.com/o/r/pull/12#issuecomment-5452430999"},
]

REVIEWS = [
    {"id": 3311, "user": {"login": "copilot-pull-request-reviewer[bot]", "type": "Bot"},
     "state": "COMMENTED", "body": "Reviewed 3 files and found one issue.",
     "html_url": "https://github.com/o/r/pull/12#pullrequestreview-3311"},
    {"id": 3312, "user": {"login": "ArangoGutierrez", "type": "User"},
     "state": "APPROVED", "body": "lgtm",
     "html_url": "https://github.com/o/r/pull/12#pullrequestreview-3312"},
]

INLINE = [
    {"id": 991, "user": {"login": "greptile-apps[bot]", "type": "Bot"},
     "path": "pkg/foo.go", "line": 42, "original_line": 40,
     "body": "Nil deref when cfg is empty.",
     "html_url": "https://github.com/o/r/pull/12#discussion_r991"},
    {"id": 992, "user": {"login": "greptile-apps[bot]", "type": "Bot"},
     "path": "pkg/bar.go", "line": None, "original_line": 7,
     "body": "Outdated hunk note.",
     "html_url": "https://github.com/o/r/pull/12#discussion_r992"},
]

ALL = {"issue_comment": ISSUE_COMMENTS, "review": REVIEWS, "inline": INLINE}


class DetectionTests(unittest.TestCase):
    def test_finds_coderabbit_on_the_issue_comment_surface(self):
        got = collect({"issue_comment": ISSUE_COMMENTS}, ALLOWLIST)
        self.assertEqual([r["comment_id"] for r in got], [5452423076])
        self.assertEqual(got[0]["reviewer"], "CodeRabbit")
        self.assertEqual(got[0]["surface"], "issue_comment")

    def test_rejects_codecov_commenter_despite_it_being_a_bot(self):
        # It reports type User AND is not a reviewer. A type-based filter would
        # miss it; an all-bots filter would wrongly include it.
        got = collect({"issue_comment": ISSUE_COMMENTS}, ALLOWLIST)
        self.assertNotIn("codecov-commenter",
                         [r["reviewer"] for r in got])

    def test_rejects_github_actions_which_is_type_bot_but_reviews_nothing(self):
        got = collect({"issue_comment": ISSUE_COMMENTS}, ALLOWLIST)
        self.assertEqual(len(got), 1)

    def test_reads_all_three_surfaces(self):
        got = collect(ALL, ALLOWLIST)
        self.assertEqual(
            sorted({r["surface"] for r in got}),
            ["inline", "issue_comment", "review"])

    def test_ignores_human_reviews(self):
        got = collect({"review": REVIEWS}, ALLOWLIST)
        self.assertEqual([r["comment_id"] for r in got], [3311])

    def test_login_match_is_case_insensitive(self):
        payload = [{"id": 1, "user": {"login": "CodeRabbitAI[bot]", "type": "Bot"},
                    "body": "x", "html_url": "u"}]
        got = collect({"issue_comment": payload}, ALLOWLIST)
        self.assertEqual(len(got), 1)

    def test_empty_input_yields_empty_list(self):
        self.assertEqual(collect({}, ALLOWLIST), [])
        self.assertEqual(collect({"issue_comment": []}, ALLOWLIST), [])


class NormalizationTests(unittest.TestCase):
    def test_non_line_anchored_surfaces_carry_null_path_and_line(self):
        got = collect({"issue_comment": ISSUE_COMMENTS}, ALLOWLIST)
        self.assertIsNone(got[0]["path"])
        self.assertIsNone(got[0]["line"])

    def test_inline_carries_path_and_line(self):
        got = collect({"inline": INLINE}, ALLOWLIST)
        self.assertEqual((got[0]["path"], got[0]["line"]), ("pkg/foo.go", 42))

    def test_inline_falls_back_to_original_line_when_line_is_null(self):
        # An outdated inline comment has line=null; original_line still anchors it.
        got = collect({"inline": INLINE}, ALLOWLIST)
        self.assertEqual(got[1]["line"], 7)

    def test_body_and_url_are_carried_through(self):
        got = collect({"inline": INLINE}, ALLOWLIST)
        self.assertEqual(got[0]["body"], "Nil deref when cfg is empty.")
        self.assertEqual(got[0]["url"],
                         "https://github.com/o/r/pull/12#discussion_r991")


class AllowlistFileTests(unittest.TestCase):
    def test_load_allowlist_lowercases_keys_and_maps_display_names(self):
        with tempfile.NamedTemporaryFile("w", suffix=".json", delete=False,
                                         encoding="utf-8") as handle:
            json.dump({"reviewers": [
                {"login": "CodeRabbitAI[bot]", "display": "CodeRabbit"}]}, handle)
            path = handle.name
        try:
            self.assertEqual(load_allowlist(path),
                             {"coderabbitai[bot]": "CodeRabbit"})
        finally:
            os.unlink(path)

    def test_shipped_allowlist_parses_and_holds_the_three_verified_logins(self):
        shipped = os.path.join(
            os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
            "ai-reviewers.json")
        allowlist = load_allowlist(shipped)
        for login in ("coderabbitai[bot]", "copilot-pull-request-reviewer[bot]",
                      "greptile-apps[bot]"):
            self.assertIn(login, allowlist)


# A fake `gh` placed first on PATH. The shell-out itself is the thing under
# test, so monkeypatching subprocess away would leave the argv it builds and the
# exit code it reads untested. `$3` is the endpoint: argv is `api --paginate X`.
ALL_FAIL_SHIM = """
echo 'gh: To get started with GitHub CLI, please run:  gh auth login' >&2
exit 1
"""

PARTIAL_FAIL_SHIM = """
echo "$3" >> __LOG__
case "$3" in
  *"/issues/"*)
    echo 'gh: HTTP 401: Bad credentials' >&2
    exit 1
    ;;
  *"/pulls/"*"/comments")
    echo '[{"id": 991, "user": {"login": "greptile-apps[bot]", "type": "Bot"}, "path": "pkg/foo.go", "line": 42, "body": "Nil deref.", "html_url": "u991"}]'
    ;;
  *)
    echo '[]'
    ;;
esac
"""

LOG_ONLY_SHIM = """
echo "$3" >> __LOG__
echo '[]'
"""


class GhShimTestCase(unittest.TestCase):
    """Base for tests that drive the gh shell-out through a fake gh on PATH."""

    def setUp(self):
        self.bindir = tempfile.mkdtemp(prefix="gh-shim-")
        self.logfile = os.path.join(self.bindir, "endpoints.log")
        self.outfile = os.path.join(self.bindir, "out.json")
        self._saved_path = os.environ["PATH"]
        os.environ["PATH"] = self.bindir + os.pathsep + self._saved_path

    def tearDown(self):
        os.environ["PATH"] = self._saved_path
        shutil.rmtree(self.bindir, ignore_errors=True)

    def install_gh(self, body):
        path = os.path.join(self.bindir, "gh")
        with open(path, "w", encoding="utf-8") as handle:
            handle.write("#!/bin/sh\n" + body.replace("__LOG__", self.logfile))
        os.chmod(path, 0o755)
        # Without this the real gh could answer and every test below would pass
        # for the wrong reason, or hit the network.
        self.assertEqual(shutil.which("gh"), path)
        return path


class SurfaceFailureTests(GhShimTestCase):
    def test_one_unreadable_surface_is_none_while_the_others_still_carry_records(self):
        # Tolerance is the point: a 404 or a permissions gap on one endpoint must
        # not discard the findings the other two returned.
        self.install_gh(PARTIAL_FAIL_SHIM)
        payloads = fetch("o/r", 12)
        self.assertIsNone(payloads["issue_comment"])
        self.assertEqual(payloads["review"], [])
        self.assertEqual([raw["id"] for raw in payloads["inline"]], [991])
        got = collect(payloads, ALLOWLIST)
        self.assertEqual([r["comment_id"] for r in got], [991])

    def test_partial_failure_still_exits_zero_and_writes_the_surviving_records(self):
        self.install_gh(PARTIAL_FAIL_SHIM)
        with contextlib.redirect_stdout(io.StringIO()), \
                contextlib.redirect_stderr(io.StringIO()):
            rc = main(["--repo", "o/r", "--number", "12",
                       "--allowlist", SHIPPED_ALLOWLIST, "--out", self.outfile])
        self.assertEqual(rc, 0)
        with open(self.outfile, encoding="utf-8") as handle:
            written = json.load(handle)
        self.assertEqual([r["reviewer"] for r in written], ["Greptile"])

    def test_every_surface_unreadable_exits_two_and_writes_no_output(self):
        # The failure this guards: an expired token made all three endpoints
        # fail, the tool printed "none", exited 0, and Task 4 skipped Reconcile
        # as though the PR simply had no AI review on it.
        self.install_gh(ALL_FAIL_SHIM)
        stderr = io.StringIO()
        with contextlib.redirect_stdout(io.StringIO()), \
                contextlib.redirect_stderr(stderr):
            rc = main(["--repo", "o/r", "--number", "12",
                       "--allowlist", SHIPPED_ALLOWLIST, "--out", self.outfile])
        self.assertEqual(rc, 2)
        self.assertEqual(rc, fetch_ai_reviews.EXIT_ALL_SURFACES_UNREADABLE)
        self.assertFalse(os.path.exists(self.outfile))
        self.assertIn("gh auth status", stderr.getvalue())

    def test_every_surface_unreadable_removes_a_stale_out_file(self):
        # The regression this guards: exiting 2 without touching --out left an
        # earlier run's records at a path Reconcile reads, so it would run
        # against a different run's AI findings. The output path is fixed by the
        # plan, so a stale file at it is reachable in normal use.
        self.install_gh(ALL_FAIL_SHIM)
        stale = [{"reviewer": "CodeRabbit", "surface": "issue_comment",
                  "comment_id": 4242, "path": None, "line": None,
                  "body": "records from an earlier run", "url": "u4242"}]
        with open(self.outfile, "w", encoding="utf-8") as handle:
            json.dump(stale, handle)
        self.assertTrue(os.path.exists(self.outfile))

        with contextlib.redirect_stdout(io.StringIO()), \
                contextlib.redirect_stderr(io.StringIO()):
            rc = main(["--repo", "o/r", "--number", "12",
                       "--allowlist", SHIPPED_ALLOWLIST, "--out", self.outfile])
        self.assertEqual(rc, 2)
        self.assertEqual(rc, fetch_ai_reviews.EXIT_ALL_SURFACES_UNREADABLE)
        self.assertFalse(os.path.exists(self.outfile))

    def test_the_gh_diagnostic_reaches_stderr_instead_of_being_discarded(self):
        # "HTTP 401" or "gh auth login" is the entire answer when this happens.
        self.install_gh(ALL_FAIL_SHIM)
        stderr = io.StringIO()
        with contextlib.redirect_stderr(stderr):
            self.assertIsNone(
                fetch_ai_reviews._gh_json("repos/o/r/pulls/12/reviews"))
        self.assertIn("gh auth login", stderr.getvalue())

    def test_a_readable_but_empty_surface_is_an_empty_list_not_none(self):
        # The distinction the loud path rests on: nothing to report is [], and
        # only an unreadable surface is None.
        self.install_gh(LOG_ONLY_SHIM)
        payloads = fetch("o/r", 12)
        self.assertEqual(
            [payloads[surface] for surface in ("issue_comment", "review", "inline")],
            [[], [], []])


class PurgeBeforeReadTests(GhShimTestCase):
    """--out is cleared before anything is read, not on a selected failure path.

    Reproduced 2026-08-31 against the pre-fix script: seeding --out and running
    with --allowlist /nonexistent/path exited 1 on an uncaught FileNotFoundError
    with the seeded records still sitting at --out. Step 4.5 reads that path by
    name, so an earlier run's bot comments would be reconciled as this run's.
    """

    def _seed(self):
        stale = [{"reviewer": "CodeRabbit", "surface": "issue_comment",
                  "comment_id": 4242, "path": None, "line": None,
                  "body": "records from an earlier run", "url": "u4242"}]
        with open(self.outfile, "w", encoding="utf-8") as handle:
            json.dump(stale, handle)
        self.assertTrue(os.path.exists(self.outfile))

    def test_an_unreadable_allowlist_leaves_no_stale_out_file(self):
        # rc=1 is the uncaught-error code and is now documented. The abort
        # happens on the allowlist read, which is why the purge has to sit
        # ahead of it rather than on the all-surfaces-unreadable branch.
        self.install_gh(LOG_ONLY_SHIM)
        self._seed()
        with self.assertRaises(FileNotFoundError):
            main(["--repo", "o/r", "--number", "12",
                  "--allowlist", os.path.join(self.bindir, "no-such.json"),
                  "--out", self.outfile])
        self.assertFalse(os.path.exists(self.outfile))

    def test_rc_1_is_documented_in_the_exit_code_help(self):
        # An operator gates on the exit code. An undocumented one sends them to
        # the source, and the SKILL's step 4.5 has no branch for it.
        self.assertIn("  1  ", fetch_ai_reviews.EXIT_CODE_HELP)

    def test_an_out_path_that_is_a_directory_exits_three_and_fetches_nothing(self):
        # A directory at --out made os.remove raise an OSError that only
        # FileNotFoundError was catching (PermissionError on macOS,
        # IsADirectoryError on Linux), and it escaped as an undocumented rc=1
        # traceback. It now aborts on a named code, before gh is called at all:
        # a path that cannot be cleared cannot be trusted to hold this run's
        # records.
        self.install_gh(LOG_ONLY_SHIM)
        outdir = os.path.join(self.bindir, "out-as-dir")
        os.mkdir(outdir)
        stderr = io.StringIO()
        with contextlib.redirect_stdout(io.StringIO()), \
                contextlib.redirect_stderr(stderr):
            rc = main(["--repo", "o/r", "--number", "12",
                       "--allowlist", SHIPPED_ALLOWLIST, "--out", outdir])
        self.assertEqual(rc, 3)
        self.assertEqual(rc, fetch_ai_reviews.EXIT_OUT_NOT_REMOVABLE)
        self.assertIn(outdir, stderr.getvalue())
        self.assertTrue(os.path.isdir(outdir))
        # Nothing was fetched: the abort precedes the gh shell-out entirely.
        self.assertFalse(os.path.exists(self.logfile))

    def test_rc_3_is_documented_in_the_exit_code_help(self):
        self.assertIn("  3  ", fetch_ai_reviews.EXIT_CODE_HELP)


class EndpointTests(GhShimTestCase):
    def test_fetch_requests_the_three_documented_endpoint_paths(self):
        # These literals came from the plan and had no executable check. A typo
        # in one of them 404s, which used to read as "no AI reviewer commented".
        self.install_gh(LOG_ONLY_SHIM)
        fetch("o/r", 12)
        with open(self.logfile, encoding="utf-8") as handle:
            asked = [line.strip() for line in handle if line.strip()]
        self.assertEqual(asked, [
            "repos/o/r/issues/12/comments",
            "repos/o/r/pulls/12/reviews",
            "repos/o/r/pulls/12/comments",
        ])


if __name__ == "__main__":
    unittest.main(verbosity=2)
