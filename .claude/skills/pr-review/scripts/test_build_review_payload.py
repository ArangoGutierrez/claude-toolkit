import json
import os
import re
import subprocess
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from build_review_payload import (  # noqa: E402
    parse_anchorable, build_payload, validate_tone, render_preview, event_for,
    corroboration_note, build_replies,
    BANNED_TOKENS, FILLER_WORDS, PROCESS_NARRATION,
)

# Two files. foo.py hunk starts new-file line 10; one deletion, two additions,
# two context lines. bar.py hunk starts new-file line 1; one deletion-only line.
SAMPLE_DIFF = """diff --git a/foo.py b/foo.py
index 1111111..2222222 100644
--- a/foo.py
+++ b/foo.py
@@ -10,3 +10,4 @@ def f():
 ctx_a
-old_line
+new_b
+new_c
 ctx_d
diff --git a/bar.py b/bar.py
index 3333333..4444444 100644
--- a/bar.py
+++ b/bar.py
@@ -1,2 +1,2 @@
-removed_only
+added_at_1
 ctx_2
"""

# Every approving payload needs one, so the tests share a realistic value
# rather than each inventing a string that might not survive the tone gate.
THANKS = "Thanks for this, the retry rework is a clear improvement."
EM_DASH = "—"


class ParseAnchorableTests(unittest.TestCase):
    def test_tracks_right_side_line_numbers(self):
        # Hand-derived: ctx_a=10, (old_line deleted, no number), new_b=11,
        # new_c=12, ctx_d=13.
        anchorable = parse_anchorable(SAMPLE_DIFF)
        self.assertEqual(anchorable["foo.py"], {10, 11, 12, 13})

    def test_deletions_dont_advance_counter_and_files_dont_bleed(self):
        # Hand-derived: removed_only deleted (no number), added_at_1=1, ctx_2=2.
        # If a deletion wrongly advanced the counter, this set would be {2, 3}.
        anchorable = parse_anchorable(SAMPLE_DIFF)
        self.assertEqual(anchorable["bar.py"], {1, 2})


ANCHORABLE = {"foo.py": {10, 11, 12, 13}, "bar.py": {1, 2}}


class ValidateToneTests(unittest.TestCase):
    def test_rejects_the_generated_by_trailer(self):
        # Referenced through the constant rather than inlined: the literal is
        # itself a watermark and trips the repo-wide guard on this file.
        with self.assertRaises(ValueError) as ctx:
            validate_tone("summary\n\n" + BANNED_TOKENS[0])
        self.assertIn(BANNED_TOKENS[0], str(ctx.exception))

    def test_rejects_the_config_file_name(self):
        with self.assertRaises(ValueError) as ctx:
            validate_tone("Flagged against CLAUDE.md.")
        self.assertIn("CLAUDE.md", str(ctx.exception))

    def test_clean_text_passes(self):
        # Must not raise.
        validate_tone("Short technical note citing foo.py:11.")


class WidenedToneGateTests(unittest.TestCase):
    """The gate listed four literal tokens, so it caught one robot emoji and
    two hands and missed every other emoji, every filler word, and the em dash.

    ~/.claude/rules/anti-ai-tells.md already names the ranges and the word
    list; enforcing only four of them meant the rule was documented and not
    applied to the one text that leaves the machine under a human's name.
    """

    def test_rejects_an_emoji_outside_the_old_literal_list(self):
        # Rocket, U+1F680. The superseded gate listed only U+1F916 and the
        # two hand signs, so this shipped.
        with self.assertRaises(ValueError):
            validate_tone("Nice work \U0001F680")

    def test_rejects_a_dingbat_range_emoji(self):
        # Sparkles, U+2728, inside the U+2600-U+27BF block.
        with self.assertRaises(ValueError):
            validate_tone("Ship it \U00002728")

    def test_rejects_the_em_dash(self):
        with self.assertRaises(ValueError):
            validate_tone("The parser is fine " + EM_DASH + " the caller is not.")

    def test_rejects_every_filler_word_in_the_canonical_list(self):
        # Iterating the constant rather than restating the words keeps this
        # test honest when the list grows: a new word is covered on arrival.
        self.assertGreater(len(FILLER_WORDS), 10)
        for word in FILLER_WORDS:
            with self.assertRaises(ValueError, msg=word):
                validate_tone("This is a " + word + " change.")

    def test_filler_matches_whole_words_only(self):
        # An identifier that merely contains a banned word is real code and
        # must survive; banning the substring would make the gate unusable.
        for word in FILLER_WORDS:
            validate_tone("Renamed to " + word + "_parser in this hunk.")

    def test_plain_technical_prose_passes(self):
        validate_tone("Guard the index before dereferencing cfg.")


class ProcessNarrationTests(unittest.TestCase):
    """The body used to narrate the review instead of describing the change.

    The reviewer is never the subject of a sentence in a posted review: an
    author gets nothing from being told what was inspected, and every such
    sentence is a machine reporting on its own run. This is the guard that
    keeps the retired clean-review and no-blockers wordings, and any reworded
    descendant of them, from coming back.
    """

    def test_rejects_the_retired_clean_review_body(self):
        # The exact string this skill shipped before the contract changed.
        with self.assertRaises(ValueError):
            validate_tone("Read through the diff and did not find anything "
                          "I would want changed before merge.")

    def test_rejects_the_retired_no_blockers_lead(self):
        with self.assertRaises(ValueError):
            validate_tone("Nothing here blocks merge.")

    def test_rejects_first_person_inspection_verbs(self):
        for text in ("I reviewed the handler and it is fine.",
                     "I checked the retry path.",
                     "I verified the bounds are correct.",
                     "I did not find a problem with the cast."):
            with self.assertRaises(ValueError, msg=text):
                validate_tone(text)

    def test_rejects_verdict_phrasing_about_the_reviewers_own_pass(self):
        for text in ("The v1/v2 dispatch and the static assert hold up.",
                     "The bounds check holds up under concurrent access.",
                     "This does not block merge."):
            with self.assertRaises(ValueError, msg=text):
                validate_tone(text)

    def test_every_listed_phrase_is_actually_rejected(self):
        # Mutation guard: a phrase present in the constant but skipped by the
        # matcher would make the list decorative. Assert each one bites.
        for phrase in PROCESS_NARRATION:
            with self.assertRaises(ValueError, msg=phrase):
                validate_tone("Context " + phrase + " context.")

    def test_describing_the_change_itself_passes(self):
        # The distinction the guard has to draw: this sentence is about the
        # code, not about the review. It must survive.
        validate_tone("The backoff rework removes a real source of flakiness.")
        validate_tone("Retry ceiling is duplicated here and in config.py.")


