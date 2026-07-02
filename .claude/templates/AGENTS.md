# Agents Workbench - {{PROJECT_NAME}}

> **Branch**: `agents-workbench` (local-only, NEVER push)
> **Base**: `{{DEFAULT_BRANCH}}`

## Workflow

This branch is the **coordination hub**. Source code is READ-ONLY here.
All implementation happens in worktrees under `.worktrees/`.

### Quick Reference

| Action | Command |
|--------|---------|
| Create worktree | `git worktree add .worktrees/<name> -b <branch> {{DEFAULT_BRANCH}}` |
| List worktrees | `git worktree list` |
| Remove worktree | `git worktree remove .worktrees/<name>` |
| Update workbench | `git rebase {{DEFAULT_BRANCH}}` |

## Active Worktrees

| Branch | Path | Agent | Status | Started |
|--------|------|-------|--------|---------|
| _none yet_ | | | | |

## Tasks

| # | Task | Priority | Assigned To | Worktree | Status |
|---|------|----------|-------------|----------|--------|
| _none yet_ | | | | | |

## Context

<!-- Preserve important context between sessions here -->
<!-- This section survives across Claude Code sessions via local commits -->

## Decisions

<!-- Document architectural decisions and their rationale -->

## Notes

<!-- Session notes, observations, things to remember -->
