#!/bin/bash
# done-hook_test.sh — integration harness for done-hook.sh
set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
HOOK="$SCRIPT_DIR/done-hook.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

PASS=0
FAIL=0

setup_fake_home() {
  local home="$1" uuid="$2"
  mkdir -p "$home/.claude/audit/session-goals"
}

fake_transcript_path() {
  local home="$1" uuid="$2"
  echo "$home/projects/fake/$uuid.jsonl"
}

assert_outcomes_entry() {
  local home="$1" uuid="$2" want_field="$3" want_value="$4"
  local log
  # shellcheck disable=SC2012  # paths are internal/controlled; ls preserves plan pattern
  log=$(ls "$home/.claude/audit/session-outcomes-"*.log 2>/dev/null | tail -1)
  if [ -z "$log" ]; then
    echo "    (no outcomes log written)"
    return 1
  fi
  grep "\"session\":\"$uuid\"" "$log" | tail -1 | \
    grep -qE "\"$want_field\":\"?$want_value\"?" || {
      echo "    (expected $want_field=$want_value in last entry; got:)"
      grep "\"session\":\"$uuid\"" "$log" | tail -1
      return 1
    }
}

# Scenario 1: no goal file → single NO_GOAL outcomes entry, silent stderr
UUID1="11111111-aaaa-bbbb-cccc-000000000001"
HOME1="$TMP/home1"
setup_fake_home "$HOME1" "$UUID1"
TRANSCRIPT1=$(fake_transcript_path "$HOME1" "$UUID1")
mkdir -p "$(dirname "$TRANSCRIPT1")"; touch "$TRANSCRIPT1"

# First fire: writes NO_GOAL
STDERR=$(echo "{\"transcript_path\":\"$TRANSCRIPT1\"}" | HOME="$HOME1" bash "$HOOK" 2>&1 >/dev/null)
if [ -n "$STDERR" ]; then
  echo "FAIL: scenario 1 first fire — expected silent stderr, got: $STDERR"; FAIL=$((FAIL+1))
elif ! assert_outcomes_entry "$HOME1" "$UUID1" "verdict" "NO_GOAL"; then
  echo "FAIL: scenario 1 first fire — outcomes entry missing NO_GOAL"; FAIL=$((FAIL+1))
else
  echo "PASS: scenario 1a — NO_GOAL entry written on first fire"; PASS=$((PASS+1))
fi

# Second fire: NO new entry (debounce on existing NO_GOAL)
ENTRIES_BEFORE=$(grep -c "\"session\":\"$UUID1\"" "$HOME1/.claude/audit/session-outcomes-"*.log 2>/dev/null || echo 0)
echo "{\"transcript_path\":\"$TRANSCRIPT1\"}" | HOME="$HOME1" bash "$HOOK" 2>/dev/null
ENTRIES_AFTER=$(grep -c "\"session\":\"$UUID1\"" "$HOME1/.claude/audit/session-outcomes-"*.log 2>/dev/null || echo 0)
if [ "$ENTRIES_BEFORE" -ne "$ENTRIES_AFTER" ]; then
  echo "FAIL: scenario 1b — debounce broken; got $ENTRIES_AFTER entries (expected $ENTRIES_BEFORE)"; FAIL=$((FAIL+1))
else
  echo "PASS: scenario 1b — debounce keeps NO_GOAL to one entry"; PASS=$((PASS+1))
fi

# Scenario 2: goal file present, 3/3 acceptance bullets match recent bash log → LIKELY_MET
UUID2="22222222-aaaa-bbbb-cccc-000000000002"
HOME2="$TMP/home2"
setup_fake_home "$HOME2" "$UUID2"
TRANSCRIPT2=$(fake_transcript_path "$HOME2" "$UUID2")
mkdir -p "$(dirname "$TRANSCRIPT2")"; touch "$TRANSCRIPT2"

# Synthesize a goal file with 3 bullets
cat > "$HOME2/.claude/audit/session-goals/$UUID2.md" <<'GOAL'
## Initial 2026-05-18T10:00:00Z
Goal: ship done-hook v1
Acceptance:
- ./done-hook_test.sh passes
- shellcheck clean
- spec committed to docs/superpowers/specs/
GOAL

# Synthesize a bash audit log with 3 matching commands, tagged with this session
# (done-hook now scopes evidence to session:<UUID> lines only — see Task 2).
BASH_LOG="$HOME2/.claude/audit/bash-commands-$(date -u +%Y-%m-%d).log"
mkdir -p "$(dirname "$BASH_LOG")"
cat > "$BASH_LOG" <<LOG
2026-05-18T14:30:00Z | session:$UUID2 | cwd:/repo | cmd: ./done-hook_test.sh
2026-05-18T14:31:00Z | session:$UUID2 | cwd:/repo | cmd: shellcheck ~/.claude/hooks/done-hook.sh
2026-05-18T14:32:00Z | session:$UUID2 | cwd:/repo | cmd: git commit -s -m "docs/superpowers/specs/ added"
LOG

# Fire the hook
echo "{\"transcript_path\":\"$TRANSCRIPT2\"}" | HOME="$HOME2" bash "$HOOK" 2>/dev/null

# Assert outcomes entry has LIKELY_MET + matched=3 + total=3
if ! assert_outcomes_entry "$HOME2" "$UUID2" "verdict" "LIKELY_MET"; then
  echo "FAIL: scenario 2 — heuristic.verdict != LIKELY_MET"; FAIL=$((FAIL+1))