class SeverityTagToneTests(unittest.TestCase):
    """SKILL.md calls a severity tag in the text non-negotiable and the guard
    did not enforce it, so `[must-fix] ...` reached the PR. The `severity`
    field already decides inline against summary; repeating it in the prose is
    linter-report format wearing a review's clothes."""

    def test_rejects_a_bracketed_severity_tag(self):
        for tag in ("must-fix", "should-fix", "consider",
                    "BLOCKER", "MAJOR", "MINOR", "NIT"):
            with self.assertRaises(ValueError, msg=tag):
                validate_tone("[" + tag + "] Nil deref when cfg is empty.")

    def test_rejects_a_leading_severity_label_with_a_colon(self):
        for tag in ("must-fix", "BLOCKER", "Major", "nit"):
            with self.assertRaises(ValueError, msg=tag):
                validate_tone(tag + ": Nil deref when cfg is empty.")

    def test_rejects_the_bold_severity_prefix_other_tools_mandate(self):
        # The external reviewing-pull-requests guard REQUIRES this shape.
        # Ours forbids it, and the forbidding has to be executable.
        with self.assertRaises(ValueError):
            validate_tone("**BLOCKER:** Nil deref when cfg is empty.")
        with self.assertRaises(ValueError):
            validate_tone("**MAJOR**: Guard the index before dereferencing.")

    def test_severity_words_in_ordinary_prose_survive(self):
        # Discrimination, not blanket keyword banning. These are the sentences
        # a reviewer actually writes; a guard that eats them is worse than no
        # guard, because it pushes the author into vaguer wording.
        validate_tone("Consider caching the parsed config here.")
        validate_tone("Worth a nit-level cleanup once the refactor lands.")
        validate_tone("The major version bump is what breaks the caller.")
        validate_tone("This is a must-fix before the release branch cuts.")

    def test_a_tag_after_real_prose_is_not_a_label(self):
        # Only a LEADING label is linter format. Mid-sentence brackets are
        # ordinary citation and must not trip the gate.
        validate_tone("Guard cfg before indexing [see the caller at foo.py:11].")


class SelfCountToneTests(unittest.TestCase):
    """"Found 3 issues." is a machine reporting on its own output. SKILL.md
    bans it and the guard did not, so it could reach the PR body."""

    def test_rejects_counting_its_own_findings(self):
        for text in ("Found 3 issues in the merge path.",
                     "Flagged 2 problems with the retry ceiling.",
                     "Raised four concerns about the dispatch path.",
                     "Identified several bugs in the parser."):
            with self.assertRaises(ValueError, msg=text):
                validate_tone(text)

    def test_counting_things_in_the_code_survives(self):
        # The guard must separate "the review found N issues" from "the code
        # has N of something", which is ordinary technical description.
        validate_tone("The retry loop runs 3 times before giving up.")
        validate_tone("This adds 2 callers for the same helper.")
        validate_tone("The parser found 3 matches in the header block.")


class PinnedDiffTests(unittest.TestCase):
    """The diff and the commit_id have to describe the same tree.

    Step 4 fetched with `gh pr diff <n>`, which resolves LIVE head, while the
    payload pins commit_id to the headRefOid captured back in step 1. A push
    between those two points means the inline anchors were computed against
    one tree and submitted against another: wrong-line comments, or a 422,
    after the review has already been authorised.

    The diff path now carries the SHA it was fetched at, so the two can be
    compared. It also makes the path SHA-scoped rather than only PR-scoped,
    which kills the separate case where a second review of the same PR reads
    the first one's diff.
    """

    SHA_A = "a" * 40
    SHA_B = "b" * 40

    def setUp(self):
        self.script = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                                   "build_review_payload.py")
        holder = tempfile.TemporaryDirectory()
        self.addCleanup(holder.cleanup)
        self.tmp = holder.name
        self.findings = os.path.join(self.tmp, "f.json")
        with open(self.findings, "w", encoding="utf-8") as handle:
            json.dump({"thanks": THANKS, "summary_lead": "", "findings": []},
                      handle)

    def _diff_at(self, name):
        path = os.path.join(self.tmp, name)
        with open(path, "w", encoding="utf-8") as handle:
            handle.write(SAMPLE_DIFF)
        return path

    def _run(self, diff_name, commit):
        return subprocess.run(
            [sys.executable, self.script,
             "--diff", self._diff_at(diff_name),
             "--findings", self.findings, "--commit", commit],
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)

    def test_rejects_a_diff_fetched_at_a_different_sha(self):
        # The failure this exists for: head moved between step 4 and step 8.
        proc = self._run("pr-review-7-{0}.diff".format(self.SHA_A), self.SHA_B)
        self.assertNotEqual(proc.returncode, 0)
        self.assertIn(self.SHA_A, proc.stderr)
        self.assertIn(self.SHA_B, proc.stderr)

    def test_accepts_a_diff_fetched_at_the_commit_being_reviewed(self):
        proc = self._run("pr-review-7-{0}.diff".format(self.SHA_A), self.SHA_A)
        self.assertEqual(proc.returncode, 0, proc.stderr)
        self.assertEqual(json.loads(proc.stdout)["commit_id"], self.SHA_A)

    def test_rejects_the_old_unpinned_path_convention(self):
        # `pr-review-<n>.diff` is exactly what `gh pr diff <n>` wrote. Leaving
        # it merely unchecked would let the defect keep shipping under a name
        # that looks deliberate.
        proc = self._run("pr-review-7.diff", self.SHA_A)
        self.assertNotEqual(proc.returncode, 0)
        self.assertIn("pin", proc.stderr.lower())

    def test_a_path_outside_the_convention_is_left_alone(self):
        # Fixtures and ad-hoc dry runs do not carry a PR-scoped name and must
        # stay usable; the convention is what production goes through.
        proc = self._run("scratch.diff", self.SHA_A)
        self.assertEqual(proc.returncode, 0, proc.stderr)


