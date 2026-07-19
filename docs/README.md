# Documentation

Welcome to the claude-toolkit documentation. This repo configures [Claude Code](https://docs.anthropic.com/en/docs/claude-code) and [Cursor IDE](https://www.cursor.com/) with opinionated enforcement of TDD, signed commits, worktree-based development, and agent-driven workflows.

## Guides

| Document | Description |
|----------|-------------|
| [Getting Started](getting-started.md) | Prerequisites, installation, verification, and first workflow |
| [Engineering Discipline](engineering-discipline.md) | The six ideas the toolkit enforces, each linked to its shipped implementation |
| [Architecture](architecture.md) | Deep-dive into the coordination-branch and worktree architecture with diagrams |
| [Graphify Code Graph](graphify.md) | Install the CLI, build a code graph, and query it before grepping |

## Reference

| Document | Description |
|----------|-------------|
| [Claude Code Configuration](claude-code.md) | Hooks, settings, plugins, and policies |
| [Cursor Configuration](cursor.md) | Agents, commands, rules, and hooks |
| [Deployment Scripts](deployment.md) | deploy.sh, capture.sh, and diff.sh explained |
| [Skills & Commands Reference](skills-and-commands.md) | Complete reference of all slash commands and skills |
| [Skill README Template](skill-readme-template.md) | The standard for per-skill README pages — agent-facing SKILL.md vs human-facing README.md |
| [Testing Agent Models](testing-agent-models.md) | How to verify Cursor agents are configured with the intended model settings |