elif ! grep -q "\"matched\":3" "$HOME2/.claude/audit/session-outcomes-"*.log; then
  echo "FAIL: scenario 2 — matched != 3"; FAIL=$((FAIL+1))
elif ! grep -q "\"total\":3" "$HOME2/.claude/audit/session-outcomes-"*.log; then
  echo "FAIL: scenario 2 — total != 3"; FAIL=$((FAIL+1))
else
  echo "PASS: scenario 2 — 3/3 matched -> LIKELY_MET"; PASS=$((PASS+1))
fi

# Scenario 3: 1/3 bullets match → PARTIAL
UUID3="33333333-aaaa-bbbb-cccc-000000000003"
HOME3="$TMP/home3"
setup_fake_home "$HOME3" "$UUID3"
TRANSCRIPT3=$(fake_transcript_path "$HOME3" "$UUID3")
mkdir -p "$(dirname "$TRANSCRIPT3")"; touch "$TRANSCRIPT3"
cat > "$HOME3/.claude/audit/session-goals/$UUID3.md" <<'GOAL'
## Initial 2026-05-18T10:00:00Z
Goal: ship done-hook v1
Acceptance:
- ./done-hook_test.sh passes
- shellcheck clean
- spec committed to docs/superpowers/specs/
GOAL
mkdir -p "$HOME3/.claude/audit"
cat > "$HOME3/.claude/audit/bash-commands-$(date -u +%Y-%m-%d).log" <<LOG
2026-05-18T14:30:00Z | session:$UUID3 | cwd:/repo | cmd: ./done-hook_test.sh
LOG
echo "{\"transcript_path\":\"$TRANSCRIPT3\"}" | HOME="$HOME3" bash "$HOOK" 2>/dev/null
if ! assert_outcomes_entry "$HOME3" "$UUID3" "verdict" "PARTIAL"; then
  echo "FAIL: scenario 3 — verdict != PARTIAL"; FAIL=$((FAIL+1))
elif ! grep -q "\"matched\":1" "$HOME3/.claude/audit/session-outcomes-"*.log; then
  echo "FAIL: scenario 3 — matched != 1"; FAIL=$((FAIL+1))
else
  echo "PASS: scenario 3 — 1/3 matched -> PARTIAL"; PASS=$((PASS+1))
fi

# Scenario 4: 0/3 bullets match → NO_EVIDENCE
UUID4="44444444-aaaa-bbbb-cccc-000000000004"
HOME4="$TMP/home4"
setup_fake_home "$HOME4" "$UUID4"
TRANSCRIPT4=$(fake_transcript_path "$HOME4" "$UUID4")
mkdir -p "$(dirname "$TRANSCRIPT4")"; touch "$TRANSCRIPT4"
cat > "$HOME4/.claude/audit/session-goals/$UUID4.md" <<'GOAL'
## Initial 2026-05-18T10:00:00Z
Goal: ship done-hook v1
Acceptance:
- ./done-hook_test.sh passes
- shellcheck clean
- spec committed to docs/superpowers/specs/
GOAL
mkdir -p "$HOME4/.claude/audit"
# Empty bash log
: > "$HOME4/.claude/audit/bash-commands-$(date -u +%Y-%m-%d).log"
echo "{\"transcript_path\":\"$TRANSCRIPT4\"}" | HOME="$HOME4" bash "$HOOK" 2>/dev/null
if ! assert_outcomes_entry "$HOME4" "$UUID4" "verdict" "NO_EVIDENCE"; then
  echo "FAIL: scenario 4 — verdict != NO_EVIDENCE"; FAIL=$((FAIL+1))
else
  echo "PASS: scenario 4 — 0/3 matched -> NO_EVIDENCE"; PASS=$((PASS+1))
fi

# Scenario 5: state-change debounce
# Fire twice with same goal + same bash log → only one new entry (besides any NO_GOAL/etc)
UUID5="55555555-aaaa-bbbb-cccc-000000000005"
HOME5="$TMP/home5"
setup_fake_home "$HOME5" "$UUID5"
TRANSCRIPT5=$(fake_transcript_path "$HOME5" "$UUID5")
mkdir -p "$(dirname "$TRANSCRIPT5")"; touch "$TRANSCRIPT5"
cat > "$HOME5/.claude/audit/session-goals/$UUID5.md" <<'GOAL'
## Initial 2026-05-18T10:00:00Z
Goal: ship done-hook v1
Acceptance:
- ./done-hook_test.sh passes
GOAL
mkdir -p "$HOME5/.claude/audit"
cat > "$HOME5/.claude/audit/bash-commands-$(date -u +%Y-%m-%d).log" <<LOG
2026-05-18T14:30:00Z | session:$UUID5 | cwd:/repo | cmd: ./done-hook_test.sh
LOG

# First fire
echo "{\"transcript_path\":\"$TRANSCRIPT5\"}" | HOME="$HOME5" bash "$HOOK" 2>/dev/null
COUNT1=$(grep -c "\"session\":\"$UUID5\"" "$HOME5/.claude/audit/session-outcomes-"*.log 2>/dev/null || echo 0)