class EventDerivationTests(unittest.TestCase):
    """A review that cannot approve is a review that always sounds
    non-committal. The event is a pure function of severity plus two explicit
    overrides, so a table pins it and a mutation flips a row."""

    def test_no_findings_approves(self):
        self.assertEqual(event_for([]), "APPROVE")

    def test_consider_only_approves(self):
        self.assertEqual(event_for([{"severity": "consider"}]), "APPROVE")

    def test_should_fix_still_approves(self):
        # The approve bar is "nothing must-fix". A should-fix note rides
        # along as an inline comment and does not withhold the approval.
        self.assertEqual(event_for([{"severity": "should-fix"}]), "APPROVE")

    def test_a_single_must_fix_downgrades_to_comment(self):
        self.assertEqual(event_for([{"severity": "must-fix"}]), "COMMENT")

    def test_must_fix_among_others_downgrades_to_comment(self):
        findings = [{"severity": "should-fix"}, {"severity": "must-fix"},
                    {"severity": "consider"}]
        self.assertEqual(event_for(findings), "COMMENT")

    def test_absent_severity_defaults_to_should_fix_and_approves(self):
        self.assertEqual(event_for([{"path": "foo.py"}]), "APPROVE")

    def test_request_changes_flag_overrides_the_derived_event(self):
        self.assertEqual(
            event_for([{"severity": "must-fix"}], request_changes=True),
            "REQUEST_CHANGES")
        self.assertEqual(
            event_for([{"severity": "consider"}], request_changes=True),
            "REQUEST_CHANGES")

    def test_force_comment_beats_request_changes(self):
        # GitHub rejects both APPROVE and REQUEST_CHANGES on your own PR, so
        # the self-review override has to win over an explicit request.
        self.assertEqual(
            event_for([{"severity": "must-fix"}],
                      force_comment=True, request_changes=True),
            "COMMENT")

    def test_force_comment_suppresses_an_approval(self):
        self.assertEqual(event_for([], force_comment=True), "COMMENT")


class ApproveThanksTests(unittest.TestCase):
    """An approving review must thank the author. Enforced here rather than
    left to the tone contract, because a contract line is advice and this is
    the one thing the author actually reads first."""

    def test_approving_payload_without_thanks_raises(self):
        with self.assertRaises(ValueError) as ctx:
            build_payload("abc123", "", [], ANCHORABLE)
        self.assertIn("thanks", str(ctx.exception).lower())

    def test_whitespace_only_thanks_is_not_thanks(self):
        with self.assertRaises(ValueError):
            build_payload("abc123", "", [], ANCHORABLE, thanks="   ")

    def test_approving_body_opens_with_the_thanks_line(self):
        payload = build_payload("abc123", "", [], ANCHORABLE, thanks=THANKS)
        self.assertEqual(payload["event"], "APPROVE")
        self.assertTrue(payload["body"].startswith(THANKS))

    def test_thanks_precedes_the_lead_and_the_notes(self):
        findings = [{"path": "foo.py", "line": 11, "body": "tidy this",
                     "severity": "consider"}]
        payload = build_payload("abc123", "Small change.", findings,
                                ANCHORABLE, thanks=THANKS)
        body = payload["body"]
        self.assertLess(body.index(THANKS), body.index("Small change."))
        self.assertLess(body.index("Small change."), body.index("tidy this"))

    def test_comment_review_needs_no_thanks(self):
        # A must-fix review is not an approval, so gratitude is optional
        # there; requiring it would put a thank-you on every rejection.
        findings = [{"path": "foo.py", "line": 11, "body": "guard the index",
                     "severity": "must-fix"}]
        payload = build_payload("abc123", "One thing to fix.", findings,
                                ANCHORABLE)
        self.assertEqual(payload["event"], "COMMENT")

    def test_request_changes_with_no_findings_raises(self):
        # Nothing to act on: an author cannot clear a changes-request that
        # points at nothing.
        with self.assertRaises(ValueError) as ctx:
            build_payload("abc123", "Please revisit.", [], ANCHORABLE,
                          request_changes=True)
        self.assertIn("finding", str(ctx.exception).lower())

    def test_request_changes_sets_the_event_on_the_payload(self):
        findings = [{"path": "foo.py", "line": 11, "body": "guard the index",
                     "severity": "must-fix"}]
        payload = build_payload("abc123", "One thing to fix.", findings,
                                ANCHORABLE, request_changes=True)
        self.assertEqual(payload["event"], "REQUEST_CHANGES")


class RetiredWordingTests(unittest.TestCase):
    """The two fixed strings are gone, not reworded.

    A constant posted verbatim on every clean PR is the loudest machine
    signal a repo's history can carry: identical text, many PRs, one author.
    """

    def test_module_exposes_no_fixed_clean_body(self):
        import build_review_payload as mod
        self.assertFalse(hasattr(mod, "NO_ISSUES_BODY"))
        self.assertFalse(hasattr(mod, "NO_BLOCKERS_LEAD"))

    def test_source_carries_neither_retired_string(self):
        path = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                            "build_review_payload.py")
        with open(path, encoding="utf-8") as handle:
            source = handle.read()
        self.assertNotIn("Nothing here blocks merge", source)
        self.assertNotIn("did not find anything", source)


