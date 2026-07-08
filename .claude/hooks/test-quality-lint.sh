#!/bin/bash
# test-quality-lint.sh - Detect theater test patterns at write-time
# Hook: PostToolUse (matcher: Write|Edit)
#
# Checks test files for:
#   - Tautological assertions (expect(true), assert.Equal(t, x, x))
#   - Zero-assertion test functions
#   - Tests that don't reference any symbol from the package under test
#
# Exit 0 = allow (not a test file, or test passes quality check)
# Exit 2 = block (theater test detected)

set -o pipefail

INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // .tool_input.path // empty')
[ -z "$FILE_PATH" ] && exit 0
[ ! -f "$FILE_PATH" ] && exit 0

# Only check test files
IS_TEST=false
case "$FILE_PATH" in
    *_test.go)          IS_TEST=true ;;
    *.test.ts|*.test.tsx|*.test.js|*.test.jsx) IS_TEST=true ;;
    *.spec.ts|*.spec.tsx|*.spec.js|*.spec.jsx) IS_TEST=true ;;
    */test_*.py)        IS_TEST=true ;;
    test_*.py)          IS_TEST=true ;;
esac
[ "$IS_TEST" = false ] && exit 0

ISSUES=""

# --- Go test checks ---
if [[ "$FILE_PATH" == *_test.go ]]; then

    # Tautological assertions
    if grep -n 'assert\.Equal(t, *\([^,]*\), *\1)' "$FILE_PATH" 2>/dev/null; then
        ISSUES="${ISSUES}\n  - Tautological assertion: assert.Equal(t, x, x) — comparing value to itself"
    fi
    if grep -nE '(assert\.True\(t,\s*true\)|assert\.False\(t,\s*false\))' "$FILE_PATH" 2>/dev/null; then
        ISSUES="${ISSUES}\n  - Tautological assertion: assert.True(t, true) or assert.False(t, false)"
    fi

    # Index-based access into list-returning APIs — assumes a stable order the
    # API doesn't guarantee (K8s .Items[N], slice[0] from a Range/List call).
    # Tests that pass on the writer's machine and break under reordering.
    if grep -nE '\.Items\[[0-9]+\]' "$FILE_PATH" 2>/dev/null; then
        ISSUES="${ISSUES}\n  - Index-based access into .Items[N]: list order is not guaranteed. Use a map keyed by Name/UID, or sort before comparison (testify ElementsMatch for sets)."
    fi

    # Test functions with no assertions (only t.Log, t.Logf, or empty)
    # Extract test function bodies and check for assert/require calls
    FUNCS=$(grep -n '^func Test' "$FILE_PATH" | sed 's/(.*//' | awk -F: '{print $1 ":" $2}')
    while IFS=: read -r line_num func_name; do
        [ -z "$line_num" ] && continue
        func_name=$(echo "$func_name" | xargs)
        # Get the function body (next 50 lines or until next func)
        BODY=$(sed -n "${line_num},$((line_num + 50))p" "$FILE_PATH" | head -50)
        # Check if body has any assertion
        if ! echo "$BODY" | grep -qE '(assert\.|require\.|\.Error\(|\.NoError\(|\.Nil\(|\.NotNil\(|\.Contains\(|\.Equal\(|\.True\(|\.False\(|if .* != |if .* == |t\.Fatal|t\.Errorf)'; then
            ISSUES="${ISSUES}\n  - ${func_name} (line ${line_num}): No assertions found. t.Log() is not a test."
        fi
    done <<< "$FUNCS"

    # Tests that don't call any function (only setup, no exercise)
    # Check if test file imports the package it's supposed to test
    PKG_DIR=$(dirname "$FILE_PATH")
    SRC_FILES=$(find "$PKG_DIR" -maxdepth 1 -name '*.go' ! -name '*_test.go' 2>/dev/null)
    if [ -n "$SRC_FILES" ]; then
        # Extract exported symbols from source files
        SYMBOLS=$(grep -ohE '^func ([A-Z][a-zA-Z0-9]*)' $SRC_FILES 2>/dev/null | awk '{print $2}' | sort -u)
        SYMBOLS="$SYMBOLS $(grep -ohE '^type ([A-Z][a-zA-Z0-9]*)' $SRC_FILES 2>/dev/null | awk '{print $2}' | sort -u)"
        if [ -n "$SYMBOLS" ]; then
            FOUND_REF=false
            for sym in $SYMBOLS; do
                if grep -q "$sym" "$FILE_PATH" 2>/dev/null; then
                    FOUND_REF=true
                    break
                fi
            done
            if [ "$FOUND_REF" = false ]; then
                ISSUES="${ISSUES}\n  - Test file doesn't reference any exported symbol from the package under test"
            fi
        fi
    fi
