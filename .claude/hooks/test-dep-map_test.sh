#!/bin/bash
# test-dep-map_test.sh - Integration tests for test-dep-map.sh + AST helper.
# Runs all eight cases from the design doc and prints PASS/FAIL summary.
# Exits 0 on full pass, 1 on any failure.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
HOOK="$SCRIPT_DIR/test-dep-map.sh"
HELPER="$SCRIPT_DIR/bin/test-dep-map-ast"

PASS=0
FAIL=0

# fail prints a failure message and increments FAIL.
fail() {
    echo "  FAIL: $1"
    FAIL=$((FAIL + 1))
}

# pass increments PASS.
pass() { PASS=$((PASS + 1)); }

# new_corpus creates a tmpdir, initializes a git repo (required by the hook),
# and prints the path on stdout.
new_corpus() {
    local d
    d=$(mktemp -d)
    (cd "$d" && git init -q && git config user.email "t@test" && git config user.name "t")
    echo "$d"
}

# run_case runs a single named case function and reports PASS/FAIL.
run_case() {
    local name="$1"
    local fn="$2"
    echo "Case: $name"
    if "$fn"; then
        echo "  PASS"
        pass
    else
        fail "$name failed"
    fi
}

# Each case function below returns 0 on pass, non-zero on fail. Cases use
# new_corpus to set up isolated tmpdirs and clean up on exit.

# Cases populated in subsequent tasks.

main() {
    if [ ! -x "$HELPER" ]; then
        echo "WARN: helper binary missing at $HELPER. Cases relying on AST path will fail."
        echo "Run: $SCRIPT_DIR/build-helpers.sh"
    fi
    # Case invocations added in subsequent tasks.
    run_case "method receivers" case_1_method_receivers
    run_case "ranking by density" case_2_ranking_by_density
    run_case "companion bonus" case_3_companion_bonus
    run_case "broken syntax fallback" case_4_broken_syntax_fallback
    run_case "env var disable" case_5_env_var_disable
    run_case "no tests found sentinel" case_6_no_tests_found_sentinel
    run_case "perf budget" case_7_perf_budget
    run_case "stdlib import no false positive" case_8_stdlib_import_no_false_positive

    echo ""
    echo "==========="
    echo "PASS: $PASS  FAIL: $FAIL"
    if [ "$FAIL" -gt 0 ]; then
        exit 1
    fi
    exit 0
}

# The case_* functions and main call live at the bottom; tasks below append.

