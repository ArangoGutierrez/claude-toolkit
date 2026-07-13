# K8s Review Checklist

Each item is: what to look for + why it bites + what right looks like. Categories map to the
finding schema — correctness, security, best-practice. Flag changed lines only unless asked
for a full-tree review.

## 1. YAML correctness

- [ ] **Norway problem / barewords** — unquoted `on/off/yes/no/y/n/true/false` and bare
  country codes coerce to booleans (`country: NO` becomes `false`, `enabled: yes` becomes `true`).
  Right: quote any string scalar that could read as a bool/number — `country: "NO"`.
- [ ] **Leading-zero / octal file modes** — `defaultMode: 0644` is octal (420 decimal) under
  YAML 1.1 but some parsers read it as the integer `644`. Right: use the explicit decimal the
  field expects (`defaultMode: 420`) or confirm your parser's YAML version and quote intentionally.
- [ ] **Numeric-looking strings** — versions and dotted/colon values silently coerce:
  `version: 1.10` becomes the float `1.1`; strict YAML 1.1 parsers may read `10:00` as a base-60
  int. Right: quote them — `version: "1.10"`.
- [ ] **String vs int for ports/UIDs** — `containerPort`/`runAsUser` are ints; `targetPort` may
  be an int or a named port string. A named `targetPort: web` must match a declared port `name`.
  Type drift fails schema validation. Right: match the field's declared type.
- [ ] **Duplicate map keys** — a repeated key (two `env:` blocks, a key set twice): strict tooling
  (kubectl, yamllint) errors, but non-strict go-yaml paths are last-wins and silently drop the
  earlier value. Right: one key per map; catch with `yamllint`/`kubeconform`.
- [ ] **List-item de-indentation** — sequence items at the parent key's column are valid YAML (the
  ubiquitous `containers:` / `- name:` style); the silent-drop trap is a field de-indented out of
  its list element, which escapes the item and becomes a sibling of the parent map. Right: keep
  every field of an item aligned inside its `-` block; catch misalignment with `yamllint`.
- [ ] **Anchors/aliases and merge keys** — `&a`/`*a` share a mutable node and `<<` merge keys are
  not expanded by all K8s tooling; an edit through one alias mutates every user. Right: prefer
  explicit duplication, or Helm/Kustomize for reuse.
- [ ] **Multi-doc separators** — a missing or extra `---` merges two resources into one document
  (only the last applies) or yields an empty doc. Right: exactly one `---` between resources.
- [ ] **Block scalars / trailing whitespace** — trailing spaces inside a `|` block become part of
  the value and break scripts and ConfigMap data; `|` keeps newlines, `>` folds, `|-`/`>-` strip
  the final newline. Right: pick the indicator deliberately and strip trailing whitespace.
- [ ] **null vs empty vs omitted** — `field:` (null), `field: ""` (empty string), and omitting the
  field differ: `null` can wipe a server default while `""` sets an empty value. Right: omit
  optional fields rather than setting them to `null`.

## 2. Helm correctness

- [ ] **Renders under all shipped values** — `helm lint` and `helm template` must succeed with
  default values AND each `values-*.yaml` in the PR. Right: a template that only renders under one
  values file is a latent break; render every combination the PR ships.
- [ ] **quote/squote on string values** — an unquoted `{{ .Values.x }}` that yields `on`, `y`, or
  `123` re-triggers the Norway/int-coercion problem in the rendered YAML. Right: `{{ .Values.x |
  quote }}` for string-typed fields.
- [ ] **nindent vs indent** — `indent` does not add a leading newline; used after a `key:` on its
  own line it collapses the block onto the key. Right: `nindent N` when the value follows a bare
  key line; `indent` only mid-line.
- [ ] **toYaml without nindent** — `{{ toYaml .Values.resources }}` unindented breaks block
  structure. Right: `{{- toYaml .Values.resources | nindent N }}`.
- [ ] **default for optional, required for mandatory** — optional values need a fallback and
  mandatory ones must fail fast. Right: `{{ .Values.image.tag | default .Chart.AppVersion }}` and
  `{{ required "image.repository is required" .Values.image.repository }}`.
- [ ] **Whitespace chomping** — over-chomping with `{{-`/`-}}` eats the newline between list items
  or map keys and merges them; under-chomping leaves blank lines that break block scalars. Right:
  verify the rendered output, not just the template source.
- [ ] **tpl on user input** — `tpl` executes template syntax found in values, so untrusted values
  become template injection. Right: only `tpl` chart-controlled, trusted strings.
- [ ] **Immutable selector vs templated labels** — `Deployment`/`StatefulSet`
  `.spec.selector.matchLabels` is immutable after create; if it is templated from a value that also
  feeds pod labels, changing that value makes upgrades fail with a selector-immutable error. Right:
  keep selector labels stable and separate from mutable labels.
- [ ] **version vs appVersion discipline** — bump chart `version` on every chart change; bump
  `appVersion` when the shipped app image changes. Right: template changes without a `version` bump
  break CD that keys on chart version.
