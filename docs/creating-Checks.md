---
title: Creating Checks
parent: Documentation
nav_order: 4
layout: default
hide:
  - navigation
---

# Creating Checks

KubeBuddy is a Kubernetes auditing and monitoring tool that helps identify misconfigurations, performance bottlenecks, and potential risks in your cluster.

Checks are defined in YAML and evaluated by the `Invoke-yamlChecks` engine. Results can be rendered in HTML, text, or JSON reports.

## 📦 Check Types

You can author three kinds of checks:

### 1. Script-Based (PowerShell)
Use when you need full procedural logic:

- Define a `Script:` block in PowerShell.
- Receive `$KubeData`, plus `$Namespace` and `-ExcludeNamespaces` flags.
- Return either:
  - An array of PSCustomObjects, or
  - A hashtable with `{ Items = <array>; IssueCount = <int> }`.

### 2. Declarative
Field-based checks for simple path/operator/value comparisons:

- Specify `Condition`, `Operator`, and `Expected`.
- No scripting required—ideal for image-tag, label, or simple field checks.

### 3. Prometheus (NEW!)
Query Prometheus directly, with built-in threshold support:

- Define a `Prometheus:` block with your PromQL.
- Provide `Operator:` and `Expected:` to compare time-series averages.
- Honor your global defaults (e.g. `cpu_critical`) via `Get-KubeBuddyThresholds`.
- Control the look-back window via `Range.Duration` (supports `m`,`h`,`d`).

## 🧾 YAML Field Reference

| Field                          | Type           | Required  | Applies to        | Description                                                                                 |
|--------------------------------|----------------|-----------|-------------------|---------------------------------------------------------------------------------------------|
| `ID`                           | String         | ✅        | All               | Unique identifier (e.g. `POD001`, `PROM003`)                                                |
| `Name`                         | String         | ✅        | All               | Human-readable name                                                                         |
| `Category`                     | String         | ✅        | All               | Broad grouping (e.g. `Security`, `Performance`)                                             |
| `Section`                      | String         | ✅        | All               | Sub-group for report navigation (e.g. `Pods`, `Nodes`)                                      |
| `ResourceKind`                 | String         | ✅        | All               | Kubernetes kind (e.g. `Pod`, `Node`)                                                        |
| `Severity`                     | String         | ✅        | All               | `Low`, `Medium`, `High`, `Warning`, etc.                                                    |
| `Weight`                       | Integer        | ✅        | All               | Sorting/priority weight                                                                     |
| `Description`                  | String         | ✅        | All               | What the check detects                                                                      |
| `FailMessage`                  | String         | ✅        | All               | Message to show when the check finds issues                                                 |
| `URL`                          | String         | ✅        | All               | Link to related docs                                                                        |
| `SpeechBubble`                 | List[String]   | ✅        | All               | CLI-friendly messages                                                                        |
| **Declarative only**           |                |           |                   |                                                                                             |
| `Condition`                    | String         | ✅†       | Declarative       | JSON path, supports `[].` arrays (e.g. `spec.containers[].image`)                           |
| `Operator`                     | String         | ✅†       | Declarative       | `equals`, `contains`, `greater_than`, etc.                                                  |
| `Expected`                     | String/Number  | ✅†       | Declarative       | Value to compare against                                                                     |
| **Script-Based only**          |                |           |                   |                                                                                             |
| `Script`                       | PowerShell     | ✅‡       | Script-Based      | Inline PowerShell script block                                                               |
| **Prometheus only**            |                |           |                   |                                                                                             |
| `Prometheus.Query`             | String         | ✅§       | Prometheus        | PromQL query (range or instant)                                                              |
| `Prometheus.Range.Step`        | String         | ✅§       | Prometheus        | Range-vector step (e.g. `5m`)                                                                 |
| `Prometheus.Range.Duration`    | String         | ✅§       | Prometheus        | Look-back window (e.g. `30m`, `24h`, `2d`)                                                   |
| `Operator`                     | String         | ✅§       | Prometheus        | How to compare average (e.g. `greater_than`)                                                 |
| `Expected`                     | String/Number  | ✅§       | Prometheus        | Threshold value or threshold-name (e.g. `cpu_critical` or `0.8`)                             |

