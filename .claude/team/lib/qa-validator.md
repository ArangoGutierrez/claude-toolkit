# QA Validator

## Overview

Language-aware validation library for QA agents in team coordination workflows. Provides automated checks for code quality, security, and compliance before PR approval.

**Key Features:**
- Automatic language detection (Go, TypeScript, Rust, Python)
- Git signature validation (required for all projects)
- Language-specific linting and testing
- Security scanning integration
- CI/CD pre-flight checks
- Approval gate with clear pass/fail signals

**Integration:** Referenced by `/team:execute` command during QA phase.

---

## Language Detection

Use this script to detect the primary language of the project:

```bash
#!/bin/bash
# Detect project language from common markers

detect_language() {
    if [ -f "go.mod" ]; then
        echo "go"
    elif [ -f "package.json" ]; then
        # Check if TypeScript
        if grep -q '"typescript"' package.json || [ -f "tsconfig.json" ]; then
            echo "typescript"
        else
            echo "node"
        fi
    elif [ -f "Cargo.toml" ]; then
        echo "rust"
    elif [ -f "setup.py" ] || [ -f "pyproject.toml" ] || [ -f "requirements.txt" ]; then
        echo "python"
    else
        echo "unknown"
    fi
}

LANGUAGE=$(detect_language)
echo "Detected language: $LANGUAGE"
```

---

## 1. Git Signature Validation (ALL PROJECTS)

**Required for all commits across all languages.**

### Check 1a: Signed-off-by Present

```bash
# Check that all commits in the branch have Signed-off-by
echo "Checking for Signed-off-by (-s flag)..."

UNSIGNED_COMMITS=$(git log origin/main..HEAD --pretty=format:"%H %s" | while read hash message; do
    if ! git log --format=%B -n 1 "$hash" | grep -q "Signed-off-by:"; then
        echo "  MISSING: $hash $message"
    fi
done)

if [ -n "$UNSIGNED_COMMITS" ]; then
    echo "❌ FAIL: Commits missing Signed-off-by:"
    echo "$UNSIGNED_COMMITS"
    echo ""
    echo "Fix: Amend commits with 'git commit --amend -s' or rebase with 'git rebase --signoff origin/main'"
    exit 1
else
    echo "✅ PASS: All commits have Signed-off-by"
fi
```

### Check 1b: GPG Signature Present

```bash
# Check that all commits in the branch are GPG signed
echo "Checking for GPG signatures (-S flag)..."

UNSIGNED_COMMITS=$(git log origin/main..HEAD --pretty=format:"%H %s" --show-signature 2>&1 | \
    grep -B1 "^commit" | grep -v "^gpg:" | grep "^commit" | awk '{print $2}')

if [ -n "$UNSIGNED_COMMITS" ]; then
    echo "❌ FAIL: Commits missing GPG signature:"
    echo "$UNSIGNED_COMMITS"
    echo ""
    echo "Fix: Amend commits with 'git commit --amend -S' or rebase with 'git rebase --exec \"git commit --amend --no-edit -S\" origin/main'"
    exit 1
else
    echo "✅ PASS: All commits are GPG signed"
fi
```

### Check 1c: Combined Signature Check

```bash
# Quick combined check (run this first)
git log origin/main..HEAD --pretty=format:"%H" | while read hash; do
    # Check Signed-off-by
    if ! git log --format=%B -n 1 "$hash" | grep -q "Signed-off-by:"; then
        echo "❌ Commit $hash missing Signed-off-by (-s)"
        exit 1
    fi

    # Check GPG signature
    if ! git verify-commit "$hash" 2>/dev/null; then
        echo "❌ Commit $hash missing GPG signature (-S)"
        exit 1
    fi
done

if [ $? -eq 0 ]; then
    echo "✅ All commits properly signed (-s and -S)"
fi
```

---

## 2. Go Project Validation

### Check 2a: Formatting

```bash
echo "Running gofmt..."
UNFORMATTED=$(gofmt -l .)
if [ -n "$UNFORMATTED" ]; then
    echo "❌ FAIL: Files need formatting:"
    echo "$UNFORMATTED"
    echo ""
    echo "Fix: gofmt -w ."
    exit 1
else
    echo "✅ PASS: All files formatted"
fi
```

### Check 2b: Vet