fi

# --- TS/JS test checks ---
if [[ "$FILE_PATH" == *.test.* ]] || [[ "$FILE_PATH" == *.spec.* ]]; then
    case "$FILE_PATH" in
        *.ts|*.tsx|*.js|*.jsx)

            # Tautological assertions
            if grep -nE 'expect\(true\)\.toBe\(true\)' "$FILE_PATH" 2>/dev/null; then
                ISSUES="${ISSUES}\n  - Tautological assertion: expect(true).toBe(true)"
            fi
            if grep -nE 'expect\(false\)\.toBe\(false\)' "$FILE_PATH" 2>/dev/null; then
                ISSUES="${ISSUES}\n  - Tautological assertion: expect(false).toBe(false)"
            fi
            if grep -nE 'expect\(1\)\.toBe\(1\)' "$FILE_PATH" 2>/dev/null; then
                ISSUES="${ISSUES}\n  - Tautological assertion: expect(1).toBe(1)"
            fi
            if grep -n 'expect(\([^)]*\))\.toBe(\1)' "$FILE_PATH" 2>/dev/null; then
                ISSUES="${ISSUES}\n  - Tautological assertion: expect(x).toBe(x) — comparing value to itself"
            fi

            # Test blocks with no expect/assert
            # Find it/test blocks and check for assertions
            BLOCKS=$(grep -n '^\s*\(it\|test\)(' "$FILE_PATH" 2>/dev/null | head -30)
            while IFS= read -r block_line; do
                [ -z "$block_line" ] && continue
                LNUM=$(echo "$block_line" | cut -d: -f1)
                LABEL=$(echo "$block_line" | sed "s/^[0-9]*://" | head -c 80)
                # Check next 60 lines for assertions (window covers realistic integration-style setups)
                BODY=$(sed -n "${LNUM},$((LNUM + 60))p" "$FILE_PATH" | head -60)
                if ! echo "$BODY" | grep -qE '(expect\(|assert\.|\.toBe|\.toEqual|\.toThrow|\.toHaveBeenCalled|\.rejects|\.resolves|\.toContain|\.toMatch|\.toHaveLength)'; then
                    ISSUES="${ISSUES}\n  - line ${LNUM}: ${LABEL} — no assertions found in test block"
                fi
            done <<< "$BLOCKS"

            # Test file that doesn't import the module under test.
            # Allowed exception: CLI integration tests that exec the compiled
            # binary via execFileSync/spawnSync/spawn pointing into dist/ —
            # they don't import source units; they run the assembled output.
            SRC_NAME=$(basename "$FILE_PATH" | sed -E 's/\.(test|spec)\./\./')
            SRC_MODULE=$(echo "$SRC_NAME" | sed 's/\.[^.]*$//')
            if ! grep -qE "from ['\"].*${SRC_MODULE}(\.m?[jt]sx?)?['\"]" "$FILE_PATH" 2>/dev/null; then
                if ! grep -qE "require\(['\"].*${SRC_MODULE}(\.m?[jt]sx?)?['\"]\)" "$FILE_PATH" 2>/dev/null; then
                    if ! grep -qE "(execFileSync|spawnSync|spawn|execSync)\b[^)]*dist/" "$FILE_PATH" 2>/dev/null; then
                        ISSUES="${ISSUES}\n  - Test file doesn't import the module under test (${SRC_MODULE})"
                    fi
                fi
            fi
            ;;
    esac
fi

# --- Report ---
if [ -n "$ISSUES" ]; then
    echo "TEST QUALITY LINT: Theater test patterns detected in $(basename "$FILE_PATH")" >&2
    echo "" >&2
    echo -e "Issues:$ISSUES" >&2
    echo "" >&2
    echo "Every test MUST:" >&2
    echo "  1. Call the code under test" >&2
    echo "  2. Assert a meaningful property of the result" >&2
    echo "  3. Fail when the implementation is broken" >&2
    echo "" >&2
    echo "Fix these issues before proceeding." >&2
    exit 2
fi

exit 0
