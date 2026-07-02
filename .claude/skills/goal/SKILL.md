---
name: goal
description: Capture or amend the session goal. The goal file at ~/.claude/audit/session-goals/<uuid>.md records the active goal and acceptance criteria for the session. Triggered by /goal, or by user phrases like "set session goal", "amend goal".
user-invocable: true
tools:
  - Read
  - Write
  - Bash
---

# /goal

Records the current session goal as a stanza in `~/.claude/audit/session-goals/<session-uuid>.md`.

## When to use

- Beginning of a session — capture the goal and 1-N acceptance bullets.
- Mid-session — amend the goal if scope has refined (brainstorm → plan → impl evolution).

## Invocation

```
/goal Goal: <one-line goal>
Acceptance:
- <bullet 1>
- <bullet 2>
- <bullet N>
```

The skill runs `~/.claude/skills/goal/goal.sh` with the provided text. Behavior:

1. Resolves the session UUID via `~/.claude/sessions/$$.json`.
2. If the goal file does not exist, writes a `## Initial <ts>` stanza.
3. If it exists, appends a `## Amendment <ts>` stanza.
4. Warns to stderr if the input lacks a `Goal:` line or an `Acceptance:` section (writes anyway — soft rollout).

## Format

Each invocation appends a timestamped stanza (`## Initial <ts>` or `## Amendment <ts>`) holding the `Goal:` line and the `Acceptance:` bullets shown above.
