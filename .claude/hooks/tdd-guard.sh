#!/bin/bash
# tdd-guard.sh - Block implementation writes when no failing test exists
# Hook: PreToolUse (matcher: Write, Edit)
#
# Enforces TDD Red-Green-Refactor: implementation files can only be
# written/edited when a test file for the same component exists and
# has been recently modified (indicating active TDD cycle).
#
# Exit 0 = allow
# Exit 2 = block (stderr becomes Claude's feedback)

set -uo pipefail

# Escape hatch for exceptional cases (hotfixes, generated code)
[ "${SKIP_TDD_GUARD:-}" = "1" ] && exit 0

INPUT=$(cat)

# Extract file path from tool input first, so git context can be resolved
# relative to the FILE rather than the parent shell's CWD. The harness CWD
# may point at a different worktree than the target file (e.g., the
# controller created a docs worktree but the implementer is editing a feature
# worktree). Without this, `git rev-parse --show-toplevel` returns the wrong
# worktree, the relative-path arithmetic breaks, and the mirror-tree lookup
# misses real test files.
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // .tool_input.path // empty')
[ -z "$FILE_PATH" ] && exit 0
FILE_DIR=$(dirname "$FILE_PATH")

# Not in a git repo? Allow.
GIT_ROOT=$(git -C "$FILE_DIR" rev-parse --show-toplevel 2>/dev/null) || exit 0

# Git mid-operation? Allow — this is integration work, not new implementation.
# Use --absolute-git-dir (git >=2.13) so sentinel paths work regardless of CWD.
GIT_DIR=$(git -C "$FILE_DIR" rev-parse --absolute-git-dir 2>/dev/null) || exit 0
for sentinel in \
    "$GIT_DIR/MERGE_HEAD" \
    "$GIT_DIR/CHERRY_PICK_HEAD" \
    "$GIT_DIR/REVERT_HEAD" \
    "$GIT_DIR/rebase-merge" \
    "$GIT_DIR/rebase-apply"; do
    [ -e "$sentinel" ] && exit 0
done

# Normalize to relative path
REL_PATH="${FILE_PATH#"$GIT_ROOT"/}"
REL_PATH="${REL_PATH#./}"

# --- Determine if this is a test file or implementation file ---

