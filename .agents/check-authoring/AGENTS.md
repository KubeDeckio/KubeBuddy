# Check Authoring Agent

Use this agent when creating, updating, or reviewing KubeBuddy checks.

This repo is Go-first. Checks are authored in YAML and executed by the native Go runtime. Do not reintroduce PowerShell script-style checks.

## Scope

This agent covers:

- Kubernetes declarative checks in `checks/kubernetes/*.yaml`
- AKS best-practice checks in `checks/aks/*.yaml`
- Prometheus-backed checks
- Native-handler checks where YAML alone is not a good fit
- Recommendation content for HTML, text, JSON, and Buddy-style speech bubbles

## Current Check Model

All checks use lower-case YAML fields.

Core fields:

- `id`
- `name`
- `category`
- `section`
- `severity`
- `weight`
- `description`
- `fail_message`
- `recommendation`
- `url`

Optional fields:

- `resource_kind`
- `value`
- `operator`
- `expected`
- `when`
- `recommendation_html`
- `speech_bubble`
- `native_handler`
- `prometheus`
- `automatic_relevance`
- `automatic_scope`
- `automatic_reason`
- `automatic_admission_behavior`
- `automatic_mutation_outcome`

Validation rule from the runtime:

- every check must define at least one of:
  - `value`
  - `native_handler`
  - `prometheus`

Current standard:

- Kubernetes checks in `checks/kubernetes` now carry explicit `recommendation_html` and `speech_bubble`
- new checks should follow that standard instead of relying on runtime synthesis

## Check Types

### 1. Declarative Kubernetes checks

Use for field comparisons, presence checks, counts, membership, and simple expressions.

Put them in:

- `checks/kubernetes/operations.yaml`
- `checks/kubernetes/security.yaml`
- `checks/kubernetes/network-storage.yaml`
- `checks/kubernetes/workloads.yaml`
- `checks/kubernetes/events.yaml`

Use this shape:

```yaml
checks:
  - id: NS004
    name: Pods in Default Namespace
    section: Namespaces
    category: Operations
    resource_kind: Pod
    severity: Warning
    weight: 2
    description: Flags pods running in the default namespace.
    fail_message: Some pods are running in the default namespace.
    recommendation: Move workloads into dedicated namespaces instead of using default.
    recommendation_html: |
      <div class="recommendation-content">
        <ul>
          <li>Move application workloads out of the <code>default</code> namespace.</li>
          <li>Create dedicated namespaces per app, team, or environment.</li>
        </ul>
      </div>
    speech_bubble:
      - Move workloads out of the default namespace.
      - Use dedicated namespaces per app or team.
    url: https://kubernetes.io/docs/concepts/overview/working-with-objects/namespaces/
    value:
      path: metadata.namespace
    operator: equals
    expected: default
```

### 2. AKS best-practice checks

Use for management-plane and platform checks against the normalized AKS document.

Put them in:

- `checks/aks/best-practices.yaml`
- `checks/aks/security.yaml`
- `checks/aks/networking.yaml`
- `checks/aks/identity.yaml`
- `checks/aks/resource-management.yaml`
- `checks/aks/monitoring.yaml`
- `checks/aks/disaster-recovery.yaml`

Rules:

- keep the recommendation actionable
- include Azure CLI examples where they help
- provide `recommendation_html` when commands or multi-step guidance need better formatting
- provide `speech_bubble` when the recommendation should be shorter in the interactive TUI

Use this shape:

```yaml
checks:
  - id: AKSNET001
    name: Authorized IP Ranges Configured (Public Clusters)
    section: AKS
    category: Networking
    severity: High
    weight: 3
    description: Checks whether public AKS clusters restrict API server access using authorized IP ranges.
    fail_message: API server accepts connections from any internet IP address.
    recommendation: Configure authorized IP ranges using 'az aks update --resource-group <rg> --name <cluster> --api-server-authorized-ip-ranges <ip-ranges>'. Include management networks, CI/CD systems, and jump boxes using CIDR notation. Alternatively, migrate to a private cluster for enhanced security.
    recommendation_html: |
      <div class="recommendation-content">
        <ul>
          <li>Restrict API server access to known CIDR ranges.</li>
          <li>Use <code>az aks update --resource-group &lt;rg&gt; --name &lt;cluster&gt; --api-server-authorized-ip-ranges &lt;ip-ranges&gt;</code>.</li>
          <li>Include admin workstations, CI/CD networks, and jump hosts.</li>
          <li>For stronger isolation, move to a private cluster.</li>
        </ul>
      </div>
    speech_bubble:
      - Restrict API access with authorized IP ranges.
      - Consider a private cluster for stronger isolation.
    url: https://learn.microsoft.com/azure/aks/api-server-authorized-ip-ranges
    value:
      path: properties.apiServerAccessProfile.authorizedIPRanges
    operator: missing
```

