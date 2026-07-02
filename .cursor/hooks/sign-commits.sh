#!/bin/bash
# sign-commits.sh — Enforce -s -S on git commit
# Hook: beforeShellExecution
# If git commit is missing -s or -S, ask the user with the corrected command.
set -euo pipefail

if ! command -v jq &>/dev/null; then
    echo '{"permission":"allow"}'
    exit 0
fi

input=$(cat)
command=$(echo "$input" | jq -r '.command // empty')

if ! echo "$command" | grep -qE "^git commit"; then
    echo '{"permission":"allow"}'
    exit 0
fi

has_s=$(echo "$command" | grep -qE "\s-[a-zA-Z]*s[a-zA-Z]*(\s|$)|--signoff" && echo 1 || echo 0)
has_S=$(echo "$command" | grep -qE "\s-[a-zA-Z]*S[a-zA-Z]*(\s|$)|--gpg-sign" && echo 1 || echo 0)

if [ "$has_s" = "1" ] && [ "$has_S" = "1" ]; then
    echo '{"permission":"allow"}'
    exit 0
fi

add=""
[ "$has_s" = "0" ] && add="-s"
if [ "$has_S" = "0" ]; then
    if git config --get user.signingkey &>/dev/null || git config --get gpg.format &>/dev/null; then
        add="$add -S"
    fi
fi

if [ -z "$add" ]; then
    echo '{"permission":"allow"}'
    exit 0
fi

corrected="git commit ${add} ${command#git commit}"
corrected=$(echo "$corrected" | sed 's/  */ /g')

jq -n \
    --arg msg "Commit is missing signing flags. Suggested: ${corrected}" \
    --arg agent "Add ${add} flags to the git commit command for DCO/GPG signing." \
    '{"permission":"ask","user_message":$msg,"agent_message":$agent}'
