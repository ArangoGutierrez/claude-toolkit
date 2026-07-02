#!/bin/bash
# security-gate.sh — Block dangerous commands
# Hook: beforeShellExecution
set -euo pipefail

if ! command -v jq &>/dev/null; then
    echo '{"permission":"ask","user_message":"Security gate degraded: jq not found. Approve only if you have inspected the command yourself."}'
    exit 0
fi

input=$(cat)
cmd=$(echo "$input" | jq -r '.command // empty')

blocked=(
    "rm -rf /"
    "rm -rf ~"
    "rm -rf \$HOME"
    "rm -rf /Users"
    ":(){ :|:& };:"
    "> /dev/sda"
    "mkfs"
    "dd if=/dev"
    "dd of=/dev"
    "chmod -R 777 /"
)

for pattern in "${blocked[@]}"; do
    if echo "$cmd" | grep -qF "$pattern"; then
        echo '{"permission":"deny","user_message":"Blocked: potentially destructive command detected."}'
        exit 0
    fi
done

# rm -rf $HOME with shell expansion or expanded
if echo "$cmd" | grep -qE 'rm -rf (\$HOME|/Users/[^/ ]+)( |$|/)'; then
    echo '{"permission":"deny","user_message":"Blocked: rm -rf targeting $HOME."}'
    exit 0
fi

# Bulk Kubernetes deletion
if echo "$cmd" | grep -qE 'kubectl (delete|drain).*(--all|--force)'; then
    echo '{"permission":"ask","user_message":"Bulk kubectl delete/drain detected. Confirm namespace and scope."}'
    exit 0
fi

# Terraform destruction
if echo "$cmd" | grep -qE 'terraform destroy'; then
    echo '{"permission":"ask","user_message":"terraform destroy detected. Confirm workspace and target."}'
    exit 0
fi

# Cloud project deletion
if echo "$cmd" | grep -qE '(gcloud projects delete|aws .* delete-(stack|cluster)|az group delete)'; then
    echo '{"permission":"ask","user_message":"Cloud resource/project deletion detected."}'
    exit 0
fi

# Force-push to ANY branch (was main/master only — too narrow)
if echo "$cmd" | grep -qE 'git push.*(--force|--force-with-lease|-f($| ))'; then
    echo '{"permission":"ask","user_message":"Force push detected. Confirm target branch."}'
    exit 0
fi

# Curl-pipe-bash (supply-chain risk)
if echo "$cmd" | grep -qE '(curl|wget) [^|]*\| *(bash|sh|zsh)'; then
    echo '{"permission":"ask","user_message":"curl|bash detected. Confirm the source URL is trusted."}'
    exit 0
fi

echo '{"permission":"allow"}'
