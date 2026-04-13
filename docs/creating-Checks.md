---
title: Creating Checks
layout: default
hide:
  - navigation
---

# Creating Checks

KubeBuddy checks are now authored for the native Go runtime.

The supported model is:

- YAML for check metadata and rule definitions
- Prometheus blocks for metric-driven checks
- native Go handlers for checks that need procedural logic

The old PowerShell `Script:` model is no longer part of the supported runtime.

## Check Locations

Use these directories:

- Kubernetes checks: `checks/kubernetes/*.yaml`
- AKS checks: `checks/aks/*.yaml`

The CLI defaults already point at those paths.

## Supported Check Styles

### Declarative checks

Use declarative checks when the result can be derived from:

- resource fields
- simple comparisons
- array membership
- counts
- existence checks

These are the preferred default.

### Prometheus checks

Use a `prometheus:` block when the check is based on PromQL and threshold comparison.

These are still YAML-defined, but the runtime executes the Prometheus query in Go.

### Native handler checks

Use `native_handler:` when the logic is too complex for a clean declarative rule.

Examples:

- cross-resource correlation
- workload ownership resolution
- storage/network consistency checks
- richer rightsizing or recommendation logic

In that model:

- YAML still defines the check id, name, severity, docs, and report content
- Go implements the handler logic

## YAML Shape

Current native checks use lower-case field names.

Common fields:

| Field | Required | Notes |
| --- | --- | --- |
| `id` | yes | Unique check id such as `SEC004` or `AKSSEC001` |
| `name` | yes | Human-readable check name |
| `category` | yes | Broad grouping used in reports |
| `section` | yes | Report/tab grouping |
| `resource_kind` | yes for Kubernetes checks | Resource type used by the runtime |
| `severity` | yes | Example values: `Low`, `Warning`, `High` |
| `weight` | yes | Used in report weighting and ordering |
| `description` | yes | What the check detects |
| `fail_message` | yes | Message shown when findings exist |
| `recommendation` | yes | Plain-text remediation guidance |
| `recommendation_html` | optional | Rich HTML recommendation block |
| `url` | yes | Primary docs link |
| `value` | usually | Path or expression to evaluate |
| `operator` | usually | Comparison operator |
| `expected` | usually | Comparison target |
| `native_handler` | optional | Use for procedural Go checks |
| `prometheus` | optional | Use for Prometheus-backed checks |

## Declarative Example

```yaml
checks:
  - id: POD004
    name: Pending Pods
    section: Pods
    category: Workloads
    resource_kind: Pod
    severity: Warning
    weight: 3
    description: Detects pods stuck in a Pending state due to scheduling or dependency issues.
    fail_message: Some pods are stuck in Pending.
    recommendation: Inspect scheduling constraints, missing dependencies, and cluster capacity.
    url: https://kubernetes.io/docs/concepts/workloads/pods/pod-lifecycle/#pod-phase
    value:
      path: status.phase
    operator: not_equals
    expected: Pending
```

## Prometheus Example

```yaml
checks:
  - id: PROM001
    name: High CPU Pods (Prometheus)
    category: Performance
    section: Pods
    resource_kind: Pod
    severity: Warning
    weight: 3
    description: Checks for pods with sustained high CPU usage over the last 24 hours.
    fail_message: Some pods show high sustained CPU usage.
    recommendation: Investigate high CPU usage and adjust requests, limits, or scaling.
    url: https://kubernetes.io/docs/concepts/cluster-administration/monitoring/
    prometheus:
      query: sum(rate(container_cpu_usage_seconds_total{container!="",pod!=""}[5m])) by (pod)
      range:
        step: 5m
        duration: 24h
    operator: greater_than
    expected: cpu_critical
```

## Native Handler Example

```yaml
checks:
  - id: NET001
    name: Services Without Endpoints
    category: Networking
    section: Networking
    resource_kind: Service
    severity: High
    weight: 2
    description: Identifies services that have no backing endpoints.
    fail_message: Service has no endpoints.
    recommendation: Check selectors, pod readiness, and EndpointSlice generation.
    url: https://kubernetes.io/docs/concepts/services-networking/service/
    native_handler: NET001
    value:
      path: metadata.name
    operator: exists
```

The YAML keeps the user-facing definition. The runtime resolves `NET001` in Go.

## Operators

The native evaluator supports operators such as:

- `equals`
- `not_equals`
- `contains`
- `not_contains`
- `exists`
- `missing`
- `greater_than`
- `greater_than_or_equal`
- `less_than`
- `less_than_or_equal`
- `matches`
- `not_matches`

Complex rules can also use composed values such as:

- `all`
- `any`
- `coalesce`
- `count_where`

For examples, inspect the existing catalog under:

- `checks/kubernetes`
- `checks/aks`

## When To Use A Native Handler

Use a handler when YAML would become harder to understand than the code.

Good reasons:

- joining multiple resource types
- resolving owners or related workloads
- deduplicating compound findings
- formatting special item payloads
- complex AKS or Prometheus logic

Do not force every check into a large declarative expression just because it is possible.

## Authoring Rules

- Keep one check focused on one concern.
- Keep ids stable once published.
- Prefer declarative YAML first.
- Use `recommendation_html` only when the richer layout is useful in the HTML report.
- Keep URLs authoritative and current.
- Match existing naming and severity patterns in the catalog.

## Validation

Useful validation commands:

```bash
go run ./cmd/kubebuddy checks
```

```bash
go test ./internal/checks ./internal/scan
```

To inspect the AKS catalog:

```bash
go run ./cmd/kubebuddy checks --checks-dir checks/aks
```

## Related Docs

- [Checks](cli/checks.md)
- [Config File](cli/kubebuddy-config.md)
- [Native CLI Usage](cli/native-cli-usage.md)
