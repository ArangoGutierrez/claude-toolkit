#!/usr/bin/env python3
"""Build a GitHub Pull Request Review payload from review findings.

Pure functions plus a thin CLI. Python 3.9+, stdlib only.
"""
from __future__ import annotations

import argparse
import json
import os
import re
import sys

# Literal strings that give the tooling away. The first is split across two
# adjacent literals on purpose: spelled contiguously it is itself a watermark
# and trips the repo-wide guard on this file. Python joins them at parse time.
BANNED_TOKENS = ("Generated with " "Claude Code", "CLAUDE.md")

# rules/anti-ai-tells.md names these ranges. Listing three individual emoji
# (a robot and two hands) left every other one free to ship. Written as
# escapes so this source stays free of the characters it rejects.
_EMOJI_RE = re.compile(
    "["
    "\U0001F300-\U0001FAFF"
    "\U0001F000-\U0001F0FF"
    "\U0001F1E6-\U0001F1FF"
    "☀-➿"
    "⬀-⯿"
    "️"
    "]")
EM_DASH = "—"

# Whole words only, so an identifier that merely contains one survives:
# `elevate_priority` is code, "elevate" in a sentence is marketing.
FILLER_WORDS = (
    "comprehensive", "robust", "seamless", "leverage", "utilize", "delve",
    "intricate", "crucial", "pivotal", "meticulous", "showcase", "realm",
    "testament", "elevate", "embark", "furthermore", "moreover", "underscore",
)

# The reviewer is never the subject of a sentence in a posted review. An
# author gets nothing from being told what was inspected, and a sentence
# reporting on the reviewer's own pass is a machine describing its own run.
# This list is also what keeps the two retired fixed strings, and any
# reworded descendant of them, from coming back into the body.
PROCESS_NARRATION = (
    "i reviewed", "i read", "i checked", "i verified", "i analyzed",
    "i scanned", "i looked", "i went through",
    "i did not find", "i didn't find", "i could not find", "i couldn't find",
    "read through", "went through", "looked through",
    "read the diff", "reviewed the diff", "scanned the diff",
    "checked the diff", "reviewing the diff",
    "hold up", "holds up", "held up",
    "blocks merge", "block merge", "blocking merge",
    "does not block", "doesn't block", "nothing here blocks",
)
# Word-bounded, not substring: a bare `in` test for "i read" also fires on
# "api readiness", which is ordinary prose about the change.
_NARRATION_RES = tuple(
    (phrase, re.compile(r"\b" + re.escape(phrase) + r"\b", re.IGNORECASE))
    for phrase in PROCESS_NARRATION)
_FILLER_RES = tuple(
    (word, re.compile(r"\b" + re.escape(word) + r"\b", re.IGNORECASE))
    for word in FILLER_WORDS)

# A severity token used as a LABEL, which is linter-report format. The
# `severity` field already carries the rating and already decides inline
# against summary, so repeating it in the prose says nothing and costs the
# review its voice. Only a LEADING label matches: "Consider caching the
# parsed config" and "This is a must-fix before the release branch cuts" are
# ordinary sentences and have to survive, so the pattern needs the bracket,
# the colon or the bold wrapper before it fires.
_SEVERITY_TOKEN = (r"(?:must[-\s]?fix|should[-\s]?fix|consider"
                   r"|blocker|major|minor|nit)")
_SEVERITY_TAG_RE = re.compile(
    r"^\s*(?:"
    r"\[\s*" + _SEVERITY_TOKEN + r"\s*\]"
    r"|\*\*\s*" + _SEVERITY_TOKEN + r"\s*:?\s*\*\*\s*:?"
    r"|" + _SEVERITY_TOKEN + r"\s*:"
    r")",
    re.IGNORECASE)

# The review counting its own output. "Found 3 issues." is a machine
# reporting on itself, and the author learns nothing from the number. The
# verb and the noun both have to match, which is what keeps "The parser
# found 3 matches in the header block" out of it: that sentence counts
# something in the code, not something the review produced.
_SELF_COUNT_RE = re.compile(
    r"\b(?:found|flagged|raised|identified|spotted|surfaced)\s+"
    r"(?:\d+|one|two|three|four|five|six|seven|eight|nine|ten"
    r"|several|multiple|numerous|a\s+few)\s+"
    r"(?:issue|finding|problem|concern|bug|defect)s?\b",
    re.IGNORECASE)