### 3. Prometheus-backed checks

Use when the signal comes from PromQL and the runtime should execute the query in Go.

Put them in:

- `checks/kubernetes/prometheus.yaml`

Use this shape:

```yaml
checks:
  - id: PROM003
    name: High Network Receive Rate (Prometheus)
    section: Pods
    category: Performance
    resource_kind: Pod
    severity: Warning
    weight: 2
    description: Detects pods with sustained high network receive throughput.
    fail_message: Some pods show high network RX throughput.
    recommendation: Check for possible DDoS, misrouted traffic, or excessive ingress.
    recommendation_html: |
      <div class="recommendation-content">
        <ul>
          <li>Confirm whether the traffic pattern is expected.</li>
          <li>Inspect ingress, service routing, and noisy-neighbor workloads.</li>
          <li>Review whether autoscaling, rate limiting, or network policy changes are needed.</li>
        </ul>
      </div>
    speech_bubble:
      - Investigate why these pods are receiving unusually high traffic.
      - Check ingress, routing, and possible noisy-neighbor patterns.
    url: https://kubernetes.io/docs/concepts/cluster-administration/monitoring/
    prometheus:
      query: sum(rate(container_network_receive_bytes_total{pod!="",container!=""}[5m])) by (pod)
      range:
        step: 5m
        duration: 24h
    operator: greater_than
    expected: network_receive_warning
```

### 4. Native-handler checks

Use when the logic needs cross-resource joins, ownership resolution, deduplication, or other procedural work.

Rules:

- YAML still defines the user-facing metadata and recommendation content.
- Go implements the evaluator in `internal/scan/native_handlers.go`.
- Prefer reusing an existing handler if the pattern already exists.

Use this shape:

```yaml
checks:
  - id: NET001
    name: Services Without Endpoints
    section: Networking
    category: Networking
    resource_kind: Service
    severity: High
    weight: 2
    description: Identifies services that have no backing endpoints.
    fail_message: Service has no endpoints.
    recommendation: Check selectors, pod readiness, and EndpointSlice generation.
    recommendation_html: |
      <div class="recommendation-content">
        <ul>
          <li>Verify the Service selector matches live pod labels.</li>
          <li>Check pod readiness and EndpointSlice generation.</li>
          <li>Confirm the workload is healthy before sending traffic.</li>
        </ul>
      </div>
    speech_bubble:
      - This service has no endpoints.
      - Check selectors, pod readiness, and EndpointSlices.
    url: https://kubernetes.io/docs/concepts/services-networking/service/
    native_handler: NET001
    value:
      path: metadata.name
    operator: exists
```

## Recommendation Rules

Always think in three user-facing surfaces:

- `recommendation`
  - plain text for TXT/CSV/basic output
- `recommendation_html`
  - richer HTML for the report
- `speech_bubble`
  - short, direct Buddy/TUI wording

If only `recommendation` is supplied, the loader now synthesizes the other two variants. That is a fallback, not the preferred authoring standard for important checks.

Authoring standard now:

- add all three fields for new checks
- preserve and improve richer variants when editing existing checks
- use synthesis only as a temporary compatibility fallback

Prefer explicit `recommendation_html` and `speech_bubble` when:

- the check is high-value or high-frequency
- commands should render as code
- the HTML report benefits from bullets
- the TUI needs shorter wording than the full recommendation text

Recommendation writing rules:

- be specific about the action
- mention the likely remediation path, not just “investigate”
- use inline code in HTML for commands and flags
- keep speech bubbles short and conversational
- do not add fluff

## Placement Rules

- Use the existing file that matches the section/domain.
- Keep ids stable.
- Do not create duplicate checks with overlapping intent.
- Preserve current severity and weight conventions unless there is a concrete reason to change them.

## Validation Workflow

After adding or editing checks:

1. Validate the catalog:

```bash
go run ./cmd/kubebuddy checks
```

2. Run focused tests:

```bash
go test ./internal/checks ./internal/scan ./internal/reports/html ./internal/reports/output
```

3. If the check affects AKS or Prometheus reports, generate a report and inspect the relevant section.

## Review Checklist

Before finalizing a check, confirm:

- the YAML schema matches `internal/checks/spec.go`
- the check is in the correct file
- the operator and expected value are valid
- the recommendation is actionable
- HTML recommendations use proper code formatting where needed
- speech bubbles are short and useful
- the docs URL is authoritative
- tests and catalog validation pass

## Do Not

- do not add PowerShell script checks
- do not put native runtime assets under `Private/`
- do not rely on synthesized recommendation variants for important checks if the old repo already had richer wording worth preserving
- do not invent a new section or category without checking existing patterns first