> † Declarative only  
> ‡ Script-Based only  
> § Prometheus only  


## 🔬 Prometheus Check Example

```yaml
checks:
  - ID: "PROM001"
    Name: "High CPU Pods (Prometheus)"
    Category: "Performance"
    Section: "Pods"
    ResourceKind: "Pod"
    Severity: "Warning"
    Weight: 3
    Description: "Checks for pods with sustained high CPU usage over the last 24 hours."
    FailMessage: "Some pods show high sustained CPU usage."
    URL: "https://kubernetes.io/docs/concepts/cluster-administration/monitoring/"
    SpeechBubble:
      - "🤖 High CPU usage detected via Prometheus!"
      - "⚠️ Might indicate a misbehaving app."
    Recommendation:
      text: "Investigate high-CPU pods; adjust limits or optimize workloads."
      html: |
        <div class="recommendation-content">
          <h4>🛠️ Investigate High CPU Pods</h4>
          <ul>
            <li>Use <code>kubectl top pod</code> for live CPU stats.</li>
            <li>Review app code or HPA settings.</li>
            <li>Consider raising CPU requests/limits or scaling out.</li>
          </ul>
        </div>
    Prometheus:
      Query:  'sum(rate(container_cpu_usage_seconds_total{container!="",pod!=""}[5m])) by (pod)'
      Range:
        Step:     "5m"
        Duration: "24h"
    Operator:   "greater_than"
    Expected:   "cpu_critical"
````

## ⚙️ Script-Based Example

```yaml
checks:
  - ID: "POD005"
    Name: "CrashLoopBackOff Pods"
    Category: "Workloads"
    Section: "Pods"
    ResourceKind: "Pod"
    Severity: "Error"
    Weight: 4
    Description: "Identifies pods stuck in CrashLoopBackOff due to repeated crashes."
    FailMessage: "Some pods are stuck restarting in CrashLoopBackOff."
    URL: "https://kubernetes.io/docs/concepts/workloads/pods/pod-lifecycle/#restart-policy"
    SpeechBubble:
      - "💥 Pods in CrashLoopBackOff!"
      - "🔍 Investigate container errors."
    Recommendation:
      text: "Check logs and fix misconfigurations."
      html: |
        <div class="recommendation-content">
          <ul>
            <li><code>kubectl logs &lt;pod&gt; -n &lt;ns&gt;</code></li>
            <li><code>kubectl describe pod &lt;pod&gt; -n &lt;ns&gt;</code></li>
          </ul>
        </div>
    Script: |
      param([object]$KubeData, $Namespace, [switch]$ExcludeNamespaces)
      $pods = if ($KubeData?.Pods) { $KubeData.Pods.items } else { (kubectl get pods -A -o json | ConvertFrom-Json).items }
      if ($ExcludeNamespaces) { $pods = Exclude-Namespaces -items $pods }
      $pods |
        Where-Object {
          $_.status.containerStatuses |
          Where-Object { $_.state.waiting.reason -eq "CrashLoopBackOff" }
        } |
        ForEach-Object {
          [PSCustomObject]@{
            Namespace = $_.metadata.namespace
            Pod       = $_.metadata.name
            Restarts  = ($_.status.containerStatuses | Measure-Object -Property restartCount -Sum).Sum
          }
        }
```


## ✅ Best Practices

* **Use meaningful IDs** (`POD001`, `PROM002`, etc.)
* Scope each check to **one responsibility**
* For Prometheus, prefer **global threshold names** (e.g. `cpu_critical`) or numeric literals
* Store your YAML in `yamlChecks/*.yaml`—no embedded JSON in PowerShell


## 📂 Folder Layout

```
yamlChecks/
├── workloads.yaml
├── security.yaml
└── prometheus.yaml
```


## 📚 Resources

* [Prometheus HTTP API](https://prometheus.io/docs/prometheus/latest/querying/api/)
* [Kubernetes Pod Lifecycle](https://kubernetes.io/docs/concepts/workloads/pods/pod-lifecycle/)
* [KubeBuddy Configuration](./kubebuddy-config.md)