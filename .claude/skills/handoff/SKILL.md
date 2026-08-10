---
name: handoff
description: Generate a structured handoff prompt to start a fresh session with full context. Use when context window approaches limit or before ending a long session. `/handoff --epic` instead produces an epic-launch brief for a session that must drive a large goal to completion autonomously.
user-invocable: true
tools:
  - Bash
  - Read
  - Write
  - Agent
---

# Session Handoff

Generates a handoff document at `~/.claude/audit/handoffs/YYYY-MM-DD-HHMM-handoff.md` and prints it to stdout for copy-paste into a new session.

## When to use

- When you notice context approaching the limit (e.g., after the `context-watch` hook nudges you).
- Before manually ending a long session that you intend to resume.
- After completing a significant chunk of work where the next session needs to pick up exactly where this one left off.

## What it does

### Step 1 — Gather context (deterministic, no model needed)

Run the following commands and capture their output:

```bash
# Active worktree path
git worktree list | head -3

# Current branch
git branch --show-current

# Files modified (unstaged + staged, relative to HEAD)
git diff --name-only HEAD
git diff --name-only --cached

# Any worktrees listed (multi-worktree sessions)
git worktree list --porcelain | grep 'worktree'
```

TDD phase and iteration: scan the visible conversation for the most recent occurrence of:
- `[RED]`, `[GREEN]`, `[REFACTOR]` — record whichever is most recent
- `[Iteration X/Y]` — record the most recent value

If none are found, record `unknown`.

### Step 2 — Locate the session transcript

The Claude Code session transcript lives at:

```
~/.claude/projects/<project-slug>/<session-id>.jsonl
```

Where `<project-slug>` is the cwd path with `/` replaced by `-` (e.g., `/Users/foo/repo` → `-Users-foo-repo`), and `<session-id>` is a UUID.

Resolution algorithm (in order):

1. **Via session file**: The session file at `~/.claude/sessions/<PID>.json` contains the `sessionId` UUID and `cwd`. Read the file matching `$$` (current PID) or the most recently modified `.json` in that directory. Extract `sessionId` and `cwd`.
2. **Construct path**: `~/.claude/projects/<slug>/<session-id>.jsonl` where `<slug>` = `<cwd>` with each `/` replaced by `-`.
3. **Verify**: Check that the file exists and is non-empty (`-s`).
4. **Fallback**: If the above fails (file missing, unreadable, or too large), set transcript path to `UNAVAILABLE` and proceed without auto-extraction.

Example shell snippet (for reference — Claude executes this, not a script):

```bash
# Find the session file for this PID
SESSION_FILE=~/.claude/sessions/$$.json
if [ -f "$SESSION_FILE" ]; then
  SESSION_ID=$(python3 -c "import json,sys; d=json.load(open('$SESSION_FILE')); print(d['sessionId'])")
  CWD=$(python3 -c "import json,sys; d=json.load(open('$SESSION_FILE')); print(d['cwd'])")
  SLUG=$(echo "$CWD" | sed 's|/|-|g')
  TRANSCRIPT=~/.claude/projects/${SLUG}/${SESSION_ID}.jsonl
  [ -s "$TRANSCRIPT" ] || TRANSCRIPT="UNAVAILABLE"
else
  # Fallback: newest session file
  TRANSCRIPT="UNAVAILABLE"
fi
echo "Transcript: $TRANSCRIPT"
```

### Step 3 — Auto-extract decisions (subagent-based)

**If transcript is AVAILABLE** (file exists and readable):

Dispatch a focused subagent with this prompt (fill in `<TRANSCRIPT_PATH>`):

> Read the JSONL transcript at `<TRANSCRIPT_PATH>`. Each line is a JSON object; look at `role` and `content` fields. Extract architectural and design decisions, approach choices, and explicit user preferences expressed during this session. Output as a bullet list (≤10 bullets). Format: `- <decision> — <rationale if stated>`. Skip routine task tracking, file paths, and tool outputs. Focus on commitments that affect future sessions.

Show the user a progress message before dispatching: `"Dispatching subagent to extract decisions from transcript (10-30s)..."`

Insert the subagent's bullet list into the "Decisions made" section.

**If transcript is UNAVAILABLE**:

Insert this placeholder instead:
```
<auto-extraction unavailable — manually summarize decisions before sending this handoff>
```

Do NOT block or abort the handoff in this case. Continue to Step 4.

### Step 4 — Prompt user for forward-looking sections

These cannot be auto-extracted; ask the user interactively:

1. "What should the next session start by doing? (1-3 actions, e.g. 'run tests', 'continue implementing X')"
2. "What verification command(s) should the next session run before claiming done? (e.g. 'go test ./...', 'make lint')"

Record the responses. If the user says "skip" or leaves blank, insert `<user did not provide — fill in before sending>`.

### Step 5 — Write and print the handoff document

