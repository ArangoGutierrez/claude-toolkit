#!/bin/bash
# Test validate-recommendation.sh hook behavior.
set -o pipefail

HOOK="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/validate-recommendation.sh"
TMP=$(mktemp -d "${TMPDIR:-/tmp}/hooktest.XXXXXX")
trap "rm -rf $TMP" EXIT

# Isolate the trace log so tests don't pollute ~/.claude/debug/.
export CLAUDE_PANEL_TRACE_LOG="$TMP/panel-trace.log"

if [ ! -x "$HOOK" ]; then
    echo "FAIL: hook missing or not executable: $HOOK"
    exit 1
fi

# Stand-in for macOS ioreg, so presence (the Mac's input idle time) is under
# test control instead of following whoever runs the suite. It answers only
# the IOHIDSystem query and prints the property lines in the shape the real
# tool does (`| | |   "HIDIdleTime" = <nanoseconds>`); any other query gets
# nothing, so a broken query reads as "idle unknown" and fails the presence
# tests. FAKE_HID_IDLE_NS sets the idle time; FAKE_HID_MODE=garbled prints a
# value that is not a number, and FAKE_HID_MODE=missing leaves the
# HIDIdleTime line out entirely.
HIDBIN="$TMP/hidbin"
mkdir -p "$HIDBIN"
cat > "$HIDBIN/ioreg" <<'FAKEIOREG'
#!/bin/bash
case " $* " in
    *" -c IOHIDSystem "*) ;;
    *) exit 1 ;;
esac
echo '    | | |   "IOProbeScore" = 0'
if [ "${FAKE_HID_MODE:-}" = "garbled" ]; then
    echo '    | | |   "HIDIdleTime" = <unreadable>'
elif [ "${FAKE_HID_MODE:-}" = "missing" ]; then
    :
else
    echo "    | | |   \"HIDIdleTime\" = ${FAKE_HID_IDLE_NS}"
fi
echo '    | | |   "HIDScrollCountIgnoreMomentumScrolls" = Yes'
FAKEIOREG
chmod +x "$HIDBIN/ioreg"

# One hour without input: the "away" path, where a marked question goes to
# the panel. run_hook defaults to it so tests 1-11 exercise the panel path as
# they did before presence existed; $envs can override it per test.
AWAY_NS=3600000000000

run_hook() {
    # $1: stdin JSON, $2: env vars (space-separated key=val), $3: optional session id
    local input="$1"; local envs="$2"; local sid="${3:-test-session}"
    env PATH="$HIDBIN:$PATH" FAKE_HID_IDLE_NS="$AWAY_NS" $envs TMPDIR="$TMP" CLAUDE_SESSION_ID="$sid" CLAUDE_PANEL_TRACE_LOG="$CLAUDE_PANEL_TRACE_LOG" bash -c "echo '$input' | '$HOOK'" 2>&1
    return $?
}

# Test 1: marker present → exit 2 (block) + stderr mentions skill
INPUT='{"tool_name":"AskUserQuestion","tool_input":{"questions":[{"question":"Pick one","options":[{"label":"Option A (Recommended)","description":"the recommended choice"},{"label":"Option B","description":"alt"}]}]},"session_id":"t1"}'
OUT=$(run_hook "$INPUT" "" "t1") && RC=0 || RC=$?
if [ "$RC" != "2" ]; then
    echo "FAIL test1: expected exit 2 (block), got $RC"
    echo "OUT: $OUT"
    exit 1
fi
if ! echo "$OUT" | grep -qi 'validate-recommendation'; then
    echo "FAIL test1: stderr should mention skill name"
    echo "OUT: $OUT"
    exit 1
fi
if [ ! -f "$TMP/claude-panel-t1.json" ]; then
    echo "FAIL test1: state file not written"
    exit 1
fi

# Test 2: no marker → exit 0 (approve), no state file
INPUT='{"tool_name":"AskUserQuestion","tool_input":{"questions":[{"question":"Pick one","options":[{"label":"Option A","description":"a"},{"label":"Option B","description":"b"}]}]},"session_id":"t2"}'
run_hook "$INPUT" "" "t2" >/dev/null && RC=0 || RC=$?
if [ "$RC" != "0" ]; then
    echo "FAIL test2: expected exit 0, got $RC"
    exit 1
