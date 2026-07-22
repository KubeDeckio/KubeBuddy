---
title: Risk Paths
nav_order: 6
---

# Risk Paths

Risk Paths is KubeBuddy's correlation layer. Normal checks still report the exact Kubernetes misconfiguration. Risk Paths groups related findings into direct risk paths and, when multiple paths combine, possible chained paths.

Use it to answer three questions:

- Which risk area is affected?
- Which normal checks prove the direct risk path is active?
- What read-only validation commands can confirm the current cluster state?

## IDs

Risk Paths uses separate IDs from normal checks.

| ID family | Meaning | Example |
| --- | --- | --- |
| `RISK###` | A direct risk path from one control area. | `RISK001` Container Isolation Risk |
| `CHAIN###` | A chained path where multiple direct risks combine. | `CHAIN001` Workload to Cluster Control Path |

A `RISK###` result is not a replacement for `SEC`, `RBAC`, `NET`, `POD`, or `WRK` checks. It is a summary of the risk created when those checks appear together.

## Current Direct Paths

| ID | Name | What it means |
| --- | --- | --- |
| `RISK001` | Container Isolation Risk | Workload security findings suggest a workload could reach host or node-level control paths. |
| `RISK002` | Namespace Isolation Risk | Network and RBAC findings suggest namespace boundaries may not contain workload access. |
| `RISK003` | RBAC Privilege Risk | RBAC findings suggest identities may cross intended authorization boundaries. |
| `RISK004` | ServiceAccount Trust Risk | ServiceAccount, workload token, and RBAC findings suggest workload identity trust may be overexposed. |
| `RISK007` | Secret Exposure Risk | Secret, ConfigMap, and RBAC findings suggest credential exposure may combine with access paths. |

## Current Chains

| ID | Name | Required direct paths |
| --- | --- | --- |
| `CHAIN001` | Workload to Cluster Control Path | `RISK001` and `RISK003` |
| `CHAIN002` | Cross-Namespace Privilege Path | `RISK002` and `RISK003` |
| `CHAIN003` | ServiceAccount to Cluster Control Path | `RISK004` and `RISK003` |
| `CHAIN005` | Secret Exposure to Cluster Control Path | `RISK007` and `RISK003` |

Chained paths only appear when the required direct risk paths are active. If no chain is triggered, KubeBuddy keeps the section quiet so the report stays focused.

## Validation Proof

Each triggered direct risk path includes validation proof commands. These commands are intended to confirm the misconfiguration without modifying cluster state.

KubeBuddy validation proof should follow these rules:

- Prefer `kubectl get`, `kubectl describe`, and `kubectl auth can-i`.
- Use `kubectl apply --dry-run=server` when a manifest validation is needed.
- Do not print Secret values.
- Treat commands as proof of current state, not exploitation steps.

## Evidence

Evidence links a risk path back to normal KubeBuddy checks. For each contributing check, KubeBuddy shows the severity, finding count, and sample affected resources where available.

Start remediation from the source check. The risk path verdict explains why that individual fix matters in a wider path.

## How to Use It

1. Open **Risk Paths** in the HTML report or Headlamp plugin.
2. Review **Fix First** for the highest-impact source checks.
3. Open an active `RISK###` path to review the verdict, proof commands, evidence, and graph.
4. If **Combined Risk Paths** appears, treat those `CHAIN###` results as higher-priority because multiple direct paths are combining.
5. Fix the source checks, rerun KubeBuddy, and confirm the risk path changes from active to clear.