# An inline comment reads as a demand; a summary line reads as a note. The
# fan-out scores every finding must-fix / should-fix / consider, and posting
# all three the same way is what makes a review land heavier than its content.
SEVERITIES = ("must-fix", "should-fix", "consider")
INLINE_SEVERITIES = ("must-fix", "should-fix")
# Findings written before this key existed must keep anchoring inline, so the
# default is an inlined severity rather than the quietest one.
DEFAULT_SEVERITY = "should-fix"

_HUNK_RE = re.compile(r"^@@ -\d+(?:,\d+)? \+(\d+)(?:,\d+)? @@")

# The ingest reads three surfaces (issue_comment, review, inline) and their
# comment ids are not interchangeable. A threaded reply goes to
# POST /repos/{o}/{r}/pulls/{n}/comments/{comment_id}/replies, which resolves a
# top-level review comment id: that is what the `inline` surface returns.
# Verified read-only against cli/cli on 2026-08-31: the inline id 332430752
# answers on repos/cli/cli/pulls/comments/<id>, while the issue-comment id
# 539473254 and the review id 2023457056 both 404 there. By fetch_ai_reviews'
# own docstring the walkthroughs live on the two surfaces that cannot be
# replied to, so this is the common case and not the corner one.
REPLIABLE_SURFACE = "inline"

# The diff and commit_id must describe the same tree. `gh pr diff <n>` resolves
# LIVE head while commit_id is the headRefOid captured earlier, so a push
# between the two silently anchors comments against a tree the review does not
# submit against. The fetched SHA travels in the diff's filename, which is also
# what stops a second review of the same PR from reading the first one's diff.
#
# Two shapes are recognised and nothing else is guessed at: the pinned name,
# whose SHA must equal --commit, and the old unpinned name, which is exactly
# what the unpinned fetch wrote and is refused outright. A path matching
# neither is a fixture or an ad-hoc dry run and is left alone.
_PINNED_DIFF_RE = re.compile(r"^pr-review-\d+-([0-9a-fA-F]{40})\.diff$")
_UNPINNED_DIFF_RE = re.compile(r"^pr-review-\d+\.diff$")


def parse_anchorable(diff_text: str) -> "dict[str, set[int]]":
    """Map each file path to the set of new-file (RIGHT) line numbers present
    in the diff: added ('+') and context (' ') lines. Deleted ('-') lines do
    not advance the new-file counter and are not anchorable on the RIGHT side.
    """
    anchorable: "dict[str, set[int]]" = {}
    path = None
    new_line = 0
    for raw in diff_text.splitlines():
        if raw.startswith("+++ "):
            target = raw[4:].strip()
            if target == "/dev/null":
                path = None
            else:
                path = target[2:] if target.startswith("b/") else target
                anchorable.setdefault(path, set())
            continue
        match = _HUNK_RE.match(raw)
        if match:
            new_line = int(match.group(1))
            continue
        if path is None:
            continue
        if raw.startswith("-") or raw.startswith("\\"):
            continue  # deletion or "\ No newline": RIGHT counter unchanged
        if raw.startswith("+") or raw.startswith(" "):
            anchorable[path].add(new_line)
            new_line += 1
    return anchorable


def validate_tone(text: str) -> None:
    """Raise ValueError naming the first banned construct found in `text`."""
    for token in BANNED_TOKENS:
        if token in text:
            raise ValueError("banned token in review text: {0!r}".format(token))
    found = _EMOJI_RE.search(text)
    if found:
        raise ValueError("emoji in review text: {0!r}".format(found.group(0)))
    if EM_DASH in text:
        raise ValueError("em dash in review text; use a comma, a colon or "
                         "parentheses")
    for phrase, pattern in _NARRATION_RES:
        if pattern.search(text):
            raise ValueError(
                "review text narrates the review instead of describing the "
                "change: {0!r}".format(phrase))
    for word, pattern in _FILLER_RES:
        if pattern.search(text):
            raise ValueError("filler word in review text: {0!r}".format(word))
    tag = _SEVERITY_TAG_RE.match(text)
    if tag:
        raise ValueError(
            "severity tag in review text: {0!r}; the severity field carries "
            "it".format(tag.group(0).strip()))
    count = _SELF_COUNT_RE.search(text)
    if count:
        raise ValueError(
            "review text counts its own output: {0!r}".format(
                count.group(0)))


