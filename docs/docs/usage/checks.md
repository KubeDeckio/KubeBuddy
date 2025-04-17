---
title: Kubernetes Checks Reference
parent: Usage
nav_order: 3
layout: default
---

# Kubernetes Checks Reference

KubeBuddy runs a suite of checks to detect issues and misconfigurations in Kubernetes clusters, powering detailed health reports. These checks help you identify problems, prioritize fixes, and maintain a robust cluster. This page lists all available checks, organized by category, with their ID, name, description, severity, and weight in the cluster health score.

## Overview

Each check evaluates a specific aspect of your cluster, such as node performance, pod stability, or security settings. The tables below group checks by category, making it easy to explore their purpose, severity (impact level), and weight (contribution to the health score).

## Checks by Category

The checks are grouped into categories based on the cluster component they target. Each table lists the **ID**, **Name**, **Description**, **Severity** (Low, Medium, High), and **Weight** (1–3) for scoring. Use these details to understand what each check does and how it affects your cluster’s health.

### Configuration
Checks for ConfigMap-related issues that may affect cluster organization or performance.

| ID      | Name                           | Description                                                                 | Severity | Weight |
|---------|--------------------------------|-----------------------------------------------------------------------------|----------|--------|
| CFG001  | Orphaned ConfigMaps            | Finds ConfigMaps not used by any pods or workloads, ripe for cleanup.       | Medium   | 1      |
| CFG002  | Duplicate ConfigMap Names      | Detects ConfigMaps with the same name in different namespaces, causing confusion. | Medium   | 1      |
| CFG003  | Large ConfigMaps               | Flags oversized ConfigMaps that may slow down cluster operations.            | Medium   | 2      |

### Events
Checks for warning events to help troubleshoot cluster issues.

| ID       | Name                           | Description                                                                 | Severity | Weight |
|----------|--------------------------------|-----------------------------------------------------------------------------|----------|--------|
| EVENT001 | Grouped Warning Events         | Summarizes recurring warning events by type to spot patterns.                | Low      | 1      |
| EVENT002 | Full Warning Event Log         | Lists all recent warning events for detailed analysis.                      | Low      | 1      |

### Jobs
Checks for issues with Kubernetes Jobs that may indicate failures or delays.

| ID      | Name                           | Description                                                                 | Severity | Weight |
|---------|--------------------------------|-----------------------------------------------------------------------------|----------|--------|
| JOB001  | Stuck Kubernetes Jobs          | Identifies jobs stuck in start or completion due to controller issues.      | High     | 2      |
| JOB002  | Failed Kubernetes Jobs         | Flags jobs that failed or hit their backoff limit, signaling errors.        | High     | 2      |

### Networking
Checks for network-related misconfigurations that could affect connectivity or security.

| ID      | Name                           | Description                                                                 | Severity | Weight |
|---------|--------------------------------|-----------------------------------------------------------------------------|----------|--------|
| NET001  | Services Without Endpoints     | Detects Services with no active endpoints, indicating potential downtime.   | Medium   | 2      |
| NET002  | Publicly Accessible Services   | Flags LoadBalancer or NodePort Services that may expose the cluster.        | High     | 2      |
| NET003  | Ingress Health Validation      | Identifies misconfigured Ingress resources causing access issues.            | Medium   | 2      |

### Nodes
Checks for node health and resource usage to ensure cluster stability.

| ID      | Name                           | Description                                                                 | Severity | Weight |
|---------|--------------------------------|-----------------------------------------------------------------------------|----------|--------|
| NODE001 | Node Readiness and Conditions  | Ensures all nodes are ready and free from critical issues.                   | High     | 3      |
| NODE002 | Node Resource Pressure         | Monitors CPU, memory, and disk usage to prevent resource shortages.         | High     | 3      |

### Namespaces
Checks for namespace configuration issues that may lead to resource misuse.

| ID      | Name                           | Description                                                                 | Severity | Weight |
|---------|--------------------------------|-----------------------------------------------------------------------------|----------|--------|
| NS001   | Empty Namespaces               | Finds namespaces with no resources, suitable for cleanup.                    | Low      | 1      |
| NS002   | Missing or Weak ResourceQuotas | Detects namespaces without quotas or with weak limits, risking overuse.     | Medium   | 2      |
| NS003   | Missing LimitRanges            | Flags namespaces without LimitRanges, allowing resource abuse.              | Medium   | 2      |

### Pods
Checks for pod-related issues that could impact application reliability.