```bash
echo "Running go vet..."
if ! go vet ./...; then
    echo "❌ FAIL: go vet found issues"
    exit 1
else
    echo "✅ PASS: go vet clean"
fi
```

### Check 2c: Linting

```bash
echo "Running golangci-lint..."
if command -v golangci-lint &> /dev/null; then
    if ! golangci-lint run ./...; then
        echo "❌ FAIL: golangci-lint found issues"
        exit 1
    else
        echo "✅ PASS: golangci-lint clean"
    fi
else
    echo "⚠️  SKIP: golangci-lint not installed"
fi
```

### Check 2d: Tests

```bash
echo "Running tests..."
if ! go test -v -race -coverprofile=coverage.out ./...; then
    echo "❌ FAIL: Tests failed"
    exit 1
else
    echo "✅ PASS: All tests passed"
fi
```

### Check 2e: Coverage

```bash
echo "Checking coverage..."
COVERAGE=$(go tool cover -func=coverage.out | grep total | awk '{print $3}' | sed 's/%//')
THRESHOLD=80

if (( $(echo "$COVERAGE < $THRESHOLD" | bc -l) )); then
    echo "❌ FAIL: Coverage ${COVERAGE}% below threshold ${THRESHOLD}%"
    exit 1
else
    echo "✅ PASS: Coverage ${COVERAGE}% meets threshold"
fi
```

### Check 2f: Security Scan

```bash
echo "Running security scans..."

# govulncheck
if command -v govulncheck &> /dev/null; then
    if ! govulncheck ./...; then
        echo "❌ FAIL: govulncheck found vulnerabilities"
        exit 1
    else
        echo "✅ PASS: No vulnerabilities (govulncheck)"
    fi
else
    echo "⚠️  SKIP: govulncheck not installed"
fi

# gosec
if command -v gosec &> /dev/null; then
    if ! gosec -quiet ./...; then
        echo "❌ FAIL: gosec found security issues"
        exit 1
    else
        echo "✅ PASS: No security issues (gosec)"
    fi
else
    echo "⚠️  SKIP: gosec not installed"
fi
```

### Go Complete Validation Script

```bash
#!/bin/bash
set -e

echo "=== Go Project Validation ==="
echo ""

# 1. Format
echo "→ Checking format..."
gofmt -l . | grep . && echo "❌ Run: gofmt -w ." && exit 1
echo "✅ Format OK"

# 2. Vet
echo "→ Running go vet..."
go vet ./... || exit 1
echo "✅ Vet OK"

# 3. Lint
if command -v golangci-lint &> /dev/null; then
    echo "→ Running golangci-lint..."
    golangci-lint run ./... || exit 1
    echo "✅ Lint OK"
fi

# 4. Test
echo "→ Running tests..."
go test -v -race -coverprofile=coverage.out ./... || exit 1
echo "✅ Tests OK"

# 5. Coverage
COVERAGE=$(go tool cover -func=coverage.out | grep total | awk '{print $3}' | sed 's/%//')
echo "→ Coverage: ${COVERAGE}%"
if (( $(echo "$COVERAGE < 80" | bc -l) )); then
    echo "❌ Coverage below 80%"
    exit 1
fi
echo "✅ Coverage OK"

# 6. Security
if command -v govulncheck &> /dev/null; then
    echo "→ Running govulncheck..."
    govulncheck ./... || exit 1
    echo "✅ No vulnerabilities"
fi

if command -v gosec &> /dev/null; then
    echo "→ Running gosec..."
    gosec -quiet ./... || exit 1
    echo "✅ No security issues"
fi

echo ""
echo "🎉 All Go validation checks passed!"
```

---

## 3. TypeScript/Node Project Validation

### Check 3a: Linting

```bash
echo "Running ESLint..."
if [ -f "package.json" ] && grep -q '"lint"' package.json; then
    if ! npm run lint; then
        echo "❌ FAIL: ESLint found issues"
        exit 1
    else
        echo "✅ PASS: ESLint clean"
    fi
else
    echo "⚠️  SKIP: No lint script found"
fi
```

### Check 3b: Type Checking

```bash
echo "Running TypeScript compiler..."
if [ -f "tsconfig.json" ]; then
    if ! npx tsc --noEmit; then
        echo "❌ FAIL: TypeScript errors found"
        exit 1
    else
        echo "✅ PASS: No type errors"
    fi
else
    echo "⚠️  SKIP: Not a TypeScript project"
fi
```

