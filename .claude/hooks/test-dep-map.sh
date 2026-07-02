#!/bin/bash
# test-dep-map.sh - Generate test↔source dependency map for changed files
# Usage: test-dep-map.sh [file_path]
#   If file_path provided: show tests for that specific file
#   If no args: show tests for all changed files in current git session
#
# Outputs markdown-formatted mapping of source → test files
# Designed to be called by tdd-guard.sh and SessionStart hooks

set -uo pipefail

GIT_ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || exit 0
cd "$GIT_ROOT" || exit 0

# --- Go test mapping ---
# regex_go_tests implements the original regex-based path. Used as a fallback
# when the AST helper is disabled, missing, or fails to parse.
regex_go_tests() {
    local src_file="$1"
    local rel_path="${src_file#"$GIT_ROOT"/}"
    rel_path="${rel_path#./}"
    local dir=$(dirname "$rel_path")
    local base=$(basename "$rel_path" .go)

    # Direct companion: foo.go → foo_test.go
    local companion="${dir}/${base}_test.go"
    if [ -f "$companion" ]; then
        local test_count=$(grep -c '^func Test' "$companion" 2>/dev/null || echo 0)
        echo "  ${companion} (${test_count} tests)"
    fi

    # Other test files in the same package that may test this file
    for tf in "${dir}"/*_test.go; do
        [ -f "$tf" ] || continue
        [ "$tf" = "$companion" ] && continue
        local symbols=$(grep -oE '^func ([A-Z][a-zA-Z0-9]*)' "$rel_path" 2>/dev/null | awk '{print $2}')
        symbols="$symbols $(grep -oE '^type ([A-Z][a-zA-Z0-9]*)' "$rel_path" 2>/dev/null | awk '{print $2}')"
        for sym in $symbols; do
            if grep -q "$sym" "$tf" 2>/dev/null; then
                local test_count=$(grep -c '^func Test' "$tf" 2>/dev/null || echo 0)
                echo "  ${tf} (${test_count} tests, references ${sym})"
                break
            fi
        done
    done

    # Integration/e2e tests that reference this package
    local pkg_name=$(basename "$dir")
    for test_dir in test tests e2e test/e2e tests/e2e; do
        [ -d "$test_dir" ] || continue
        local matches=$(grep -rl "$pkg_name" "$test_dir" --include="*_test.go" 2>/dev/null)
        for tf in $matches; do
            local test_count=$(grep -c '^func Test' "$tf" 2>/dev/null || echo 0)
            echo "  ${tf} (${test_count} tests, integration)"
        done
    done
}

# find_go_tests dispatches: AST helper for accurate ranking, else regex.
# Env var TDAD_DISABLE_AST (values 1|YES|yes|true|TRUE) forces the regex path.
find_go_tests() {
    local src_file="$1"
    case "${TDAD_DISABLE_AST:-}" in
        1|YES|yes|true|TRUE)
            regex_go_tests "$src_file"
            return
            ;;
    esac
    local helper
    helper="$(dirname "$0")/bin/test-dep-map-ast"
    if [ ! -x "$helper" ]; then
        regex_go_tests "$src_file"
        return
    fi
    local out
    if ! out=$("$helper" "$src_file" 2>/dev/null); then
        regex_go_tests "$src_file"
        return
    fi
    printf '%s\n' "$out"
}

# --- TS/JS test mapping ---
find_ts_tests() {
    local src_file="$1"
    local rel_path="${src_file#"$GIT_ROOT"/}"
    rel_path="${rel_path#./}"
    local dir=$(dirname "$rel_path")
    local base=$(basename "$rel_path")
    local name="${base%.*}"
    local ext="${base##*.}"

    # Common test file locations
    for pattern in \
        "${dir}/${name}.test.${ext}" \
        "${dir}/${name}.spec.${ext}" \
        "${dir}/${name}.test.ts" \
        "${dir}/${name}.test.tsx" \
        "${dir}/${name}.spec.ts" \
        "${dir}/${name}.spec.tsx" \
        "${dir}/__tests__/${name}.test.${ext}" \
        "${dir}/__tests__/${name}.spec.${ext}" \
        "${dir}/__tests__/${name}.test.ts" \
        "${dir}/__tests__/${name}.test.tsx"; do
        if [ -f "$pattern" ]; then
            local test_count=$(grep -cE '(it|test|describe)\(' "$pattern" 2>/dev/null || echo 0)
            echo "  ${pattern} (${test_count} test blocks)"
        fi
    done

    # Check if any test file imports this module
    local module_name="./${name}"
    for test_dir in "${dir}" "${dir}/__tests__"; do
        [ -d "$test_dir" ] || continue
        for tf in "${test_dir}"/*.test.* "${test_dir}"/*.spec.*; do
            [ -f "$tf" ] || continue
            # Skip already-listed companions
            local tf_base=$(basename "$tf")
            case "$tf_base" in
                ${name}.test.*|${name}.spec.*) continue ;;
            esac
            if grep -qE "from ['\"].*/${name}['\"]" "$tf" 2>/dev/null; then
                local test_count=$(grep -cE '(it|test|describe)\(' "$tf" 2>/dev/null || echo 0)
                echo "  ${tf} (${test_count} test blocks, imports ${name})"
            fi
        done
    done
}

# --- Main ---
find_tests_for_file() {
    local file="$1"
    [ -f "$file" ] || return

    case "$file" in
        *_test.go|*.test.*|*.spec.*|test_*|*/tests/*|*/test/*|*/__tests__/*) return ;;
    esac

    local rel="${file#"$GIT_ROOT"/}"
    rel="${rel#./}"

    local results=""
    case "$file" in
        *.go)
            results=$(find_go_tests "$file")
            ;;
        *.ts|*.tsx|*.js|*.jsx)
            results=$(find_ts_tests "$file")
            ;;
    esac

    if [ -n "$results" ]; then
        echo "$rel →"
        echo "$results"
    else
        echo "$rel → NO TESTS FOUND"
    fi
}

if [ -n "${1:-}" ]; then
    # Single file mode (called by tdd-guard.sh)
    find_tests_for_file "$1"
else
    # Changed files mode (called at session start or manually)
    changed_files=$(git diff --name-only HEAD 2>/dev/null; git diff --name-only --cached 2>/dev/null)
    [ -z "$changed_files" ] && exit 0

    echo "# Test Dependency Map (changed files)"
    echo ""
    echo "$changed_files" | sort -u | while IFS= read -r file; do
        [ -f "$file" ] && find_tests_for_file "$file"
    done
fi