# Second fire with identical state
echo "{\"transcript_path\":\"$TRANSCRIPT5\"}" | HOME="$HOME5" bash "$HOOK" 2>/dev/null
COUNT2=$(grep -c "\"session\":\"$UUID5\"" "$HOME5/.claude/audit/session-outcomes-"*.log 2>/dev/null || echo 0)

if [ "$COUNT1" -ne "$COUNT2" ]; then
  echo "FAIL: scenario 5 — debounce broken; entries grew $COUNT1 -> $COUNT2"; FAIL=$((FAIL+1))
elif [ "$COUNT1" -eq 0 ]; then
  echo "FAIL: scenario 5 — no entries written at all"; FAIL=$((FAIL+1))
else
  echo "PASS: scenario 5 — debounce holds entries at $COUNT1"; PASS=$((PASS+1))
fi

# Scenario 6: stderr evidence block on a state change
UUID6="66666666-aaaa-bbbb-cccc-000000000006"
HOME6="$TMP/home6"
setup_fake_home "$HOME6" "$UUID6"
TRANSCRIPT6=$(fake_transcript_path "$HOME6" "$UUID6")
mkdir -p "$(dirname "$TRANSCRIPT6")"; touch "$TRANSCRIPT6"
cat > "$HOME6/.claude/audit/session-goals/$UUID6.md" <<'GOAL'
## Initial 2026-05-18T10:00:00Z
Goal: ship done-hook v1
Acceptance:
- ./done-hook_test.sh passes
GOAL
mkdir -p "$HOME6/.claude/audit"
cat > "$HOME6/.claude/audit/bash-commands-$(date -u +%Y-%m-%d).log" <<LOG
2026-05-18T14:30:00Z | session:$UUID6 | cwd:/repo | cmd: ./done-hook_test.sh
LOG
STDERR6=$(echo "{\"transcript_path\":\"$TRANSCRIPT6\"}" | HOME="$HOME6" bash "$HOOK" 2>&1 >/dev/null)

# Must surface evidence; must NOT claim "accomplished"
if ! echo "$STDERR6" | grep -q "Heuristic: LIKELY_MET"; then
  echo "FAIL: scenario 6 — missing 'Heuristic: LIKELY_MET' in stderr"; FAIL=$((FAIL+1))
elif echo "$STDERR6" | grep -qi "session goal accomplished"; then
  echo "FAIL: scenario 6 — hook claimed 'Session goal accomplished' (theater)"; FAIL=$((FAIL+1))
elif ! echo "$STDERR6" | grep -q "${UUID6:0:8}"; then
  echo "FAIL: scenario 6 — UUID prefix missing from header"; FAIL=$((FAIL+1))
elif ! echo "$STDERR6" | grep -q "ship done-hook v1"; then
  echo "FAIL: scenario 6 — goal name missing from header"; FAIL=$((FAIL+1))
else
  echo "PASS: scenario 6 — evidence block surfaced; no completion claim"; PASS=$((PASS+1))
fi

# Scenario 7: performance gate — <300ms on a 1.5 MB synthetic bash log
UUID7="77777777-aaaa-bbbb-cccc-000000000007"
HOME7="$TMP/home7"
setup_fake_home "$HOME7" "$UUID7"
TRANSCRIPT7=$(fake_transcript_path "$HOME7" "$UUID7")
mkdir -p "$(dirname "$TRANSCRIPT7")"; touch "$TRANSCRIPT7"
cat > "$HOME7/.claude/audit/session-goals/$UUID7.md" <<'GOAL'
## Initial 2026-05-18T10:00:00Z
Goal: ship done-hook v1
Acceptance:
- ./done-hook_test.sh passes
- shellcheck clean
- spec committed to docs/superpowers/specs/
- plan committed to docs/superpowers/plans/
GOAL
mkdir -p "$HOME7/.claude/audit"

# Generate 1.5 MB of synthetic bash log entries, tagged with this session so the
# session-scoping filter (Task 2) doesn't just fast-path an empty tail file.
{
  for i in $(seq 1 30000); do
    printf '2026-05-18T14:30:%02dZ | session:%s | cwd:/repo | cmd: some_command_%d arg1 arg2\n' $((i % 60)) "$UUID7" "$i"
  done
} > "$HOME7/.claude/audit/bash-commands-$(date -u +%Y-%m-%d).log"
LOG_SIZE=$(wc -c < "$HOME7/.claude/audit/bash-commands-$(date -u +%Y-%m-%d).log")
echo "  (perf scenario: log size = $LOG_SIZE bytes)"

START=$(date +%s%N)
echo "{\"transcript_path\":\"$TRANSCRIPT7\"}" | HOME="$HOME7" bash "$HOOK" 2>/dev/null
END=$(date +%s%N)
ELAPSED_MS=$(( (END - START) / 1000000 ))
echo "  (perf scenario: elapsed = ${ELAPSED_MS} ms)"

if [ "$ELAPSED_MS" -ge 300 ]; then
  echo "FAIL: scenario 7 — perf budget exceeded: ${ELAPSED_MS}ms (limit 300ms)"; FAIL=$((FAIL+1))
else
  echo "PASS: scenario 7 — perf ${ELAPSED_MS}ms < 300ms"; PASS=$((PASS+1))
fi