### Check 3c: Tests

```bash
echo "Running tests..."
if grep -q '"test"' package.json; then
    if ! npm test; then
        echo "❌ FAIL: Tests failed"
        exit 1
    else
        echo "✅ PASS: All tests passed"
    fi
else
    echo "⚠️  SKIP: No test script found"
fi
```

### Check 3d: Security Audit

```bash
echo "Running npm audit..."
if ! npm audit --audit-level=moderate; then
    echo "❌ FAIL: Security vulnerabilities found"
    echo "Fix: npm audit fix"
    exit 1
else
    echo "✅ PASS: No security vulnerabilities"
fi
```

### TypeScript Complete Validation Script

```bash
#!/bin/bash
set -e

echo "=== TypeScript/Node Project Validation ==="
echo ""

# 1. Install dependencies
echo "→ Installing dependencies..."
npm ci --quiet || npm install --quiet

# 2. Lint
if grep -q '"lint"' package.json; then
    echo "→ Running lint..."
    npm run lint || exit 1
    echo "✅ Lint OK"
fi

# 3. Type check
if [ -f "tsconfig.json" ]; then
    echo "→ Type checking..."
    npx tsc --noEmit || exit 1
    echo "✅ Types OK"
fi

# 4. Test
if grep -q '"test"' package.json; then
    echo "→ Running tests..."
    npm test || exit 1
    echo "✅ Tests OK"
fi

# 5. Security
echo "→ Running security audit..."
npm audit --audit-level=moderate || exit 1
echo "✅ No vulnerabilities"

echo ""
echo "🎉 All TypeScript validation checks passed!"
```

---

## 4. Rust Project Validation

### Check 4a: Formatting

```bash
echo "Running rustfmt..."
if ! cargo fmt -- --check; then
    echo "❌ FAIL: Code needs formatting"
    echo "Fix: cargo fmt"
    exit 1
else
    echo "✅ PASS: Code formatted"
fi
```

### Check 4b: Clippy

```bash
echo "Running clippy..."
if ! cargo clippy -- -D warnings; then
    echo "❌ FAIL: Clippy found issues"
    exit 1
else
    echo "✅ PASS: Clippy clean"
fi
```

### Check 4c: Tests

```bash
echo "Running tests..."
if ! cargo test; then
    echo "❌ FAIL: Tests failed"
    exit 1
else
    echo "✅ PASS: All tests passed"
fi
```

### Check 4d: Security Audit

```bash
echo "Running cargo-audit..."
if command -v cargo-audit &> /dev/null; then
    if ! cargo audit; then
        echo "❌ FAIL: Security vulnerabilities found"
        exit 1
    else
        echo "✅ PASS: No vulnerabilities"
    fi
else
    echo "⚠️  SKIP: cargo-audit not installed"
fi
```

### Rust Complete Validation Script

```bash
#!/bin/bash
set -e

echo "=== Rust Project Validation ==="
echo ""

# 1. Format check
echo "→ Checking format..."
cargo fmt -- --check || (echo "❌ Run: cargo fmt" && exit 1)
echo "✅ Format OK"

# 2. Clippy
echo "→ Running clippy..."
cargo clippy -- -D warnings || exit 1
echo "✅ Clippy OK"

# 3. Test
echo "→ Running tests..."
cargo test || exit 1
echo "✅ Tests OK"

# 4. Security
if command -v cargo-audit &> /dev/null; then
    echo "→ Running security audit..."
    cargo audit || exit 1
    echo "✅ No vulnerabilities"
fi

echo ""
echo "🎉 All Rust validation checks passed!"
```

---

## 5. Python Project Validation

### Check 5a: Formatting

```bash
echo "Running black..."
if command -v black &> /dev/null; then
    if ! black --check .; then
        echo "❌ FAIL: Code needs formatting"
        echo "Fix: black ."
        exit 1
    else
        echo "✅ PASS: Code formatted"
    fi
else
    echo "⚠️  SKIP: black not installed"
fi
```

### Check 5b: Linting