class BuildPayloadTests(unittest.TestCase):
    def test_anchors_valid_finding_inline(self):
        findings = [{"path": "foo.py", "line": 11, "body": "nil deref here",
                     "severity": "must-fix", "permalink": "https://x/foo#L11"}]
        payload = build_payload("abc123", "One thing.", findings, ANCHORABLE)
        self.assertEqual(payload["event"], "COMMENT")
        self.assertEqual(payload["commit_id"], "abc123")
        self.assertEqual(len(payload["comments"]), 1)
        comment = payload["comments"][0]
        self.assertEqual(comment, {"path": "foo.py", "line": 11,
                                   "side": "RIGHT", "body": "nil deref here"})
        # The inline comment IS the report for an anchorable blocking finding.
        # Restating it in the summary made the author read the same sentence
        # twice on one page and doubled the apparent weight of the review.
        self.assertNotIn("nil deref here", payload["body"])
        self.assertNotIn("foo.py:11", payload["body"])

    def test_unanchorable_finding_falls_back_to_body_with_permalink(self):
        # line 999 is NOT in the diff; it must not become an inline comment
        # (that would 422 the whole review) and must surface in the body.
        findings = [{"path": "foo.py", "line": 999, "body": "stale doc",
                     "severity": "must-fix", "permalink": "https://x/foo#L999"}]
        payload = build_payload("abc123", "One thing.", findings, ANCHORABLE)
        self.assertEqual(payload["comments"], [])
        self.assertIn("stale doc (foo.py:999)", payload["body"])
        self.assertIn("https://x/foo#L999", payload["body"])

    def test_permalink_separator_is_not_an_em_dash(self):
        # The builder joined the permalink with an em dash, so its own output
        # could not pass the gate it applies to everyone else.
        findings = [{"path": "foo.py", "line": 999, "body": "stale doc",
                     "severity": "must-fix", "permalink": "https://x/foo#L999"}]
        payload = build_payload("abc123", "One thing.", findings, ANCHORABLE)
        self.assertNotIn(EM_DASH, payload["body"])

    def test_clean_payload_has_no_comments(self):
        payload = build_payload("abc123", "", [], ANCHORABLE, thanks=THANKS)
        self.assertEqual(payload["comments"], [])

    def test_rejects_banned_token_in_finding_body(self):
        findings = [{"path": "foo.py", "line": 11, "severity": "must-fix",
                     "body": "ok " + BANNED_TOKENS[0]}]
        with self.assertRaises(ValueError):
            build_payload("abc123", "One thing.", findings, ANCHORABLE)


class SeverityRoutingTests(unittest.TestCase):
    """An inline comment reads as a demand; a summary line reads as a note.

    Routing every finding inline regardless of severity is what made a review
    of one should-fix and two considers land as three equal-weight demands on
    a PR with no correctness defect.
    """

    def test_consider_stays_out_of_inline_comments(self):
        findings = [{"path": "foo.py", "line": 11, "body": "tidy this",
                     "severity": "consider"}]
        payload = build_payload("abc123", "", findings, ANCHORABLE,
                                thanks=THANKS)
        self.assertEqual(payload["comments"], [])
        # It is still reported, demoted rather than dropped, but a bracketed
        # severity tag is linter-report format and never appears in a body.
        self.assertIn("tidy this (foo.py:11)", payload["body"])
        self.assertNotIn("[consider]", payload["body"])

    def test_must_fix_and_should_fix_get_inline_comments(self):
        findings = [
            {"path": "foo.py", "line": 11, "body": "blocker", "severity": "must-fix"},
            {"path": "foo.py", "line": 12, "body": "nit", "severity": "should-fix"},
        ]
        # Both go inline, so a lead is required: the body would otherwise be
        # empty and the review would post blank.
        payload = build_payload("abc123", "Lead.", findings, ANCHORABLE)
        self.assertEqual([c["body"] for c in payload["comments"]], ["blocker", "nit"])

    def test_absent_severity_keeps_the_previous_inline_behaviour(self):
        # Back-compat: findings written before severity existed must still
        # anchor inline rather than silently demote to a summary line.
        findings = [{"path": "foo.py", "line": 11, "body": "no severity key"}]
        payload = build_payload("abc123", "Lead.", findings, ANCHORABLE,
                                thanks=THANKS)
        self.assertEqual(len(payload["comments"]), 1)

    def test_unknown_severity_raises(self):
        # A typo must not silently downgrade a blocker to a note. Surfacing an
        # error is the cheap direction; a quiet demotion is the expensive one.
        findings = [{"path": "foo.py", "line": 11, "body": "x", "severity": "must fix"}]
        with self.assertRaises(ValueError) as ctx:
            build_payload("abc123", "Lead.", findings, ANCHORABLE)
        # Must fail for the severity typo, not for a missing thanks line.
        self.assertIn("severity", str(ctx.exception).lower())


