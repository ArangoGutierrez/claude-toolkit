# Security Standards

## Secrets
- No secrets in code, images, or git history. K8s Secrets or external operators only.
- If committed, rotate immediately.

## SAST & Supply Chain
- `gosec` on Go changes, `govulncheck` in CI, `trivy` on images — block on critical/high
- SBOM at build time. Sigstore/cosign for prod images. `go mod tidy` enforced.
- No `replace` in released modules. Pin deps; review major bumps.

## Containers
- No `--privileged`/`hostPID`/`hostNetwork` without documented threat model
- Drop all caps, add back only needed. Read-only rootfs where possible.

## RBAC
- Namespaced Role over ClusterRole. One SA per workload, never `default`.

## CVE Response
- Critical/high: block merge. Medium: fix in sprint. Low: fix when touching code.
