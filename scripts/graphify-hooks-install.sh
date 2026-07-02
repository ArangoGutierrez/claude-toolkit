#!/usr/bin/env bash
set -euo pipefail
# Install global graphify-refresh hooks (post-commit, post-merge, post-rewrite)
# into the effective git hooks dir. Idempotent and append-safe. Each hook is a
# no-op unless the repo has graphify-out/ and graphify is on PATH. 2026.

hooks_dir() {
  if [ -n "${GRAPHIFY_HOOKS_DIR:-}" ]; then printf '%s\n' "$GRAPHIFY_HOOKS_DIR"; return; fi
  local cp; cp="$(git config --global --get core.hooksPath 2>/dev/null || true)"
  if [ -n "$cp" ]; then
    case "$cp" in "~"*) cp="${HOME}${cp#\~}";; esac
    printf '%s\n' "$cp"
  else
    printf '%s\n' "${HOME}/.config/git/hooks"
  fi
}

MARKER='graphify-refresh'
block() {
  printf '# %s (no-op unless repo has graphify-out/ and graphify is installed)\n' "$MARKER"
  printf 'if command -v graphify >/dev/null 2>&1 && [ -d graphify-out ]; then\n'
  printf '  ( env -u OPENAI_API_KEY -u ANTHROPIC_API_KEY graphify update . >/dev/null 2>&1 & )\n'
  printf 'fi\n'
}

main() {
  local dir; dir="$(hooks_dir)"; mkdir -p "$dir"
  local h f
  for h in post-commit post-merge post-rewrite; do
    f="$dir/$h"
    if [ ! -f "$f" ]; then
      { printf '#!/usr/bin/env bash\n'; block; } > "$f"; chmod +x "$f"
      echo ">> installed $h in $dir"
    elif ! grep -qF "$MARKER" "$f"; then
      { printf '\n'; block; } >> "$f"; chmod +x "$f"
      echo ">> appended $MARKER to existing $f"
    else
      echo ">> $h already has $MARKER (idempotent)"
    fi
  done
}
main "$@"
