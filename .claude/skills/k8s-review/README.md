# /k8s-review — Kubernetes review for YAML, Helm, API best practices, and RBAC

`/k8s-review` (also auto-triggered by phrases like "review Kubernetes manifests", "review Helm
chart", or "RBAC audit") runs static analysis, walks a Kubernetes-specific review checklist, and
reports each finding as `file:line` with a category, severity, and the checklist item that flagged
it. It flags correctness, security, and best-practice issues — not style that yamllint/CI already
handles.

## When to use it

- Before requesting human review on a PR that changes manifests, Helm charts, CRDs, or RBAC.
- When you want a review scoped to YAML correctness, Helm rendering, API best practices, and RBAC
  least-privilege rather than a general sweep.
- Say "review Kubernetes manifests", "review Helm chart", or "RBAC audit" to trigger it
  automatically, or invoke `/k8s-review` directly.
- **Not for:** YAML style/formatting nits — those are yamllint/CI's job, and this skill skips them.

## Examples

    > /k8s-review
    → Validates changed manifests (kubeconform, or a kubectl server dry-run when a cluster
      context exists), lints and renders any changed Helm charts with default and edge values,
      walks the YAML / Helm / API / RBAC checklist, then reports each finding as file:line with
      category (correctness/security/best-practice), severity (must-fix/should-fix/consider),
      and the checklist item that flagged it.

    > RBAC audit on the changed Role and its binding
    → Same checklist, scoped to the RBAC section — wildcard verbs/resources, cluster-wide secrets
      access, Role-vs-ClusterRole, and ServiceAccount hygiene.

## Dispatched mode

The `pr-review` dispatcher can seed a reviewer subagent with this skill's checklist. In that mode
the reviewer reads `references/k8s-review-checklist.md`, reviews only the changed lines in the
diff, and returns findings as structured data — `file`, NEW-file `line`, `description`,
`category`, `severity`, and `reason` (the checklist item that flagged it). It takes no external
action; findings are returned to the dispatcher as data.

## Setup

Optional tools sharpen the static-analysis step; each is guarded by `command -v` and skipped when
absent: `kubeconform` (or a `kubectl` cluster context) for manifest validation, `helm` for chart
lint/template, and `kube-linter` for extra checks. The checklist walk still runs with none installed.

## Notes

- Won't redesign charts or the API surface during a review — it flags issues within the existing
  pattern, not a rewrite.
- Verifies apiVersion deprecations against the target cluster version, not just the newest.
- Pairs well with `superpowers:requesting-code-review` once findings are fixed.
- Index: [`docs/skills-and-commands.md`](../../../docs/skills-and-commands.md).