```bash
echo "Running flake8..."
if command -v flake8 &> /dev/null; then
    if ! flake8 .; then
        echo "❌ FAIL: Linting issues found"
        exit 1
    else
        echo "✅ PASS: Linting clean"
    fi
else
    echo "⚠️  SKIP: flake8 not installed"
fi
```

### Check 5c: Type Checking

```bash
echo "Running mypy..."
if command -v mypy &> /dev/null; then
    if ! mypy .; then
        echo "❌ FAIL: Type errors found"
        exit 1
    else
        echo "✅ PASS: No type errors"
    fi
else
    echo "⚠️  SKIP: mypy not installed"
fi
```

### Check 5d: Tests

```bash
echo "Running pytest..."
if command -v pytest &> /dev/null; then
    if ! pytest; then
        echo "❌ FAIL: Tests failed"
        exit 1
    else
        echo "✅ PASS: All tests passed"
    fi
else
    echo "⚠️  SKIP: pytest not installed"
fi
```

### Check 5e: Security

```bash
echo "Running safety..."
if command -v safety &> /dev/null; then
    if ! safety check; then
        echo "❌ FAIL: Security vulnerabilities found"
        exit 1
    else
        echo "✅ PASS: No vulnerabilities"
    fi
else
    echo "⚠️  SKIP: safety not installed"
fi
```

### Python Complete Validation Script

```bash
#!/bin/bash
set -e

echo "=== Python Project Validation ==="
echo ""

# 1. Format check
if command -v black &> /dev/null; then
    echo "→ Checking format..."
    black --check . || (echo "❌ Run: black ." && exit 1)
    echo "✅ Format OK"
fi

# 2. Lint
if command -v flake8 &> /dev/null; then
    echo "→ Running flake8..."
    flake8 . || exit 1
    echo "✅ Lint OK"
fi

# 3. Type check
if command -v mypy &> /dev/null; then
    echo "→ Running mypy..."
    mypy . || exit 1
    echo "✅ Types OK"
fi

# 4. Test
if command -v pytest &> /dev/null; then
    echo "→ Running tests..."
    pytest || exit 1
    echo "✅ Tests OK"
fi

# 5. Security
if command -v safety &> /dev/null; then
    echo "→ Running security check..."
    safety check || exit 1
    echo "✅ No vulnerabilities"
fi

echo ""
echo "🎉 All Python validation checks passed!"
```

---

## 6. CI/CD Pre-flight Checks

Check if CI/CD configuration exists and is valid before creating PR.

### GitHub Actions

```bash
echo "Checking GitHub Actions..."
if [ -d ".github/workflows" ]; then
    echo "→ Found GitHub Actions workflows:"
    ls -1 .github/workflows/*.yml .github/workflows/*.yaml 2>/dev/null || true

    # Validate YAML syntax
    for file in .github/workflows/*.{yml,yaml}; do
        [ -f "$file" ] || continue
        if command -v yamllint &> /dev/null; then
            if ! yamllint "$file"; then
                echo "❌ FAIL: Invalid YAML in $file"
                exit 1
            fi
        fi
    done
    echo "✅ GitHub Actions configuration valid"
else
    echo "⚠️  No GitHub Actions workflows found"
fi
```

### GitLab CI

```bash
echo "Checking GitLab CI..."
if [ -f ".gitlab-ci.yml" ]; then
    echo "→ Found GitLab CI configuration"

    if command -v yamllint &> /dev/null; then
        if ! yamllint .gitlab-ci.yml; then
            echo "❌ FAIL: Invalid .gitlab-ci.yml"
            exit 1
        fi
    fi
    echo "✅ GitLab CI configuration valid"
else
    echo "⚠️  No GitLab CI configuration found"
fi
```

### Jenkins

```bash
echo "Checking Jenkins..."
if [ -f "Jenkinsfile" ]; then
    echo "→ Found Jenkinsfile"
    echo "✅ Jenkins configuration present"
else
    echo "⚠️  No Jenkinsfile found"
fi
```

---

## 6b. Draft PR State Verification

**Before running CI replication (Section 7), QA MUST verify the PR is in draft state.**

### Check: PR is Draft