fi
if [ -f "$TMP/claude-panel-t2.json" ]; then
    echo "FAIL test2: state file should NOT exist"
    exit 1
fi

# Test 3: loop guard (Panel-flagged) → exit 0
INPUT='{"tool_name":"AskUserQuestion","tool_input":{"questions":[{"question":"Pick one","options":[{"label":"Option A (Recommended; Panel-flagged)","description":"a"},{"label":"Option B","description":"b"}]}]},"session_id":"t3"}'
run_hook "$INPUT" "" "t3" >/dev/null && RC=0 || RC=$?
if [ "$RC" != "0" ]; then
    echo "FAIL test3 loop guard: expected exit 0, got $RC"
    exit 1
fi
if [ -f "$TMP/claude-panel-t3.json" ]; then
    echo "FAIL test3: state file should NOT exist on loop guard"
    exit 1
fi

# Test 4: CLAUDE_PANEL=off bypasses panel even with marker
INPUT='{"tool_name":"AskUserQuestion","tool_input":{"questions":[{"question":"Pick one","options":[{"label":"Option A (Recommended)","description":"a"}]}]},"session_id":"t4"}'
run_hook "$INPUT" "CLAUDE_PANEL=off" "t4" >/dev/null && RC=0 || RC=$?
if [ "$RC" != "0" ]; then
    echo "FAIL test4 CLAUDE_PANEL=off: expected exit 0, got $RC"
    exit 1
fi
if [ -f "$TMP/claude-panel-t4.json" ]; then
    echo "FAIL test4: state file should NOT exist when panel off"
    exit 1
fi

# Test 5: malformed JSON → exit 0 (fail-open) + stderr log
INPUT='not valid json'
OUT=$(run_hook "$INPUT" "" "t5") && RC=0 || RC=$?
if [ "$RC" != "0" ]; then
    echo "FAIL test5 malformed: expected exit 0 (fail-open), got $RC"
    exit 1
fi

# Test 6: state file has expected keys
INPUT='{"tool_name":"AskUserQuestion","tool_input":{"questions":[{"question":"Pick one","options":[{"label":"Option A (Recommended)","description":"a"},{"label":"Option B","description":"b"}]}]},"session_id":"t6"}'
run_hook "$INPUT" "" "t6" >/dev/null 2>&1 || true
STATE="$TMP/claude-panel-t6.json"
if [ ! -f "$STATE" ]; then
    echo "FAIL test6: state file missing"
    exit 1
fi
for key in session_id tool_input recommended_label timeout_seconds created_at; do
    if ! jq -e --arg k "$key" 'has($k)' "$STATE" >/dev/null 2>&1; then
        echo "FAIL test6: state file missing key: $key"
        cat "$STATE"
        exit 1
    fi
done
# State file must be mode 0600 (user-only). Defense-in-depth on shared /tmp.
# stat differs between BSD (macOS) and GNU (Linux); try both.
MODE=$(stat -f '%Lp' "$STATE" 2>/dev/null) || MODE=$(stat -c '%a' "$STATE" 2>/dev/null)
if [ "$MODE" != "600" ]; then
    echo "FAIL test6: state file mode is $MODE, expected 600"
    exit 1
fi

# Test 7: non-AskUserQuestion tool → exit 0 (no-op)
INPUT='{"tool_name":"Bash","tool_input":{"command":"ls"},"session_id":"t7"}'
run_hook "$INPUT" "" "t7" >/dev/null && RC=0 || RC=$?
if [ "$RC" != "0" ]; then
    echo "FAIL test7 wrong tool: expected exit 0, got $RC"
    exit 1
fi

# After test 1+ the trace log should exist and contain a trigger line for
# session t1 (default-on telemetry; lets the operator detect silent decay).
if [ ! -f "$CLAUDE_PANEL_TRACE_LOG" ]; then
    echo "FAIL telemetry: trace log not created at $CLAUDE_PANEL_TRACE_LOG"
    exit 1
fi
if ! grep -q 'event=trigger session=t1' "$CLAUDE_PANEL_TRACE_LOG"; then
    echo "FAIL telemetry: missing 'event=trigger session=t1' in trace log"
    cat "$CLAUDE_PANEL_TRACE_LOG"
    exit 1
fi