# Test file patterns (allow freely — writing tests is always OK)
case "$REL_PATH" in
    *_test.go)          exit 0 ;;
    *_test.*)           exit 0 ;;
    *.test.*)           exit 0 ;;
    *.spec.*)           exit 0 ;;
    test_*.py)          exit 0 ;;
    */test_*.py)        exit 0 ;;
    tests/*)            exit 0 ;;
    test/*)             exit 0 ;;
    */tests/*)          exit 0 ;;
    */test/*)           exit 0 ;;
    */__tests__/*)      exit 0 ;;
esac

# Non-code files (allow freely — docs, configs, plans, etc.)
case "$REL_PATH" in
    *.md)               exit 0 ;;
    *.txt)              exit 0 ;;
    *.json)             exit 0 ;;
    *.yaml|*.yml)       exit 0 ;;
    *.toml)             exit 0 ;;
    *.cfg|*.ini|*.conf) exit 0 ;;
    *.xml)              exit 0 ;;
    *.html|*.css)       exit 0 ;;
    *.sh)               exit 0 ;;
    Makefile|*/Makefile|Dockerfile|*/Dockerfile|*.dockerfile) exit 0 ;;
    *commitlint.config.*|*.commitlintrc.*) exit 0 ;;
    *next.config.*|*eslint.config.*|*.eslintrc.*) exit 0 ;;
    .gitignore|.gitattributes) exit 0 ;;
    *vitest.config.*|*vite.config.*|*rollup.config.*|*webpack.config.*) exit 0 ;;
    *tsup.config.*|*tsconfig*.json|*electron-builder.*) exit 0 ;;
    *tailwind.config.*|*postcss.config.*) exit 0 ;;
    *.prettierrc*|*prettier.config.*) exit 0 ;;
    .editorconfig|*/.editorconfig) exit 0 ;;
    .gitignore|.gitattributes|*/.gitignore|*/.gitattributes) exit 0 ;;
    .nvmrc|.node-version|.npmrc|.yarnrc|*/.nvmrc|*/.node-version) exit 0 ;;
    LICENSE|LICENSE.*|COPYING|COPYING.*|*/LICENSE|*/LICENSE.*|*/COPYING|*/COPYING.*) exit 0 ;;
    NOTICE|*/NOTICE|AUTHORS|*/AUTHORS|CONTRIBUTORS|*/CONTRIBUTORS) exit 0 ;;
    OWNERS|*/OWNERS|CODEOWNERS|*/CODEOWNERS|.github/CODEOWNERS) exit 0 ;;
    go.mod|go.sum)      exit 0 ;;
    package.json|package-lock.json) exit 0 ;;
    yarn.lock|pnpm-lock.yaml) exit 0 ;;
    requirements*.txt|Pipfile*|pyproject.toml|setup.py|setup.cfg) exit 0 ;;
    Cargo.toml|Cargo.lock) exit 0 ;;
    *.proto)            exit 0 ;;
    *.tf|*.tfvars|*.hcl) exit 0 ;;
    CLAUDE.md|AGENTS.md) exit 0 ;;
    .agents/*)          exit 0 ;;
    .worktrees/*)       exit 0 ;;
    docs/*)             exit 0 ;;
    # Demo scripts (run inside K8s pods, not library code)
    demos/*/scripts/*)  exit 0 ;;
    # CGo bridge files (buildmode=c-shared, no unit tests possible)
    */bridge/*.go)      exit 0 ;;
    */bridge/*.h|*/bridge/*.c) exit 0 ;;
    # Pure data-structure files (no logic to test)
    *config_types.go)   exit 0 ;;
    # Binary entrypoints (require full stack/K8s mocking, not unit-TDD-eligible)
    cmd/*/main.go)      exit 0 ;;
    # Database schema definitions (declarative, no logic to test)
    */schema/*.ts)      exit 0 ;;
    # Next.js error boundaries (framework convention files)
    */error.tsx)        exit 0 ;;
    # Next.js route entrypoint files (page.tsx, layout.tsx, loading.tsx, not-found.tsx)
    # These are component compositions with no unit-testable logic, analogous to cmd/*/main.go
    */page.tsx)         exit 0 ;;
    */layout.tsx)       exit 0 ;;
    */loading.tsx)      exit 0 ;;
    */not-found.tsx)    exit 0 ;;
    # Drizzle migrations (generated SQL)
    */drizzle/*.sql)    exit 0 ;;
    # Electron framework glue: main process (BrowserWindow lifecycle, IPC),
    # preload (contextBridge), and renderer mount points. These require a
    # full Electron environment to exercise; analogous to cmd/*/main.go.
    # Component-level renderer code (panels, dialogs) is NOT exempt and
    # must be TDD'd via @testing-library/react + jsdom.
    electron/main/*)    exit 0 ;;
    */electron/main/*)  exit 0 ;;
    electron/preload/*) exit 0 ;;
    */electron/preload/*) exit 0 ;;
    electron/renderer/main.tsx) exit 0 ;;
    */electron/renderer/main.tsx) exit 0 ;;
    electron/renderer/index.html) exit 0 ;;
    */electron/renderer/index.html) exit 0 ;;
esac

# --- This is an implementation file. Check for corresponding test. ---

# Find test files modified in the current git session (staged or unstaged).
# Use git -C to bind to the file's worktree, not the parent shell's CWD.
CHANGED_TEST_FILES=$(git -C "$FILE_DIR" diff --name-only HEAD 2>/dev/null; git -C "$FILE_DIR" diff --name-only --cached 2>/dev/null)

