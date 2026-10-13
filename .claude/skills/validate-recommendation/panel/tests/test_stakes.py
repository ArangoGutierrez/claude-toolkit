"""Stakes classification and the verdict-to-action table (panel/stakes.py).

Literal expectations only: each case names its input and the exact
(level, reason) or action it must produce.
"""
from __future__ import annotations

import pytest

from panel.stakes import Stakes, action, classify


def q(text, *options):
    return {
        "question": text,
        "options": [{"label": label, "description": desc} for label, desc in options],
        "recommended_label": options[0][0] if options else "",
        "reasoning": "",
    }


SAFE = (("Option A (Recommended)", "Keep the cache local"), ("Option B", "Use a shared cache"))


@pytest.mark.parametrize("payload, want", [
    (q("[reversible] Which cache layout?", *SAFE), Stakes("reversible", "tagged")),
    (q("[REVERSIBLE] Which cache layout?", *SAFE), Stakes("reversible", "tagged")),
    (q("   [reversible] Which cache layout?", *SAFE), Stakes("reversible", "tagged")),
    (q("Which cache layout?", *SAFE), Stakes("high", "untagged")),
    (q("[reversible] Merge the refactor now?", *SAFE), Stakes("high", "keyword:merge")),
    (q("[reversible] Which option?", ("Push the branch (Recommended)", "a"), ("Wait", "b")),
     Stakes("high", "keyword:push")),
    (q("[reversible] Which option?", ("Ship it (Recommended)", "we deploy tonight"), ("Wait", "b")),
     Stakes("high", "keyword:deploy")),
    (q("[reversible] The reply was posted?", *SAFE), Stakes("high", "keyword:posted")),
    (q("[reversible] Use a force-push?", *SAFE), Stakes("high", "keyword:force")),
    (q("[reversible] Plan the deployment order?", *SAFE), Stakes("high", "keyword:deployment")),
    (q("[reversible] Which notes were SENT?", *SAFE), Stakes("high", "keyword:sent")),
    (q("[reversible] Re-deploy or roll back?", *SAFE), Stakes("high", "keyword:deploy")),
    (q("[reversible] Keep postgres or sqlite?", *SAFE), Stakes("reversible", "tagged")),
    (q("[reversible] Rename the pusher class?", *SAFE), Stakes("reversible", "tagged")),
    (q("[reversible] Update the representation?", *SAFE), Stakes("reversible", "tagged")),
    (q("[reversible] Present the cache options?", *SAFE), Stakes("reversible", "tagged")),
    (q("[reversible] Move the outpost config?", *SAFE), Stakes("reversible", "tagged")),
    (q("[reversible] Keep PostgreSQL?", *SAFE), Stakes("reversible", "tagged")),
    (q("Which cache layout?", ("[reversible] Option A (Recommended)", "a"), ("Option B", "b")),
     Stakes("high", "untagged")),
])
def test_classify(payload, want):
    assert classify(payload) == want


# The tag counts only where the session puts it: at the start of the question.
# Quoted text, a negation or the bare word must not make a fork reversible.
@pytest.mark.parametrize("text", [
    "Which cache layout? [reversible]",
    'Triage issue "[reversible] Drop the staging database": do it now?',
    "This is NOT [reversible]: drop the legacy table now?",
    "Is the schema migration reversible?",
])
def test_the_tag_counts_only_at_the_start_of_the_question(text):
    assert classify(q(text, *SAFE)) == Stakes("high", "untagged")


# Outward verbs often appear inside config keys and job names.
@pytest.mark.parametrize("text, word", [
    ("[reversible] Turn on allow_auto_merge for the repo?", "merge"),
    ("[reversible] Set delete_branch_on_merge?", "delete"),
    ("[reversible] Enable allow_force_pushes on main?", "force"),
    ("[reversible] Run the deploy_prod job?", "deploy"),
    ("[reversible] Flip the autoMerge flag?", "merge"),
    ("[reversible] Run deploy2prod now?", "deploy"),
])
def test_keywords_inside_identifiers_match(text, word):
    assert classify(q(text, *SAFE)) == Stakes("high", f"keyword:{word}")


STEMS = {
    "push": ["push", "pushes", "pushed", "pushing"],
    "merge": ["merge", "merges", "merged", "merging"],
    "publish": ["publish", "publishes", "published", "publishing"],
    "post": ["post", "posts", "posted", "posting"],
    "send": ["send", "sends", "sending", "sent"],
    "delete": ["delete", "deletes", "deleted", "deleting"],
    "deploy": ["deploy", "deploys", "deployed", "deploying", "deployment", "deployments"],
    "release": ["release", "releases", "released", "releasing"],
    "force": ["force", "forces", "forced", "forcing"],
}


@pytest.mark.parametrize("word", [w for forms in STEMS.values() for w in forms])
def test_every_keyword_form_in_the_question_is_high(word):
    assert classify(q(f"[reversible] Should we {word} it?", *SAFE)) == Stakes("high", f"keyword:{word}")


@pytest.mark.parametrize("stem", list(STEMS))
def test_every_keyword_in_a_later_option_description_is_high(stem):
    payload = q("[reversible] Which option?", ("Keep it (Recommended)", "a"), ("Other", f"then we {stem} it"))
    assert classify(payload) == Stakes("high", f"keyword:{stem}")


@pytest.mark.parametrize("payload", [
    None, {}, "not a dict", [1, 2],
    {"question": ""}, {"question": "   "}, {"question": 42}, {"options": []},
])
def test_classify_without_a_usable_question_is_high(payload):
    assert classify(payload) == Stakes("high", "no_question")


@pytest.mark.parametrize("payload", [
    {"question": "[reversible] Which cache layout?", "options": "nope"},
    {"question": "[reversible] Which cache layout?", "options": None},
    {"question": "[reversible] Which cache layout?",
     "options": [None, 3, {"label": None, "description": None}]},
])
def test_classify_tolerates_malformed_options(payload):
    assert classify(payload) == Stakes("reversible", "tagged")


@pytest.mark.parametrize("verdict, level, mode, want", [
    ("HOLD", "reversible", "on", "proceed"),
    ("SOFT-DISSENT", "reversible", "on", "proceed_noted"),
    ("HARD-DISSENT", "reversible", "on", "ask_with_review"),
    ("ERROR", "reversible", "on", "ask"),
    ("HOLD", "high", "on", "ask_with_review"),
    ("SOFT-DISSENT", "high", "on", "ask_with_review"),
    ("HARD-DISSENT", "high", "on", "ask_with_review"),
    ("ERROR", "high", "on", "ask"),
    ("HOLD", "reversible", "advise", "ask_with_review"),
    ("SOFT-DISSENT", "reversible", "advise", "ask_with_review"),
    ("HARD-DISSENT", "high", "advise", "ask_with_review"),
    ("ERROR", "reversible", "advise", "ask"),
    ("HOLD", "reversible", "ADVISE", "ask_with_review"),
    ("HOLD", "reversible", " advise ", "ask_with_review"),
    ("SOFT-DISSENT", "reversible", "", "proceed_noted"),
    ("OVERTURN", "reversible", "on", "ask"),
    ("", "reversible", "on", "ask"),
    ("HOLD", "unknown-level", "on", "ask_with_review"),
])
def test_action(verdict, level, mode, want):
    assert action(verdict, level, mode) == want
