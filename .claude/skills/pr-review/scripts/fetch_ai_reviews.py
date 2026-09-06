#!/usr/bin/env python3
"""Fetch prior AI code-reviewer comments on a pull request.

AI reviewers do not share one surface. Verified 2026-08-28: CodeRabbit posts its
walkthrough on issues/{n}/comments, while Copilot and Greptile post on
pulls/{n}/reviews. Reading one endpoint misses most of what they said.

Detection is a login allowlist rather than `user.type == "Bot"`, which is wrong
in both directions: codecov-commenter posts as type User, and github-actions[bot]
is a Bot that reviews nothing.
"""

import argparse
import json
import os
import subprocess
import sys

SURFACES = ("issue_comment", "review", "inline")

# Every surface unreadable is a fetch failure, not an absence of AI review.
EXIT_ALL_SURFACES_UNREADABLE = 2
# --out could not be cleared, so it cannot be trusted to hold this run's records.
EXIT_OUT_NOT_REMOVABLE = 3

EXIT_CODE_HELP = """exit codes:
  0  the fetch worked. --out holds a JSON array, empty when no AI reviewer
     commented on the PR. One unreadable surface is tolerated at this level so
     long as another surface answered.
  1  the run aborted on an unhandled error, most often an --allowlist path that
     does not exist or does not parse. --out is already removed by then: the
     purge runs before anything is read, so no earlier run's file survives.
  2  every surface was unreadable, so this is a fetch failure and not an
     absence of AI review. --out is removed rather than left stale, so an
     earlier run's records cannot be read as this run's.
  3  --out could not be cleared: it is a directory, or its directory is not
     writable. Nothing is fetched, because a path that cannot be cleared cannot
     be trusted to hold this run's records rather than an earlier run's.

Gate on the exit code, not on the stdout text.
"""

DEFAULT_ALLOWLIST = os.path.join(
    os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
    "ai-reviewers.json")


def load_allowlist(path) -> dict:
    """Map lowercased login to the display name used in the posted review."""
    with open(path, encoding="utf-8") as handle:
        data = json.load(handle)
    allowlist = {}
    for entry in data.get("reviewers", []):
        login = (entry.get("login") or "").strip().lower()
        if not login:
            continue
        allowlist[login] = entry.get("display") or entry["login"]
    return allowlist


def _record(raw, surface, display):
    """Normalize one raw API object to the record Reconcile consumes.

    `path` and `line` are None on the issue_comment and review surfaces: neither
    is line-anchored, and inventing a line for them would let Reconcile match on
    a coordinate GitHub never gave us.
    """
    path = None
    line = None
    if surface == "inline":
        path = raw.get("path")
        # An outdated inline comment carries line=null; original_line still says
        # where it was written against.
        line = raw.get("line")
        if line is None:
            line = raw.get("original_line")
    return {
        "reviewer": display,
        "surface": surface,
        "comment_id": raw.get("id"),
        "path": path,
        "line": line,
        "body": raw.get("body") or "",
        "url": raw.get("html_url") or "",
    }


def collect(payloads, allowlist) -> list:
    """Filter raw per-surface API payloads down to AI-reviewer records.

    `payloads` maps a surface name to the list of raw objects fetched from it.
    Absent surfaces are treated as empty, so a caller may pass only what it read.
    """
    out = []
    for surface in SURFACES:
        for raw in payloads.get(surface) or []:
            login = ((raw.get("user") or {}).get("login") or "").strip().lower()
            display = allowlist.get(login)
            if display is None:
                continue
            out.append(_record(raw, surface, display))
    return out


def _warn(message):
    print("fetch_ai_reviews: {0}".format(message), file=sys.stderr)


def _last_line(raw):
    text = raw.decode("utf-8", "replace").strip()
    return text.splitlines()[-1] if text else "no diagnostic on stderr"