# Test 8: re-entry guard — if state file already exists for the session,
# hook bypasses (exit 0) and removes the stale state. Models the scenario
# where the skill failed mid-flight and the assistant re-issued the same
# AskUserQuestion; we must not loop.
INPUT='{"tool_name":"AskUserQuestion","tool_input":{"questions":[{"question":"Pick one","options":[{"label":"Option A (Recommended)","description":"a"},{"label":"Option B","description":"b"}]}]},"session_id":"t8"}'
# First call: hook blocks and writes state.
run_hook "$INPUT" "" "t8" >/dev/null 2>&1 || true
STATE8="$TMP/claude-panel-t8.json"
if [ ! -f "$STATE8" ]; then
    echo "FAIL test8 setup: state file not written by first call"
    exit 1
fi
# Second call (same session, same payload): re-entry path must approve.
run_hook "$INPUT" "" "t8" >/dev/null 2>&1 && RC=0 || RC=$?
if [ "$RC" != "0" ]; then
    echo "FAIL test8 re-entry: expected exit 0 (bypass), got $RC"
    exit 1
fi
# Hook must remove the stale state file on bypass so the next legitimate
# session can start fresh.
if [ -f "$STATE8" ]; then
    echo "FAIL test8: hook must remove stale state file on re-entry bypass"
    exit 1
fi
# Third call after bypass: state is fresh, hook blocks again.
run_hook "$INPUT" "" "t8" >/dev/null 2>&1 && RC=0 || RC=$?
if [ "$RC" != "2" ]; then
    echo "FAIL test8 post-bypass: expected exit 2 on fresh call, got $RC"
    exit 1
fi

# Test 9: collision-proof state-file path when CLAUDE_SESSION_ID is unset.
# Two concurrent Claude Code sessions both resolving SID to "unknown" would
# share the same state-file path and corrupt each other's skill execution
# (session A's panel-skill cleanup deletes the file session B is mid-read
# on). The hook must fall back to a per-process identifier instead of the
# shared "unknown" sentinel.
INPUT='{"tool_name":"AskUserQuestion","tool_input":{"questions":[{"question":"Pick one","options":[{"label":"Option A (Recommended)","description":"a"}]}]}}'
# Away, so the hook reaches the state-file write this test is about; the
# exit 2 below proves it got there, or the absence check proves nothing.
env -u CLAUDE_SESSION_ID PATH="$HIDBIN:$PATH" FAKE_HID_IDLE_NS="$AWAY_NS" TMPDIR="$TMP" CLAUDE_PANEL_TRACE_LOG="$CLAUDE_PANEL_TRACE_LOG" \
    bash -c "echo '$INPUT' | '$HOOK'" >/dev/null 2>&1 && RC=0 || RC=$?
if [ "$RC" != "2" ]; then
    echo "FAIL test9 setup: expected exit 2 (panel path, state file written), got $RC"
    exit 1
fi
if [ -f "$TMP/claude-panel-unknown.json" ]; then
    echo "FAIL test9 collision: hook wrote to the shared 'unknown' state-file path when CLAUDE_SESSION_ID was unset. Two concurrent CC sessions would collide here. Hook must fall back to a per-process id (e.g. \$PPID)."
    exit 1
fi

# Test 10: stale re-entry guard — a state file older than the 600s
# threshold is NOT a same-flight re-issue; it's a leftover from an
# earlier, unrelated run (e.g. the skill's cleanup silently no-op'd on a
# bad glob). The hook must discard it, log event=stale_state_replaced,
# and fall through to writing a FRESH state file + blocking (exit 2) —
# exactly as if this were the first trigger. This is the defect from the
# trace log: any leftover state file, however old, was bypassing the next
# unrelated paneled question.
INPUT='{"tool_name":"AskUserQuestion","tool_input":{"questions":[{"question":"Pick one","options":[{"label":"Option A (Recommended)","description":"a"},{"label":"Option B","description":"b"}]}]},"session_id":"t10"}'
STATE10="$TMP/claude-panel-t10.json"
# Seed a stale state file directly (not via a real hook call) so its
# mtime is fully under test control.
echo '{"session_id":"t10","tool_input":{},"recommended_label":"stale-placeholder","timeout_seconds":90,"created_at":"2020-01-01T00:00:00Z"}' > "$STATE10"
STALE_EPOCH=$(( $(date +%s) - 660 ))
STALE_TS=$(date -r "$STALE_EPOCH" +"%Y%m%d%H%M.%S" 2>/dev/null || date -d "@$STALE_EPOCH" +"%Y%m%d%H%M.%S")
touch -t "$STALE_TS" "$STATE10"

