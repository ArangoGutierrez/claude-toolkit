---
name: config-audit
description: Audit your own .claude config surface (skills/hooks/MCP/settings) for secrets, injection sinks, over-broad permissions, and hook hygiene. Triggered by "audit my config", "scan .claude", or /config-audit
user-invocable: true
tools:
  - Read
  - Grep
  - Glob
  - Bash
  - Edit
---

# Config Audit — Self-Audit of the Agent Surface

Audits the `.claude` configuration itself (not project code). Read-only scan,
then propose fixes for your approval.

## Process

1. Run the scanner on the live config:
   `bash scripts/scan-config.sh "$HOME/.claude"`
   Optionally also scan this repo: `bash scripts/scan-config.sh .claude`
2. Parse the TSV output: `SEVERITY<TAB>CATEGORY<TAB>FILE:LINE<TAB>MESSAGE`.
3. Present a severity-ranked report (high → low) with file:line and a concrete fix.
4. For each finding, propose a fix. **Apply only after user approval, in a
   separate turn and a separate commit.** The skill never mutates config silently.
5. On completion, record the run: `date +%Y-%m-%d > "$HOME/.claude/audit/.last-config-audit"`.

## Categories

- `secrets` — hardcoded tokens/keys/passwords/PEM blocks.
- `injection-sink` — untrusted content piped to a shell / eval.
- `broad-perms` — sandbox/permission bypass, wildcard Bash grants.
- `hook-hygiene` — unhardened shell scripts, executable `.bak` backups.
- `mcp-hygiene` — too many enabled MCP servers (>10) inflating context.

## Suppression

Add `# config-audit:ignore <category|all>` on a line to suppress a known-safe match.

## Exit Codes (for CI later)

`0` clean · `1` low/medium · `2` high/critical · `3` scan aborted / nothing scanned (fails closed — e.g. missing target dir, `mktemp` failure, or a findings-buffer write error; never reports clean on abort).

## Gotchas

- Read-only by design — never auto-fix. Propose, then apply on approval.
- Re-run after fixes to confirm the finding is gone.
- A finding is not a vulnerability until triaged; review before acting.
