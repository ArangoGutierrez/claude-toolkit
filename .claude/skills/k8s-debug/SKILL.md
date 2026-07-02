---
name: k8s-debug
description: Structured Kubernetes debugging for GPU workloads. Triggered by "pod crash", "CrashLoopBackOff", "OOMKilled", "GPU scheduling", or /k8s-debug
user-invocable: true
tools:
  - Read
  - Bash
  - Grep
---

# K8s Debug — GPU Workload Triage

Structured debugging workflow. Do NOT skip steps.

## Triage Order

### 1. Pod Status
```bash
kubectl get pod <name> -n <ns> -o wide
kubectl describe pod <name> -n <ns>
```
Check: phase, conditions, restart count, node, QoS class.

### 2. Events (BEFORE logs)
```bash
kubectl get events -n <ns> --sort-by=.lastTimestamp --field-selector involvedObject.name=<name>
```
Events explain why logs may be empty.

### 3. Container Logs
```bash
kubectl logs <name> -n <ns> --previous
kubectl logs <name> -n <ns> -c <init-container>
```

### 4. Node Conditions
```bash
kubectl describe node <node>
kubectl get node <node> -o jsonpath='{.status.allocatable}'
```

### 5. Resource Requests vs Allocatable
```bash
kubectl describe node <node> | grep -A 20 "Allocated resources"
```

### 6. GPU Checks
See `references/gpu-scheduling-checklist.md` for full checklist.
```bash
kubectl get nodes -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.status.allocatable.nvidia\.com/gpu}{"\n"}{end}'
kubectl get pods -n kube-system -l app=nvidia-device-plugin
```

### 7. DRA Checks
```bash
kubectl get resourceclaims -n <ns>
kubectl describe resourceclaim <name> -n <ns>
```

## Common Patterns

| Symptom | Cause | Fix |
|---------|-------|-----|
| CrashLoopBackOff + CUDA error | CUDA mismatch | Match runtime to driver |
| Pending + insufficient GPU | No capacity | Check allocatable |
| OOMKilled | GPU mem exceeded | Reduce batch size |
| Device plugin not ready | Plugin crashed | Check DaemonSet |

## Gotchas
- Check events before logs
- Verify node allocatable before assuming GPU issue
- CUDA errors often = driver/runtime mismatch, not code bugs
