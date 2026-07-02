---
name: reflection
description: Analyze session patterns, capture mistakes, curate rules. Unified learning loop. Triggered by "analyze session", "what did I learn", "improve CLAUDE.md", or /reflection
user-invocable: true
tools:
  - Read
  - Grep
  - Glob
  - Bash
  - Edit
  - Write
---

# Reflection — Unified Learning Loop

Three modes based on context:

## Mode 1: Session Analysis
Reads `audit/bash-commands-*.log` for patterns and recent `git log`.

1. Run `scripts/analyze-sessions.sh` to aggregate recent activity
2. Identify: repeated errors, permission blocks, hook violations, time sinks
3. Summarize: files touched, patterns observed, recurring issues
4. Propose: specific improvements to CLAUDE.md or rules/

## Mode 2: Mistake Capture
When user says "I keep making this mistake" or describes a recurring error:

1. Prompt for: context, mistake, correction, severity (critical/warning/info), tags
2. Check `rules/learned-anti-patterns.md` for duplicates
3. Duplicate → increment Count, update Since date
4. New → append: `- **Pattern**: <desc> | **Fix**: <fix> | **Severity**: <level> | **Tags**: <tags> | **Count**: 1 | **Since**: YYYY-MM-DD`
5. Check `audit/.anti-patterns.lock` before writing

## Mode 3: Rules Curation
1. Prune learned-anti-patterns.md per severity rules:
   - `critical`: never auto-pruned
   - `warning`: prune when Count < 2 AND Since > 90 days
   - `info`: prune by lowest count when over 50-line cap
2. Check rules/ for staleness (specific versions, untriggered in 90 days)
3. Update `audit/.last-reflection` with today's date when complete

### Pattern Promotion
When anti-pattern hits Count >= 3 AND is mechanically detectable (regex, AST grep, or exit-code without model reasoning):
- Propose new regex in `hooks/test-quality-lint.sh` (test patterns)
- Or new check in existing hook (code patterns)
- Or new rule in `rules/` (convention patterns)
- Mark entry: append `| **Promoted**: <hook-name>`

## Write Safety
Before writing to `rules/learned-anti-patterns.md`:
- If `audit/.anti-patterns.lock` exists → blocked (team-execute QA is writing)

## All changes require user approval before writing.

## Gotchas
- Don't remove rules that haven't been tested
- Don't add rules already covered by hooks
- Don't treat one-off errors as patterns (require Count >= 2)
- Don't propose rules that are generic software engineering
