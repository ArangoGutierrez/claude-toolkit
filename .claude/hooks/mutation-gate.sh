#!/bin/bash
# mutation-gate.sh - Incremental mutation testing on changed files
# Usage: mutation-gate.sh [--threshold N]
#
# Runs mutation testing ONLY on packages/modules with changes.
# If surviving mutant rate exceeds threshold, exits non-zero.
#
# Designed to be called:
#   - Manually between Green and Refactor phases
#   - By QA validator in team workflows
#   - By tdd-protocol skill as a quality gate
#
# Exit 0 = mutation score acceptable
# Exit 1 = mutation score too low (theater tests detected)
# Exit 2 = mutation tool not available (skip gracefully)

set -uo pipefail

THRESHOLD=30
if [ "${1:-}" = "--threshold" ] && [ -n "${2:-}" ]; then
    THRESHOLD="${2}"
elif [ -n "${1:-}" ] && [ "${1:-}" != "--threshold" ]; then
    THRESHOLD="${1}"
fi

GIT_ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || { echo "Not in a git repo"; exit 2; }
cd "$GIT_ROOT" || exit 2

# Find changed source files (not test files)
CHANGED=$(git diff --name-only HEAD 2>/dev/null; git diff --name-only --cached 2>/dev/null)
[ -z "$CHANGED" ] && { echo "No changed files. Nothing to mutate."; exit 0; }

# --- Go mutation testing ---
GO_PKGS=""
while IFS= read -r file; do
    case "$file" in
        *.go)
            case "$file" in *_test.go) continue ;; esac
            pkg="./$(dirname "$file")"
            GO_PKGS="$GO_PKGS $pkg"
            ;;
    esac
done <<< "$CHANGED"
GO_PKGS=$(echo "$GO_PKGS" | tr ' ' '\n' | sort -u | tr '\n' ' ')

if [ -n "$GO_PKGS" ]; then
    if command -v gremlins &>/dev/null; then
        echo "=== Go Mutation Testing (gremlins) ==="
        echo "Packages: $GO_PKGS"
        echo ""

        RESULT=$(gremlins unleash $GO_PKGS 2>&1)
        GREMLINS_EXIT=$?

        echo "$RESULT"
        echo ""

        # Parse gremlins output for survival rate
        # gremlins v0.6+ uses "Killed: N, Lived: N" format
        KILLED=$(echo "$RESULT" | grep -ioE 'killed: [0-9]+' | grep -oE '[0-9]+' | head -1)
        LIVED=$(echo "$RESULT" | grep -ioE 'lived: [0-9]+' | grep -oE '[0-9]+' | head -1)
        NOT_COVERED=$(echo "$RESULT" | grep -ioE 'not covered: [0-9]+' | grep -oE '[0-9]+' | head -1)
        # Count NOT COVERED as surviving — untested code is the same risk as weak tests
        SURVIVED=$(( ${LIVED:-0} + ${NOT_COVERED:-0} ))
        TOTAL=$((${KILLED:-0} + ${SURVIVED:-0}))

        if [ "$TOTAL" -gt 0 ]; then
            SURVIVAL_RATE=$(( (${SURVIVED:-0} * 100) / TOTAL ))
            echo "Mutation score: ${KILLED:-0}/${TOTAL} killed (${SURVIVAL_RATE}% survived)"

            if [ "$SURVIVAL_RATE" -gt "$THRESHOLD" ]; then
                echo ""
                echo "MUTATION GATE FAILED: ${SURVIVAL_RATE}% of mutants survived (threshold: ${THRESHOLD}%)"
                echo "Your tests are not catching regressions. Strengthen them before proceeding."
                exit 1
            else
                echo "MUTATION GATE PASSED: ${SURVIVAL_RATE}% survived (threshold: ${THRESHOLD}%)"
                exit 0
            fi
        else
            echo "No mutants generated. Skipping gate."
            exit 0
        fi

    elif command -v go-mutesting &>/dev/null; then
        echo "=== Go Mutation Testing (go-mutesting) ==="
        echo "Packages: $GO_PKGS"
        echo ""

        for pkg in $GO_PKGS; do
            echo "--- $pkg ---"
            go-mutesting "$pkg" 2>&1
        done
        # go-mutesting exit code indicates if mutations survived
        exit $?

    else
        echo "No Go mutation tool found. Install gremlins: go install github.com/go-gremlins/gremlins/cmd/gremlins@latest"
        echo "Skipping Go mutation gate."
    fi
fi

# --- TS/JS mutation testing ---
TS_FILES=""
while IFS= read -r file; do
    case "$file" in
        *.ts|*.tsx|*.js|*.jsx)
            case "$file" in *.test.*|*.spec.*) continue ;; esac
            TS_FILES="$TS_FILES $file"
            ;;
    esac
done <<< "$CHANGED"

if [ -n "$TS_FILES" ]; then
    if [ -f "stryker.conf.js" ] || [ -f "stryker.conf.mjs" ] || [ -f "stryker.conf.json" ]; then
        if command -v npx &>/dev/null; then
            echo "=== TS/JS Mutation Testing (Stryker) ==="
            echo "Files:$TS_FILES"
            echo ""

            # Run Stryker in incremental mode on changed files only
            MUTATE_PATTERN=$(echo "$TS_FILES" | tr ' ' '\n' | grep -v '^\s*$' | paste -sd ',' -)
            npx stryker run --mutate "$MUTATE_PATTERN" 2>&1
            STRYKER_EXIT=$?

            if [ "$STRYKER_EXIT" -ne 0 ]; then
                echo ""
                echo "MUTATION GATE FAILED: Stryker reported insufficient mutation score."
                echo "Strengthen your tests before proceeding."
                exit 1
            fi
            exit 0
        fi
    else
        echo "No Stryker config found. To enable TS/JS mutation testing:"
        echo "  npx stryker init"
        echo "Skipping TS/JS mutation gate."
    fi
fi

# If we got here with no tools found at all
if [ -z "$GO_PKGS" ] && [ -z "$TS_FILES" ]; then
    echo "No Go or TS/JS source files changed. Nothing to mutate."
    exit 0
fi

exit 0
