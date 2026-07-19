# Claude Code Configuration Reference

## Overview

[Claude Code](https://docs.anthropic.com/claude-code) is Anthropic's official CLI for Claude — an AI coding assistant that runs in your terminal. Out of the box it provides conversational code generation, file editing, shell command execution, and web search. This dotfiles repository layers a set of opinionated engineering standards on top of those defaults.

What this configuration adds:

- **Engineering standards** codified in `CLAUDE.md` — a mandatory brainstorm-first policy, a full TDD protocol (Plan→Red→Green→Refactor), an iteration budget, and a clear priority stack (Security > Correctness > Performance > Style).
- **Enforcement hooks** that make the standards machine-checkable — core shell scripts that intercept file writes and Bash commands before Claude executes them, blocking violations with actionable error messages. The toolkit ships more hooks for verification, audit logging, and budget governance; see [Engineering Discipline](engineering-discipline.md) for the full catalog.
- **A plugin ecosystem** — five official plugins covering code review, code simplification, Go and C/C++ language server integration, and the `superpowers` workflow engine that drives brainstorming, TDD, worktree management, and parallel agent dispatch.
- **A fine-grained permissions model** — explicit allow/deny/ask lists for every tool Claude can call, plus a sandbox with network restrictions for remote use.

### File layout

```
.claude/
├── CLAUDE.md               # Engineering standards injected into every session
├── settings.json           # Permissions, hooks, plugins, sandbox, env vars
├── hooks/
│   ├── inject-date.sh      # SessionStart: inject current date into context
│   ├── sign-commits.sh     # PreToolUse/Bash: enforce DCO signoff + GPG signature
│   ├── prevent-push-workbench.sh  # PreToolUse/Bash: block pushing agents-workbench
│   ├── enforce-worktree.sh # PreToolUse/Write+Edit: block source edits on coordination branch
│   ├── tdd-guard.sh        # PreToolUse/Write+Edit: block impl writes without a test
│   └── validate-year.sh    # PreToolUse/Write: block stale copyright years in new files
├── plugins/
│   └── installed_plugins.json
├── .claudeignore           # Patterns excluded from Claude's context window
├── policy-limits.json      # Disable product feedback prompts and remote sessions
└── remote-settings.json    # Network restrictions for sandboxed/remote use
```

The `hooks/` subtree above lists the **core** enforcement hooks documented on this page. The toolkit ships more hooks — for verification, audit logging, and budget governance — under `.claude/hooks/`; see [Engineering Discipline](engineering-discipline.md) for the full catalog.

---

## CLAUDE.md — Engineering Standards

`CLAUDE.md` is loaded into every Claude Code session as system context. It defines the behavioral contract the AI must follow for every task in this repository.

### Role

```
Senior engineer mindset. Rigor > speed.
```

The persona sets the tone: correctness and deliberate design take precedence over moving fast. Every decision should be defensible.

### Brainstorm First

Every non-trivial task must begin with the `superpowers:brainstorming` skill. No exceptions. The workflow is:

```
brainstorm → ≥3 options → user approval → document decision
```

Exempt tasks (tasks where brainstorming is skipped entirely): fixing typos, adding comments, running tests, reading files, answering questions.

"Just do it" phrasing is treated as a request for a *quick brainstorm* — one paragraph summary plus at least two options — rather than a full skip. "Skip brainstorm" is the only phrase that truly bypasses the step. When in doubt, brainstorm. Default is always brainstorm.

### Principles

| Principle | Meaning |
|-----------|---------|
| **Atomicity** | If a task has more than one concern, break it down before starting |
| **No placeholders** | Complete, runnable code only — no `// TODO: implement` stubs |
| **Verify before claiming** | Any response claiming a task is complete must include the output of a verification command (test, build, or lint) in that same response |
| **YAGNI** | Do not add abstractions the current task does not require |
| **≥3 options** | Produce at least three design alternatives before committing to one |

### TDD Protocol (DORA)

The full Red-Green-Refactor cycle is mandatory. Phases must not be skipped or reordered.

| Phase | Signal | Rule |
|-------|--------|------|
| **Plan** | — | Write a design doc or plan before any code. See Brainstorm First. |
| **Red** | `[RED]` | Write the failing test first. Do nothing else in this turn. |
| **Green** | `[GREEN]` | Write the minimum implementation to make the test pass. Never modify tests and implementation code in the same turn. |
| **Refactor** | `[REFACTOR]` | Clean up only after green. Checkpoint first if the change touches more than 3 files or 50 lines. |

Additional rules:

- **Tests are contracts.** Never weaken, delete, or modify a test to make an implementation pass. If a test is wrong, that is a separate concern addressed in a separate commit.
- **Batch size.** Smallest PR-sized chunks. One concern equals one PR.
- **Hook guard.** The `tdd-guard.sh` hook (described below) mechanically enforces the Red-before-Green constraint at the filesystem level.
- **Escalation.** When a diff grows large, use isolated subagent contexts — one subagent writes the tests (Red), a separate subagent writes the implementation (Green). This eliminates same-author blind spots.

### agents-workbench Workflow

All implementation work happens in git worktrees. The `agents-workbench` branch is the local-only coordination hub: planning documents, agent configuration, and task tracking live here, but source code is read-only on this branch.

See [Architecture](architecture.md) for a full deep-dive on the worktree strategy.

**Branch roles:**

- `agents-workbench` — local-only. Never pushed to any remote. Source code is read-only here.
- Feature branches — created under `.worktrees/` from the remote default branch, never from the local branch.

**Worktree creation (always from the remote ref):**

```bash
# Detect the right remote (upstream for forks, origin otherwise)
git fetch upstream 2>/dev/null \
  && BASE="upstream/$(git symbolic-ref refs/remotes/upstream/HEAD 2>/dev/null \
       | sed 's@^refs/remotes/upstream/@@' || echo main)" \
  || { git fetch origin \
       && BASE="origin/$(git symbolic-ref refs/remotes/origin/HEAD \
            | sed 's@^refs/remotes/origin/@@')"; }
git worktree add .worktrees/<name> -b <branch> "$BASE"
```

**Flow:**

1. Plan on `agents-workbench` — write `AGENTS.md`, create `.agents/plans/` documents
2. Create a worktree from the remote ref (see above)
3. Implement inside the worktree
4. Push the feature branch and open a PR
5. After merge: `git worktree remove .worktrees/<name>`

### Iteration Budget

Each response is tracked against a budget that scales with task complexity:

| Complexity | Budget |
|------------|--------|
| Trivial | 1 iteration |
| Simple | 2 iterations |
| Moderate | 3 iterations |
| Complex | 4 iterations |

When the budget is exhausted without resolution, escalate to the user rather than continuing to iterate. Iteration progress is displayed inline as `[Iteration X/Y]`.

### Priority

```
Security > Correctness > Performance > Style
```

A correct-but-insecure solution is not acceptable. A fast-but-incorrect solution is not acceptable. Style discussions come last.

### Subagent Discipline

- **Agent teams** (parallel subagents) are allowed when each agent works in its own worktree.
- **Regular subagents** must be launched sequentially — wait for one to complete before launching the next.
- Prefer a single focused subagent over multiple broad ones.

---

## Settings

`settings.json` is the primary Claude Code configuration file. It controls the permissions model, hook registration, plugin activation, sandbox behavior, and environment.

### Permissions model

Claude Code's permission system uses three lists: `allow` (no prompt), `deny` (always blocked), and `ask` (requires user confirmation).

**Allow — granted without prompting:**

| Category | Patterns |
|----------|---------|
| Version control | `Bash(git *)`, `Bash(gh *)` |
| Build and test | `Bash(go *)`, `Bash(make *)`, `Bash(npm *)`, `Bash(yarn *)`, `Bash(pnpm *)` |
| Kubernetes toolchain | `Bash(kubectl *)`, `Bash(kind *)`, `Bash(helm *)`, `Bash(kustomize *)`, `Bash(controller-gen *)`, `Bash(setup-envtest *)` |
| Security scanners | `Bash(govulncheck *)`, `Bash(gosec *)`, `Bash(trivy *)`, `Bash(grype *)` |
| Code quality | `Bash(golangci-lint *)` |
| Utilities | `Bash(jq *)`, `Bash(rg *)` |
| File operations | `Read(*)`, `Write(*)`, `Edit(*)` |
| Web | `WebFetch(*)`, `WebSearch` |
| GitHub MCP | `mcp__github__*` |

**Deny — always blocked:**

Secrets and credentials are blocked from both reading and writing:

- Read: `.env`, `.env.*`, `secret*`, `credential*`, `*.pem`, `*.key`, `*id_rsa*`, `.ssh/*`, `.aws/*`, `.kube/config`, `*token*`, `*password*`
- Write/Edit: `.env`, `.env.*`, `*secret*`, `*credential*`, `*.pem`, `*.key`

**Ask — requires confirmation before proceeding:**

- `Bash(rm *)`, `Bash(rm -rf *)`
- `Bash(git rebase *)`, `Bash(git reset --hard *)`, `Bash(git push --force *)`
- `Bash(sudo *)`

### Suffix-wildcard Bash allows

A suffix-wildcard allow pattern like `Bash(* --version)` matches on the
trailing text of a command line, not its leading command, so it approves
*any* string that happens to end with that flag:

```
Bash(* --help)  matches:  bash -c '<payload>' --help
```

That auto-approves an attacker-controlled payload disguised as a flag.
`settings.json` used to carry `Bash(* --version)` and `Bash(* --help)` as
blanket allows; both were removed with no replacement, because every tool
listed in the table above already has its own `Bash(<tool> *)` rule, which
covers that tool's `--version`/`--help` invocations without the bypass. If
a new tool needs unprompted version/help checks, add a scoped
`Bash(<tool> *)` rule rather than a suffix wildcard. Issue #15 adds a
`config-audit` scanner check that flags this pattern class.

### Hooks configuration

Hooks are shell scripts that intercept Claude's tool calls before they execute. They receive tool input as JSON on stdin and signal allow (exit 0) or block (exit 2, with stderr surfaced to Claude as feedback).

| Event | Matcher | Hook(s) |
|-------|---------|---------|
| `SessionStart` | — | `inject-date.sh` |
| `PreToolUse` | `Bash` | `sign-commits.sh`, `prevent-push-workbench.sh` |
| `PreToolUse` | `Write` | `enforce-worktree.sh`, `validate-year.sh`, `tdd-guard.sh` |
| `PreToolUse` | `Edit` | `enforce-worktree.sh`, `tdd-guard.sh` |

Note: `validate-year.sh` runs only on `Write` (new file creation) because existing files may legitimately carry older copyright years.

This table covers the core enforcement hooks. `settings.json` also wires additional hooks for verification, audit logging, and budget governance; see [Engineering Discipline](engineering-discipline.md) for the full catalog.

### Plugins

Five official plugins are enabled:

```json
"enabledPlugins": {
  "code-review@claude-plugins-official": true,
  "code-simplifier@claude-plugins-official": true,
  "superpowers@claude-plugins-official": true,
  "gopls-lsp@claude-plugins-official": true,
  "clangd-lsp@claude-plugins-official": true
}
```

See the [Plugins section](#plugins) below for details on each.

### Sandbox

```json
"sandbox": {
  "enabled": true,
  "autoAllowBashIfSandboxed": false
}
```

The sandbox is on by default. `autoAllowBashIfSandboxed` is `false`, so running inside the sandbox does not bypass the permission system: sandboxed Bash commands still go through the same allow/deny/ask evaluation as unsandboxed ones, and the sandbox's filesystem/network restrictions apply on top.

### Environment variables

```json
"env": {
  "CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS": "1"
}
```

Enables the experimental agent teams feature, allowing Claude to dispatch parallel subagents. Combined with `"teammateMode": "in-process"`, agent teams run within the same process rather than spawning separate Claude Code instances.

### Other settings

- `"respectGitignore": true` — Files matched by `.gitignore` are excluded from context.
- `"effortLevel": "high"` — Default reasoning effort level for responses.
- `"attribution"` — Commit and PR attribution strings (empty strings mean no attribution suffix is appended).

### Network restrictions

Network access is unrestricted in normal (non-sandboxed) mode. When running remotely or in sandbox mode, `remote-settings.json` applies additional restrictions (see [Policy and Ignore](#policy-and-ignore)).

---

## Hooks

All hooks live in `.claude/hooks/` and are registered in `settings.json`. Each hook reads tool input from stdin as JSON (parsed with `jq`), and exits with either 0 (allow) or 2 (block). Exit 2 causes Claude Code to surface the hook's stderr output back to Claude as an error message, giving the model actionable feedback about what to fix.

### inject-date.sh

**Event:** `SessionStart`

Injects the current date and year into Claude's context at the start of every session (including resume, clear, and compact events). AI models frequently default to years from their training data when writing copyright headers, changelog entries, or commit messages. This hook corrects that.

The hook writes to stdout, which Claude Code adds to session context:

```
TODAY: Thursday February 20, 2026
CURRENT YEAR: 2026
RULE: When writing dates or years in ANY context (copyright headers, license files,
documentation, commit messages, changelogs, comments, code), always use 2026 as the
current year. Never use years from training data or copy years from existing files in
the project. New files get 2026. Year ranges in existing files being updated should
end with 2026.
```

This hook pairs with `validate-year.sh`, which provides a second line of defense at write time.

### sign-commits.sh

**Event:** `PreToolUse` / `Bash`

Intercepts every Bash command and checks whether it contains a `git commit`. If a commit is found, the hook verifies that both `-s` (DCO signoff) and `-S` (GPG signature) flags are present.

The check handles commit commands in chained invocations:

```bash
# All of these are intercepted correctly:
git commit -s -S -m "message"
make build && git commit -s -S -m "message"
git add . ; git commit -s -S -m "message"
```

If either flag is missing, the hook blocks the command and tells Claude exactly what to add:

```
Blocked: All commits must be signed. Add -s (signoff) and -S (GPG signature) flags.
Use: git commit -s -S -m "message"
```

### prevent-push-workbench.sh

**Event:** `PreToolUse` / `Bash`

Blocks any attempt to push the `agents-workbench` branch to a remote. The hook handles two cases:

1. **Explicit branch name** — catches `git push origin agents-workbench` and similar.
2. **Implicit push while on the branch** — catches bare `git push`, `git push origin`, and `git push ... HEAD` when the current branch is `agents-workbench`.

Error output when blocked by explicit branch name:

```
BLOCKED: agents-workbench is a local-only branch and must NEVER be pushed to any remote.
This branch is the local coordination hub. Only feature branches from worktrees should be pushed.
```

Error output when blocked by implicit push while on the branch:

```
BLOCKED: You are on agents-workbench. This branch must NEVER be pushed.
Switch to a worktree to push feature branches:
  cd .worktrees/<name> && git push -u origin <branch>
```

### enforce-worktree.sh

**Event:** `PreToolUse` / `Write` and `Edit`

When the current branch is `agents-workbench`, this hook blocks writes to source code files. Only agent coordination files are writable on this branch:

| Allowed path | Purpose |
|-------------|---------|
| `AGENTS.md` | Top-level agent coordination document |
| `.agents/*` | Agent plans, task definitions |
| `.worktrees/*` | Worktree-scoped files |
| `docs/plans/*` | Planning documents |
| `CLAUDE.md` | Engineering standards |
| `.cursor/rules/*`, `.cursor/AGENTS.md` | Cursor IDE configuration |
| `.gitignore`, `.cursorrules`, `.claudeignore` | Ignore files |

On any other branch (including worktrees), all writes are permitted. The hook does nothing when not in a git repository.

When blocked, the error message includes the exact commands needed to create a worktree:

```
BLOCKED: Source code is READ-ONLY on agents-workbench.
File: src/mypackage/handler.go

This branch is the coordination hub. Implementation happens in worktrees.
Create a worktree (ALWAYS from remote ref, never local):
  git fetch upstream 2>/dev/null && BASE="upstream/main" || { git fetch origin && BASE="origin/main"; }
  git worktree add .worktrees/<name> -b <branch-name> "$BASE"

Allowed files on agents-workbench:
  AGENTS.md, .agents/*, .worktrees/*, docs/plans/*, CLAUDE.md, .cursor/rules/*, .gitignore
```

### tdd-guard.sh

**Event:** `PreToolUse` / `Write` and `Edit`

Enforces the TDD Red-before-Green constraint. When Claude attempts to write or edit an implementation file, this hook checks whether the TDD cycle is active. If not, the write is blocked.

**Always allowed (no check):**

- Test files: `*_test.go`, `*_test.*`, `*.test.*`, `*.spec.*`, `test_*.py`, files under `tests/`, `test/`, `__tests__/`
- Configuration and documentation: `.json`, `.yaml`, `.md`, `.toml`, `.cfg`, `.sh`, `Makefile`, `Dockerfile`, `.proto`, `.tf`, and many others
- Coordination files: `CLAUDE.md`, `AGENTS.md`, `.agents/*`, `docs/*`

**For implementation files, two checks run in order:**

1. **Active TDD cycle check** — If any test file has been modified (staged or unstaged) in the current git session, the TDD cycle is considered active and the write is allowed.
2. **Test file existence check** — If no test file has been modified, the hook looks for a corresponding test file on disk at standard locations (`<name>_test.<ext>`, `<name>.test.<ext>`, `tests/<name>_test.<ext>`, etc.). If found, the write is allowed (the tests exist, even if not recently modified). If no test file exists at all, the write is blocked.

The hook also allows writes during git merge, cherry-pick, revert, and rebase operations, since those involve integration work rather than new implementation.

**Escape hatch** for hotfixes and generated code:

```bash
SKIP_TDD_GUARD=1 # set in environment before the write
```

When blocked:

```
TDD GUARD: No test file found for implementation file.
File: src/mypackage/handler.go

Write the failing test FIRST (Red phase), then implement.
Expected test file locations:
  src/mypackage/handler_test.go
  src/mypackage/handler.test.go
  src/mypackage/tests/handler_test.go
```

### validate-year.sh

**Event:** `PreToolUse` / `Write` (new files only)

A second line of defense against stale copyright years, operating at write time. Where `inject-date.sh` provides a proactive rule in context, `validate-year.sh` is a reactive check that inspects the content of a file before it is created.

The hook only runs on **new files** — if the file path already exists on disk, the hook exits immediately. Existing files may legitimately have older years in their copyright history.

For new files, the hook scans content for copyright indicator lines matching:

- `Copyright YYYY`
- `SPDX-FileCopyrightText: YYYY`
- `(c) YYYY` / `(C) YYYY` / `© YYYY`

If a matched line contains a four-digit year that is not the current year, the write is blocked. Year ranges are valid as long as the current year appears somewhere in the range (e.g., `2020-2026` passes when the current year is 2026).

Example error:

```
BLOCKED: New file has copyright/license header with year <STALE_YEAR> instead of 2026.
File: src/mypackage/handler.go

Fix: Replace <STALE_YEAR> with 2026 (or use a range ending in 2026, e.g., <STALE_YEAR>-2026).
```

---

## Plugins

Five plugins from the official Claude plugins registry are enabled. Plugin metadata is stored in `.claude/plugins/installed_plugins.json`.

### code-review

**Version:** `ca6eb4c4bd53` | **Registry:** `claude-plugins-official`

Provides automated code review suggestions and a `code-reviewer` agent. Use it to get structured feedback on diffs, pull requests, or individual files — covering correctness, security, readability, and adherence to project conventions.

### code-simplifier

**Version:** `1.0.0` | **Registry:** `claude-plugins-official`

Analyzes code and suggests targeted simplifications: reducing nesting, eliminating dead code, clarifying variable names, collapsing unnecessarily complex control flow. Useful in the Refactor phase of TDD after tests are green.

### superpowers

**Version:** `5.1.0` | **Registry:** `claude-plugins-official`

The primary workflow engine for this configuration. `superpowers` provides the skills that drive the engineering standards defined in `CLAUDE.md`:

| Skill | Purpose |
|-------|---------|
| `superpowers:brainstorming` | Structured brainstorm with ≥3 options and decision documentation |
| TDD enforcement | Plan, Red, Green, Refactor phase management |
| Plan writing and execution | Structured design documents, `.agents/plans/` |
| Git worktrees | Worktree creation, branch management, parallel agent dispatch |
| Parallel agent dispatch | Coordinate agent teams, each in an isolated worktree |
| Code review | Supplemental review skill (complements the code-review plugin) |
| Skill authoring | Create and register new skills |
| Debugging | Structured root-cause analysis workflows |

`superpowers` is the largest and most important plugin in this setup. Most of the engineering standard workflows (brainstorm, TDD cycle phases, verification-before-completion) are driven by skills it provides.

### gopls-lsp

**Version:** `1.0.0` | **Registry:** `claude-plugins-official`

Integrates the [gopls](https://pkg.go.dev/golang.org/x/tools/gopls) Go language server into Claude Code sessions, providing Go-aware completions, type information, symbol navigation, and diagnostics. Particularly useful when navigating large Go codebases or when Claude needs accurate type resolution before writing implementation code.

### clangd-lsp

**Version:** `1.0.0` | **Registry:** `claude-plugins-official`

Integrates the [clangd](https://clangd.llvm.org/) language server for C and C++ into Claude Code sessions, providing completions, type information, symbol navigation, and diagnostics for C/C++ sources. Useful when working in mixed Go/C or container-runtime codebases where Claude needs accurate C/C++ symbol resolution before writing implementation code.

---

## Policy and Ignore

### policy-limits.json

Disables two features at the policy level:

```json
{
  "restrictions": {
    "allow_product_feedback": { "allowed": false },
    "allow_remote_sessions":  { "allowed": false }
  }
}
```

- `allow_product_feedback: false` — Suppresses prompts asking for product feedback during sessions.
- `allow_remote_sessions: false` — Disables the remote session functionality (Claude Code's ability to be accessed as a remote agent). Sessions are local-only.

### .claudeignore

Controls which files and directories Claude Code reads into its context window. Keeping large, irrelevant files out of context improves response quality and reduces token consumption.

**Excluded categories:**

| Category | Patterns |
|----------|---------|
| Dependencies | `node_modules/`, `vendor/`, `.venv/`, `__pycache__/`, `*.pyc` |
| Build artifacts | `dist/`, `build/`, `bin/`, `*.exe`, `*.dll`, `*.so`, `*.dylib` |
| Large data files | `*.log`, `*.sql`, `*.csv`, `*.parquet`, `*.zip`, `*.tar`, `*.gz`, `*.jar`, `*.whl` |
| IDE metadata | `.idea/`, `.vscode/`, `*.swp`, `*.swo` |
| Cache directories | `.cache/`, `*.cache`, `.pytest_cache/`, `.mypy_cache/` |
| Git internals | `.git/objects/` |
| Media files | `*.mp4`, `*.mov`, `*.png`, `*.jpg`, `*.jpeg`, `*.gif`, `*.pdf` |

Note: `.git/objects/` is excluded specifically to avoid loading pack-file history from large repositories into context.

### remote-settings.json

Applied in sandboxed or remote execution environments. It overrides permissions to be more conservative and restricts network access to a defined allowlist.

**Permission overrides:**

In remote/sandbox mode, all Bash commands, file deletions, and web fetches require explicit user confirmation before proceeding:

```json
"permissions": {
  "ask": ["Bash(rm:*)", "Bash", "WebFetch"]
}
```

**Network restrictions:**

```json
"sandbox": {
  "network": {
    "allowedDomains": [
      "github.com",
      "*.github.com",
      "*.gitlab.example.com",
      "gitlab.example.com"
    ],
    "allowManagedDomainsOnly": true
  }
}
```

`allowManagedDomainsOnly: true` means all network requests are blocked by default; only domains in `allowedDomains` are reachable. This is the network policy when running Claude Code in a sandboxed CI or remote session context.
