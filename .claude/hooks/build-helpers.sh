#!/bin/bash
# build-helpers.sh - Build compiled Go helpers for hooks.
# Idempotent: only rebuilds when source is newer than the binary, or the
# binary is missing.
#
# Usage: ./build-helpers.sh [--force]
#   --force: rebuild even if up to date.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BIN_DIR="$SCRIPT_DIR/bin"
mkdir -p "$BIN_DIR"

FORCE=0
[ "${1:-}" = "--force" ] && FORCE=1

build_one() {
    local name="$1"
    local src_dir="$SCRIPT_DIR/src/$name"
    local bin_path="$BIN_DIR/$name"
    if [ ! -d "$src_dir" ]; then
        echo "skip $name (no source dir)"
        return
    fi
    if [ $FORCE -eq 0 ] && [ -f "$bin_path" ]; then
        local newer
        newer=$(find "$src_dir" -name '*.go' -newer "$bin_path" 2>/dev/null | head -1)
        if [ -z "$newer" ]; then
            echo "up to date: $bin_path"
            return
        fi
    fi
    (cd "$src_dir" && go build -o "$bin_path" .)
    echo "built: $bin_path"
}

# No compiled Go helpers currently registered. Add `build_one <name>` calls
# here as new hooks/src/<name>/ modules are introduced.
