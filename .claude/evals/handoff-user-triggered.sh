#!/usr/bin/env bash
# handoff-user-triggered.sh — regression eval: the handoff skill must never
# regain prose that lets the assistant invoke it on its own judgment.
#
# Failure→Eval: 2026-08-17. An orchestrator session repeatedly stopped mid-goal
# at ~40% context to propose a handoff during explicitly-requested autonomous
# runs. The cause was not a hook — context-watch.sh fires at 90% and is advisory
# — but prose. The skill's front-matter description said "Use when context
# window approaches limit" (unquantified, and a skill description sits in the
# model's context permanently), and its "When to use" list ended with "After
# completing a significant chunk of work", which every finished task satisfies.
# Handoff is now user-triggered only. This eval goes RED if that licence returns.
#
# Asserts BOTH directions on purpose. A banned-phrase blocklist alone is
# defeated by rewording — "feel free to hand off at a natural pause" passes any
# blocklist — so the required user-triggered-only text must also be PRESENT.
# Rewording the rule trips the positive assertion even when it dodges every
# negative one.
#
# Contract: exit 0 PASS / 1 FAIL / 2 SKIP; last stdout line:
#   EVAL handoff-user-triggered: PASS|FAIL|SKIP — <detail>
set -uo pipefail

NAME="handoff-user-triggered"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Subject resolves SCRIPT_DIR-relative (the repo copy) so worktree TDD exercises
# the artifact under edit rather than the deployed one. The live copy is checked
# too, which also catches deploy drift.
REPO_SKILL="${EVAL_SUBJECT_SKILL_REPO:-$SCRIPT_DIR/../skills/handoff/SKILL.md}"
LIVE_SKILL="${EVAL_SUBJECT_SKILL_LIVE:-$HOME/.claude/skills/handoff/SKILL.md}"
# The user-facing README restated the same licence in DIFFERENT WORDS ("You just
# finished a significant chunk of work"), so it dodged the SKILL.md blocklist
# entirely. Guarding one file and not its sibling doc is how a reworded licence
# survives — the README is a subject too.
REPO_README="${EVAL_SUBJECT_README_REPO:-$SCRIPT_DIR/../skills/handoff/README.md}"
LIVE_README="${EVAL_SUBJECT_README_LIVE:-$HOME/.claude/skills/handoff/README.md}"

# --- Negative: this prose licensed the self-initiated stop. ---
BANNED=(
  "Use when context window approaches limit"
  "After completing a significant chunk of work"
)

# --- Positive: the replacement rule must be present in BOTH places it matters.
# Anchoring to the file as a whole is too weak: gutting the "When to use" body
# while leaving the front-matter intact still passed a whole-file grep (caught
# by mutation testing while writing this eval). The description is what sits in
# the model's context permanently; the section is what it reads on invocation.
# Both must survive.
REQUIRED="ONLY when the user explicitly requests"
REQUIRED_SECTION="## When NOT to use"

fail() { echo "EVAL $NAME: FAIL — $1"; exit 1; }

checked=0
for pair in "repo:$REPO_SKILL" "live:$LIVE_SKILL"; do
  label="${pair%%:*}"; file="${pair#*:}"
  [ -f "$file" ] || continue

  for phrase in "${BANNED[@]}"; do
    grep -qF -- "$phrase" "$file" && \
      fail "$label reintroduced self-handoff licence \"$phrase\" ($file)"
  done
  # The front-matter description is always in context — it must carry the rule.
  desc=$(grep -m1 '^description:' "$file")
  [ -n "$desc" ] || fail "$label has no front-matter description: line ($file)"
  printf '%s' "$desc" | grep -qF -- "$REQUIRED" || \
    fail "$label description no longer carries \"$REQUIRED\" — the rule was gutted or reworded ($file)"

  # The body section is what gets read on invocation — it must survive too.
  grep -qF -- "$REQUIRED_SECTION" "$file" || \
    fail "$label is missing the \"$REQUIRED_SECTION\" section ($file)"

  checked=$((checked+1))
done

# --- README: same rule, different prose, so a distinct blocklist. ---
README_BANNED=(
  "Context is approaching the limit"
  "just finished a significant chunk of work"
)
for pair in "repo-readme:$REPO_README" "live-readme:$LIVE_README"; do
  label="${pair%%:*}"; file="${pair#*:}"
  [ -f "$file" ] || continue

  for phrase in "${README_BANNED[@]}"; do
    grep -qF -- "$phrase" "$file" && \
      fail "$label reintroduced self-handoff licence \"$phrase\" ($file)"
  done
  grep -qF -- "$REQUIRED_SECTION" "$file" || \
    fail "$label is missing the \"$REQUIRED_SECTION\" section ($file)"

  checked=$((checked+1))
done

if [ "$checked" -eq 0 ]; then
  echo "EVAL $NAME: SKIP — no handoff SKILL.md or README.md found"
  exit 2
fi

echo "EVAL $NAME: PASS — handoff is user-triggered-only in $checked subject(s)"
exit 0
