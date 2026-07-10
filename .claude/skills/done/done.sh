#!/bin/bash
# done.sh — /done skill orchestrator.
# Spec: docs/superpowers/specs/2026-05-18-done-hook-design.md §Component 5
set -o pipefail

SUBCOMMAND="${1:-confirm}"
shift || true
REASON="${*:-}"

# Resolve session UUID (same algorithm as goal.sh)
UUID="${CLAUDE_SESSION_ID:-}"
if [ -z "$UUID" ] || [ "$UUID" = "unknown" ]; then
  UUID="${CLAUDE_CODE_SESSION_ID:-}"   # Claude Code sets this; the old code missed it.
fi
if [ -z "$UUID" ] || [ "$UUID" = "unknown" ]; then
  if [ -f "$HOME/.claude/sessions/$$.json" ]; then
    UUID=$(jq -r '.sessionId // empty' "$HOME/.claude/sessions/$$.json" 2>/dev/null)
  fi
fi
if [ -z "$UUID" ] || [ "$UUID" = "unknown" ]; then
  # last-resort: newest session file — UNRELIABLE, may belong to a different session.
  # shellcheck disable=SC2012  # paths are internal/controlled; matches goal.sh
  SESS_FILE=$(ls -t "$HOME/.claude/sessions/"*.json 2>/dev/null | head -1)
  [ -n "$SESS_FILE" ] && UUID=$(jq -r '.sessionId // empty' "$SESS_FILE" 2>/dev/null)
  [ -n "$UUID" ] && echo "[done] WARNING: guessed session UUID from newest file ($UUID); may be the wrong session — set CLAUDE_CODE_SESSION_ID" >&2
fi
if [ -z "$UUID" ]; then
  echo "[done] ERROR: could not resolve session UUID" >&2
  exit 1
fi

GOAL_FILE="$HOME/.claude/audit/session-goals/$UUID.md"
OUTCOMES_LOG="$HOME/.claude/audit/session-outcomes-$(date -u +%Y-%m-%d).log"
TS=$(date -u +%Y-%m-%dT%H:%M:%SZ)
mkdir -p "$(dirname "$OUTCOMES_LOG")"

# Compute next seq
SEQ=1
if [ -f "$OUTCOMES_LOG" ]; then
  PREV_SEQ=$(grep "\"session\":\"$UUID\"" "$OUTCOMES_LOG" 2>/dev/null | \
             grep -oE '"seq":[0-9]+' | grep -oE '[0-9]+' | sort -n | tail -1)
  [ -n "$PREV_SEQ" ] && SEQ=$((PREV_SEQ + 1))
fi

GOAL_REL_PATH="session-goals/${UUID}.md"

json_escape() {
  python3 -c 'import json,sys; print(json.dumps(sys.stdin.read().rstrip("\n"))[1:-1])' <<< "$1"
}

append_user_entry() {
  local verdict="$1" reason="$2" evaluator="$3" nat_verdict="$4" rationale="$5"
  reason=$(json_escape "$reason")
  rationale=$(json_escape "$rationale")
  printf '{"schema":1,"session":"%s","seq":%d,"ts":"%s","goal_file":"%s","heuristic":null,"evidence":[],"state_hash":"","user":{"verdict":"%s","reason":"%s","evaluator":"%s","nat_verdict":"%s","evaluator_rationale":"%s","ts":"%s"}}\n' \
    "$UUID" "$SEQ" "$TS" "$GOAL_REL_PATH" "$verdict" "$reason" "$evaluator" "$nat_verdict" "$rationale" "$TS" \
    >> "$OUTCOMES_LOG"
}

