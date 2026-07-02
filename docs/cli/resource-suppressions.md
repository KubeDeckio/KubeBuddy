---
title: Resource Suppressions
---

# Resource Suppressions

KubeBuddy supports resource-level finding suppression with Kubernetes annotations. Use this when a specific resource is intentionally allowed to fail one or more checks, but you still want the check to run for the rest of the cluster.

## Annotations

Add `kubebuddy.io/ignore-checks` to the resource that produces the finding:

```yaml
metadata:
  annotations:
    kubebuddy.io/ignore-checks: "NET001,SEC001"
    kubebuddy.io/ignore-reason: "Known during migration"
    kubebuddy.io/ignore-until: "2026-08-01"
```

Supported annotations:

| Annotation | Required | Description |
| --- | --- | --- |
| `kubebuddy.io/ignore-checks` | Yes | Comma, space, or semicolon separated check IDs to suppress for this resource. Use `*` to suppress all checks for the resource. |
| `kubebuddy.io/ignore-reason` | No | Human-readable reason included in suppressed finding metadata. |
| `kubebuddy.io/ignore-until` | No | Expiry date. Use `YYYY-MM-DD` or RFC3339. Expired suppressions are ignored. |

## Workload Pods

For Pod findings created by Deployments, DaemonSets, StatefulSets, Jobs, or CronJobs, put the annotation on the Pod template so Kubernetes copies it to the created Pods:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: demo
spec:
  template:
    metadata:
      annotations:
        kubebuddy.io/ignore-checks: "SEC003,SEC020"
        kubebuddy.io/ignore-reason: "Vendor image under review"
```

## Reporting

Suppressed findings do not count toward check failure totals or health score calculations.

JSON reports include suppressed findings separately using `SuppressedTotal` and `SuppressedFindings` so suppressions remain auditable. Headlamp plugin reports include the same suppression metadata in exported JSON.

