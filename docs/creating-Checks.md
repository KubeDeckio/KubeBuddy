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

Checks are defined using YAML and are evaluated by the `Invoke-yamlChecks` engine. These checks output results that can be shown in HTML reports or integrated with systems like Slack or Prometheus/Grafana.


## 📦 Check Types

There are three main types of checks you can define:

### 1. Script-Based (PowerShell)
Use for complex, custom logic that can’t be handled declaratively.

- Define logic in the `Script:` field
- Uses `$KubeData` and optional params like `$Namespace` and `$ExcludeNamespaces`

### 2. Declarative
Use for simple field-based condition checks.

- Uses `Operator`, `Path`, and `Value`
- No scripting required
- Great for image tag, label, and field value checks

### 3. Prometheus (NEW!)
Query Prometheus directly (supports Azure Monitor, Bearer, Basic, or anonymous mode).

- Uses `Type: Prometheus`
- Supports instant and range queries
- Applies thresholds to Prometheus metrics
- Output includes per-target violations


## 🧾 YAML Field Reference

| Field                  | Type           | Required | Description |
|------------------------|----------------|----------|-------------|
| `ID`                   | String         | ✅       | Unique identifier (e.g. `POD001`) |
| `Name`                 | String         | ✅       | Descriptive name |
| `Category`             | String         | ✅       | Broad grouping (e.g. Security) |
| `Section`              | String         | ✅       | Logical sub-group |
| `ResourceKind`         | String         | ✅*      | Kubernetes resource kind (or "Prometheus" for Prometheus checks) |
| `Severity`             | String         | ✅       | `Low`, `Medium`, `High`, `Warning`, etc. |
| `Weight`               | Integer        | ✅       | Affects priority and sorting |
| `Description`          | String         | ✅       | What this check identifies |
| `FailMessage`          | String         | ✅       | Message to show when check fails |
| `URL`                  | String         | ✅       | Link to related documentation |
| `SpeechBubble`         | List[String]   | ✅       | CLI-friendly output messages |
| `Recommendation.text`  | String         | ✅       | Recommendation for CLI |
| `Recommendation.html`  | HTML Block     | ✅       | Detailed HTML for web report |
| `Script`               | PowerShell     | ✅†      | Required for script-based checks |
| `Path`                 | String         | ✅†      | Field path (declarative only) |
| `Operator`             | String         | ✅†      | e.g., `equals`, `contains`, `greater_than`, etc. |
| `Value`                | String/Number  | ✅†      | Expected value (declarative only) |
| `Type`                 | String         | ✅‡      | Set to `"Prometheus"` for Prometheus-based checks |
| `Query`                | String         | ✅‡      | PromQL query |
| `Threshold.type`       | String         | ✅‡      | Threshold operator (e.g. `greater_than`) |
| `Threshold.value`      | Number/String  | ✅‡      | Threshold value or reference |
| `TargetLabel`          | String         | Optional| Label to group results by (e.g., `node`, `instance`) |

> † Required for **script-based**
>
> ‡ Required for **Prometheus** checks


## 🔬 Prometheus Check Example

```yaml
checks:
  - ID: "PROM001"
    Name: "High CPU Usage (Node)"
    Category: "Prometheus"
    Section: "Performance"
    ResourceKind: "Prometheus"
    Type: "Prometheus"
    Severity: "Warning"
    Weight: 3
    Description: "Alerts if average node CPU usage is over 80% in the past 1h."
    FailMessage: "Some nodes exceed 80% CPU usage."
    URL: "https://prometheus.io/docs/prometheus/latest/querying/"
    TargetLabel: "node"
    Query: |
      100 - (avg by(node) (rate(node_cpu_seconds_total{mode="idle"}[1h])) * 100)
    Threshold:
      type: "greater_than"
      value: 80
    Recommendation:
      text: "Review node workloads and consider scaling."
      html: |
        <ul>
          <li>Check pod distribution across nodes</li>
          <li>Use <code>kubectl top nodes</code> to verify</li>
          <li>Consider horizontal scaling or taints</li>
        </ul>
    SpeechBubble:
      - "🤖 Some nodes are running hot on CPU."
      - "📌 Try scaling up or balancing pods."
```


## ⚙️ Script-Based Example

```yaml
checks:
  - ID: "POD008"
    Name: "High Memory Usage Pods"
    Category: "Pods"
    Section: "Performance"
    ResourceKind: "Pod"
    Severity: "High"
    Weight: 3
    Description: "Detects pods using >80% of memory limit."
    FailMessage: "Pod memory usage exceeds 80% of limit."
    URL: "https://kubernetes.io/docs/concepts/configuration/manage-resources-containers/"
    Recommendation:
      text: "Review pod memory limits and actual usage."
      html: |
        <ul>
          <li>Use <code>kubectl top pod -n &lt;namespace&gt;</code></li>
          <li>Adjust resource requests/limits</li>
        </ul>
    SpeechBubble:
      - "🤖 Some pods are using too much memory!"
      - "📌 Could lead to evictions or instability."
    Script: |
      param([object]$KubeData, $Namespace, [switch]$ExcludeNamespaces)
      $pods = $KubeData.Pods.items
      $results = @()
      foreach ($pod in $pods) {
        foreach ($c in $pod.spec.containers) {
          $used = [int]($KubeData.Metrics[$pod.metadata.namespace][$pod.metadata.name][$c.name].memory)
          $limit = [int]$c.resources.limits.memory
          if ($limit -and $used -gt ($limit * 0.8)) {
            $results += [pscustomobject]@{
              Namespace = $pod.metadata.namespace
              Resource  = $pod.metadata.name
              Value     = "$used / $limit"
              Message   = "Memory usage exceeds 80% for $($c.name)"
            }
          }
        }
      }
      return $results
```


## ✅ Best Practices

* Use meaningful IDs like `POD001`, `NET005`, `PROM002`
* Keep checks scoped to a single responsibility
* Use `$ExcludeNamespaces` to skip system namespaces
* Store queries or scripts in YAML — no hardcoded data in PowerShell
* Use `Threshold.valueFrom` to reference global thresholds


## 📂 Folder Structure

```
yamlChecks/
  ├── workloads.yaml
  ├── security.yaml
  └── prometheus.yaml
```


## 🧪 Test Your Checks

Run locally with:

```powershell
Invoke-yamlChecks -KubeData $data -Html
```


## 🛠 Troubleshooting

| Problem                 | Tip                                                            |
| ----------------------- | -------------------------------------------------------------- |
| Prometheus query empty  | Validate the `Query:` syntax manually                          |
| Script fails            | Try running your PowerShell separately                         |
| Declarative logic fails | Check your `Path` and value types                              |
| Check not showing       | Make sure file ends in `.yaml` and is in `yamlChecks/` folder  |
| Prometheus auth issues  | Ensure `$env:PROMETHEUS_URL` and auth mode (e.g. Azure) is set |


## 📚 Resources

* [Prometheus Query Language](https://prometheus.io/docs/prometheus/latest/querying/)
* [Azure Monitor Prometheus Docs](https://learn.microsoft.com/en-us/azure/azure-monitor/)
* [Kubernetes API Reference](https://kubernetes.io/docs/reference/generated/kubernetes-api/)

Kubebuddy checks are flexible and powerful — use script, YAML, or PromQL to validate and visualize the health of your cluster with ease.