| ID      | Name                           | Description                                                                 | Severity | Weight |
|---------|--------------------------------|-----------------------------------------------------------------------------|----------|--------|
| POD001  | Pods with High Restarts        | Flags pods restarting too often, suggesting instability.                    | Medium   | 2      |
| POD002  | Long Running Pods              | Identifies pods running longer than expected, possibly stale.                | Medium   | 2      |
| POD003  | Failed Pods                    | Detects pods in a failed state due to crashes or scheduling errors.         | High     | 3      |
| POD004  | Pending Pods                   | Finds pods stuck in pending state, often due to resource issues.            | Medium   | 2      |
| POD005  | CrashLoopBackOff Pods          | Flags pods repeatedly crashing in CrashLoopBackOff state.                   | High     | 3      |
| POD006  | Leftover Debug Pods            | Detects lingering debug containers wasting resources.                       | Medium   | 2      |
| POD007  | Container Images with Latest Tag | Flags containers using the `latest` tag, risking inconsistent deployments.  | Low      | 1      |

### RBAC
Checks for Role-Based Access Control (RBAC) issues that could affect security or access.

| ID       | Name                           | Description                                                                 | Severity | Weight |
|----------|--------------------------------|-----------------------------------------------------------------------------|----------|--------|
| RBAC001  | RBAC Misconfigurations         | Identifies RBAC errors or missing bindings disrupting access control.        | High     | 3      |
| RBAC002  | RBAC Overexposure              | Flags roles with excessive permissions, like wildcard access.                | High     | 3      |
| RBAC003  | Orphaned ServiceAccounts       | Detects unused ServiceAccounts, suitable for cleanup.                       | Medium   | 2      |
| RBAC004  | Orphaned and Ineffective Roles | Finds unused roles that can be removed safely.                              | Medium   | 2      |

### Security
Checks for security-related misconfigurations that could expose vulnerabilities.

| ID      | Name                           | Description                                                                 | Severity | Weight |
|---------|--------------------------------|-----------------------------------------------------------------------------|----------|--------|
| SEC001  | Orphaned Secrets               | Finds unused Secrets, indicating cleanup opportunities.                      | Medium   | 2      |
| SEC002  | Pods Using hostPID or hostNetwork | Flags pods using host namespaces, risking security breaches.               | High     | 3      |
| SEC003  | Pods Running as Root           | Detects containers running as root, increasing risk if compromised.         | High     | 3      |
| SEC004  | Privileged Containers          | Identifies containers with `privileged: true`, granting excessive access.   | High     | 3      |
| SEC005  | Pods Using hostIPC             | Flags pods sharing IPC with the host, exposing vulnerabilities.             | Medium   | 2      |

### Storage
Checks for storage-related issues that may indicate unused resources.

| ID      | Name                           | Description                                                                 | Severity | Weight |
|---------|--------------------------------|-----------------------------------------------------------------------------|----------|--------|
| PVC001  | Unused Persistent Volume Claims | Finds PVCs not bound or mounted, suitable for cleanup.                      | Medium   | 2      |

### Workloads
Checks for workload issues that could affect application deployment or scaling.

| ID      | Name                           | Description                                                                 | Severity | Weight |
|---------|--------------------------------|-----------------------------------------------------------------------------|----------|--------|
| WRK001  | DaemonSets Not Fully Running   | Ensures all DaemonSet pods are scheduled and ready.                         | High     | 2      |
| WRK002  | Deployment Missing Replicas    | Detects deployments with fewer replicas than desired, indicating issues.    | High     | 2      |
| WRK003  | StatefulSet Incomplete Rollout | Flags StatefulSets not fully rolled out, disrupting applications.           | Medium   | 2      |
| WRK004  | HPA Misconfiguration or Inactivity | Finds HPAs not targeting valid workloads or inactive, affecting scaling.   | Medium   | 2      |
| WRK005  | Missing Resource Requests or Limits | Flags containers without resource limits, risking contention.             | High     | 3      |
| WRK006  | PDB Coverage and Effectiveness | Checks PodDisruptionBudgets for proper coverage and settings.               | Medium   | 2      |
| WRK007  | Missing Readiness and Liveness Probes | Detects workloads without probes, risking undetected failures.            | Medium   | 2      |

## Usage Notes

- **Severity**:
  - **Low**: Minor issues, often for optimization or cleanup (e.g., empty namespaces).
  - **Medium**: Issues that could impact performance or security if ignored (e.g., unused PVCs).
  - **High**: Critical issues risking outages or vulnerabilities (e.g., privileged containers).
  - Prioritize High-severity checks to address urgent problems first.

- **Weight**:
  - Weights (1–3) determine a check’s impact on the cluster health score.
  - Higher weights (e.g., 3 for `NODE001`) reflect greater importance to cluster stability.
  - Example: Fixing `POD003` (weight 3) improves the score more than `EVENT001` (weight 1).

- **Reading Reports**:
  - **Passed** checks indicate no issues and list no items in the report.
  - **Failed** checks detail affected resources and provide fix recommendations.
  - Use the report’s URLs and suggestions to resolve issues efficiently.