OUT=$(run_hook "$INPUT" "" "t10") && RC=0 || RC=$?
if [ "$RC" != "2" ]; then
    echo "FAIL test10 stale: expected exit 2 (fresh block after stale replace), got $RC"
    echo "OUT: $OUT"
    exit 1
fi
if [ ! -f "$STATE10" ]; then
    echo "FAIL test10 stale: a fresh state file should have been written after the stale one was replaced"
    exit 1
fi
if jq -e '.recommended_label == "stale-placeholder"' "$STATE10" >/dev/null 2>&1; then
    echo "FAIL test10 stale: state file still holds the stale placeholder content — it was not replaced"
    exit 1
fi
if ! grep -q 'event=stale_state_replaced session=t10' "$CLAUDE_PANEL_TRACE_LOG"; then
    echo "FAIL test10 stale: missing 'event=stale_state_replaced session=t10' in trace log"
    cat "$CLAUDE_PANEL_TRACE_LOG"
    exit 1
fi

# Test 11: unreadable mtime must fail OPEN (bypass), never fail into the
# stale-replace path. A parse/stat failure turning into a block would be
# worse than the bug being fixed. Simulate a garbled/unreadable stat
# result (e.g. a TOCTOU race where the file vanished between the -f check
# and the stat call) by shadowing `stat` on PATH with a version that
# always fails to produce a parseable mtime.
INPUT='{"tool_name":"AskUserQuestion","tool_input":{"questions":[{"question":"Pick one","options":[{"label":"Option A (Recommended)","description":"a"},{"label":"Option B","description":"b"}]}]},"session_id":"t11"}'
STATE11="$TMP/claude-panel-t11.json"
echo '{"session_id":"t11","tool_input":{},"recommended_label":"placeholder","timeout_seconds":90,"created_at":"2020-01-01T00:00:00Z"}' > "$STATE11"

FAKEBIN="$TMP/fakebin"
mkdir -p "$FAKEBIN"
cat > "$FAKEBIN/stat" <<'FAKESTAT'
#!/bin/bash
# Always produce unusable output, simulating an unreadable/garbled mtime
# (both the macOS -f and GNU -c forms hit this same fake binary).
exit 1
FAKESTAT
chmod +x "$FAKEBIN/stat"

# A minimal, space-free PATH. run_hook passes $envs to `env` UNQUOTED so that
# multiple KEY=VAL pairs split correctly — which means a value containing a
# space splits too. This machine's PATH holds six "Application Support/..."
# entries, so $FAKEBIN:$PATH made env try to run "Support/Claude/..." and
# return 127, a false failure that looked like the hook crashing. $HIDBIN
# stays first so the fake ioreg, not the real one in /usr/sbin, answers.
run_hook "$INPUT" "PATH=$HIDBIN:$FAKEBIN:/usr/bin:/bin:/usr/sbin:/sbin" "t11" >/dev/null 2>&1 && RC=0 || RC=$?
if [ "$RC" != "0" ]; then
    echo "FAIL test11 unreadable mtime: expected exit 0 (fail-open bypass), got $RC"
    exit 1
fi
if [ -f "$STATE11" ]; then
    echo "FAIL test11 unreadable mtime: hook should remove the state file on fail-open bypass"
    exit 1
fi
if ! grep -q 'event=reentry_bypass reason=unreadable session=t11' "$CLAUDE_PANEL_TRACE_LOG"; then
    echo "FAIL test11 unreadable mtime: missing 'event=reentry_bypass reason=unreadable session=t11' in trace log"
    cat "$CLAUDE_PANEL_TRACE_LOG"
    exit 1
fi

# Presence (2026-10-10). The panel stands in for the user while they are
# away. While they are using the Mac, a marked question goes straight to
# them instead. Presence is the Mac's input idle time (IOHIDSystem
# HIDIdleTime): under CLAUDE_PANEL_AWAY_AFTER seconds (default 600) is
# present. Every AskUserQuestion logs one presence line, marked or not, so
# the threshold can be tuned later against answer times in the transcripts.

