# GPU Scheduling Checklist

## Pre-Flight
- [ ] GPU operator running: `kubectl get pods -n gpu-operator`
- [ ] Device plugin DaemonSet healthy: `kubectl get ds -n kube-system nvidia-device-plugin-daemonset`
- [ ] Nodes show GPU allocatable: `kubectl get nodes -o custom-columns=NAME:.metadata.name,GPU:.status.allocatable.nvidia\.com/gpu`

## Scheduling Failures
- [ ] Resource requests match available GPU types
- [ ] Node selectors/affinity match GPU node labels
- [ ] Tolerations for GPU node taints
- [ ] Topology manager policy compatible
- [ ] MIG profiles match requested resources

## Runtime Failures
- [ ] CUDA version: `nvidia-smi` driver >= toolkit requirement
- [ ] GPU memory fits within physical memory
- [ ] Device health: `nvidia-smi -q -d HEALTH`
- [ ] ECC errors: `nvidia-smi -q -d ECC` (uncorrectable = hardware)

## DRA
- [ ] ResourceClaim allocated
- [ ] Driver registered: `kubectl get resourceslices`
- [ ] CDI spec generated
- [ ] Container has `/dev/nvidia*`

## MIG
- [ ] MIG mode enabled: `nvidia-smi -i <gpu> --query-gpu=mig.mode.current --format=csv`
- [ ] Profiles created: `nvidia-smi mig -lgip`
- [ ] Instances created: `nvidia-smi mig -lgi`
- [ ] Device plugin configured for MIG strategy