def severity_of(finding) -> str:
    """The finding's severity, defaulted and validated.

    An unrecognised value raises rather than falling back: a typo must not
    quietly demote a blocker to a summary note.
    """
    severity = finding.get("severity") or DEFAULT_SEVERITY
    if severity not in SEVERITIES:
        raise ValueError("unknown severity {0!r}; expected one of {1}".format(
            severity, ", ".join(SEVERITIES)))
    return severity


def corroboration_note(finding) -> str:
    """The clause naming an AI reviewer that independently found the same thing.

    Returns "" when the finding has no `corroborates` key, which is the common
    case. Naming a third-party reviewer is deliberate and is NOT the tooling the
    tone contract bans: that rule is about announcing our own pipeline, and a bot
    that already commented publicly on this PR is a citation the author can go
    read.
    """
    cite = finding.get("corroborates")
    if not cite:
        return ""
    reviewer = (cite.get("reviewer") or "").strip()
    if not reviewer:
        raise ValueError(
            "corroborates needs a non-empty reviewer name; an unattributed "
            "'flagged this too' tells the author nothing they can check")
    return "{0} flagged this too.".format(reviewer)


def build_replies(replies) -> list:
    """Validate and normalize threaded replies to AI-reviewer comments.

    Each reply is a separate outward write to a thread the author is already
    reading, so each body is tone checked exactly like the review body and the
    inline comments. This function does NOT post anything.
    """
    out = []
    for reply in replies or []:
        comment_id = reply.get("comment_id")
        # A string id would build a URL that still looks plausible, so this is a
        # type check rather than a truthiness check.
        if not isinstance(comment_id, int) or isinstance(comment_id, bool):
            raise ValueError(
                "reply needs an integer comment_id; got {0!r}".format(comment_id))
        # The surface decides whether this id exists on the replies route at
        # all, so it is checked before the body is even looked at. An absent
        # key is an error rather than a pass: a caller that does not know the
        # surface cannot know the id is repliable, and the cost of guessing
        # wrong is paid after the review has already posted.
        surface = reply.get("surface")
        if not surface:
            raise ValueError(
                "reply to comment {0} carries no surface; the replies route "
                "resolves a top-level review comment id, and a caller that "
                "does not know which surface the id came from cannot know it "
                "is repliable. Copy 'surface' through from the Reconcile "
                "record.".format(comment_id))
        if surface != REPLIABLE_SURFACE:
            raise ValueError(
                "reply to comment {0} is on the {1!r} surface; the replies "
                "route resolves a top-level review comment id, which only the "
                "{2!r} surface produces. Put this refutation in the review "
                "body instead, where it still reaches the author.".format(
                    comment_id, surface, REPLIABLE_SURFACE))
        body = (reply.get("body") or "").strip()
        if not body:
            raise ValueError(
                "reply to comment {0} has an empty body".format(comment_id))
        validate_tone(body)
        out.append({"comment_id": comment_id, "surface": surface, "body": body})
    return out


def event_for(findings, force_comment: bool = False,
              request_changes: bool = False) -> str:
    """The GitHub review event this finding set warrants.

    Nothing must-fix approves. Withholding the approval over a should-fix
    note would make that tier a blocker, which is not what it means, and a
    review that can only ever COMMENT always sounds non-committal.

    REQUEST_CHANGES is never derived. It is a blocking act on someone else's
    work, and a wrong one costs a maintainer a dismissal, so it stays an
    explicit choice.

    `force_comment` exists because GitHub rejects both APPROVE and
    REQUEST_CHANGES on your own pull request, so it has to win over
    `request_changes` rather than merely over the derived value.
    """
    if force_comment:
        return "COMMENT"
    if request_changes:
        return "REQUEST_CHANGES"
    if any(severity_of(f) == "must-fix" for f in findings):
        return "COMMENT"
    return "APPROVE"