```bash
echo "=== Verifying PR Draft State ==="

PR_URL="<PR-URL>"

IS_DRAFT=$(gh pr view "$PR_URL" --json isDraft -q '.isDraft')

if [ "$IS_DRAFT" = "true" ]; then
    echo "✅ PR is in draft state — proceeding with validation"
else
    echo "❌ VIOLATION: PR is NOT a draft!"
    echo "Workers MUST create PRs with 'gh pr create --draft'"
    echo "Only QA can promote a draft PR to ready-for-review"
    echo ""
    echo "Action: Report this violation to Team Lead. Halt validation."
    exit 1
fi
```

**If the PR is not a draft, QA MUST:**
1. Report the violation to Team Lead immediately
2. Halt all validation — do NOT proceed to Sections 7-10
3. The Worker must explain why they created a non-draft PR

---

## Usage in /team:execute

The QA agent should run the appropriate validation script based on detected language:

```bash
# 1. Detect language
LANGUAGE=$(detect_language)

# 2. ALWAYS run git signature validation (required for all projects)
validate_git_signatures || exit 1

# 3. Run language-specific validation
case "$LANGUAGE" in
    go)
        validate_go_project || exit 1
        ;;
    typescript|node)
        validate_typescript_project || exit 1
        ;;
    rust)
        validate_rust_project || exit 1
        ;;
    python)
        validate_python_project || exit 1
        ;;
    *)
        echo "⚠️  Unknown language, skipping language-specific validation"
        ;;
esac

# 4. Run CI/CD checks
validate_cicd_config || exit 1

echo ""
echo "✅ All QA validation checks passed"
echo "Ready for PR approval"
```

---

## 7. CI Pipeline Replication (ALL PROJECTS)

**This is the most critical validation step.** The QA agent MUST replicate what the project's actual CI pipeline runs, not just the generic language checks above.

### Why

Generic checks (sections 2-5) may not match what CI actually runs. Projects use custom build scripts, specific tool versions, Makefile targets, monorepo task runners (turbo, nx), and CI-specific gates (coverage thresholds, type checking). If QA doesn't run the same commands CI runs, PRs will fail on GitHub.

### Step 7a: Discover CI Configuration

```bash
# Find CI configuration files
echo "=== Discovering CI Pipeline ==="

if [ -d ".github/workflows" ]; then
    echo "Found GitHub Actions workflows:"
    ls -1 .github/workflows/*.yml .github/workflows/*.yaml 2>/dev/null
    CI_TYPE="github-actions"
elif [ -f ".gitlab-ci.yml" ]; then
    echo "Found GitLab CI"
    CI_TYPE="gitlab"
elif [ -f "Jenkinsfile" ]; then
    echo "Found Jenkinsfile"
    CI_TYPE="jenkins"
else
    echo "⚠️  No CI configuration found — skip CI replication"
    CI_TYPE="none"
fi
```

### Step 7b: Extract and Run CI Commands

**For GitHub Actions:** Read each workflow YAML file. For every `run:` step in every job, extract the command and run it locally in the worktree directory.

**The QA agent MUST:**

1. **Read every workflow file** in `.github/workflows/`
2. **Identify all `run:` steps** in all jobs (including matrix builds)
3. **Run each command** in the worktree directory, in the order CI would run them
4. **Pay special attention to:**
   - Package manager commands (`pnpm`, `npm`, `yarn`, `go`, `cargo`, `pip`)
   - Type checking commands (`tsc --noEmit`, `pnpm turbo check-types`, `mypy`, etc.)
   - Lint commands that CI uses (may differ from generic linters in sections 2-5)
   - Build commands (`pnpm build`, `go build`, `cargo build`, `make`, etc.)
   - Test commands with specific flags (coverage thresholds, race detection, etc.)
5. **Skip non-replicable steps** like: Docker image pulls, deployment steps, cache setup, artifact upload/download, checkout actions. Focus on the `run:` commands that do actual validation.

**Example — extracting from a GitHub Actions workflow:**

```yaml
# If CI has this:
jobs:
  ci:
    steps:
      - run: pnpm install --frozen-lockfile
      - run: pnpm turbo check-types
      - run: pnpm turbo lint
      - run: pnpm turbo build
      - run: pnpm turbo test -- --coverage
```

**Then QA MUST run all of these locally:**

```bash
pnpm install --frozen-lockfile
pnpm turbo check-types    # <-- This was being missed!
pnpm turbo lint
pnpm turbo build
pnpm turbo test -- --coverage
```

**For Go projects with Makefile-driven CI:**