**Filename**: `~/.claude/audit/handoffs/$(date +%Y-%m-%d-%H%M)-handoff.md`

**Document template** (fill all `<placeholders>`):

```markdown
# Session Handoff — <YYYY-MM-DD HH:MM>

## Context
- Active worktree: <path from git worktree list>
- Branch: <branch>
- TDD phase: <phase or unknown>
- Iteration: <X/Y or unknown>

## Files modified this session
<bullet list from git diff --name-only HEAD and git diff --name-only --cached; merge and deduplicate>
- <file1>
- <file2>
(if empty, write: none detected)

## Decisions made
<subagent-extracted bullets, or unavailability placeholder>

## Next session should
1. <user input 1>
2. <user input 2>
(add more as needed)

## Verification before claiming done
```
<user-provided commands, one per line>
```
```

After writing, print the full document to stdout with this header:

```
=== HANDOFF DOCUMENT ===
(copy everything below this line into your next session)
```

Then print the document content.

## Epic-launch mode — `/handoff --epic`

A different genre from the session handoff above. The session-resumption handoff
answers *"what was I doing?"*. An epic-launch handoff answers *"here is a large
goal — drive it to completion autonomously."* The receiving session runs for
hours, dispatches subagents, and opens many PRs, so it needs the **mechanism**,
not only the context.

Use this mode when the receiving session will:
- execute a multi-PR epic rather than resume in-flight work, **and**
- dispatch subagents rather than do the work in one context, **and**
- run with bypass-permissions or otherwise unattended for long stretches.

### Required sections, in addition to the standard ones

1. **Mission + definition of done** — what "finished" means, objectively.
2. **Verified ground truth** — facts the session must NOT re-derive, each with the
   command that produced it. This is the highest-value part of the document:
   every hour spent verifying here is an hour the receiving session does not
   spend rediscovering, and a claim carried without its command is a liability.
3. **Execution loop** — paste and adapt `references/epic-execution-loop.md`.
   **Do not omit it and do not paraphrase away its exit conditions or bounds.**
   It carries the DAG/wave decomposition, the `chief-dispatch` critic gate, the
   per-task exit condition, `review-verify` before any external review, the
   loop-until-dry completeness critic, and the standing triggers.
4. **Constraints and gates** — what the session may never do unattended. At
   minimum: never post externally without per-action user approval, never merge,
   and the repo's own PR-size and commit conventions.
5. **Ordered first actions** — front-load work that has no cross-session
   dependency, so the session never idles waiting on a peer.

### Authoring rules

- **Verify every literal before it ships.** Commands, paths, line numbers, counts
  and tool/workflow names in a handoff are untested code. Check each against the
  branch the work will actually run on — not whichever checkout happens to be
  open. This is the single most common defect in these documents.
- **Prefer executed evidence to cited evidence.** "I ran X, here is the output"
  outranks "the file says X". A citation proves the code *says* something, not
  that it *does* it.
- **State blind spots explicitly** — unreadable paths, stale graphs, assumptions
  established by inspection rather than execution. A named gap is safe; a silent
  one is not.
- **Name the epic's specific failure mode** for the `review-verify` dimension.
  The generic three dimensions are table stakes; the fourth is where the value is.

## Limitations

- **TDD phase / iteration parsing** is heuristic — relies on markers being present in the visible conversation context. False negatives are expected. The user should manually correct the handoff doc if needed.
- **Transcript path resolution** depends on Claude Code's session-management conventions, specifically the `~/.claude/sessions/<PID>.json` → `~/.claude/projects/<slug>/<session-id>.jsonl` chain. This has been verified against Claude Code 2.1.131 but may change in future versions. The UNAVAILABLE fallback is the safety net.
- **Auto-extraction subagent** can be slow (10-30s typical) and counts against the token budget. If context is already at 95%+, skip transcript extraction and go directly to Step 4.
- **No `$CLAUDE_TRANSCRIPT_PATH` or `$CLAUDE_SESSION_ID` env vars** are exposed at runtime (verified). Resolution relies entirely on the session file + project directory pattern.

## Gotchas

- Don't run during normal work — only at session-end or near context limit. Generating a handoff mid-task creates noise.
- The handoff doc is a permanent record; treat it as immutable after write. Edit it manually if needed, don't regenerate.
- The `~/.claude/audit/handoffs/` directory is pre-created. If it's missing for any reason, create it with `mkdir -p ~/.claude/audit/handoffs` before writing.
- `git diff --name-only HEAD` may show staged + unstaged changes depending on the repo state; supplement with `--cached` to capture staged-only changes not yet committed.

## File locations

- Skill: `~/.claude/skills/handoff/SKILL.md`
- Handoff docs: `~/.claude/audit/handoffs/`
- Session files: `~/.claude/sessions/<PID>.json`
- Transcripts: `~/.claude/projects/<project-slug>/<session-id>.jsonl`
