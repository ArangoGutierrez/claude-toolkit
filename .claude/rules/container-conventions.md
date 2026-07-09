# Container Conventions

## Image Builds
- Multi-stage builds: `builder` stage for compilation, `runtime` stage with minimal base
- Prefer distroless or UBI-micro for runtime base images
- Pin base image digests in production (`FROM image@sha256:...`), use tags in development
- `.dockerignore` mirrors `.gitignore` — no source, no secrets, no test fixtures in images

## Security
- Rootless by default: run as a non-root user — distroless `nonroot` is UID 65532 (UID 65534 is `nobody`); never run as UID 0
- No `--privileged`, no `hostPID`, no `hostNetwork` unless documented with justification
- Deliver secrets via K8s Secrets or external secret operators; do not embed them in images
- Scan images with `trivy` before push; block on critical/high CVEs

## GPU Images
- NVIDIA base images: distinguish `cuda:X.Y-devel` (build) vs `cuda:X.Y-runtime` (deploy)
- CUDA toolkit in builder only; runtime image gets just CUDA runtime libs
- Test GPU access: `nvidia-smi` must work inside the container

## OCI Standards
- Add OCI labels for provenance: `org.opencontainers.image.source`, `org.opencontainers.image.revision`
- Use `org.opencontainers.image.created` with build timestamp
- Generate SBOM at build time (Syft or buildx `--sbom`)
- Verify a referenced image/registry path actually resolves before relying on it (registry API or HTTP HEAD); never assume an OCI path or URL exists from pattern-matching alone

## systemd Units (incl. quadlets)
- Exec lines reference a bare path to an installed script — never inline
  `sh -c 'a && b && c'` chains: the unit-file lexer can truncate after the
  first command and still report exit 0 (silent half-run).
- `RuntimeDirectory=` re-applies the unit's exec ownership (its User=) on
  EVERY command spawn — never chown it for another uid from ExecStartPre;
  create and own such dirs in the prep script itself and clean up via
  `ExecStopPost=/bin/rm -rf …` (bare argv, nothing to misparse).
- Prep scripts end with an owner/mode self-verify so a partial run can
  never exit 0.