```bash
# If CI runs:
#   make lint
#   make test
#   make build
# Then QA MUST run:
make lint
make test
make build

# If CI runs raw commands:
#   golangci-lint run ./...
#   go test -race -coverprofile=coverage.out ./...
#   go build ./...
# Then QA MUST run those exact commands
```

### Step 7c: Verify CI-Specific Gates

Some CI pipelines enforce gates not covered by generic language checks:

- **Coverage thresholds:** Check if CI enforces a minimum coverage percentage
- **Type checking:** CI may run type checks as a separate step (e.g., `check-types` in turbo)
- **Custom linting:** CI may run project-specific linters or custom scripts
- **Build verification:** CI may require a clean build with zero warnings

**QA MUST identify and enforce ALL gates the CI enforces.**

---

## 8. PR Metadata Validation

Check that the PR has all required metadata before declaring PASS.

### Step 8a: Read Project Requirements

```bash
# Check AGENTS.md for PR requirements
if [ -f "AGENTS.md" ]; then
    echo "Checking AGENTS.md for PR requirements..."
    # Look for milestone, label, and reviewer requirements
fi
```

### Step 8b: Verify PR Metadata

**After the PR is created, QA MUST check:**

```bash
# Get PR details
PR_JSON=$(gh pr view --json milestone,labels,reviewRequests,title,body)

# Check milestone
MILESTONE=$(echo "$PR_JSON" | jq -r '.milestone.title // empty')
if [ -z "$MILESTONE" ]; then
    echo "❌ FAIL: PR has no milestone set"
    echo "Fix: gh pr edit --milestone <milestone-name>"
fi

# Check labels
LABELS=$(echo "$PR_JSON" | jq -r '.labels[].name // empty')
if [ -z "$LABELS" ]; then
    echo "❌ FAIL: PR has no labels set"
    echo "Fix: gh pr edit --add-label <label-name>"
fi
```

**QA should verify:**

1. **Milestone is set** (if project uses milestones)
2. **Labels are applied** (at minimum: type label like `bug`, `feature`, `enhancement`)
3. **PR title follows convention** (if AGENTS.md specifies a convention)
4. **PR body is not empty** and describes what changed

**If AGENTS.md does not specify PR metadata requirements, QA should still warn (not fail) about missing milestone and labels.**

---

## 9. Post-Push CI Verification

**QA MUST NOT declare PASS based only on local validation.** After the worker pushes and creates the PR, QA must verify that CI passes on GitHub.

### Step 9a: Wait for CI to Complete

```bash
# Wait for all CI checks to complete on the PR
echo "Waiting for CI checks to complete..."
gh pr checks <PR-NUMBER> --watch

# Check exit code
if [ $? -ne 0 ]; then
    echo "❌ FAIL: CI checks failed on GitHub"
fi
```

### Step 9b: Diagnose CI Failures

If CI fails on GitHub, QA MUST investigate:

```bash
# List failed checks
echo "Failed CI checks:"
gh pr checks <PR-NUMBER> | grep -i fail

# Get the failed run ID and read logs
FAILED_RUN_ID=$(gh run list --branch <branch-name> --status failure --limit 1 --json databaseId -q '.[0].databaseId')
if [ -n "$FAILED_RUN_ID" ]; then
    echo "Reading failure logs..."
    gh run view "$FAILED_RUN_ID" --log-failed
fi
```

### Step 9c: Report Actionable Failures

QA MUST report failures with:
1. Which CI job failed
2. The specific error message from the CI log
3. Actionable fix command (not just "fix the error")

**Example failure report:**

```
❌ CI FAILED: check-types job

Error: src/utils/parser.ts(42,5): error TS2322: Type 'string' is not assignable to type 'number'.

Fix: Update the return type in src/utils/parser.ts:42 or fix the type mismatch.
```

### Step 9d: Promote Draft PR to Ready

**After ALL checks pass (Sections 1-9c), QA promotes the draft PR:**

```bash
echo "=== Promoting Draft PR to Ready ==="

PR_URL="<PR-URL>"

# Final verification that we're about to promote a draft
IS_DRAFT=$(gh pr view "$PR_URL" --json isDraft -q '.isDraft')

if [ "$IS_DRAFT" = "true" ]; then
    gh pr ready "$PR_URL"
    echo "✅ PR promoted to ready-for-review"
    echo "QA gate passed — PR is now visible for review"
else
    echo "⚠️  PR is already ready-for-review — skipping promotion"
fi
```

