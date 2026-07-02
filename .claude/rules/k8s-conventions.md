# Kubernetes Conventions

## CRDs
- Status subresource always. Printer columns for key fields. Validation webhooks for cross-field.
- Version with `storage` annotation + conversion webhooks

## controller-runtime
- `Reconcile` returns `ctrl.Result{}` — own requeue logic. Use `SetControllerReference`.
- Finalizers for external resource cleanup. `Owns()`/`Watches()` for secondary resources.
- `Reconcile` returns quickly: requeue with backoff instead of blocking

## client-go
- Informers/listers, not direct API calls. `SharedInformerFactory`. Respect rate limiting.

## RBAC
- Namespaced `Role` over `ClusterRole`. `+kubebuilder:rbac` markers. Audit ClusterRoleBindings.

## GPU Scheduling
- Device plugin lifecycle: register, allocate, health-check
- TopologyManager hints for GPU locality. MIG profiles as separate devices.
- DRA: resource claim lifecycle, driver allocation, CDI injection

## Labels
- `app.kubernetes.io/*` conventions. Custom: `<org>.io/<purpose>`