# Scenario 8: session-scoped evidence — own-session line matches -> LIKELY_MET
# (Task 2: done-hook must only accept evidence tagged with its own session.)
UUID8="88888888-aaaa-bbbb-cccc-000000000008"
HOME8="$TMP/home8"
setup_fake_home "$HOME8" "$UUID8"
TRANSCRIPT8=$(fake_transcript_path "$HOME8" "$UUID8")
mkdir -p "$(dirname "$TRANSCRIPT8")"; touch "$TRANSCRIPT8"
# Two bullets (not one): with a single-bullet goal, done-hook's existing
# matched>=total-1 tolerance is vacuously true at total=1 (matched=0 >= 0),
# which would mask what these scenarios are meant to discriminate. See report
# for this out-of-scope heuristic note.
cat > "$HOME8/.claude/audit/session-goals/$UUID8.md" <<'GOAL'
## Initial 2026-05-18T10:00:00Z
Goal: run pkg/foo tests
Acceptance:
- go test ./pkg/foo/...
- shellcheck clean
GOAL
mkdir -p "$HOME8/.claude/audit"
cat > "$HOME8/.claude/audit/bash-commands-$(date -u +%Y-%m-%d).log" <<LOG
2026-05-18T14:30:00Z | session:$UUID8 | cwd:/repo | cmd: go test ./pkg/foo/...
2026-05-18T14:31:00Z | session:$UUID8 | cwd:/repo | cmd: shellcheck ~/.claude/hooks/done-hook.sh
LOG
echo "{\"transcript_path\":\"$TRANSCRIPT8\"}" | HOME="$HOME8" bash "$HOOK" 2>/dev/null
if ! assert_outcomes_entry "$HOME8" "$UUID8" "verdict" "LIKELY_MET"; then
  echo "FAIL: scenario 8 — own-session evidence line did not produce LIKELY_MET"; FAIL=$((FAIL+1))
elif ! grep -q "\"matched\":2" "$HOME8/.claude/audit/session-outcomes-"*.log; then
  echo "FAIL: scenario 8 — matched != 2 (own-session lines not both counted)"; FAIL=$((FAIL+1))
else
  echo "PASS: scenario 8 — own-session tagged lines matched (2/2) -> LIKELY_MET"; PASS=$((PASS+1))
fi

# Scenario 9: session scoping discriminator — identical matching line, but tagged
# with ANOTHER session's id -> must NOT count as evidence (NO_EVIDENCE).
# This is the real false positive: a bullet matching an unrelated line from
# another session's bash-commands log.
UUID9="99999999-aaaa-bbbb-cccc-000000000009"
OTHER_SESSION="ffffffff-ffff-ffff-ffff-ffffffffffff"
HOME9="$TMP/home9"
setup_fake_home "$HOME9" "$UUID9"
TRANSCRIPT9=$(fake_transcript_path "$HOME9" "$UUID9")
mkdir -p "$(dirname "$TRANSCRIPT9")"; touch "$TRANSCRIPT9"
cat > "$HOME9/.claude/audit/session-goals/$UUID9.md" <<'GOAL'
## Initial 2026-05-18T10:00:00Z
Goal: run pkg/foo tests
Acceptance:
- go test ./pkg/foo/...
- shellcheck clean
GOAL
mkdir -p "$HOME9/.claude/audit"
cat > "$HOME9/.claude/audit/bash-commands-$(date -u +%Y-%m-%d).log" <<LOG
2026-05-18T14:30:00Z | session:$OTHER_SESSION | cwd:/repo | cmd: go test ./pkg/foo/...
LOG
echo "{\"transcript_path\":\"$TRANSCRIPT9\"}" | HOME="$HOME9" bash "$HOOK" 2>/dev/null
if ! assert_outcomes_entry "$HOME9" "$UUID9" "verdict" "NO_EVIDENCE"; then
  echo "FAIL: scenario 9 — cross-session line was wrongly accepted as evidence"; FAIL=$((FAIL+1))
elif ! grep -q "\"matched\":0" "$HOME9/.claude/audit/session-outcomes-"*.log; then
  echo "FAIL: scenario 9 — matched != 0 (cross-session line leaked in as evidence)"; FAIL=$((FAIL+1))
else
  echo "PASS: scenario 9 — cross-session line excluded -> NO_EVIDENCE"; PASS=$((PASS+1))
fi

# Scenario 10: goal-tooling noise filter — a goal.sh line tagged with THIS
# session, whose command line echoes the bullet text verbatim (e.g. a kickoff
# invocation quoting the goal), must still NOT count as evidence.
UUID10="a0a0a0a0-aaaa-bbbb-cccc-00000000000a"
HOME10="$TMP/home10"
setup_fake_home "$HOME10" "$UUID10"
TRANSCRIPT10=$(fake_transcript_path "$HOME10" "$UUID10")
mkdir -p "$(dirname "$TRANSCRIPT10")"; touch "$TRANSCRIPT10"
cat > "$HOME10/.claude/audit/session-goals/$UUID10.md" <<'GOAL'
## Initial 2026-05-18T10:00:00Z
Goal: run pkg/foo tests
Acceptance:
- go test ./pkg/foo/...
- shellcheck clean
GOAL
mkdir -p "$HOME10/.claude/audit"
cat > "$HOME10/.claude/audit/bash-commands-$(date -u +%Y-%m-%d).log" <<LOG
2026-05-18T14:30:00Z | session:$UUID10 | cwd:/repo | cmd: bash ~/.claude/hooks/goal.sh "go test ./pkg/foo/..."
LOG
echo "{\"transcript_path\":\"$TRANSCRIPT10\"}" | HOME="$HOME10" bash "$HOOK" 2>/dev/null
if ! assert_outcomes_entry "$HOME10" "$UUID10" "verdict" "NO_EVIDENCE"; then
  echo "FAIL: scenario 10 — goal.sh echo of bullet text was wrongly accepted as evidence"; FAIL=$((FAIL+1))
