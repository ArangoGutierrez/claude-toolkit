#!/bin/bash
# scan-config.sh — read-only audit of a .claude config tree.
# Usage: scan-config.sh [DIR]   (default: ~/.claude)
# Stdout: SEVERITY<TAB>CATEGORY<TAB>FILE:LINE<TAB>MESSAGE  (highest severity first)
# Exit:   0 clean, 1 low/medium, 2 high/critical, 3 scan aborted (e.g. mktemp
#         failed) -- fails closed, never silently reports clean on abort.
#         macOS bash 3.2 compatible.
set -uo pipefail

DIR="${1:-$HOME/.claude}"
[ -d "$DIR" ] || { echo "scan-config: no such dir: $DIR" >&2; exit 0; }

FINDINGS="$(mktemp)"
mk_rc=$?
if [ "$mk_rc" -ne 0 ] || [ -z "$FINDINGS" ] || [ ! -f "$FINDINGS" ]; then
  echo "scan-config: mktemp failed (rc=$mk_rc); cannot create findings buffer, failing closed" >&2
  exit 3
fi
trap 'rm -f "$FINDINGS"' EXIT
add() { printf '%s\t%s\t%s\t%s\n' "$1" "$2" "$3" "$4" >> "$FINDINGS"; }
is_suppressed() { sed -n "${2}p" "$1" 2>/dev/null | grep -qE "config-audit:ignore[[:space:]]+(all|$3)"; }

# find_config DIR PRED... — list files under DIR matching find predicate PRED,
# pruning noise trees (huge, machine-managed, or archived) that are not live config.
# -prune skips the whole subtree, unlike a post-hoc -not -path filter that still descends.
find_config() {
  local d="$1"; shift
  find "$d" \
    \( -type d \( -name .git -o -name node_modules -o -name plugins -o -name projects \
       -o -name tasks -o -name shell-snapshots -o -name telemetry -o -name archive \
       -o -name venv -o -name .venv -o -name site-packages -o -name __pycache__ \
       -o -name .tox -o -name handoffs -o -name teams \) -prune \) \
    -o \( -type f \( "$@" \) -print \)
}