# Test 12: a marked question while the Mac is in use (idle 30 s) goes
# straight to the user: exit 0, no state file, no trigger, and a presence
# line saying so. Catches a missing or inverted presence branch, which would
# run the panel here.
INPUT='{"tool_name":"AskUserQuestion","tool_input":{"questions":[{"question":"Pick one","options":[{"label":"Option A (Recommended)","description":"a"},{"label":"Option B","description":"b"}]}]},"session_id":"uuid-t12"}'
OUT=$(run_hook "$INPUT" "FAKE_HID_IDLE_NS=30000000000" "t12") && RC=0 || RC=$?
if [ "$RC" != "0" ]; then
    echo "FAIL test12 present: expected exit 0 (question goes to the user), got $RC"
    echo "OUT: $OUT"
    exit 1
fi
if [ -f "$TMP/claude-panel-t12.json" ]; then
    echo "FAIL test12 present: no panel state file should be written while the user is present"
    exit 1
fi
if grep -q 'event=trigger session=t12' "$CLAUDE_PANEL_TRACE_LOG"; then
    echo "FAIL test12 present: the panel was triggered while the user is present"
    exit 1
fi
if ! grep -q 'event=presence session=t12 uuid=uuid-t12 hid_idle=30 marked=1 decision=present$' "$CLAUDE_PANEL_TRACE_LOG"; then
    echo "FAIL test12 present: missing 'event=presence session=t12 uuid=uuid-t12 hid_idle=30 marked=1 decision=present' in trace log"
    cat "$CLAUDE_PANEL_TRACE_LOG"
    exit 1
fi

# Test 13: the same question after an hour without input runs the panel as
# before: exit 2, a state file, a trigger, and decision=away. Catches an
# inverted comparison that would treat a long idle as present.
INPUT='{"tool_name":"AskUserQuestion","tool_input":{"questions":[{"question":"Pick one","options":[{"label":"Option A (Recommended)","description":"a"},{"label":"Option B","description":"b"}]}]},"session_id":"uuid-t13"}'
OUT=$(run_hook "$INPUT" "FAKE_HID_IDLE_NS=3600000000000" "t13") && RC=0 || RC=$?
if [ "$RC" != "2" ]; then
    echo "FAIL test13 away: expected exit 2 (panel), got $RC"
    echo "OUT: $OUT"
    exit 1
fi
if [ ! -f "$TMP/claude-panel-t13.json" ]; then
    echo "FAIL test13 away: state file not written"
    exit 1
fi
if ! grep -q 'event=trigger session=t13' "$CLAUDE_PANEL_TRACE_LOG"; then
    echo "FAIL test13 away: missing 'event=trigger session=t13' in trace log"
    exit 1
fi
if ! grep -q 'event=presence session=t13 uuid=uuid-t13 hid_idle=3600 marked=1 decision=away$' "$CLAUDE_PANEL_TRACE_LOG"; then
    echo "FAIL test13 away: missing 'event=presence session=t13 uuid=uuid-t13 hid_idle=3600 marked=1 decision=away' in trace log"
    cat "$CLAUDE_PANEL_TRACE_LOG"
    exit 1
fi

# Test 14: idle of exactly the threshold (600 s) counts as away. Catches an
# off-by-one (<= where < belongs) that keeps the panel off at the boundary.
INPUT='{"tool_name":"AskUserQuestion","tool_input":{"questions":[{"question":"Pick one","options":[{"label":"Option A (Recommended)","description":"a"},{"label":"Option B","description":"b"}]}]},"session_id":"uuid-t14"}'
run_hook "$INPUT" "FAKE_HID_IDLE_NS=600000000000" "t14" >/dev/null 2>&1 && RC=0 || RC=$?
if [ "$RC" != "2" ]; then
    echo "FAIL test14 boundary: an idle of exactly 600 s should run the panel (exit 2), got $RC"
    exit 1
fi
if ! grep -q 'event=presence session=t14 uuid=uuid-t14 hid_idle=600 marked=1 decision=away$' "$CLAUDE_PANEL_TRACE_LOG"; then
    echo "FAIL test14 boundary: missing 'event=presence session=t14 uuid=uuid-t14 hid_idle=600 marked=1 decision=away' in trace log"
    cat "$CLAUDE_PANEL_TRACE_LOG"
    exit 1