elif ! grep -q "\"matched\":0" "$HOME10/.claude/audit/session-outcomes-"*.log; then
  echo "FAIL: scenario 10 — matched != 0 (goal.sh noise line leaked in as evidence)"; FAIL=$((FAIL+1))
else
  echo "PASS: scenario 10 — goal.sh noise line excluded -> NO_EVIDENCE"; PASS=$((PASS+1))
fi

# Scenario 11: single-bullet goal, zero matching evidence — must NOT be
# vacuously LIKELY_MET. At TOTAL=1, the old `MATCHED >= TOTAL-1` check
# reduces to `MATCHED >= 0`, which is always true, so a one-bullet goal was
# reported LIKELY_MET even with zero evidence. The bash log below is
# session-tagged (non-empty) but contains no line matching the bullet.
UUID11="b0b0b0b0-bbbb-cccc-dddd-00000000000b"
HOME11="$TMP/home11"
setup_fake_home "$HOME11" "$UUID11"
TRANSCRIPT11=$(fake_transcript_path "$HOME11" "$UUID11")
mkdir -p "$(dirname "$TRANSCRIPT11")"; touch "$TRANSCRIPT11"
cat > "$HOME11/.claude/audit/session-goals/$UUID11.md" <<'GOAL'
## Initial 2026-05-18T10:00:00Z
Goal: run pkg/foo tests
Acceptance:
- go test ./pkg/foo/...
GOAL
mkdir -p "$HOME11/.claude/audit"
cat > "$HOME11/.claude/audit/bash-commands-$(date -u +%Y-%m-%d).log" <<LOG
2026-05-18T14:30:00Z | session:$UUID11 | cwd:/repo | cmd: ls -la
LOG
echo "{\"transcript_path\":\"$TRANSCRIPT11\"}" | HOME="$HOME11" bash "$HOOK" 2>/dev/null
if ! assert_outcomes_entry "$HOME11" "$UUID11" "verdict" "NO_EVIDENCE"; then
  echo "FAIL: scenario 11 — single-bullet goal with zero evidence was not NO_EVIDENCE"; FAIL=$((FAIL+1))
elif ! grep -q "\"matched\":0" "$HOME11/.claude/audit/session-outcomes-"*.log; then
  echo "FAIL: scenario 11 — matched != 0 (single-bullet vacuous-LIKELY_MET regression)"; FAIL=$((FAIL+1))
else
  echo "PASS: scenario 11 — single-bullet goal, zero evidence -> NO_EVIDENCE (not vacuously LIKELY_MET)"; PASS=$((PASS+1))
fi

# Scenario 12: data-line shadow (the today-failure). A genuine EXECUTION line
# EARLIER and a heredoc ledger-append DATA line LATER both match the same
# bullet's anchors (here, the generic word "superpowers", which also appears in
# a `.superpowers/...` ledger path). The evidence `raw` recorded for NAT must be
# the EXECUTION line, not the later data-carrier line. The old
# `grep -F ... | tail -1` returned the data line, producing false NAT DISAGREEs.
# Discriminators: exec line carries `run-superpowers-suite.sh`; data line carries
# `progress.md`. Neither token appears in the bullet, so grepping the outcomes
# entry for them isolates which line landed in `raw`.
UUID12="c0c0c0c0-cccc-dddd-eeee-00000000000c"
HOME12="$TMP/home12"
setup_fake_home "$HOME12" "$UUID12"
TRANSCRIPT12=$(fake_transcript_path "$HOME12" "$UUID12")
mkdir -p "$(dirname "$TRANSCRIPT12")"; touch "$TRANSCRIPT12"
cat > "$HOME12/.claude/audit/session-goals/$UUID12.md" <<'GOAL'
## Initial 2026-05-18T10:00:00Z
Goal: run the superpowers suite
Acceptance:
- run superpowers eval suite
GOAL
mkdir -p "$HOME12/.claude/audit"
cat > "$HOME12/.claude/audit/bash-commands-$(date -u +%Y-%m-%d).log" <<LOG
2026-05-18T14:30:00Z | session:$UUID12 | cwd:/repo | cmd: bash run-superpowers-suite.sh
2026-05-18T14:35:00Z | session:$UUID12 | cwd:/repo | cmd: cat >> /repo/.superpowers/sdd/progress.md <<'EOF'
LOG
echo "{\"transcript_path\":\"$TRANSCRIPT12\"}" | HOME="$HOME12" bash "$HOOK" 2>/dev/null
OUTLOG12=$(ls "$HOME12/.claude/audit/session-outcomes-"*.log 2>/dev/null | tail -1)
RAW12=$(grep "\"session\":\"$UUID12\"" "$OUTLOG12" 2>/dev/null | tail -1)
if echo "$RAW12" | grep -qF "run-superpowers-suite.sh" && ! echo "$RAW12" | grep -qF "progress.md"; then
  echo "PASS: scenario 12 — execution line wins over later heredoc data line"; PASS=$((PASS+1))
