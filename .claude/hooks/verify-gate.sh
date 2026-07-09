#!/usr/bin/env bash
# verify-gate.sh — Stop hook: block once if code changed this session but no
# test/build/lint command ran. Fail-open (exit 0) on any error; block = exit 2.
set -uo pipefail

DEFAULT_VERIFY_PATTERN='go test|go build|go vet|gotestsum|pytest|py\.test|tox|nox|npm test|npm run test|yarn test|pnpm test|jest|vitest|cargo test|cargo build|cargo check|cargo clippy|make test|make check|make lint|make verify|make ci|golangci-lint|staticcheck|ruff|mypy|pyright|eslint|tsc|shellcheck|bats|ctest|bazel test|gradle test|mvn test|mvn verify|rspec|[a-z0-9_-]+_test\.sh'
DEFAULT_CODE_EXT='go py ts tsx js jsx mjs cjs rs sh bash c h cc cpp hpp java rb php swift kt scala sql proto'

# extract_rows <transcript_file>: print "name<TAB>arg" per tool_use entry
# (arg = .input.command, else .input.file_path, else .input.notebook_path, else "").
extract_rows() {
  jq -rc 'select((.message.content? // []) | type=="array")
          | .message.content[]
          | select(.type=="tool_use")
          | [.name, (.input.command // .input.file_path // .input.notebook_path // "")] | @tsv' "$1" 2>/dev/null
}

# code_changed: read rows on stdin; print the first Edit/Write/MultiEdit/NotebookEdit
# target whose path ends in a source extension (empty if none).
code_changed() {
  local exts="${VERIFY_GATE_EXT:-$DEFAULT_CODE_EXT}" re
  re=$(printf '%s' "$exts" | tr -s ' ' '|' | sed 's/^|//; s/|$//')
  awk -F'\t' -v re="$re" '
    BEGIN { pat = "\\.(" re ")$" }
    ($1=="Edit" || $1=="Write" || $1=="MultiEdit" || $1=="NotebookEdit") {
      if (tolower($2) ~ pat) { print $2; exit }
    }'
}

# verification_ran: read rows on stdin; rc 0 iff any Bash command matches the
# verification allowlist. Bar is "ran", not "passed".
verification_ran() {
  local pat="${VERIFY_GATE_PATTERN:-$DEFAULT_VERIFY_PATTERN}"
  awk -F'\t' '$1=="Bash"{print $2}' | grep -iEq "$pat"
}

main() {
  local input transcript rows changed
  input=$(cat)
  # 1. loop guard (Stop-hook infinite-loop protection)
  [ "$(printf '%s' "$input" | jq -r '.stop_hook_active // false' 2>/dev/null)" = "true" ] && exit 0
  # 2. escape hatch
  [ "${VERIFY_GATE:-on}" = "off" ] && exit 0
  # 3. transcript must exist
  transcript=$(printf '%s' "$input" | jq -r '.transcript_path // empty' 2>/dev/null)
  [ -n "$transcript" ] && [ -f "$transcript" ] || exit 0
  # 4. extract tool-use rows (fail-open on jq error / empty)
  rows=$(extract_rows "$transcript") || exit 0
  [ -n "$rows" ] || exit 0
  # 5. did code change? (no -> allow)
  changed=$(printf '%s\n' "$rows" | code_changed)
  [ -n "$changed" ] || exit 0
  # 6. did verification run? (yes -> allow)
  printf '%s\n' "$rows" | verification_ran && exit 0
  # 7. block — stderr reaches the model on a Stop exit-2
  printf '[verify-gate] You changed code this session (e.g. %s) but no test/build/lint command ran.\n' "$changed" >&2
  printf 'Run the relevant verification before finishing — e.g. go test ./... , pytest, npm test, golangci-lint, shellcheck.\n' >&2
  printf 'If verification genuinely does not apply here, say so explicitly in your reply. (Disable for this session: export VERIFY_GATE=off)\n' >&2
  exit 2
}

if [ "${BASH_SOURCE[0]}" = "${0}" ]; then main; fi
