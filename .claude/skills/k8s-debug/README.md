# /k8s-debug — ordered triage for Kubernetes GPU workload failures

`/k8s-debug` (also triggered by phrases like "pod crash", "CrashLoopBackOff",
"OOMKilled", or "GPU scheduling") runs a fixed triage order for a failing pod
instead of jumping straight to logs: pod status, events, logs, node
conditions, resource requests, GPU/device-plugin state, then DRA resource
claims. GPU-specific failures are cross-checked against a full
scheduling/runtime/MIG checklist in `references/gpu-scheduling-checklist.md`.

## When to use it

- A pod is in `CrashLoopBackOff` or repeatedly `OOMKilled` and you need the
  root cause before changing resource limits or the image.
- A GPU pod is stuck `Pending` and you need to check node allocatable,
  device-plugin health, node selectors/taints, or MIG profiles.
- Container logs show a CUDA error and you need to rule out a driver/runtime
  version mismatch before assuming an application bug.
- A DRA `ResourceClaim` isn't allocating and you need to check the claim,
  the driver, and CDI injection in order.
- **Not for:** debugging application logic unrelated to pod scheduling or
  node resources — use `superpowers:systematic-debugging` for that.

## Examples

    > /k8s-debug training-job-7f8 is in CrashLoopBackOff in namespace ml
    → Runs `kubectl describe pod`, then events (before logs, since events
      explain why logs may be empty), then `kubectl logs --previous`, then
      node conditions and allocated-vs-requested resources. Flags the
      Common Patterns row: CrashLoopBackOff + CUDA error → driver/runtime
      mismatch, not a code bug.

    > /k8s-debug GPU pod stuck Pending
    → Skips to node conditions and GPU allocatable counts, checks the
      nvidia-device-plugin DaemonSet, then walks the pre-flight and
      scheduling-failure sections of the GPU checklist (node
      selectors/taints, MIG profile match) before ruling on the cause.

    > /k8s-debug ResourceClaim not allocating for a MIG workload
    → Runs `kubectl get/describe resourceclaims`, then the DRA section of
      the checklist: claim allocated, driver registered (`resourceslices`),
      CDI spec generated, `/dev/nvidia*` present in the container.

## Setup

Requires a working `kubectl` context for the target cluster. GPU-specific
steps (device plugin, MIG, DRA) assume the NVIDIA GPU Operator is installed;
skip those steps on clusters without GPU nodes.

## Notes

- Always checks events before logs and node allocatable before assuming a
  GPU shortage — both are common causes of chasing the wrong symptom.
- Full GPU checklist: [`references/gpu-scheduling-checklist.md`](references/gpu-scheduling-checklist.md).
- Related: `superpowers:systematic-debugging` for non-k8s bugs. Index:
  [`docs/skills-and-commands.md`](../../../docs/skills-and-commands.md).