else
  echo "FAIL: scenario 12 — data line shadowed the execution line in recorded evidence"; FAIL=$((FAIL+1))
  echo "    (evidence raw: $(echo "$RAW12" | grep -oE '"raw":"[^"]*"'))"
fi

# Scenario 13: tier-2 fallback — when ONLY a data-carrier line matches a bullet,
# the matcher must NOT go blind. It falls back to recording that line (matched=1),
# so the two-tier filter never makes evidence worse than the old behavior. This
# guards the fix against over-filtering. The matching anchors (`superpowers`,
# `changelog`) live in the redirect TARGET path, which is base-visible.
# Discriminator: data line carries `changelog.md`; a blind matcher would record
# matched=0.
#
# EP-F: fixture is a bare echo-append (NOT a heredoc). Body-blindness now strips
# heredoc payloads at `<<`, so a heredoc-shaped fixture here would conflate two
# concerns — the point of this scenario is the tier-2 fallback for a base-visible
# single-line data carrier, which an echo-append expresses without a heredoc body.
UUID13="d0d0d0d0-dddd-eeee-ffff-00000000000d"
HOME13="$TMP/home13"
setup_fake_home "$HOME13" "$UUID13"
TRANSCRIPT13=$(fake_transcript_path "$HOME13" "$UUID13")
mkdir -p "$(dirname "$TRANSCRIPT13")"; touch "$TRANSCRIPT13"
cat > "$HOME13/.claude/audit/session-goals/$UUID13.md" <<'GOAL'
## Initial 2026-05-18T10:00:00Z
Goal: ship the superpowers changelog
Acceptance:
- ship superpowers changelog
GOAL
mkdir -p "$HOME13/.claude/audit"
cat > "$HOME13/.claude/audit/bash-commands-$(date -u +%Y-%m-%d).log" <<LOG
2026-05-18T14:30:00Z | session:$UUID13 | cwd:/repo | cmd: echo "- shipped the release notes" >> /repo/.superpowers/sdd/changelog.md
LOG
echo "{\"transcript_path\":\"$TRANSCRIPT13\"}" | HOME="$HOME13" bash "$HOOK" 2>/dev/null
OUTLOG13=$(ls "$HOME13/.claude/audit/session-outcomes-"*.log 2>/dev/null | tail -1)
RAW13=$(grep "\"session\":\"$UUID13\"" "$OUTLOG13" 2>/dev/null | tail -1)
if echo "$RAW13" | grep -qF '"matched":1' && echo "$RAW13" | grep -qF "changelog.md"; then
  echo "PASS: scenario 13 — tier-2 fallback records the sole data-line match (not blind)"; PASS=$((PASS+1))
else
  echo "FAIL: scenario 13 — over-filtered: sole data-line match dropped (matcher went blind)"; FAIL=$((FAIL+1))
  echo "    (outcomes: $RAW13)"
fi

# Scenario 14: supersede semantics preserved — two EXECUTION lines (neither a
# data carrier) match the same bullet; the LATER run must win (a re-run
# supersedes an earlier one). Discriminators: RUN_SECOND vs RUN_FIRST arg tokens.
UUID14="e0e0e0e0-eeee-ffff-0000-00000000000e"
HOME14="$TMP/home14"
setup_fake_home "$HOME14" "$UUID14"
TRANSCRIPT14=$(fake_transcript_path "$HOME14" "$UUID14")
mkdir -p "$(dirname "$TRANSCRIPT14")"; touch "$TRANSCRIPT14"
cat > "$HOME14/.claude/audit/session-goals/$UUID14.md" <<'GOAL'
## Initial 2026-05-18T10:00:00Z
Goal: run the integration harness
Acceptance:
- run integration harness
GOAL
mkdir -p "$HOME14/.claude/audit"
cat > "$HOME14/.claude/audit/bash-commands-$(date -u +%Y-%m-%d).log" <<LOG
2026-05-18T14:30:00Z | session:$UUID14 | cwd:/repo | cmd: bash integration-harness.sh RUN_FIRST
2026-05-18T14:40:00Z | session:$UUID14 | cwd:/repo | cmd: bash integration-harness.sh RUN_SECOND
LOG
echo "{\"transcript_path\":\"$TRANSCRIPT14\"}" | HOME="$HOME14" bash "$HOOK" 2>/dev/null
OUTLOG14=$(ls "$HOME14/.claude/audit/session-outcomes-"*.log 2>/dev/null | tail -1)
RAW14=$(grep "\"session\":\"$UUID14\"" "$OUTLOG14" 2>/dev/null | tail -1)
if echo "$RAW14" | grep -qF "RUN_SECOND" && ! echo "$RAW14" | grep -qF "RUN_FIRST"; then
  echo "PASS: scenario 14 — later execution supersedes earlier among tier-1 matches"; PASS=$((PASS+1))
else
  echo "FAIL: scenario 14 — supersede semantics broken (later run did not win)"; FAIL=$((FAIL+1))
  echo "    (evidence raw: $(echo "$RAW14" | grep -oE '"raw":"[^"]*"'))"
fi

# Scenario 15: echo-append shadow (EM-F, task 99507d70). A genuine EXECUTION
# line EARLIER and a bare `echo "..." >> .../progress.md` ledger-append DATA
# line LATER both match the same bullet's anchor (generic word "superpowers",
# shared with the `.superpowers/...` ledger path). This is the live shape
# observed in session 265be882 (e.g. `echo "- ... T2 HOST LANE GREEN ..." >>
# .../progress.md`), which the HEAD-2439427 denylist (heredoc/`cat >>`/
# `tee -a`/`goal.sh` only) does NOT catch, so the echo data line still shadows
# the execution line. Discriminators: exec line carries `run-hostlane-check.sh`;
# data line carries `progress.md`. Neither token appears in the bullet.
UUID15="f0f0f0f0-ffff-0000-1111-00000000000f"
HOME15="$TMP/home15"
setup_fake_home "$HOME15" "$UUID15"
TRANSCRIPT15=$(fake_transcript_path "$HOME15" "$UUID15")
mkdir -p "$(dirname "$TRANSCRIPT15")"; touch "$TRANSCRIPT15"
cat > "$HOME15/.claude/audit/session-goals/$UUID15.md" <<'GOAL'
## Initial 2026-05-18T10:00:00Z
Goal: run the superpowers host-lane check
Acceptance:
- run superpowers host-lane check
GOAL
mkdir -p "$HOME15/.claude/audit"
cat > "$HOME15/.claude/audit/bash-commands-$(date -u +%Y-%m-%d).log" <<LOG
2026-05-18T14:30:00Z | session:$UUID15 | cwd:/repo | cmd: bash run-hostlane-check.sh
2026-05-18T14:35:00Z | session:$UUID15 | cwd:/repo | cmd: echo "- host-lane check green" >> /repo/.superpowers/sdd/progress.md
LOG
echo "{\"transcript_path\":\"$TRANSCRIPT15\"}" | HOME="$HOME15" bash "$HOOK" 2>/dev/null
OUTLOG15=$(ls "$HOME15/.claude/audit/session-outcomes-"*.log 2>/dev/null | tail -1)
RAW15=$(grep "\"session\":\"$UUID15\"" "$OUTLOG15" 2>/dev/null | tail -1)
if echo "$RAW15" | grep -qF "run-hostlane-check.sh" && ! echo "$RAW15" | grep -qF "progress.md"; then
  echo "PASS: scenario 15 — execution line wins over later echo-append data line"; PASS=$((PASS+1))
else
  echo "FAIL: scenario 15 — echo-append data line shadowed the execution line in recorded evidence"; FAIL=$((FAIL+1))
  echo "    (evidence raw: $(echo "$RAW15" | grep -oE '"raw":"[^"]*"'))"
fi

# Scenario 16: printf-append shadow, COMPOUND-command form (EM-F, task
# 99507d70). Real live sessions append via a compound command where printf is
# NOT the first token after `cmd: ` — it follows an earlier `;`-separated
# segment (session 75b1e5a9, e.g. `W=...; git ...; printf 'Task N: complete
# (...)' >> $W/.superpowers/sdd/progress.md; SK=...`). A genuine EXECUTION
# line EARLIER and this LATER mid-command printf-append DATA line share the
# bullet's anchor. This specifically exercises the command-boundary
# (`; printf`) branch of the widened denylist, not just a `cmd: printf`-start
# match — a denylist anchored ONLY on `cmd: ` command-start (the form
# suggested in the brief) would miss this exact live shape. Discriminators:
# exec line carries `run-kueue-task.sh`; data line carries `progress.md`.
# Neither token appears in the bullet.
UUID16="a1b1c1d1-a1b1-c1d1-e1f1-0000000000aa"
HOME16="$TMP/home16"
setup_fake_home "$HOME16" "$UUID16"
TRANSCRIPT16=$(fake_transcript_path "$HOME16" "$UUID16")
mkdir -p "$(dirname "$TRANSCRIPT16")"; touch "$TRANSCRIPT16"
cat > "$HOME16/.claude/audit/session-goals/$UUID16.md" <<'GOAL'
## Initial 2026-05-18T10:00:00Z
Goal: ship the superpowers kueue task
Acceptance:
- ship superpowers kueue task
GOAL
mkdir -p "$HOME16/.claude/audit"
cat > "$HOME16/.claude/audit/bash-commands-$(date -u +%Y-%m-%d).log" <<LOG
2026-05-18T14:30:00Z | session:$UUID16 | cwd:/repo | cmd: bash run-kueue-task.sh
2026-05-18T14:40:00Z | session:$UUID16 | cwd:/repo | cmd: W=/repo; printf 'Task done\n' >> \$W/.superpowers/sdd/progress.md; echo done
LOG
echo "{\"transcript_path\":\"$TRANSCRIPT16\"}" | HOME="$HOME16" bash "$HOOK" 2>/dev/null
OUTLOG16=$(ls "$HOME16/.claude/audit/session-outcomes-"*.log 2>/dev/null | tail -1)
RAW16=$(grep "\"session\":\"$UUID16\"" "$OUTLOG16" 2>/dev/null | tail -1)
if echo "$RAW16" | grep -qF "run-kueue-task.sh" && ! echo "$RAW16" | grep -qF "progress.md"; then
  echo "PASS: scenario 16 — execution line wins over later compound printf-append data line"; PASS=$((PASS+1))
else
  echo "FAIL: scenario 16 — compound printf-append data line shadowed the execution line in recorded evidence"; FAIL=$((FAIL+1))
  echo "    (evidence raw: $(echo "$RAW16" | grep -oE '"raw":"[^"]*"'))"
fi

# Scenario 17: heredoc-BODY false evidence (EP-F, critic's probe). bash-audit-log
# folds a compound/heredoc call's real newlines to literal `\n`, so a heredoc
# BODY lands inline on the SAME physical, marker-bearing line as its
# `cat > … <<EOF` command. An anchor present ONLY in that body, with NO genuine
# execution, must NOT be accepted as evidence (matched=0). Pre-fold the body sat
# on marker-less continuation lines and was invisible (matched 0/1); the fold made
# it tier-2-visible (matched 1/1) — the false-POSITIVE this fix closes.
# Discriminator anchors `provisionwidget`/`cluster` appear only AFTER `<<EOF`; the
# command part (`cat > plan.md`) carries no bullet anchor.
UUID17="0a0a0a0a-1717-1717-1717-000000000017"
HOME17="$TMP/home17"
setup_fake_home "$HOME17" "$UUID17"
TRANSCRIPT17=$(fake_transcript_path "$HOME17" "$UUID17")
mkdir -p "$(dirname "$TRANSCRIPT17")"; touch "$TRANSCRIPT17"
cat > "$HOME17/.claude/audit/session-goals/$UUID17.md" <<'GOAL'
## Initial 2026-05-18T10:00:00Z
Goal: provisionwidget the cluster
Acceptance:
- provisionwidget the cluster
GOAL
mkdir -p "$HOME17/.claude/audit"
cat > "$HOME17/.claude/audit/bash-commands-$(date -u +%Y-%m-%d).log" <<LOG
2026-05-18T14:30:00Z | session:$UUID17 | cwd:/repo | cmd: cat > plan.md <<EOF\n# provisionwidget rollout for the cluster\nEOF
LOG
echo "{\"transcript_path\":\"$TRANSCRIPT17\"}" | HOME="$HOME17" bash "$HOOK" 2>/dev/null
OUTLOG17=$(ls "$HOME17/.claude/audit/session-outcomes-"*.log 2>/dev/null | tail -1)
RAW17=$(grep "\"session\":\"$UUID17\"" "$OUTLOG17" 2>/dev/null | tail -1)
if echo "$RAW17" | grep -qF '"matched":0' && ! echo "$RAW17" | grep -qF "provisionwidget"; then
  echo "PASS: scenario 17 — heredoc-body-only anchor not accepted as evidence (matched 0)"; PASS=$((PASS+1))
else
  echo "FAIL: scenario 17 — heredoc body satisfied a false match / was recorded as evidence"; FAIL=$((FAIL+1))
  echo "    (outcomes: $RAW17)"
fi

# Scenario 18: MIXED folded line — a genuine command PLUS a trailing heredoc on
# ONE physical line (EP-F guard for the never-worse-than-base property). The
# command part must stay evidence-visible (matched=1, `widget_test.sh` recorded)
# while the heredoc BODY stays blind (its `wrote` token must NOT reach the
# recorded evidence). This discriminates body-STRIPPING from whole-line SKIPPING:
# a whole-line `<<` skip would drop this line entirely (matched=0), regressing
# below the pre-fold base where line 1 (`… widget_test.sh … <<EOF`) already
# matched.
UUID18="0b0b0b0b-1818-1818-1818-000000000018"
HOME18="$TMP/home18"
setup_fake_home "$HOME18" "$UUID18"
TRANSCRIPT18=$(fake_transcript_path "$HOME18" "$UUID18")
mkdir -p "$(dirname "$TRANSCRIPT18")"; touch "$TRANSCRIPT18"
cat > "$HOME18/.claude/audit/session-goals/$UUID18.md" <<'GOAL'
## Initial 2026-05-18T10:00:00Z
Goal: run the widget test
Acceptance:
- run widget_test.sh
GOAL
mkdir -p "$HOME18/.claude/audit"
cat > "$HOME18/.claude/audit/bash-commands-$(date -u +%Y-%m-%d).log" <<LOG
2026-05-18T14:30:00Z | session:$UUID18 | cwd:/repo | cmd: bash widget_test.sh && cat > note.md <<EOF\nwrote the note body\nEOF
LOG
echo "{\"transcript_path\":\"$TRANSCRIPT18\"}" | HOME="$HOME18" bash "$HOOK" 2>/dev/null
OUTLOG18=$(ls "$HOME18/.claude/audit/session-outcomes-"*.log 2>/dev/null | tail -1)
RAW18=$(grep "\"session\":\"$UUID18\"" "$OUTLOG18" 2>/dev/null | tail -1)
if echo "$RAW18" | grep -qF '"matched":1' && echo "$RAW18" | grep -qF "widget_test.sh" && ! echo "$RAW18" | grep -qF "wrote"; then
  echo "PASS: scenario 18 — mixed line: command part matches, heredoc body stays blind"; PASS=$((PASS+1))
else
  echo "FAIL: scenario 18 — mixed folded line regressed (command lost or body leaked)"; FAIL=$((FAIL+1))
  echo "    (outcomes: $RAW18)"
fi

echo
echo "==== Results: ${PASS} passed, ${FAIL} failed ===="
[ "$FAIL" -eq 0 ]