while IFS= read -r f; do
  [ -f "$f" ] || continue

  # secrets (sev 2)
  while IFS=: read -r ln text; do
    [ -n "${ln:-}" ] || continue
    case "$f" in *_test.sh) continue;; esac   # test files hold deliberate fixtures, not real secrets
    case "$text" in *'<'*'>'*|*example*|*EXAMPLE*|*REDACTED*|*xxxx*|*placeholder*|*your_*) continue;; esac
    # example-code, not a credential: value is a dotted method/property chain (a.b.c)
    printf '%s\n' "$text" | grep -qEi "(api[_-]?key|secret|token|password|bearer)[\"' ]*[:=][\"' ]*[A-Za-z_]+(\.[A-Za-z_]+)+" && continue
    # ...or a bare ALL_CAPS_CONSTANT name (screaming-snake, no digits-only token would have '_')
    printf '%s\n' "$text" | grep -qE  "(api[_-]?key|secret|token|password|bearer)[\"' ]*[:=][\"' ]*[A-Z][A-Z0-9]*_[A-Z0-9_]*" && continue
    is_suppressed "$f" "$ln" secrets && continue
    add 2 secrets "$f:$ln" "possible hardcoded secret"
  done < <(grep -nEi "(api[_-]?key|secret|token|password|bearer)[\"' ]*[:=][\"' ]*[A-Za-z0-9_/+.-]{16,}|ghp_[A-Za-z0-9]{20,}|AKIA[0-9A-Z]{12,}|BEGIN [A-Z ]*PRIVATE KEY" "$f" 2>/dev/null)

  # injection-sink (sev 2)
  while IFS=: read -r ln text; do
    [ -n "${ln:-}" ] || continue
    case "$f" in *_test.sh) continue;; esac   # test files hold deliberate fixtures, not real sinks
    # printed as advice (echo/printf) or commented out — not an executed sink
    printf '%s\n' "$text" | grep -qE '^[[:space:]]*(echo|printf)[[:space:]]' && continue
    printf '%s\n' "$text" | grep -qE '^[[:space:]]*#' && continue
    is_suppressed "$f" "$ln" injection-sink && continue
    add 2 injection-sink "$f:$ln" "untrusted content piped to shell / eval"
  done < <(grep -nE 'curl[^|]*\|[[:space:]]*(ba)?sh|eval[[:space:]]+"?\$\(|\$\(curl' "$f" 2>/dev/null)

  # broad-perms: only real in JSON config — docs that quote these keywords are not findings
  case "$f" in
  *.json)
    # bypass (sev 2)
    while IFS=: read -r ln text; do
      [ -n "${ln:-}" ] || continue
      is_suppressed "$f" "$ln" broad-perms && continue
      add 2 broad-perms "$f:$ln" "sandbox/permission bypass"
    done < <(grep -nE 'dangerouslyDisableSandbox"?[[:space:]]*:[[:space:]]*true|"bypassPermissions"' "$f" 2>/dev/null)

    # wildcard Bash (sev 1) — covers exact "Bash(*)" and suffix-wildcard forms
    # like "Bash(* --version)"/"Bash(* --help)": any allow entry whose Bash
    # command component starts with * is a broad grant.
    while IFS=: read -r ln text; do
      [ -n "${ln:-}" ] || continue
      is_suppressed "$f" "$ln" broad-perms && continue
      add 1 broad-perms "$f:$ln" "wildcard Bash permission grant"
    done < <(grep -nE '"Bash\(\*[^)]*\)"' "$f" 2>/dev/null)
    ;;
  esac

  # hook-hygiene: shell script with no hardening at all (sev 1)
  # suppressible via a 'config-audit:ignore hook-hygiene' marker in the head (e.g. after the
  # shebang) — needed for sourced libs, where 'set -u' would leak into the caller's shell.
  case "$f" in
    *.sh)
      if ! grep -qE '^[[:space:]]*set -' "$f" 2>/dev/null; then
        head -5 "$f" 2>/dev/null | grep -qE "config-audit:ignore[[:space:]]+(all|hook-hygiene)" \
          || add 1 hook-hygiene "$f:1" "shell script missing 'set -euo pipefail'"
      fi ;;
  esac
done < <(find_config "$DIR" -name '*.sh' -o -name '*.md' -o -name '*.json' -o -name '*.js' -o -name '*.toml' -o -name '*.yaml' -o -name '*.yml' -o -name '*.py' 2>/dev/null)

# hook-hygiene: executable backup scripts (sev 1)
while IFS= read -r b; do
  [ -n "$b" ] || continue
  [ -x "$b" ] || continue
  add 1 hook-hygiene "$b:1" "executable backup script (drop exec bit or delete)"
done < <(find_config "$DIR" -name '*.bak' -o -name '*.bak-*' 2>/dev/null)

# mcp-hygiene: enabled MCP count (sev 1 if >10) — best-effort, needs jq
if command -v jq >/dev/null 2>&1; then
  for sf in "$DIR/settings.json" "$DIR/settings.local.json"; do
    [ -f "$sf" ] || continue
    n=$(jq -r '(.enabledMcpjsonServers // []) | length' "$sf" 2>/dev/null || echo 0)
    [ "${n:-0}" -gt 10 ] && add 1 mcp-hygiene "$sf:1" "$n MCP servers enabled (>10 inflates context)"
  done
fi

maxsev=0
if [ -s "$FINDINGS" ]; then
  sort -t$'\t' -k1,1nr "$FINDINGS" | while IFS=$'\t' read -r sev cat loc msg; do
    case "$sev" in 2) label=high;; 1) label=low;; *) label=info;; esac
    printf '%s\t%s\t%s\t%s\n' "$label" "$cat" "$loc" "$msg"
  done
  maxsev=$(cut -f1 "$FINDINGS" | sort -nr | head -1)
fi
case "${maxsev:-0}" in 2) exit 2;; 1) exit 1;; *) exit 0;; esac