fi

# Test 15: an idle time that is not a number reads as unknown, and the panel
# runs as it did before presence existed. Catches an unreadable value being
# treated as present (a 0 s default, or unknown routed to the user), which
# would silently skip the panel. The empty-value case is test 21.
INPUT='{"tool_name":"AskUserQuestion","tool_input":{"questions":[{"question":"Pick one","options":[{"label":"Option A (Recommended)","description":"a"},{"label":"Option B","description":"b"}]}]},"session_id":"uuid-t15"}'
run_hook "$INPUT" "FAKE_HID_MODE=garbled" "t15" >/dev/null 2>&1 && RC=0 || RC=$?
if [ "$RC" != "2" ]; then
    echo "FAIL test15 garbled: an unreadable idle time should run the panel (exit 2), got $RC"
    exit 1
fi
if ! grep -q 'event=presence session=t15 uuid=uuid-t15 hid_idle=na marked=1 decision=unknown$' "$CLAUDE_PANEL_TRACE_LOG"; then
    echo "FAIL test15 garbled: missing 'event=presence session=t15 uuid=uuid-t15 hid_idle=na marked=1 decision=unknown' in trace log"
    cat "$CLAUDE_PANEL_TRACE_LOG"
    exit 1
fi

# Test 16: no ioreg on PATH (not macOS) also reads as unknown and runs the
# panel. Catches a hook that crashes, or skips the panel, when the idle time
# cannot be read at all. /usr/bin keeps jq; ioreg lives in /usr/sbin.
NOIOREG_PATH="/usr/bin:/bin"
if (PATH="$NOIOREG_PATH"; command -v ioreg >/dev/null 2>&1); then
    echo "FAIL test16 setup: ioreg is reachable on $NOIOREG_PATH, so this test cannot simulate its absence"
    exit 1
fi
INPUT='{"tool_name":"AskUserQuestion","tool_input":{"questions":[{"question":"Pick one","options":[{"label":"Option A (Recommended)","description":"a"},{"label":"Option B","description":"b"}]}]},"session_id":"uuid-t16"}'
run_hook "$INPUT" "PATH=$NOIOREG_PATH" "t16" >/dev/null 2>&1 && RC=0 || RC=$?
if [ "$RC" != "2" ]; then
    echo "FAIL test16 no ioreg: a missing ioreg should run the panel (exit 2), got $RC"
    exit 1
fi
if ! grep -q 'event=presence session=t16 uuid=uuid-t16 hid_idle=na marked=1 decision=unknown$' "$CLAUDE_PANEL_TRACE_LOG"; then
    echo "FAIL test16 no ioreg: missing 'event=presence session=t16 uuid=uuid-t16 hid_idle=na marked=1 decision=unknown' in trace log"
    cat "$CLAUDE_PANEL_TRACE_LOG"
    exit 1
fi

# Test 17: an unmarked question is approved and still logs a presence line
# (marked=0, no decision). Catches logging only marked questions: the
# unmarked ones are most of the data for tuning the threshold.
INPUT='{"tool_name":"AskUserQuestion","tool_input":{"questions":[{"question":"Pick one","options":[{"label":"Option A","description":"a"},{"label":"Option B","description":"b"}]}]},"session_id":"uuid-t17"}'
run_hook "$INPUT" "FAKE_HID_IDLE_NS=30000000000" "t17" >/dev/null 2>&1 && RC=0 || RC=$?
if [ "$RC" != "0" ]; then
    echo "FAIL test17 unmarked: expected exit 0, got $RC"
    exit 1
fi
if ! grep -q 'event=presence session=t17 uuid=uuid-t17 hid_idle=30 marked=0 decision=-$' "$CLAUDE_PANEL_TRACE_LOG"; then
    echo "FAIL test17 unmarked: missing 'event=presence session=t17 uuid=uuid-t17 hid_idle=30 marked=0 decision=-' in trace log"
    cat "$CLAUDE_PANEL_TRACE_LOG"
    exit 1
fi

