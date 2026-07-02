#!/bin/bash
# statusline_test.sh — verifies threshold coloring of the context-% token segment.
# Run: bash statusline_test.sh < /dev/null
#
# Bug each case catches: an off-by-one or wrong-band mapping in pct_color()
# (e.g. 50% staying green instead of yellow, or 90% staying amber instead of
# red), and a missing/misplaced reset that would bleed color into the
# rate-limit segment. Deleting pct_color() or flattening it to one color turns
# this suite RED.
set -uo pipefail

SCRIPT="$(cd "$(dirname "$0")" && pwd)/statusline.sh"

# SGR codes — must match pct_color() in statusline.sh (independent literals).
GREEN=$'\033[32m'
YELLOW=$'\033[33m'
AMBER=$'\033[38;5;208m'
RED=$'\033[31m'
RESET=$'\033[0m'

PASS=0
FAIL=0

# Render the status line for a given used_percentage.
run_pct() {
    printf '{"context_window":{"used_percentage":%s,"total_input_tokens":1000,"total_output_tokens":0},"rate_limits":{"five_hour":{"used_percentage":10}}}' "$1" \
        | bash "$SCRIPT"
}

# Assert: for percentage $1, the segment carries band color $2 and ONLY that
# color, a reset directly follows "(NN%)", and the other three band colors are
# absent from the whole line.
assert_band() {
    local pct="$1" want="$2" name="$3" out other
    out="$(run_pct "$pct")"

    if [[ "$out" != *"$want"* ]]; then
        echo "FAIL [$name]: pct=$pct missing expected band color"; FAIL=$((FAIL+1)); return
    fi
    if [[ "$out" != *"(${pct}%)${RESET}"* ]]; then
        echo "FAIL [$name]: pct=$pct reset not directly after (${pct}%)"; FAIL=$((FAIL+1)); return
    fi
    for other in "$GREEN" "$YELLOW" "$AMBER" "$RED"; do
        [ "$other" = "$want" ] && continue
        if [[ "$out" == *"$other"* ]]; then
            echo "FAIL [$name]: pct=$pct unexpected extra band color present"; FAIL=$((FAIL+1)); return
        fi
    done
    echo "PASS [$name]: pct=$pct"; PASS=$((PASS+1))
}

# Boundary discrimination — each line flips on an off-by-one.
assert_band 49  "$GREEN"  "green-below-50"
assert_band 50  "$YELLOW" "yellow-lower-bound"
assert_band 74  "$YELLOW" "yellow-upper"
assert_band 75  "$AMBER"  "amber-lower-bound"
assert_band 89  "$AMBER"  "amber-upper"
assert_band 90  "$RED"    "red-lower-bound"
assert_band 0   "$GREEN"  "zero-green"
assert_band 100 "$RED"    "hundred-red"

echo "----"
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
