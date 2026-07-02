# Container Conventions

## Image Builds
- Multi-stage builds: `builder` stage for compilation, `runtime` stage with minimal base
- Prefer distroless or UBI-micro for runtime base images
- Pin base image digests in production (`FROM image@sha256:...`), use tags in development
- `.dockerignore` mirrors `.gitignore` — no source, no secrets, no test fixtures in images

## Security
- Rootless by default: `USER nonroot:nonroot` (UID 65534)
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