class RootCauseDedupeTests(unittest.TestCase):
    """Two symptoms of one cause posted as two comments doubles the apparent
    weight of a review without adding information."""

    def test_shared_root_cause_collapses_to_one_entry_and_one_comment(self):
        findings = [
            {"path": "foo.py", "line": 11, "body": "symptom one",
             "severity": "should-fix", "root_cause": "fake-clientset"},
            {"path": "foo.py", "line": 12, "body": "symptom two",
             "severity": "should-fix", "root_cause": "fake-clientset"},
        ]
        payload = build_payload("abc123", "Lead.", findings, ANCHORABLE,
                                thanks=THANKS)
        self.assertEqual(len(payload["comments"]), 1)
        self.assertEqual(payload["comments"][0]["line"], 11)
        # The group is anchorable and blocking, so it lives inline; the folded
        # sibling has to be cited there or it is silently discarded.
        self.assertIn("symptom one", payload["comments"][0]["body"])
        self.assertIn("foo.py:12", payload["comments"][0]["body"])
        self.assertNotIn("symptom one", payload["body"])

    def test_distinct_root_causes_are_not_merged(self):
        findings = [
            {"path": "foo.py", "line": 11, "body": "a", "root_cause": "one"},
            {"path": "foo.py", "line": 12, "body": "b", "root_cause": "two"},
        ]
        payload = build_payload("abc123", "Lead.", findings, ANCHORABLE,
                                thanks=THANKS)
        self.assertEqual(len(payload["comments"]), 2)

    def test_absent_root_cause_never_merges(self):
        # Two findings that simply lack the key are unrelated, not siblings.
        findings = [
            {"path": "foo.py", "line": 11, "body": "a"},
            {"path": "foo.py", "line": 12, "body": "b"},
        ]
        payload = build_payload("abc123", "Lead.", findings, ANCHORABLE,
                                thanks=THANKS)
        # Two inline comments is what proves they did not merge.
        self.assertEqual(len(payload["comments"]), 2)
        self.assertEqual([c["body"] for c in payload["comments"]], ["a", "b"])


class RenderPreviewTests(unittest.TestCase):
    def test_lists_summary_and_inline(self):
        payload = {"commit_id": "abc", "event": "COMMENT",
                   "body": "One thing.\n\n- nil deref (foo.py:11)",
                   "comments": [{"path": "foo.py", "line": 11,
                                 "side": "RIGHT", "body": "nil deref"}]}
        out = render_preview(payload)
        self.assertIn("One thing.", out)
        self.assertIn("nil deref", out)

    def test_names_the_event_so_an_approval_is_never_posted_unseen(self):
        # The preview is the only thing standing between a derived APPROVE
        # and a submitted one. A render that does not say which event it is
        # cannot be the confirmation surface for it.
        payload = {"commit_id": "abc", "event": "APPROVE",
                   "body": THANKS, "comments": []}
        self.assertIn("APPROVE", render_preview(payload))

    def test_no_inline_comments_states_so(self):
        payload = {"commit_id": "abc", "event": "APPROVE",
                   "body": THANKS, "comments": []}
        self.assertIn("(no inline comments)", render_preview(payload))


class CliTests(unittest.TestCase):
    def _run(self, payload_json, *extra):
        script = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                              "build_review_payload.py")
        with tempfile.TemporaryDirectory() as tmp:
            diff_path = os.path.join(tmp, "d.diff")
            findings_path = os.path.join(tmp, "f.json")
            with open(diff_path, "w", encoding="utf-8") as handle:
                handle.write(SAMPLE_DIFF)
            with open(findings_path, "w", encoding="utf-8") as handle:
                json.dump(payload_json, handle)
            return subprocess.check_output(
                [sys.executable, script, "--diff", diff_path,
                 "--findings", findings_path, "--commit", "abc123"] + list(extra),
                text=True)

    def test_cli_emits_payload_json(self):
        out = self._run({"summary_lead": "One thing.",
                         "findings": [{"path": "foo.py", "line": 11,
                                       "severity": "must-fix",
                                       "body": "nil deref", "permalink": ""}]})
        payload = json.loads(out)
        self.assertEqual(payload["commit_id"], "abc123")
        self.assertEqual(payload["comments"][0]["line"], 11)
        self.assertEqual(payload["event"], "COMMENT")

    def test_cli_reads_thanks_from_the_findings_file(self):
        out = self._run({"thanks": THANKS, "summary_lead": "", "findings": []})
        payload = json.loads(out)
        self.assertEqual(payload["event"], "APPROVE")
        self.assertTrue(payload["body"].startswith(THANKS))

    def test_cli_force_comment_flag_suppresses_the_approval(self):
        out = self._run({"thanks": THANKS, "summary_lead": "Nothing outstanding.",
                         "findings": []}, "--force-comment")
        self.assertEqual(json.loads(out)["event"], "COMMENT")

    def test_cli_request_changes_flag_sets_the_event(self):
        out = self._run({"summary_lead": "One thing to fix.",
                         "findings": [{"path": "foo.py", "line": 11,
                                       "severity": "must-fix",
                                       "body": "nil deref"}]},
                        "--request-changes")
        self.assertEqual(json.loads(out)["event"], "REQUEST_CHANGES")