# Test 18: CLAUDE_PANEL_AWAY_AFTER moves the threshold. With 60 s, a 120 s
# idle is away and runs the panel. Catches the override being ignored: the
# 600 s default would call 120 s present.
INPUT='{"tool_name":"AskUserQuestion","tool_input":{"questions":[{"question":"Pick one","options":[{"label":"Option A (Recommended)","description":"a"},{"label":"Option B","description":"b"}]}]},"session_id":"uuid-t18"}'
run_hook "$INPUT" "FAKE_HID_IDLE_NS=120000000000 CLAUDE_PANEL_AWAY_AFTER=60" "t18" >/dev/null 2>&1 && RC=0 || RC=$?
if [ "$RC" != "2" ]; then
    echo "FAIL test18 override: with CLAUDE_PANEL_AWAY_AFTER=60 a 120 s idle should run the panel (exit 2), got $RC"
    exit 1
fi
if ! grep -q 'event=presence session=t18 uuid=uuid-t18 hid_idle=120 marked=1 decision=away$' "$CLAUDE_PANEL_TRACE_LOG"; then
    echo "FAIL test18 override: missing 'event=presence session=t18 uuid=uuid-t18 hid_idle=120 marked=1 decision=away' in trace log"
    cat "$CLAUDE_PANEL_TRACE_LOG"
    exit 1
fi

# Test 19: a non-numeric CLAUDE_PANEL_AWAY_AFTER falls back to 600 s, so a
# 120 s idle is present. Catches the value coercing to 0, which would call
# every question away and run the panel on all of them.
INPUT='{"tool_name":"AskUserQuestion","tool_input":{"questions":[{"question":"Pick one","options":[{"label":"Option A (Recommended)","description":"a"},{"label":"Option B","description":"b"}]}]},"session_id":"uuid-t19"}'
run_hook "$INPUT" "FAKE_HID_IDLE_NS=120000000000 CLAUDE_PANEL_AWAY_AFTER=ten" "t19" >/dev/null 2>&1 && RC=0 || RC=$?
if [ "$RC" != "0" ]; then
    echo "FAIL test19 bad override: CLAUDE_PANEL_AWAY_AFTER=ten should fall back to 600 s, so a 120 s idle is present (exit 0), got $RC"
    exit 1
fi
if ! grep -q 'event=presence session=t19 uuid=uuid-t19 hid_idle=120 marked=1 decision=present$' "$CLAUDE_PANEL_TRACE_LOG"; then
    echo "FAIL test19 bad override: missing 'event=presence session=t19 uuid=uuid-t19 hid_idle=120 marked=1 decision=present' in trace log"
    cat "$CLAUDE_PANEL_TRACE_LOG"
    exit 1
fi

# Test 20: the present path removes this session's leftover state file, and
# only that one. Catches a leftover surviving it (the re-entry guard would
# read the next away question, inside 600 s, as a same-flight re-issue and
# skip the panel) and a cleanup wide enough to delete another session's
# in-flight state file (the collision class test 9 guards).
STATE20="$TMP/claude-panel-t20.json"
OTHER20="$TMP/claude-panel-other-session.json"
echo '{"session_id":"t20","tool_input":{},"recommended_label":"leftover","timeout_seconds":90,"created_at":"2020-01-01T00:00:00Z"}' > "$STATE20"
echo '{"session_id":"other-session","tool_input":{},"recommended_label":"in-flight","timeout_seconds":90,"created_at":"2020-01-01T00:00:00Z"}' > "$OTHER20"
INPUT='{"tool_name":"AskUserQuestion","tool_input":{"questions":[{"question":"Pick one","options":[{"label":"Option A (Recommended)","description":"a"},{"label":"Option B","description":"b"}]}]},"session_id":"uuid-t20"}'
run_hook "$INPUT" "FAKE_HID_IDLE_NS=30000000000" "t20" >/dev/null 2>&1 && RC=0 || RC=$?
if [ "$RC" != "0" ]; then
    echo "FAIL test20 leftover: expected exit 0 (present), got $RC"
    exit 1
fi
if [ -f "$STATE20" ]; then
    echo "FAIL test20 leftover: the present path left this session's state file behind"
    exit 1
fi
if [ ! -f "$OTHER20" ]; then
    echo "FAIL test20 leftover: the present path deleted another session's state file"
    exit 1