- [ ] **Hook weights and delete policies** — `helm.sh/hook-weight` orders hooks (lower first); a
  missing `hook-delete-policy` leaves one-shot Jobs lingering. Right: set weights and
  `before-hook-creation`/`hook-succeeded` deliberately.
- [ ] **values.schema.json drift** — when the chart ships a schema, new values must be represented
  in it or `helm lint` rejects them. Right: update schema and `values.yaml` together.

## 3. K8s API best practices

- [ ] **Deprecated/removed apiVersions** — verify against the TARGET cluster version, not the
  newest: `extensions/v1beta1`, `policy/v1beta1` PodDisruptionBudget, and `batch/v1beta1` CronJob
  are removed in modern clusters. Right: use the apiVersion the deployment target still serves.
- [ ] **Probes present and distinct** — `livenessProbe` restarts a hung container, `readinessProbe`
  gates traffic, `startupProbe` grants slow-start grace. Sharing one endpoint/timing for liveness
  and readiness causes restart storms under load. Right: define them separately with distinct thresholds.
- [ ] **Requests AND limits** — requests drive scheduling, limits cap usage. Missing requests risks
  noisy-neighbor eviction; missing limits risks node pressure. Right: set both, or document why a
  resource is intentionally unbounded.
- [ ] **securityContext hardening** — `runAsNonRoot: true`, `readOnlyRootFilesystem: true`,
  `allowPrivilegeEscalation: false`, `capabilities.drop: ["ALL"]` with explicit add-back, and
  `seccompProfile.type: RuntimeDefault`. Right: absent fields mean the container runs with excess
  privilege — set them.
- [ ] **Image tags pinned** — no `:latest` (non-reproducible, silent drift). Right: a semver tag in
  dev and a digest (`image@sha256:...`) for production.
- [ ] **PodDisruptionBudget for multi-replica** — without a PDB a node drain can evict every replica
  at once. Right: set `minAvailable`/`maxUnavailable` for any workload claiming availability.
- [ ] **Spread where HA is claimed** — replicas that all schedule onto one node are not highly
  available. Right: `topologySpreadConstraints` or pod anti-affinity across nodes/zones.
- [ ] **Standard labels** — `app.kubernetes.io/name`, `/instance`, `/version`, `/component`,
  `/part-of`, `/managed-by` enable tooling interop and selection. Right: apply the recommended set.
- [ ] **Deployment selector immutability** — `.spec.selector` cannot change after create; the API
  server rejects the update, and shipping it requires a manual delete+recreate. Right: flag any
  selector mutation.
- [ ] **CRD hygiene** — status subresource enabled, printer columns for key fields, `storage: true`
  on exactly one version, and a conversion webhook when multiple versions coexist. Right: a CRD
  missing these is hard to operate and upgrade.
- [ ] **Controller conventions** — `Reconcile` returns quickly and requeues instead of blocking; set
  owner references so garbage collection cascades; use finalizers for external-resource cleanup.
  Right: a blocking reconcile or missing owner refs leaks resources.

## 4. RBAC least-privilege

- [ ] **Wildcards = must-fix** — `*` in `verbs`, `resources`, or `apiGroups` grants far more than
  needed and auto-includes future resources. Right: enumerate exactly the verbs and resources the
  workload uses.
- [ ] **escalate / bind / impersonate** — these verbs let a subject grant privileges beyond the role
  itself. Right: require an explicit, documented justification; default to omitting them.
- [ ] **Cluster-wide secrets access = must-fix** — `get/list/watch` on `secrets` at cluster scope
  exposes every token and credential in the cluster. Right: scope to a namespace and named secrets,
  or use a bound/projected ServiceAccount token.
- [ ] **Role over ClusterRole** — use a namespaced `Role` unless the resource is genuinely
  cluster-scoped (nodes, PVs, CRDs) or the workload spans namespaces. Right: prefer the smallest
  blast radius; a ClusterRole is cluster-wide.
- [ ] **Dedicated ServiceAccount** — the `default` SA is shared and often over-bound. Right: one
  ServiceAccount per workload, bound to only what it needs; never rely on `default`.
- [ ] **ClusterRoleBinding audit** — a binding to a broad ClusterRole (`cluster-admin`, `edit`)
  grants cluster-wide. Right: prefer a RoleBinding that scopes a ClusterRole to a single namespace;
  audit who binds to what.
- [ ] **Aggregated ClusterRoles** — a role with `aggregationRule` inherits every labeled
  ClusterRole's rules, so the empty shell understates its power. Right: review the aggregate effect,
  not just the definition.
- [ ] **nonResourceURLs** — these grant access to non-resource endpoints (`/metrics`, `/healthz`,
  `/version`). Right: scrutinize wildcards here as closely as resource rules.

## Gotchas

- Don't flag YAML style already handled by yamllint/CI (indentation width, quote style, line length).
- Don't redesign charts or the API surface during review — flag issues within the existing pattern.
- Changed files only unless the review explicitly asks for a full-tree pass.
- Respect existing chart conventions (naming, values layout, templating idioms) rather than imposing new ones.