class SummaryIsNotAnIndexTests(unittest.TestCase):
    """The posted review has two surfaces and they had the same content.

    Every anchorable blocking finding was written once as an inline comment
    and again as a numbered summary entry carrying a bracketed severity tag.
    A reader saw each finding twice, and the body read as a generated report
    rather than as a person who looked at the change.
    """

    def test_body_carries_no_bracketed_severity_tag(self):
        findings = [
            {"path": "foo.py", "line": 11, "body": "blocker", "severity": "must-fix"},
            {"path": "foo.py", "line": 12, "body": "note", "severity": "consider"},
        ]
        payload = build_payload("abc123", "Lead.", findings, ANCHORABLE)
        for tag in ("[must-fix]", "[should-fix]", "[consider]"):
            self.assertNotIn(tag, payload["body"])

    def test_anchorable_blocking_finding_is_absent_from_the_body(self):
        findings = [{"path": "foo.py", "line": 11, "body": "guard the index",
                     "severity": "must-fix"}]
        payload = build_payload("abc123", "Lead.", findings, ANCHORABLE)
        self.assertEqual(payload["comments"][0]["body"], "guard the index")
        self.assertNotIn("guard the index", payload["body"])

    def test_unanchorable_blocking_finding_still_reaches_the_body(self):
        # No inline home, so the summary is the only place it can be reported.
        findings = [{"path": "foo.py", "line": 999, "body": "stale contract",
                     "severity": "must-fix", "permalink": "https://x/foo#L999"}]
        payload = build_payload("abc123", "Lead.", findings, ANCHORABLE)
        self.assertEqual(payload["comments"], [])
        self.assertIn("stale contract", payload["body"])

    def test_summary_entries_are_bullets_not_a_numbered_report(self):
        # Numbering your own findings is linter-report format. Two inline
        # findings must also not consume numbers and leave the single visible
        # note labelled 3.
        findings = [
            {"path": "foo.py", "line": 11, "body": "inline a", "severity": "must-fix"},
            {"path": "foo.py", "line": 12, "body": "inline b", "severity": "should-fix"},
            {"path": "foo.py", "line": 13, "body": "the note", "severity": "consider"},
        ]
        payload = build_payload("abc123", "Lead.", findings, ANCHORABLE)
        self.assertIn("- the note (foo.py:13)", payload["body"])
        self.assertIsNone(re.search(r"^\s*\d+\.\s", payload["body"], re.M))

    def test_body_that_would_be_empty_raises_rather_than_posting_blank(self):
        # Every finding inline and no lead: the review would post blank.
        findings = [{"path": "foo.py", "line": 11, "body": "x", "severity": "must-fix"}]
        with self.assertRaises(ValueError) as ctx:
            build_payload("abc123", "", findings, ANCHORABLE)
        self.assertIn("summary_lead", str(ctx.exception))


class CorroborationTests(unittest.TestCase):
    """A finding two reviewers reached independently says so, once."""

    def _finding(self, **over):
        finding = {"path": "foo.py", "line": 10, "severity": "must-fix",
                   "body": "Nil deref when cfg is empty; guard before indexing.",
                   "corroborates": {"reviewer": "CodeRabbit",
                                    "comment_id": 5452423076,
                                    "url": "https://github.com/o/r/pull/12#c1"}}
        finding.update(over)
        return finding

    def test_inline_body_names_the_reviewer_that_agreed(self):
        payload = build_payload(
            "sha", "lead.", [self._finding()], parse_anchorable(SAMPLE_DIFF))
        self.assertIn("CodeRabbit flagged this too",
                      payload["comments"][0]["body"])

    def test_finding_without_corroborates_gains_no_clause(self):
        finding = self._finding()
        del finding["corroborates"]
        payload = build_payload(
            "sha", "lead.", [finding], parse_anchorable(SAMPLE_DIFF))
        self.assertNotIn("flagged this too", payload["comments"][0]["body"])

    def test_summary_entry_carries_the_clause_when_not_anchorable(self):
        # line 999 is outside SAMPLE_DIFF, so this finding has no inline home.
        finding = self._finding(line=999, severity="consider")
        payload = build_payload(
            "sha", "lead.", [finding], parse_anchorable(SAMPLE_DIFF),
            thanks=THANKS)
        self.assertIn("CodeRabbit flagged this too", payload["body"])

    def test_corroboration_does_not_change_severity_or_event(self):
        # A bot agreeing is not evidence of severity, and severity decides
        # routing: a "consider" finding is a note in the summary body, while an
        # inlined one reads as a demand. If the citation escalated severity, a
        # bot agreeing with a minor observation would turn it into that demand.
        anchorable = parse_anchorable(SAMPLE_DIFF)
        plain = self._finding(severity="consider")
        del plain["corroborates"]
        cited = self._finding(severity="consider")
        plain_payload = build_payload("sha", "lead.", [plain], anchorable,
                                      thanks=THANKS)
        cited_payload = build_payload("sha", "lead.", [cited], anchorable,
                                      thanks=THANKS)
        # Against a literal, so the two cannot pass by being equally wrong.
        self.assertEqual("APPROVE", plain_payload["event"])
        self.assertEqual("APPROVE", cited_payload["event"])
        # The emitted shape, not just the event. Line 10 is anchorable, so
        # severity alone keeps this finding out of the inline comments.
        self.assertEqual([], cited_payload["comments"])
        self.assertIn("Nil deref when cfg is empty", cited_payload["body"])

    def test_empty_reviewer_name_raises(self):
        finding = self._finding(corroborates={"reviewer": "  ", "comment_id": 1,
                                              "url": "u"})
        with self.assertRaises(ValueError) as ctx:
            build_payload("sha", "lead.", [finding],
                          parse_anchorable(SAMPLE_DIFF))
        self.assertIn("non-empty reviewer name", str(ctx.exception))

    def test_reviewer_name_goes_through_the_tone_gate(self):
        # The citation is posted text like any other. A name carrying an em dash
        # must not slip onto the PR through this path.
        finding = self._finding(
            corroborates={"reviewer": "Code" + EM_DASH + "Rabbit",
                          "comment_id": 1, "url": "u"})
        with self.assertRaises(ValueError) as ctx:
            build_payload("sha", "lead.", [finding],
                          parse_anchorable(SAMPLE_DIFF))
        self.assertIn("em dash", str(ctx.exception))

    def test_note_is_appended_after_the_folded_sibling_citation(self):
        # root_cause folding already appends "Also at ...". The corroboration
        # clause must not land between the body and that citation.
        group = [self._finding(root_cause="cfg"),
                 self._finding(path="bar.py", line=1, root_cause="cfg")]
        payload = build_payload(
            "sha", "lead.", group, parse_anchorable(SAMPLE_DIFF))
        body = payload["comments"][0]["body"]
        self.assertLess(body.index("Also at"), body.index("CodeRabbit"))


