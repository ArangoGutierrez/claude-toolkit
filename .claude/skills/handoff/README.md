# /handoff — capture session state for a fresh start

`/handoff` assembles a structured handoff document — active worktree, branch,
modified files, TDD phase, and (via a dispatched subagent) the session's key
decisions — then asks two forward-looking questions and writes the result to
`~/.claude/audit/handoffs/<timestamp>-handoff.md`, printing it to stdout for
copy-paste into a new session. If the transcript can't be located, extraction
is skipped rather than the handoff blocking.

## When to use it

- Context is approaching the limit (e.g., after a `context-watch` hook nudge).
- You're ending a long session you intend to resume later.
- You just finished a significant chunk of work and want the next session to
  start with full context instead of re-deriving it from scratch.
- **Not for:** mid-task pauses — generating a handoff mid-task creates noise;
  only run it at session-end or near the context limit.

## Examples

    > /handoff
    → Gathers git state (worktree, branch, `diff --name-only`), scans the
      visible conversation for the most recent [RED]/[GREEN]/[REFACTOR] marker
      and iteration count, dispatches a subagent to extract decisions from the
      session transcript, then asks what the next session should do first and
      which verification commands to run. Writes the filled template to
      `~/.claude/audit/handoffs/<YYYY-MM-DD-HHMM>-handoff.md` and prints it
      under an `=== HANDOFF DOCUMENT ===` header for copy-paste.

    > /handoff (session transcript file missing or unreadable)
    → Decision extraction is skipped; the "Decisions made" section gets
      `<auto-extraction unavailable — manually summarize decisions before
      sending this handoff>` instead. The rest of the document is still
      assembled and printed — a missing transcript never blocks the handoff.

## Notes

- TDD phase and iteration parsing is heuristic — it scans visible context for
  markers, so false negatives happen; correct the doc by hand if it misses.
- Transcript resolution depends on Claude Code's
  `~/.claude/sessions/<PID>.json` → `~/.claude/projects/<slug>/<session-id>.jsonl`
  convention; if that breaks, resolution falls back to `UNAVAILABLE` instead
  of failing the handoff.
- The handoff doc is a permanent record — treat it as immutable once written;
  edit it by hand rather than regenerating.
- Paste the printed document into the new session and pick up from "Next
  session should" — [`kickoff`](../kickoff/) is a natural next step if that
  work still needs scoping. Index:
  [`docs/skills-and-commands.md`](../../../docs/skills-and-commands.md).