def _gh_json(endpoint):
    """GET one paginated endpoint through gh, or None when it is unreadable.

    None rather than [], because the caller has to tell a surface that failed
    apart from a surface that simply had nothing on it. Flattening both to []
    let an expired token read as "no AI reviewer commented" and exit 0.

    A surface that 404s (a permissions gap, an endpoint this PR does not have)
    still must not take the whole review down: the caller keeps the other two.
    The gh diagnostic is echoed rather than discarded, because "HTTP 401: Bad
    credentials" is the entire answer when this happens.
    """
    try:
        proc = subprocess.run(
            ["gh", "api", "--paginate", endpoint],
            stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    except OSError as err:
        _warn("could not run gh for {0}: {1}".format(endpoint, err))
        return None
    if proc.returncode != 0:
        _warn("gh api {0} failed (exit {1}): {2}".format(
            endpoint, proc.returncode, _last_line(proc.stderr)))
        return None
    try:
        data = json.loads(proc.stdout.decode("utf-8"))
    except ValueError:
        _warn("gh api {0} returned output that is not JSON".format(endpoint))
        return None
    if not isinstance(data, list):
        _warn("gh api {0} returned {1}, not a list".format(
            endpoint, type(data).__name__))
        return None
    return data


def fetch(owner_repo, number) -> dict:
    """Read all three surfaces for one PR. A surface that could not be read
    is None rather than an empty list.
    """
    return {
        "issue_comment": _gh_json(
            "repos/{0}/issues/{1}/comments".format(owner_repo, number)),
        "review": _gh_json(
            "repos/{0}/pulls/{1}/reviews".format(owner_repo, number)),
        "inline": _gh_json(
            "repos/{0}/pulls/{1}/comments".format(owner_repo, number)),
    }


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(
        description="Fetch prior AI code-reviewer comments on a pull request.",
        epilog=EXIT_CODE_HELP,
        formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--repo", required=True, help="owner/repo")
    parser.add_argument("--number", required=True, type=int, help="PR number")
    parser.add_argument("--allowlist", default=DEFAULT_ALLOWLIST,
                        help="path to ai-reviewers.json")
    parser.add_argument("--out", required=True,
                        help="path to write the JSON array to")
    args = parser.parse_args(argv)

    # Purge before any read, not on a selected failure path. Reconcile reads
    # this path and treats absent-or-empty as "no AI reviewer commented", so an
    # earlier run's file left sitting here makes it run against a different
    # run's findings. Every abort below this line, including the uncaught
    # allowlist error that exits 1, then leaves nothing stale behind, because
    # the file is already gone before the first thing that can fail runs.
    try:
        os.remove(args.out)
    except FileNotFoundError:
        pass
    except OSError as err:
        # A directory at --out, or a read-only parent. Removing is the same
        # permission the write at the end of this function needs, so failing
        # here costs nothing that was going to work anyway, and it fails on a
        # named code instead of an undocumented traceback.
        _warn("could not clear {0}: {1}. Nothing was fetched: a path that "
              "cannot be cleared cannot be trusted to hold this run's records "
              "rather than an earlier run's.".format(args.out, err))
        return EXIT_OUT_NOT_REMOVABLE

    allowlist = load_allowlist(args.allowlist)
    payloads = fetch(args.repo, args.number)

    unreadable = [name for name in SURFACES if payloads.get(name) is None]
    if len(unreadable) == len(SURFACES):
        _warn("every surface of {0}#{1} was unreadable. That is a fetch failure, "
              "not an absence of AI review: check `gh auth status` and that the "
              "repo and PR number are right. There is now no file at {2}: any "
              "earlier one was removed, so a previous run's records cannot be "
              "read as this run's.".format(args.repo, args.number, args.out))
        return EXIT_ALL_SURFACES_UNREADABLE

    records = collect(payloads, allowlist)
    with open(args.out, "w", encoding="utf-8") as handle:
        json.dump(records, handle, indent=1)

    by_reviewer = {}
    for record in records:
        by_reviewer[record["reviewer"]] = by_reviewer.get(record["reviewer"], 0) + 1
    if by_reviewer:
        summary = ", ".join("{0} x{1}".format(name, count)
                            for name, count in sorted(by_reviewer.items()))
    else:
        summary = "none"
    print("ai reviewers found: {0} -> {1}".format(summary, args.out))
    if unreadable:
        _warn("{0} of {1} surfaces were unreadable ({2}), so findings from "
              "them are missing.".format(
                  len(unreadable), len(SURFACES), ", ".join(unreadable)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