class RepliesTests(unittest.TestCase):
    """Replies are outward writes and are gated like the review itself."""

    def test_valid_reply_is_normalized(self):
        got = build_replies([{"comment_id": 991, "surface": "inline",
                              "body": "  Agreed; cfg is empty on first run.  "}])
        self.assertEqual(got, [{"comment_id": 991, "surface": "inline",
                                "body": "Agreed; cfg is empty on first run."}])

    def test_reply_body_goes_through_the_tone_gate(self):
        # This is the bug the test exists for: every other posted string is tone
        # checked, and a replies channel that skipped it would be the one way an
        # em dash reaches a PR.
        with self.assertRaises(ValueError):
            build_replies([{"comment_id": 1, "surface": "inline",
                            "body": "Agreed" + EM_DASH + " cfg is empty."}])

    def test_reply_narrating_the_review_is_rejected(self):
        with self.assertRaises(ValueError):
            build_replies([{"comment_id": 1, "surface": "inline",
                            "body": "I checked this and agree."}])

    def test_empty_body_raises(self):
        with self.assertRaises(ValueError):
            build_replies([{"comment_id": 1, "surface": "inline", "body": "   "}])

    def test_non_integer_comment_id_raises(self):
        # A string id silently posts to the wrong endpoint shape.
        with self.assertRaises(ValueError):
            build_replies([{"comment_id": "991", "surface": "inline",
                            "body": "Agreed."}])

    def test_no_replies_is_an_empty_list(self):
        self.assertEqual(build_replies([]), [])
        self.assertEqual(build_replies(None), [])


class ReplySurfaceTests(unittest.TestCase):
    """Only an `inline` id can be replied to.

    POST /repos/{o}/{r}/pulls/{n}/comments/{comment_id}/replies resolves a
    top-level review comment id, which is what the `inline` surface returns.
    Verified read-only against cli/cli on 2026-08-31: the inline id 332430752
    answers on repos/cli/cli/pulls/comments/<id>, while the issue-comment id
    539473254 and the review id 2023457056 both 404 there.

    The ingest reads three surfaces, and by fetch_ai_reviews' own docstring the
    two that cannot be replied to are where the walkthroughs live. Without this
    gate the review POST lands first and cannot be retracted, then the reply
    loop 404s on its first entry and every refutation is lost silently.
    """

    def test_reply_on_the_issue_comment_surface_is_rejected(self):
        with self.assertRaises(ValueError) as caught:
            build_replies([{"comment_id": 991, "surface": "issue_comment",
                            "body": "The defer above cancels ctx."}])
        self.assertEqual(
            str(caught.exception),
            "reply to comment 991 is on the 'issue_comment' surface; the "
            "replies route resolves a top-level review comment id, which only "
            "the 'inline' surface produces. Put this refutation in the review "
            "body instead, where it still reaches the author.")

    def test_reply_on_the_review_surface_is_rejected(self):
        # Copilot and Greptile post here, so this is not a hypothetical shape.
        with self.assertRaises(ValueError) as caught:
            build_replies([{"comment_id": 77, "surface": "review",
                            "body": "The guard on line 4 covers that case."}])
        self.assertEqual(
            str(caught.exception),
            "reply to comment 77 is on the 'review' surface; the replies route "
            "resolves a top-level review comment id, which only the 'inline' "
            "surface produces. Put this refutation in the review body instead, "
            "where it still reaches the author.")

    def test_reply_with_no_surface_is_rejected(self):
        # Not a silent pass: a caller that does not know the surface cannot know
        # the id is repliable, so an absent key is the same unverified state as
        # a wrong one.
        with self.assertRaises(ValueError) as caught:
            build_replies([{"comment_id": 991, "body": "Agreed."}])
        self.assertEqual(
            str(caught.exception),
            "reply to comment 991 carries no surface; the replies route "
            "resolves a top-level review comment id, and a caller that does "
            "not know which surface the id came from cannot know it is "
            "repliable. Copy 'surface' through from the Reconcile record.")

    def test_an_unknown_surface_is_rejected(self):
        with self.assertRaises(ValueError) as caught:
            build_replies([{"comment_id": 5, "surface": "discussion",
                            "body": "Agreed."}])
        self.assertEqual(
            str(caught.exception),
            "reply to comment 5 is on the 'discussion' surface; the replies "
            "route resolves a top-level review comment id, which only the "
            "'inline' surface produces. Put this refutation in the review body "
            "instead, where it still reaches the author.")

    def test_the_surface_check_runs_before_the_reply_is_accepted(self):
        # A repliable entry ahead of a non-repliable one must not buy the batch
        # a pass: the post loop stops on the first failure, so a mixed batch
        # posts a prefix and then dies mid-way through someone else's PR.
        with self.assertRaises(ValueError):
            build_replies([
                {"comment_id": 1, "surface": "inline", "body": "Agreed."},
                {"comment_id": 2, "surface": "review", "body": "Also agreed."},
            ])


class PayloadPurityTests(unittest.TestCase):
    def test_review_payload_never_carries_replies(self):
        # gh api --input sends this object verbatim to the Reviews API. An extra
        # key here is an unexpected field on a real request.
        payload = build_payload(
            "sha", "lead.",
            [{"path": "foo.py", "line": 10, "severity": "consider",
              "body": "Consider renaming."}],
            parse_anchorable(SAMPLE_DIFF), thanks=THANKS)
        self.assertEqual(sorted(payload.keys()),
                         ["body", "comments", "commit_id", "event"])


