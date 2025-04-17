---
title: CreatingAlerts
nav_order: 2
layout: default
---


# Creating Alerts

## Overview

Kubebuddy is a Kubernetes auditing and monitoring tool that helps identify misconfigurations, resource issues, and potential security risks in your cluster.

Alerts in Kubebuddy are generated from **checks**—rules that evaluate cluster resources and produce issues when conditions are met.

### Types of Checks

- **Script-based:** Written in PowerShell for complex checks.
- **Declarative:** YAML-based conditions for simple threshold checks.

Kubebuddy processes checks using `Invoke-yamlChecks`, which outputs results suitable for Prometheus, Grafana, or custom tools like Slack/email.

---

## Alert Types

### 1. Script-Based Checks

These use PowerShell for dynamic logic. Example checks:

- `SEC001`: Unused Secrets
- `WRK004`: Misconfigured HPAs

**Details:**

- Defined using the `Script` field
- Use `$KubeData`, `kubectl`, optional `$Namespace`, `$ExcludeNamespaces`
- Output: `[pscustomobject]` with `Namespace`, `Resource`, `Value`, `Message`

---

### 2. Declarative Checks

Simpler checks defined with `Path`, `Operator`, and `Value`.

- Example: `POD007` checks CPU usage > 80%

**Details:**

- No scripting required
- Evaluated directly by `Invoke-yamlChecks`
- Less flexible, easier to write

---

## YAML Configuration Fields

| Field             | Type           | Required | Description |
|------------------|----------------|----------|-------------|
| `ID`             | String         | Yes      | Unique check ID (e.g. `SEC001`) |
| `Name`           | String         | Yes      | Human-readable name |
| `Category`       | String         | Yes      | Category (e.g. Security, Workloads) |
| `Section`        | String         | Yes      | Subcategory or section |
| `ResourceKind`   | String         | Yes      | Kubernetes resource type |
| `Severity`       | String         | Yes      | `Low`, `Medium`, `High`, `Warning` |
| `Weight`         | Integer        | Yes      | Priority for sorting or filtering |
| `Description`    | String         | Yes      | What the check looks for |
| `FailMessage`    | String         | Yes      | Message if the check fails |
| `URL`            | String         | Yes      | Link to Kubernetes docs |
| `Operator`       | String         | No*      | Used for declarative checks only |
| `Path`           | String         | No*      | Attribute to evaluate (declarative only) |
| `Value`          | String/Number  | No*      | Threshold (declarative only) |
| `Script`         | String Block   | No*      | PowerShell code (script-based only) |
| `Recommendation.text` | String    | Yes      | Text recommendation |
| `Recommendation.html` | HTML      | Yes      | HTML-formatted guidance |
| `SpeechBubble`   | List of Strings| Yes      | Friendly messages for CLI output |

\* `Operator`, `Path`, `Value` required for declarative. `Script` required for script-based.

---

## Script Parameters

- `$KubeData`: Cached resource data
- `$Namespace`: Optional namespace scope
- `$ExcludeNamespaces`: Exclude system namespaces like `kube-system`

---

## Example: Script-Based Alert

```yaml
checks:
  - ID: "POD008"
    Name: "High Memory Usage Pods"
    Category: "Pods"
    Section: "Performance"
    ResourceKind: "Pod"
    Severity: "High"
    Weight: 3
    Description: "Detects pods with memory usage exceeding 80% of their limit."
    FailMessage: "Pod memory usage exceeds 80% of limit."
    URL: "https://kubernetes.io/docs/concepts/configuration/manage-resources-containers/"
    Recommendation:
      text: "Review pod memory usage and adjust resource limits or optimize the application."
      html: |
        <ul>
          <li>Check memory: <code>kubectl top pod -n &lt;namespace&gt;</code></li>
          <li>Adjust <code>resources.limits.memory</code></li>
          <li>Optimize app usage if needed</li>
        </ul>
    SpeechBubble:
      - "🤖 Some pods are using too much memory!"
      - "📌 Memory usage above 80% can lead to evictions."
    Script: |
      param([object]$KubeData, $Namespace, [switch]$ExcludeNamespaces)
      $pods = $KubeData?.Pods?.items ?? (kubectl get pods -A -o json | ConvertFrom-Json).items
      if ($ExcludeNamespaces) { $pods = Exclude-Namespaces -items $pods }
      if ($Namespace) { $pods = $pods | Where-Object { $_.metadata.namespace -eq $Namespace } }
      $results = @()
      foreach ($pod in $pods) {
        foreach ($container in $pod.spec.containers) {
          $limit = $container.resources.limits.memory
          if (-not $limit) { continue }
          $usage = $KubeData?.Metrics[$pod.metadata.namespace][$pod.metadata.name][$container.name].memory
          if ($usage -and $usage -gt ($limit * 0.8)) {
            $results += [pscustomobject]@{
              Namespace = $pod.metadata.namespace
              Resource  = "pod/$($pod.metadata.name)"
              Value     = "$usage/$limit"
              Message   = "Container $($container.name) memory usage exceeds 80% of limit."
            }
          }
        }
      }
      return $results
```

---

## Example: Declarative Alert

```yaml
checks:
  - ID: "POD009"
    Name: "High CPU Usage Pods"
    Category: "Pods"
    Section: "Performance"
    ResourceKind: "Pod"
    Severity: "High"
    Weight: 3
    Description: "Detects pods with CPU usage exceeding 80%."
    FailMessage: "Pod CPU usage exceeds 80%."
    URL: "https://kubernetes.io/docs/concepts/configuration/manage-resources-containers/"
    Operator: "gt"
    Path: "status.cpuUsage"
    Value: "80%"
    Recommendation:
      text: "Review pod CPU usage and adjust resource limits or optimize the application."
      html: |
        <ul>
          <li>Run <code>kubectl top pod -n &lt;namespace&gt;</code></li>
          <li>Update <code>resources.limits.cpu</code></li>
          <li>Improve app efficiency</li>
        </ul>
    SpeechBubble:
      - "🤖 Some pods are consuming excessive CPU!"
      - "📌 CPU usage above 80% can impact performance."
```

---

## Best Practices

- **Minimize noise:** Use Severity + Weight to prioritize
- **Skip system namespaces:** Use `$ExcludeNamespaces`
- **Make recommendations clear:** Use HTML + CLI-friendly messages
- **Test checks thoroughly:** Especially for edge cases
- **Use unique IDs:** Prevent collisions

---

## Integration

Use Kubebuddy output with:

- **Prometheus/Alertmanager**: Export as metrics
- **Grafana**: Visualize with dashboards
- **Slack/Discord**: Send alerts with webhooks
- **Custom scripts**: Trigger emails, PagerDuty, etc.

Run checks like:

```bash
./Invoke-yamlChecks.ps1 -CheckFiles custom.yaml
```

---

## Example Output

```json
{
  "Namespace": "default",
  "Resource": "secret/my-secret",
  "Value": "my-secret",
  "Message": "Secret appears unused across workloads, ingresses, service accounts, or CRs"
}
```

---

## Troubleshooting

| Issue                  | Fix |
|------------------------|-----|
| No alerts              | Check script logic or `$KubeData` availability |
| False positives        | Refine conditions, use `$ExcludeNamespaces` |
| YAML syntax errors     | Use a linter (`yq`, `yamllint`) |
| Integration not working| Verify output format and ingestion pipeline |

---

## Conclusion

Kubebuddy alerts help monitor your cluster by using declarative or script-based checks. Define checks, test them with `Invoke-yamlChecks`, and integrate the output with your monitoring stack.

For more help:

- [Kubebuddy GitHub](#)