**QA MUST NOT promote the PR if any validation failed.** The `gh pr ready` command is the QA seal of approval.

---

## 10. External Review Monitoring & Triage

After the PR is created and CI passes (sections 1-9), the QA agent monitors for external review bot comments while the Architect performs a full code review.

### Step 10a: Monitor for External Reviews

```bash
# Wait for external bot reviews (GitHub Copilot, CodeRabbitAI, etc.)
echo "=== Monitoring for External Reviews ==="

PR_NUMBER="<PR-NUMBER>"
REPO="{owner}/{repo}"

# Check for PR reviews (approve/request changes/comment)
echo "Checking PR reviews..."
gh pr reviews "$PR_NUMBER" --json author,body,state

# Check for inline review comments from bots
echo "Checking inline review comments..."
gh api "repos/$REPO/pulls/$PR_NUMBER/comments" \
    --jq '.[] | {user: .user.login, body: .body, path: .path, line: .line, created_at: .created_at}'

# Check for general PR comments (some bots post summaries as comments)
echo "Checking PR comments..."
gh api "repos/$REPO/issues/$PR_NUMBER/comments" \
    --jq '.[] | {user: .user.login, body: .body, created_at: .created_at}'
```

**Wait up to 5 minutes** for bot reviews to appear. Most bots respond within 1-3 minutes. If no external reviews appear after 5 minutes, proceed with Architect's own review only.

**Known bot usernames to watch for:**
- `github-copilot` / `copilot` — GitHub Copilot code review
- `coderabbitai` — CodeRabbitAI
- `github-actions[bot]` — GitHub Actions status checks
- Other bots configured in the repository

### Step 10b: Collect All Review Feedback

QA collects ALL feedback into a structured format for the Architect to triage:

```
REVIEW FEEDBACK SUMMARY — PR #<NUMBER>

Source: GitHub Copilot
- [path/to/file.ts:42] "Consider using a type guard here instead of a cast"
- [path/to/file.ts:87] "This function has cyclomatic complexity of 12, consider splitting"

Source: CodeRabbitAI
- [path/to/handler.go:15] "Error return value of `Close` is not checked"
- [GENERAL] "Missing test coverage for the error handling path in ProcessOrder"

Source: Architect Review
- [path/to/service.ts:20] "This violates the repository pattern — data access should go through the repository layer"
- [path/to/types.ts:5] "Missing export for the new OrderStatus type used by other modules"
```

### Step 10c: Architect Triage Protocol

The Architect reviews ALL collected feedback and classifies each comment:

| Category | Action | When to use |
|----------|--------|-------------|
| **Address** | Worker MUST fix | Real bug, type error, security issue, missing error handling, architecture violation, test gap |
| **Ignore — false positive** | Document reason, no action | Bot misunderstands context, stylistic preference that conflicts with project conventions, bot suggests something already intentionally done differently |
| **Ignore — already handled** | Document reason, no action | Comment about something addressed elsewhere in the PR or in a related PR |
| **Discuss** | Escalate to Team Lead | Architectural disagreement that needs user input, significant design tradeoff the bot raised that wasn't considered |

**Architect MUST document the reason for every "Ignore" decision.** Format:

```
TRIAGE DECISION: Ignore (false positive)
Source: CodeRabbitAI
Comment: "Error return value of `Close` is not checked"
File: path/to/handler.go:15
Reason: This is a deferred Close() on a read-only file handle. Checking the error would add noise with no actionable recovery. Consistent with project convention per architect-patterns.md.
```

### Step 10d: Consolidated Feedback to Worker

After triage, the Architect sends the Worker a **single message** with ALL changes needed. NOT one message per comment. Format:

```
PR REVIEW FEEDBACK — PR #<NUMBER>

Changes required (X items):

1. [Address — Architect] path/to/service.ts:20
   Issue: Data access bypasses repository layer
   Fix: Move the database query to OrderRepository.findByStatus()

2. [Address — CodeRabbitAI] path/to/types.ts:5
   Issue: Missing export for OrderStatus type
   Fix: Add `export` to the OrderStatus type declaration

3. [Address — Copilot] path/to/file.ts:42
   Issue: Unsafe type cast
   Fix: Use a type guard (isOrderStatus()) instead of `as OrderStatus`

Ignored comments (documented):
- CodeRabbitAI: "Error return value of Close not checked" → false positive (deferred read-only Close, project convention)
- Copilot: "Consider extracting magic number" → false positive (value is a well-known HTTP status code, not a magic number)
```