class OutwardWriteRenderTests(unittest.TestCase):
    def _payload(self):
        return build_payload(
            "sha", "lead.",
            [{"path": "foo.py", "line": 10, "severity": "consider",
              "body": "Consider renaming."}],
            parse_anchorable(SAMPLE_DIFF), thanks=THANKS)

    def test_render_counts_every_outward_write(self):
        text = render_preview(
            self._payload(),
            [{"comment_id": 991, "surface": "inline", "body": "Agreed."},
             {"comment_id": 992, "surface": "inline",
              "body": "This one does not hold; ctx is "
                      "cancelled by the defer above."}],
            pr_number=12)
        self.assertIn("1 review + 2 threaded replies", text)

    def test_render_names_each_reply_target_and_body(self):
        # The rendered route must be the one GitHub actually serves:
        # POST /repos/{owner}/{repo}/pulls/{pull_number}/comments/{id}/replies.
        # An earlier draft rendered `pulls/comments/{id}/replies`, a route that
        # does not exist and that only accepts GET/PATCH/DELETE at its two-segment
        # form. That shape fails in the worst possible order: the review POST
        # succeeds and cannot be retracted, then every reply 404s. The negative
        # assertion is what catches a regression back to it, since the positive
        # one alone would still pass on a line containing both.
        text = render_preview(
            self._payload(),
            [{"comment_id": 991, "surface": "inline", "body": "Agreed."}],
            pr_number=12)
        self.assertIn("pulls/12/comments/991/replies", text)
        self.assertNotIn("pulls/comments/", text)
        self.assertIn("Agreed.", text)

    def test_render_with_no_replies_says_one_write(self):
        text = render_preview(self._payload(), [], pr_number=12)
        self.assertIn("1 review + 0 threaded replies", text)

    def test_render_still_leads_with_the_event(self):
        # The event line is what the confirm authorises; the write list must not
        # push it below the fold.
        text = render_preview(self._payload(), [], pr_number=12)
        self.assertTrue(text.startswith("=== REVIEW EVENT:"))

class CliRepliesTests(unittest.TestCase):
    """The CLI is the real boundary.

    Step 9 pipes main's STDOUT into `gh api --input` and reads the sidecar by
    path. Asserting on a function's return value one layer below that leaves
    both of those surfaces unguarded.
    """

    def setUp(self):
        self.script = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                                   "build_review_payload.py")
        holder = tempfile.TemporaryDirectory()
        self.addCleanup(holder.cleanup)
        self.tmp = holder.name
        self.diff_path = os.path.join(self.tmp, "d.diff")
        with open(self.diff_path, "w", encoding="utf-8") as handle:
            handle.write(SAMPLE_DIFF)

    def _findings(self, replies):
        path = os.path.join(self.tmp, "f.json")
        with open(path, "w", encoding="utf-8") as handle:
            json.dump({"thanks": THANKS, "summary_lead": "", "findings": [],
                       "replies": replies}, handle)
        return path

    def _run(self, replies, *extra):
        return subprocess.run(
            [sys.executable, self.script, "--diff", self.diff_path,
             "--findings", self._findings(replies), "--commit", "abc123"]
            + list(extra),
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)

    def test_printed_payload_has_no_replies_key_even_when_replies_exist(self):
        # PayloadPurityTests guards build_payload's return value, which is one
        # layer below the wire. A single `payload["replies"] = replies` in main
        # ships an unexpected field on a real Reviews API request with every
        # other test still green, so the assertion has to be on stdout.
        proc = self._run([{"comment_id": 991, "surface": "inline",
                           "body": "Agreed."}])
        self.assertEqual(proc.returncode, 0, proc.stderr)
        self.assertEqual(sorted(json.loads(proc.stdout).keys()),
                         ["body", "comments", "commit_id", "event"])

    def test_replies_out_writes_the_normalized_replies(self):
        # The sidecar is the one mechanism by which replies leave the process.
        out = os.path.join(self.tmp, "replies.json")
        proc = self._run([{"comment_id": 991, "surface": "inline",
                           "body": "  Agreed.  "}],
                         "--replies-out", out)
        self.assertEqual(proc.returncode, 0, proc.stderr)
        with open(out, encoding="utf-8") as handle:
            self.assertEqual(json.load(handle),
                             [{"comment_id": 991, "surface": "inline",
                               "body": "Agreed."}])

    def test_a_non_inline_reply_fails_the_cli_and_names_the_surface(self):
        # The CLI is where this matters: step 9 pipes the sidecar into a post
        # loop with check=True, so a non-repliable id 404s AFTER the review has
        # posted and cannot be retracted. Failing the build is the only point
        # at which nothing has been written yet.
        out = os.path.join(self.tmp, "replies.json")
        proc = self._run([{"comment_id": 991, "surface": "issue_comment",
                           "body": "The defer above cancels ctx."}],
                         "--replies-out", out)
        self.assertEqual(proc.returncode, 1)
        self.assertIn("is on the 'issue_comment' surface", proc.stderr)
        self.assertFalse(os.path.exists(out))

    def test_render_without_replies_out_is_a_usage_error(self):
        # --render enumerates every threaded reply as a write it is
        # authorising. Without the flag nothing is written to or cleared from
        # the sidecar, so the operator approves this run's replies and the post
        # loop sends whatever an earlier run left at that path.
        proc = self._run([], "--render", "--pr-number", "12")
        self.assertEqual(proc.returncode, 2)
        self.assertIn("--render requires --replies-out", proc.stderr)

    def test_a_rejected_run_leaves_no_stale_sidecar(self):
        # Same failure class Task 1 fixed for --out. Step 9 reads this path by
        # name, so an earlier run's file surviving a rejected run is posted as
        # this run's replies. The rc and the reason are both asserted: a file
        # absent because the run died on a missing diff would prove nothing.
        out = os.path.join(self.tmp, "replies.json")
        with open(out, "w", encoding="utf-8") as handle:
            json.dump([{"comment_id": 111, "body": "From an earlier run."}],
                      handle)
        self.assertTrue(os.path.exists(out))
        proc = self._run([{"comment_id": 991, "surface": "inline",
                           "body": "Agreed" + EM_DASH + " cfg is empty."}],
                         "--replies-out", out)
        self.assertEqual(proc.returncode, 1)
        self.assertIn("em dash", proc.stderr)
        self.assertFalse(os.path.exists(out))

if __name__ == "__main__":
    unittest.main()