# Check if ANY test file has been changed (indicating active TDD)
HAS_CHANGED_TESTS=false
while IFS= read -r file; do
    case "$file" in
        *_test.go|*_test.*|*.test.*|*.spec.*|test_*.py|*/test_*.py|tests/*|test/*|*/tests/*|*/test/*|*/__tests__/*)
            HAS_CHANGED_TESTS=true
            break
            ;;
    esac
done <<< "$CHANGED_TEST_FILES"

if [ "$HAS_CHANGED_TESTS" = true ]; then
    # Tests have been modified in this session — TDD cycle is active
    exit 0
fi

# Check if the file is brand new (no test companion found)
BASENAME=$(basename "$REL_PATH")
DIRNAME=$(dirname "$REL_PATH")
EXTENSION="${BASENAME##*.}"
NAME="${BASENAME%.*}"

# Look for a corresponding test file.
# If the impl is under src/, also check the mirror path under test/.
MIRROR_DIR=""
if [[ "$REL_PATH" == src/* ]]; then
    MIRROR_DIR="test/${DIRNAME#src/}"
elif [[ "$REL_PATH" == lib/* ]]; then
    MIRROR_DIR="test/${DIRNAME#lib/}"
elif [[ "$REL_PATH" == electron/renderer/* ]]; then
    # Electron renderer testable code (lib/, components/, hooks/) mirrors
    # to test/electron/ — flat layout since the renderer is a single
    # bundle target. Glue files (main.tsx, index.html) are exempted above.
    MIRROR_DIR="test/electron"
fi

FOUND_TEST=false
for pattern in \
    "${DIRNAME}/${NAME}_test.${EXTENSION}" \
    "${DIRNAME}/${NAME}.test.${EXTENSION}" \
    "${DIRNAME}/${NAME}.spec.${EXTENSION}" \
    ${MIRROR_DIR:+"${MIRROR_DIR}/${NAME}_test.${EXTENSION}"} \
    ${MIRROR_DIR:+"${MIRROR_DIR}/${NAME}.test.${EXTENSION}"} \
    ${MIRROR_DIR:+"${MIRROR_DIR}/${NAME}.spec.${EXTENSION}"} \
    "${DIRNAME}/test_${NAME}.py" \
    "${DIRNAME}/tests/test_${NAME}.py" \
    "${DIRNAME}/../tests/test_${NAME}.py" \
    "${DIRNAME}/tests/${NAME}_test.${EXTENSION}" \
    "${DIRNAME}/tests/${NAME}.test.${EXTENSION}" \
    "${DIRNAME}/../tests/${NAME}_test.${EXTENSION}" \
    "${DIRNAME}/../test/${NAME}_test.${EXTENSION}" \
    "${DIRNAME}/__tests__/${NAME}.test.${EXTENSION}" \
    "${DIRNAME}/__tests__/${NAME}.spec.${EXTENSION}"; do
    if [ -f "$GIT_ROOT/$pattern" ]; then
        FOUND_TEST=true
        break
    fi
done

if [ "$FOUND_TEST" = false ]; then
    echo "TDD GUARD: No test file found for implementation file." >&2
    echo "File: $REL_PATH" >&2
    echo "" >&2
    echo "Write the failing test FIRST (Red phase), then implement." >&2
    echo "" >&2
    # Use test-dep-map to show related tests if any exist via cross-references
    SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
    DEP_MAP=$("$SCRIPT_DIR/test-dep-map.sh" "$GIT_ROOT/$REL_PATH" 2>/dev/null)
    if [ -n "$DEP_MAP" ] && ! echo "$DEP_MAP" | grep -q "NO TESTS FOUND"; then
        echo "Related test files found by dependency analysis:" >&2
        echo "$DEP_MAP" >&2
    else
        echo "Expected test file locations:" >&2
        echo "  ${DIRNAME}/${NAME}_test.${EXTENSION}" >&2
        echo "  ${DIRNAME}/${NAME}.test.${EXTENSION}" >&2
        echo "  ${DIRNAME}/tests/${NAME}_test.${EXTENSION}" >&2
    fi
    echo "" >&2
    echo "If this is not a TDD-eligible file, add its pattern to tdd-guard.sh." >&2
    exit 2
fi

# Test file exists but hasn't been modified this session
# This could be valid (existing tests, adding implementation) — allow with warning
exit 0