### Step 10e: Re-validation After Fixes

After the Worker pushes fixes:

1. **QA re-runs sections 7-9** (CI pipeline replication, PR metadata, post-push CI verification)
2. **QA checks for NEW external review comments** on the fix commits:

```bash
# Check if new comments appeared after the fix push
echo "Checking for new review comments after fixes..."
LATEST_PUSH=$(git log -1 --format=%cI)

gh api "repos/$REPO/pulls/$PR_NUMBER/comments" \
    --jq ".[] | select(.created_at > \"$LATEST_PUSH\") | {user: .user.login, body: .body, path: .path}"
```

3. If new comments appear, repeat the triage cycle (Steps 10b-10e)
4. The review loop ends when:
   - Architect approves the code
   - QA re-validates CI passes
   - No unresolved external review comments remain

---

## Approval Gate

The QA agent MUST NOT approve the PR unless ALL of the following are true:

1. **Git signatures present:** ALL commits have both `-s` (Signed-off-by) and `-S` (GPG signature)
2. **Language checks passed:** All applicable linting, formatting, type checking
3. **Tests passed:** All tests pass with adequate coverage
4. **Security clean:** No vulnerabilities found in security scans
5. **CI/CD config valid:** CI/CD configuration files are valid (if present)
6. **PR verified as draft:** PR was in draft state at start of validation (Section 6b) — if it wasn't, validation was halted
7. **CI pipeline replicated locally:** ALL commands from `.github/workflows/` (or equivalent) ran successfully in the worktree (Section 7)
8. **PR metadata verified:** Milestone and labels set per project requirements (Section 8)
9. **GitHub Actions CI passed:** `gh pr checks` shows all checks green on the remote (Section 9)
10. **Architect approved:** Architect has completed full code review and triaged all external review comments (Section 10)
11. **External reviews resolved:** All "Address" items from external bots have been fixed, all "Ignore" items are documented with reasons (Section 10)

**Validation order:** Run sections 1-6 first (local checks), then section 6b (draft PR state verification), then section 7 (CI replication), then section 8 (PR metadata after PR creation), then section 9 (post-push CI verification including PR promotion via `gh pr ready`), then section 10 (external review monitoring and Architect triage). QA MUST NOT skip section 9 — local passes do NOT guarantee remote CI passes. Section 10 runs as a loop until all parties approve.

**Failure handling:**
- Report specific failures with actionable fix commands
- Block approval until issues are resolved
- Provide clear feedback to implementer agent
- For CI failures: include the exact CI log output and which job/step failed
- For review comments: include the triage decision and consolidated feedback

**Approval signal:**
```
QA VALIDATION PASSED

All checks completed successfully:
- Git signatures present (-s and -S)
- Code formatted and linted
- All tests passed (coverage: 85%)
- No security vulnerabilities
- CI/CD configuration valid
- PR verified as draft (Section 6b)
- CI pipeline replicated locally (all workflow commands passed)
- PR metadata verified (milestone: v1.2, labels: feature)
- GitHub Actions CI passed (all checks green)
- Draft PR promoted to ready-for-review
- Architect approved (full code review complete)
- External reviews resolved (3 addressed, 2 ignored with documented reasons)

Draft PR promoted to ready-for-review via `gh pr ready`.
Ready for Architect review and merge.
```

**Failure signal:**
```
QA VALIDATION FAILED

Issues found:
- CI pipeline replication: `pnpm turbo check-types` failed
- External review: 2 unresolved CodeRabbitAI comments pending Architect triage
- Architect review: 1 architecture violation not yet addressed

Cannot approve PR until issues are resolved.

Recommended actions:
1. Fix type errors flagged by check-types
2. Architect: triage pending CodeRabbitAI comments on src/handler.ts
3. Worker: move data access to repository layer per Architect feedback
4. Re-push and wait for CI + re-review

Please address issues and request re-validation.
```