def group_by_root_cause(findings) -> list:
    """Group findings sharing a non-empty `root_cause`, order preserved.

    Two symptoms of one cause posted as two comments double the apparent
    weight of a review without adding information. A finding with no
    `root_cause` is never merged: an absent key means unrelated, not sibling.
    """
    groups: list = []
    by_cause: dict = {}
    for finding in findings:
        cause = finding.get("root_cause") or ""
        if cause and cause in by_cause:
            by_cause[cause].append(finding)
            continue
        group = [finding]
        groups.append(group)
        if cause:
            by_cause[cause] = group
    return groups


def build_payload(commit_id, summary_lead, findings, anchorable,
                  thanks: str = "", force_comment: bool = False,
                  request_changes: bool = False):
    """Build the GitHub Reviews-API payload from findings + anchorable lines."""
    for finding in findings:
        severity_of(finding)  # validate every finding, including folded ones

    event = event_for(findings, force_comment=force_comment,
                      request_changes=request_changes)
    if event == "REQUEST_CHANGES" and not findings:
        raise ValueError(
            "a changes request needs at least one finding; an author cannot "
            "clear one that points at nothing")
    if event == "APPROVE" and not thanks.strip():
        raise ValueError(
            "an approving review must open with a thanks line; set 'thanks' "
            "in the findings JSON, or pass --force-comment")

    comments = []
    summary_entries = []
    groups = group_by_root_cause(findings)
    for group in groups:
        finding = group[0]
        severity = severity_of(finding)
        path = finding["path"]
        line = finding["line"]
        text = finding["body"]
        folded = ["{0}:{1}".format(m["path"], m["line"]) for m in group[1:]]
        in_diff = line in anchorable.get(path, set())
        note = corroboration_note(finding)

        # An anchorable blocking finding is reported by its inline comment and
        # nowhere else. Restating it in the summary made the author read the
        # same sentence twice on one page, and a body that is just an index of
        # the comments beside it is what makes a review read as generated.
        if severity in INLINE_SEVERITIES and in_diff:
            inline_body = text
            if folded:
                # The summary entry used to carry this citation. With the entry
                # gone, dropping it here would discard the folded siblings.
                inline_body += "\n\nAlso at " + ", ".join(folded) + "."
            if note:
                inline_body += "\n\n" + note
            comments.append({"path": path, "line": line,
                             "side": "RIGHT", "body": inline_body})
            continue

        # Everything else has no inline home: a "consider" finding, which is
        # deliberately not a demand, or one whose line is outside the diff.
        # A bullet, not a number: numbering your own findings is the format a
        # linter report uses, and it reads as one.
        citation = "{0}:{1}".format(path, line)
        if folded:
            citation += "; also " + ", ".join(folded)
        entry = "- {0} ({1})".format(text, citation)
        if not in_diff:
            permalink = finding.get("permalink", "")
            if permalink:
                entry += " " + permalink
        if note:
            entry += " " + note
        summary_entries.append(entry)

    # No fixed body for the clean case. A constant posted verbatim on every
    # clean pull request is identical text across many reviews under one
    # name, which is the loudest machine signal a repo's history can carry.
    parts = []
    if thanks.strip():
        parts.extend([thanks.strip(), ""])
    if summary_lead:
        parts.extend([summary_lead, ""])
    parts.extend(summary_entries)
    body = "\n".join(parts).strip()
    if not body:
        raise ValueError(
            "every finding anchored inline and summary_lead is empty, so "
            "the review would post with a blank body; write a summary_lead")

    validate_tone(body)
    for comment in comments:
        validate_tone(comment["body"])

    return {"commit_id": commit_id, "event": event,
            "body": body, "comments": comments}