case_1_method_receivers() {
    local d
    d=$(new_corpus)
    trap "rm -rf '$d'" RETURN
    cat > "$d/server.go" <<'EOF'
package mypkg
type Server struct{}
func (s *Server) Start() error { return nil }
EOF
    cat > "$d/server_test.go" <<'EOF'
package mypkg
import "testing"
func TestStart(t *testing.T) { s := &Server{}; _ = s.Start() }
EOF
    local out
    out=$(cd "$d" && "$HOOK" server.go)
    # AST path must include the method name Start in the references.
    # The helper outputs symbols comma-separated, e.g. "references Server, Start".
    echo "$out" | grep -qE 'references[^)]*Start' || {
        echo "  expected 'references ... Start' in: $out"
        return 1
    }
    return 0
}
case_2_ranking_by_density() {
    local d
    d=$(new_corpus)
    trap "rm -rf '$d'" RETURN
    cat > "$d/foo.go" <<'EOF'
package mypkg
func DoFoo() {}
EOF
    # Test that references DoFoo (strong match).
    cat > "$d/foo_test.go" <<'EOF'
package mypkg
import "testing"
func TestDoFoo(t *testing.T) { DoFoo() }
EOF
    # Test that references unrelated symbols (zero match).
    cat > "$d/bar_test.go" <<'EOF'
package mypkg
import "testing"
func TestBar(t *testing.T) { _ = 1 }
EOF
    local out
    out=$(cd "$d" && "$HOOK" foo.go)
    echo "$out" | grep -q "foo_test.go" || { echo "  foo_test.go missing in: $out"; return 1; }
    echo "$out" | grep -q "bar_test.go" && { echo "  bar_test.go should be omitted: $out"; return 1; }
    # AST-path signature: foo_test.go line must include `references DoFoo`
    # (regex companion path emits just `(N tests)` with no references clause).
    echo "$out" | grep -qE 'foo_test\.go.*references[^)]*DoFoo' || {
        echo "  expected 'foo_test.go ... references DoFoo' (AST-path signature) in: $out"
        return 1
    }
    return 0
}
case_3_companion_bonus() {
    local d
    d=$(new_corpus)
    trap "rm -rf '$d'" RETURN
    cat > "$d/thing.go" <<'EOF'
package mypkg
func Do() {}
EOF
    # Companion: Do referenced, +1 bonus.
    cat > "$d/thing_test.go" <<'EOF'
package mypkg
import "testing"
func TestDo(t *testing.T) { Do() }
EOF
    # Non-companion: Do referenced, no bonus.
    cat > "$d/other_test.go" <<'EOF'
package mypkg
import "testing"
func TestOther(t *testing.T) { Do() }
EOF
    local out
    out=$(cd "$d" && "$HOOK" thing.go)
    # First listed test file should be the companion.
    local first_line
    first_line=$(echo "$out" | grep '_test.go' | head -1)
    echo "$first_line" | grep -q "thing_test.go" || {
        echo "  companion should rank first, got first line: $first_line"
        return 1
    }
    # AST-path signature: the line must include `references Do` (regex companion
    # emission omits the references clause, so this fails if AST was bypassed).
    echo "$first_line" | grep -qE 'references[^)]*Do' || {
        echo "  expected AST-path 'references Do' in first line: $first_line"
        return 1
    }
    # And the non-companion line should also exist (AST keeps it because score > 0).
    echo "$out" | grep -q "other_test.go" || {
        echo "  non-companion other_test.go missing (should be ranked second): $out"
        return 1
    }
    return 0
}
case_4_broken_syntax_fallback() {
    local d
    d=$(new_corpus)
    trap "rm -rf '$d'" RETURN
    # Source with unclosed paren — go/parser returns an error.
    cat > "$d/broken.go" <<'EOF'
package mypkg

func Bad(
EOF
    # A test file that references symbols by name (regex path can match).
    cat > "$d/broken_test.go" <<'EOF'
package mypkg
import "testing"
func TestBad(t *testing.T) { /* mentions Bad */ }
EOF
    local out
    out=$(cd "$d" && "$HOOK" broken.go 2>&1)
    # Non-empty output expected from the regex fallback.
    [ -n "$out" ] || { echo "  expected non-empty fallback output"; return 1; }
    # Output should NOT contain a Go error message — fallback is silent.
    echo "$out" | grep -qE 'expected|syntax error' && {
        echo "  fallback leaked a Go error message: $out"
        return 1
    }
    # Regex-path signature: companion-line path is prefixed with `./` (the
    # regex_go_tests function emits relative paths starting with `./`).
    # AST path emits bare paths. This proves we actually fell back, not that
    # the AST helper silently produced something usable.
    echo "$out" | grep -qE '^  \./broken_test\.go' || {
        echo "  expected regex-path './broken_test.go' prefix (proof of fallback) in: $out"
        return 1
    }
    return 0
}
case_5_env_var_disable() {
    local d
    d=$(new_corpus)
    trap "rm -rf '$d'" RETURN
    cat > "$d/server.go" <<'EOF'
package mypkg
type Server struct{}
func (s *Server) Start() error { return nil }
EOF
    cat > "$d/server_test.go" <<'EOF'
package mypkg
import "testing"
func TestStart(t *testing.T) { s := &Server{}; _ = s.Start() }
EOF
    local out
    out=$(cd "$d" && TDAD_DISABLE_AST=YES "$HOOK" server.go)
    # Regex path: cannot extract the method name Start from func (s *Server) Start().
    echo "$out" | grep -qE 'references[^)]*Start' && {
        echo "  AST was not bypassed — output contains Start reference: $out"
        return 1
    }
    # Regex-path signature: companion line has `./` prefix and NO references
    # clause. AST emits bare paths with a references clause. Both must match
    # to prove TDAD_DISABLE_AST was honored (not just that AST silently
    # produced this output).
    echo "$out" | grep -qE '^  \./server_test\.go \([0-9]+ tests\)$' || {
        echo "  expected regex companion line '  ./server_test.go (N tests)' (proof of disable) in: $out"
        return 1
    }
    return 0
}
case_6_no_tests_found_sentinel() {
    local d
    d=$(new_corpus)
    trap "rm -rf '$d'" RETURN
    cat > "$d/lonely.go" <<'EOF'
package mypkg
func Lonely() {}
EOF
    # No test files in directory.
    local out
    out=$(cd "$d" && "$HOOK" lonely.go)
    echo "$out" | grep -q "NO TESTS FOUND" || {
        echo "  expected 'NO TESTS FOUND' sentinel in: $out"
        return 1
    }
    return 0
}
case_7_perf_budget() {
    local d
    d=$(new_corpus)
    trap "rm -rf '$d'" RETURN
    cat > "$d/main.go" <<'EOF'
package mypkg
type Thing struct{}
func (t *Thing) Do() {}
func (t *Thing) Undo() {}
EOF
    # Generate 50 test files in the package.
    local i
    for i in $(seq 1 50); do
        cat > "$d/case${i}_test.go" <<EOF
package mypkg

import "testing"

func TestCase${i}A(t *testing.T) { th := &Thing{}; th.Do() }
func TestCase${i}B(t *testing.T) { th := &Thing{}; th.Undo() }
EOF
    done
    # Measure wall time in ms.
    local start_ns end_ns elapsed_ms
    start_ns=$(date +%s%N 2>/dev/null || gdate +%s%N 2>/dev/null)
    if [ -z "$start_ns" ] || [ "$start_ns" = "+%N" ]; then
        # macOS without coreutils: use Python for ms precision.
        local start_s
        start_s=$(python3 -c 'import time; print(time.time())')
        (cd "$d" && "$HOOK" main.go) > /dev/null
        local end_s
        end_s=$(python3 -c 'import time; print(time.time())')
        elapsed_ms=$(python3 -c "print(int(($end_s - $start_s) * 1000))")
    else
        (cd "$d" && "$HOOK" main.go) > /dev/null
        end_ns=$(date +%s%N 2>/dev/null || gdate +%s%N 2>/dev/null)
        elapsed_ms=$(( (end_ns - start_ns) / 1000000 ))
    fi
    echo "  elapsed: ${elapsed_ms}ms"
    if [ "$elapsed_ms" -gt 500 ]; then
        echo "  perf budget exceeded: ${elapsed_ms}ms > 500ms"
        return 1
    fi
    return 0
}

case_8_stdlib_import_no_false_positive() {
    local d
    d=$(new_corpus)
    trap "rm -rf '$d'" RETURN
    cat > "$d/thing.go" <<'EOF'
package mypkg
type Server struct{}
func Run() {}
EOF
    # Test references http.Server (imported) — must NOT credit local Server.
    cat > "$d/stdlib_test.go" <<'EOF'
package mypkg

import (
	"net/http"
	"testing"
)

func TestStdlib(t *testing.T) {
	_ = &http.Server{}
	Run()
}
EOF
    local out
    out=$(cd "$d" && "$HOOK" thing.go)
    # Must list stdlib_test.go (because of Run()).
    echo "$out" | grep -q "stdlib_test.go" || { echo "  stdlib_test.go missing: $out"; return 1; }
    # References must be EXACTLY 'Run', not 'Server'.
    echo "$out" | grep -qE 'stdlib_test\.go.*references[^)]*Server' && {
        echo "  AST counted http.Server as local Server (false positive): $out"
        return 1
    }
    echo "$out" | grep -qE 'stdlib_test\.go.*references[^)]*Run' || {
        echo "  AST missed legitimate Run() call: $out"
        return 1
    }
    return 0
}

main "$@"
