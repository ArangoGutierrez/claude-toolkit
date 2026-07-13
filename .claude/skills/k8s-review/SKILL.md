---
name: k8s-review
description: Kubernetes-specific code review — YAML correctness, Helm charts, API best practices, RBAC least-privilege. Triggered by "review Kubernetes manifests", "review Helm chart", "RBAC audit", or /k8s-review
user-invocable: true
tools:
  - Read
  - Grep
  - Glob
  - Bash
---

# K8s Review

Systematic Kubernetes review across manifests, Helm charts, and RBAC. Flags correctness,
security, and best-practice issues — not style that yamllint/CI already handles.

## Process

1. **Static analysis** (guarded — each tool runs only if installed):

   ```bash
   changed=$(git diff --name-only --diff-filter=d HEAD~1 -- '*.yaml' '*.yml')
   # Validate changed manifests against the K8s schema, or dry-run against a live cluster
   command -v kubeconform >/dev/null && printf '%s\n' $changed | xargs -r kubeconform -strict -summary
   command -v kubectl     >/dev/null && kubectl apply --dry-run=server -f $changed  # needs a cluster context
   # Helm charts — lint and render with default AND each values-*.yaml in the PR
   command -v helm >/dev/null && helm lint ./chart && helm template ./chart
   command -v helm >/dev/null && for v in ./chart/values-*.yaml; do helm template ./chart -f "$v"; done
   # Extra static checks when available
   command -v kube-linter >/dev/null && kube-linter lint $changed
   ```

2. **Walk checklist** (see `references/k8s-review-checklist.md`):
   - YAML correctness, Helm correctness, K8s API best practices, RBAC least-privilege

3. **Report findings:**
   - file:line for each issue (NEW-file / RIGHT-side line number)
   - Category: correctness / security / best-practice
   - Severity: must-fix / should-fix / consider
   - Reason: which checklist item flagged it, plus a suggested fix

## Dispatched mode (pr-review integration)

When invoked by the pr-review dispatcher, the reviewer reads `references/k8s-review-checklist.md`,
reviews ONLY the changed lines in the PR diff, and returns a findings list. Each finding has:

- `file` — repo-relative path
- `line` — NEW-file (RIGHT-side) line number
- `description` — 1–2 sentences
- `category` — correctness / security / best-practice
- `severity` — must-fix / should-fix / consider
- `reason` — which checklist item flagged it

Findings are returned as data. Take NO external action of any kind in dispatched mode — no
posting, commenting, submitting, or writing outside the returned findings payload.

## Scope

Changed files only unless explicitly asked for a full-tree review.

## Gotchas

- Don't flag YAML style that yamllint/CI already handles
- Don't redesign charts or the API surface during review — flag within the existing pattern
- Respect existing chart conventions (naming, structure, values layout)
- Verify apiVersion deprecations against the target cluster version, not just the newest