fi
if ! grep -q 'event=presence session=t20 uuid=uuid-t20 hid_idle=30 marked=1 decision=present$' "$CLAUDE_PANEL_TRACE_LOG"; then
    echo "FAIL test20 leftover: missing 'event=presence session=t20 uuid=uuid-t20 hid_idle=30 marked=1 decision=present' in trace log"
    cat "$CLAUDE_PANEL_TRACE_LOG"
    exit 1
fi

# Test 21: ioreg output with no HIDIdleTime line reads as unknown, and the
# panel runs. Catches the empty-string-as-zero coercion: without the numeric
# check, bash arithmetic turns the empty value into 0 s, which reads as
# present and skips the panel silently.
INPUT='{"tool_name":"AskUserQuestion","tool_input":{"questions":[{"question":"Pick one","options":[{"label":"Option A (Recommended)","description":"a"},{"label":"Option B","description":"b"}]}]},"session_id":"uuid-t21"}'
run_hook "$INPUT" "FAKE_HID_MODE=missing" "t21" >/dev/null 2>&1 && RC=0 || RC=$?
if [ "$RC" != "2" ]; then
    echo "FAIL test21 no idle line: ioreg output without a HIDIdleTime line should run the panel (exit 2), got $RC"
    exit 1
fi
if ! grep -q 'event=presence session=t21 uuid=uuid-t21 hid_idle=na marked=1 decision=unknown$' "$CLAUDE_PANEL_TRACE_LOG"; then
    echo "FAIL test21 no idle line: missing 'event=presence session=t21 uuid=uuid-t21 hid_idle=na marked=1 decision=unknown' in trace log"
    cat "$CLAUDE_PANEL_TRACE_LOG"
    exit 1
fi

# Test 22: an idle time too large for bash arithmetic reads as unknown.
# Catches 64-bit wraparound: bash wraps values above 2^63, and UINT64_MAX
# nanoseconds divides to 0 s, present, which would skip the panel.
INPUT='{"tool_name":"AskUserQuestion","tool_input":{"questions":[{"question":"Pick one","options":[{"label":"Option A (Recommended)","description":"a"},{"label":"Option B","description":"b"}]}]},"session_id":"uuid-t22"}'
run_hook "$INPUT" "FAKE_HID_IDLE_NS=18446744073709551615" "t22" >/dev/null 2>&1 && RC=0 || RC=$?
if [ "$RC" != "2" ]; then
    echo "FAIL test22 overflow: an idle time of UINT64_MAX ns should run the panel (exit 2), got $RC"
    exit 1
fi
if ! grep -q 'event=presence session=t22 uuid=uuid-t22 hid_idle=na marked=1 decision=unknown$' "$CLAUDE_PANEL_TRACE_LOG"; then
    echo "FAIL test22 overflow: missing 'event=presence session=t22 uuid=uuid-t22 hid_idle=na marked=1 decision=unknown' in trace log"
    cat "$CLAUDE_PANEL_TRACE_LOG"
    exit 1
fi

# Test 23: CLAUDE_PANEL=advise keeps the panel on while the user is present.
# Advise mode exists to show the panel's commentary on every marked question
# the user answers, so presence must not skip it there; the presence line
# says decision=advise. Catches presence silently turning advise mode off.
INPUT='{"tool_name":"AskUserQuestion","tool_input":{"questions":[{"question":"Pick one","options":[{"label":"Option A (Recommended)","description":"a"},{"label":"Option B","description":"b"}]}]},"session_id":"uuid-t23"}'
run_hook "$INPUT" "FAKE_HID_IDLE_NS=30000000000 CLAUDE_PANEL=advise" "t23" >/dev/null 2>&1 && RC=0 || RC=$?
if [ "$RC" != "2" ]; then
    echo "FAIL test23 advise: advise mode should run the panel while the user is present (exit 2), got $RC"
    exit 1
fi
if [ ! -f "$TMP/claude-panel-t23.json" ]; then
    echo "FAIL test23 advise: state file not written"
    exit 1
fi
if ! grep -q 'event=presence session=t23 uuid=uuid-t23 hid_idle=30 marked=1 decision=advise$' "$CLAUDE_PANEL_TRACE_LOG"; then
    echo "FAIL test23 advise: missing 'event=presence session=t23 uuid=uuid-t23 hid_idle=30 marked=1 decision=advise' in trace log"
    cat "$CLAUDE_PANEL_TRACE_LOG"
    exit 1
fi

echo "PASS"