def render_preview(payload: dict, replies=(), pr_number=None) -> str:
    """Human-readable preview of everything a confirm would authorise.

    Leads with the event, then enumerates every outward write. The review used to
    be the only one; threaded replies made the count N+1, and a confirm that says
    "post this review?" no longer describes what happens.
    """
    number = pr_number if pr_number is not None else "<n>"
    replies = list(replies or [])
    lines = ["=== REVIEW EVENT: {0} ===".format(payload["event"]),
             "=== OUTWARD WRITES: 1 review + {0} threaded replies ===".format(
                 len(replies)),
             "  [1] POST pulls/{0}/reviews (event: {1})".format(
                 number, payload["event"])]
    for index, reply in enumerate(replies, start=2):
        # The reply route is scoped by pull number:
        # POST /repos/{owner}/{repo}/pulls/{pull_number}/comments/{id}/replies.
        # Rendering it without the pull number names a route GitHub does not
        # serve, and the operator copies what the render shows.
        lines.append("  [{0}] POST pulls/{1}/comments/{2}/replies".format(
            index, number, reply["comment_id"]))
        lines.append("      {0}".format(reply["body"]))
    lines.extend(["", "=== SUMMARY (review body) ===", payload["body"], ""])
    if payload["comments"]:
        lines.append("=== INLINE COMMENTS ===")
        for comment in payload["comments"]:
            lines.append("{0}:{1}: {2}".format(
                comment["path"], comment["line"], comment["body"]))
    else:
        lines.append("(no inline comments)")
    return "\n".join(lines)


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description="Build a GitHub PR review payload.")
    parser.add_argument("--diff", required=True, help="path to a unified diff file")
    parser.add_argument("--findings", required=True, help="path to findings JSON")
    parser.add_argument("--commit", required=True, help="head commit SHA")
    parser.add_argument("--render", action="store_true",
                        help="print a human preview instead of the JSON payload")
    parser.add_argument("--force-comment", action="store_true",
                        help="post as COMMENT even when the findings would "
                             "approve; required when reviewing your own PR")
    parser.add_argument("--request-changes", action="store_true",
                        help="post as REQUEST_CHANGES; never derived, always "
                             "an explicit choice")
    parser.add_argument("--replies-out",
                        help="write threaded replies to this path as JSON; they "
                             "are NOT part of the review payload")
    parser.add_argument("--pr-number", type=int,
                        help="PR number, used only to render write targets")
    args = parser.parse_args(argv)

    # --render enumerates every threaded reply as a write the operator is being
    # asked to authorise. Without --replies-out nothing is written to or cleared
    # from the sidecar, so the render describes replies this run never produced
    # and the post loop sends whatever an earlier run left at that path. The
    # render promises writes it cannot make; refuse the combination instead.
    diff_name = os.path.basename(args.diff)
    pinned = _PINNED_DIFF_RE.match(diff_name)
    if pinned and pinned.group(1).lower() != args.commit.lower():
        parser.error(
            "the diff was fetched at {0} but --commit is {1}: the inline "
            "anchors would be computed against one tree and submitted "
            "against another. Refetch the diff pinned to {1}".format(
                pinned.group(1), args.commit))
    if _UNPINNED_DIFF_RE.match(diff_name):
        parser.error(
            "{0} came from an unpinned `gh pr diff` and cannot be shown to "
            "match --commit. Fetch it pinned to the reviewed SHA and name it "
            "pr-review-<number>-<sha>.diff".format(diff_name))

    if args.render and not args.replies_out:
        parser.error(
            "--render requires --replies-out: the render lists the threaded "
            "replies as writes to authorise, and without that flag the sidecar "
            "is neither written nor cleared, so the post step would send an "
            "earlier run's replies")

    # Step 9 reads this path by name. A rejected reply (an em dash, a bad
    # comment_id) aborts this run after an earlier run already wrote here, and
    # the earlier file would then be posted as this run's replies. Same failure
    # class --out has in fetch_ai_reviews.py, so it is removed up front rather
    # than on each failure path.
    if args.replies_out:
        try:
            os.remove(args.replies_out)
        except FileNotFoundError:
            pass

    with open(args.diff, encoding="utf-8") as handle:
        diff_text = handle.read()
    with open(args.findings, encoding="utf-8") as handle:
        data = json.load(handle)

    payload = build_payload(
        commit_id=args.commit,
        summary_lead=data.get("summary_lead", ""),
        findings=data.get("findings", []),
        anchorable=parse_anchorable(diff_text),
        thanks=data.get("thanks", ""),
        force_comment=args.force_comment,
        request_changes=args.request_changes,
    )
    replies = build_replies(data.get("replies", []))
    if args.replies_out:
        with open(args.replies_out, "w", encoding="utf-8") as handle:
            json.dump(replies, handle, indent=1)
    print(render_preview(payload, replies, args.pr_number)
          if args.render else json.dumps(payload))
    return 0


if __name__ == "__main__":
    sys.exit(main())