case "$SUBCOMMAND" in
  abandon)
    [ -z "$REASON" ] && { echo "[done] ERROR: /done abandon requires <reason>" >&2; exit 1; }
    append_user_entry "ABANDONED" "$REASON" "user_only" "n/a" ""
    echo "[done] session $UUID logged as ABANDONED: $REASON" >&2
    ;;
  amend)
    [ -z "$REASON" ] && { echo "[done] ERROR: /done amend requires <text>" >&2; exit 1; }
    exec bash "$HOME/.claude/skills/goal/goal.sh" "amend $REASON"
    ;;
  override)
    [ ! -f "$GOAL_FILE" ] && { echo "[done] ERROR: no goal file for $UUID; run /goal first" >&2; exit 1; }
    OVERRIDE_REASON="${REASON:-user override}"
    append_user_entry "MET" "$OVERRIDE_REASON" "user_override" "OVERRIDDEN" ""
    echo "[done] session $UUID recorded as MET via user override (reason: $OVERRIDE_REASON) — outcomes log: $OUTCOMES_LOG" >&2
    ;;
  confirm|"")
    [ ! -f "$GOAL_FILE" ] && { echo "[done] ERROR: no goal file for $UUID; run /goal first" >&2; exit 1; }
    STANZA=$(awk '/^## /{buf=""} {buf=buf $0 "\n"} END{printf "%s", buf}' "$GOAL_FILE")
    EVAL_DIR="$(dirname "$(readlink -f "$0" 2>/dev/null || echo "$0")")"
    PY="${CLAUDE_TOOL_PYTHON:-${CLAUDE_PANEL_PYTHON:-python3.12}}"
    EVIDENCE_JSON='[]'
    if [ -f "$OUTCOMES_LOG" ]; then
      EVIDENCE_JSON=$(grep "\"session\":\"$UUID\"" "$OUTCOMES_LOG" | \
                      DONE_EVAL_DIR="$EVAL_DIR" "$PY" -c '
import json, os, sys
sys.path.insert(0, os.environ["DONE_EVAL_DIR"])
import eval as e
print(json.dumps(e.collect_evidence(sys.stdin.read())))
' 2>/dev/null || echo '[]')
    fi

    PAYLOAD=$(python3 -c '
import json, os, sys
payload = {"goal_stanza": sys.argv[1], "evidence": json.loads(sys.argv[2]), "user_claim": "MET"}
model = os.environ.get("DONE_NAT_MODEL")
if model:
    payload["model"] = model
print(json.dumps(payload))' "$STANZA" "$EVIDENCE_JSON")

    if [ -n "${DONE_FAKE_NAT_RESPONSE:-}" ]; then
      RESULT=$(DONE_EVAL_DIR="$EVAL_DIR" "$PY" -c '
import json, os, sys
sys.path.insert(0, os.environ["DONE_EVAL_DIR"])
import eval as e
def fake(prompt, model, **k): return os.environ["DONE_FAKE_NAT_RESPONSE"].replace("{MODEL}", model)
e._invoke_nat = fake
payload = json.loads(sys.stdin.read())
kwargs = {"model": payload["model"]} if "model" in payload else {}
print(json.dumps(e.evaluate(payload["goal_stanza"], payload["evidence"], payload["user_claim"], **kwargs)))
' <<< "$PAYLOAD")
    else
      CLAUDE_ROOT="$(cd "$EVAL_DIR/../.." && pwd)"
      RESULT=$(echo "$PAYLOAD" | PYTHONPATH="${PYTHONPATH:-$CLAUDE_ROOT}" "$PY" "$EVAL_DIR/eval.py")
    fi

    NAT_VERDICT=$(echo "$RESULT" | jq -r '.verdict')
    NAT_RATIONALE=$(echo "$RESULT" | jq -r '.rationale')

    case "$NAT_VERDICT" in
      AGREE)
        append_user_entry "MET" "NAT agree" "nat-goal-evaluator" "AGREE" "$NAT_RATIONALE"
        echo "[done] Session goal accomplished. NAT: $NAT_RATIONALE" >&2
        ;;
      DISAGREE)
        echo "[done] NAT disagreed: $NAT_RATIONALE" >&2
        echo "[done] No verdict written. Run /done override [reason] to record MET over NAT's objection, or /done amend / abandon." >&2
        ;;
      INSUFFICIENT_EVIDENCE)
        echo "[done] NAT: insufficient evidence: $NAT_RATIONALE" >&2
        echo "[done] No verdict written. Provide explicit verdict via /done override [reason], /done abandon <reason>, or refine the goal." >&2
        ;;
      ERROR|*)
        append_user_entry "MET" "user claim; NAT unavailable" "user_only" "ERROR" "$NAT_RATIONALE"
        echo "[done] NAT unavailable ($NAT_RATIONALE); logged user claim as MET." >&2
        ;;
    esac
    ;;
  *)
    echo "[done] ERROR: unknown subcommand '$SUBCOMMAND'" >&2
    exit 1
    ;;
esac
