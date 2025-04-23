---
title: Kubernetes Checks Reference
parent: Usage
nav_order: 3
layout: default
---

# Kubernetes Checks Reference

KubeBuddy runs checks to find issues and misconfigurations in your Kubernetes cluster. These checks power the health report and help you fix problems, reduce risk, and improve stability. This page lists all checks by category, with their ID, name, description, severity, and score weight.

## Overview

Each check targets a specific part of your cluster—nodes, pods, workloads, security, etc. Tables group checks by category. Use them to understand what’s being evaluated, how serious the issue is, and how much it affects your overall health score.

## Section Mapping: YAML to Report Tabs

Each check includes a `Section` value in its YAML. This table shows how those values map to the tabs in the HTML report:

| YAML Section Value      | Report Tab Name         |
|-------------------------|-------------------------|
| `Nodes`                 | Nodes                   |
| `Namespaces`            | Namespaces              |
| `Workloads`             | Workloads               |
| `Pods`                  | Pods                    |
| `Jobs`                  | Jobs                    |
| `Networking`            | Networking              |
| `Storage`               | Storage                 |
| `Configuration`         | Configuration Hygiene   |
| `Security`              | Security                |
| `Kubernetes Events`     | Kubernetes Events       |

Use this when defining or updating checks to control where they appear in the report.

## Checks by Category

Each table includes:

- **ID** – Identifier for the check
- **Name** – Short label
- **Description** – What it checks and why it matters
- **Severity** – Low / Medium / High
- **Weight** – Contribution to health score


### Configuration

| ID     | Name                        | Description                                                                 | Severity | Weight |
|--------|-----------------------------|-----------------------------------------------------------------------------|----------|--------|
| CFG001 | Orphaned ConfigMaps         | Unused ConfigMaps that can be removed.                                     | Medium   | 1      |
| CFG002 | Duplicate ConfigMap Names   | Same name used in different namespaces. Creates confusion.                 | Medium   | 1      |
| CFG003 | Large ConfigMaps            | Oversized ConfigMaps that may affect performance.                          | Medium   | 2      |

### Events

| ID       | Name                    | Description                                                   | Severity | Weight |
|----------|-------------------------|---------------------------------------------------------------|----------|--------|
| EVENT001 | Grouped Warning Events  | Groups frequent warnings to help identify recurring issues.   | Low      | 1      |
| EVENT002 | Full Warning Event Log  | Lists all recent warning events.                              | Low      | 1      |

### Jobs

| ID     | Name                  | Description                                                             | Severity | Weight |
|--------|-----------------------|-------------------------------------------------------------------------|----------|--------|
| JOB001 | Stuck Kubernetes Jobs | Jobs stuck in start or finish states due to controller issues.          | High     | 2      |
| JOB002 | Failed Kubernetes Jobs| Jobs that failed or hit backoff limits.                                | High     | 2      |

### Networking

| ID     | Name                        | Description                                                           | Severity | Weight |
|--------|-----------------------------|-----------------------------------------------------------------------|----------|--------|
| NET001 | Services Without Endpoints  | No active endpoints; likely causes downtime.                          | Medium   | 2      |
| NET002 | Publicly Accessible Services| LoadBalancer/NodePort services that expose the cluster.              | High     | 2      |
| NET003 | Ingress Health Validation   | Misconfigured Ingress resources affecting access.                    | Medium   | 2      |
| NET004 | Namespace Missing Network Policy | Detects namespaces that have running pods but no associated NetworkPolicy resources. This could allow unrestricted pod-to-pod communication. | Medium | 3    |

### Nodes

| ID      | Name                      | Description                                                 | Severity | Weight |
|---------|---------------------------|-------------------------------------------------------------|----------|--------|
| NODE001 | Node Readiness            | Nodes not ready or with critical conditions.                | High     | 3      |
| NODE002 | Node Resource Pressure    | High usage of CPU, memory, or disk.                         | High     | 3      |

### Namespaces

| ID     | Name                         | Description                                                     | Severity | Weight |
|--------|------------------------------|-----------------------------------------------------------------|----------|--------|
| NS001  | Empty Namespaces             | No resources; can be cleaned up.                                | Low      | 1      |
| NS002  | Weak or Missing ResourceQuotas | No quotas or soft limits; risks resource overuse.             | Medium   | 2      |
| NS003  | Missing LimitRanges          | No resource caps; enables excessive use.                        | Medium   | 2      |

### Pods

| ID      | Name                           | Description                                                         | Severity | Weight |
|---------|--------------------------------|---------------------------------------------------------------------|----------|--------|
| POD001  | High Restart Count             | Pods restarting too often. Suggests instability.                    | Medium   | 2      |
| POD002  | Long Running Pods              | Pods running longer than expected.                                  | Medium   | 2      |
| POD003  | Failed Pods                    | Pods in failed state.                                               | High     | 3      |
| POD004  | Pending Pods                   | Pods stuck in pending. Usually resource-related.                    | Medium   | 2      |
| POD005  | CrashLoopBackOff               | Frequent crashing and restart loops.                               | High     | 3      |
| POD006  | Leftover Debug Pods            | Debug containers not cleaned up. Wastes resources.                  | Medium   | 2      |
| POD007  | Images Using `latest` Tag      | Risk of inconsistent deployments due to floating tags.             | Low      | 1      |

### RBAC

| ID       | Name                           | Description                                                          | Severity | Weight |
|----------|--------------------------------|----------------------------------------------------------------------|----------|--------|
| RBAC001  | Misconfigurations              | Missing or incorrect role bindings.                                 | High     | 3      |
| RBAC002  | Overexposed Roles              | Roles with overly broad permissions.                                | High     | 3      |
| RBAC003  | Orphaned ServiceAccounts       | Not in use. Can be removed.                                         | Medium   | 2      |
| RBAC004  | Ineffective Roles              | Unused roles cluttering the system.                                 | Medium   | 2      |

### Security

| ID      | Name                              | Description                                                                                           | Severity | Weight |
|---------|-----------------------------------|-------------------------------------------------------------------------------------------------------|----------|--------|
| SEC001  | Orphaned Secrets                  | Not used. Safe to delete.                                                                             | Medium   | 2      |
| SEC002  | hostPID/hostNetwork Usage         | Shared host namespaces increase risk.                                                                | High     | 3      |
| SEC003  | Pods Running as Root              | Containers should avoid root for security.                                                           | High     | 3      |
| SEC004  | Privileged Containers             | Grants unnecessary access.                                                                            | High     | 3      |
| SEC005  | hostIPC Usage                     | Sharing IPC namespace with host is a security risk.                                                  | Medium   | 2      |
| SEC006  | Pods Missing Secure Defaults      | Checks if pods are missing recommended securityContext fields such as runAsNonRoot, readOnlyRootFilesystem, or allowPrivilegeEscalation. | Medium   | 3      |
| SEC007  | Missing Pod Security Admission Labels | Checks if namespaces are missing the 'pod-security.kubernetes.io/enforce' label required for Pod Security Admission enforcement. | Low      | 1      |
| SEC008  | Secrets in Environment Variables  | Detects secrets exposed via env.valueFrom.secretKeyRef. This can be leaked via logs or /proc.        | High     | 4      |
| SEC009  | Missing Capabilities Drop         | Flags containers not dropping all capabilities via securityContext.capabilities.drop = ['ALL'].      | Medium   | 3      |
| SEC010  | HostPath Volume Usage             | Detects use of hostPath volumes that can expose or manipulate the host filesystem.                   | High     | 3      |
| SEC011  | Containers Running as UID 0       | Flags containers explicitly running as user 0 (root), even with securityContext set.                 | High     | 3      |
| SEC012  | Added Linux Capabilities          | Detects use of added Linux capabilities via securityContext.capabilities.add.                        | Medium   | 2      |
| SEC013  | EmptyDir Volume Usage             | Flags usage of emptyDir volumes, which are non-persistent and cleared on pod restart.                | Low      | 1      |
| SEC014  | Untrusted Image Registries        | Flags containers pulling images from unapproved registries.                                           | High     | 3      |
| SEC015  | Pods Using Default ServiceAccount | Flags pods using the default service account, which may have broad permissions.                     | Medium   | 3      |
| SEC016  | Non-Existent Secret References    | Flags pods referencing Secrets that do not exist. This may cause runtime failures.                  | High     | 4      |

### Storage

| ID     | Name                         | Description                                                     | Severity | Weight |
|--------|------------------------------|-----------------------------------------------------------------|----------|--------|
| PVC001 | Unused PVCs                  | Not mounted or bound. Can be deleted.                           | Medium   | 2      |

### Workloads

| ID     | Name                            | Description                                                                 | Severity | Weight |
|--------|----------------------------------|-----------------------------------------------------------------------------|----------|--------|
| WRK001 | DaemonSets Not Fully Running     | Some pods unscheduled or not ready.                                        | High     | 2      |
| WRK002 | Deployment Missing Replicas      | Fewer replicas than specified.                                             | High     | 2      |
| WRK003 | Incomplete StatefulSet Rollout   | Rollout not finished; may cause issues.                                    | Medium   | 2      |
| WRK004 | HPA Misconfig or Inactivity      | HPA not working or pointing to nothing.                                    | Medium   | 2      |
| WRK005 | Missing Resource Requests/Limits | No CPU/memory limits; risks noisy neighbor problems.                       | High     | 3      |
| WRK006 | PodDisruptionBudget Coverage     | Missing or misconfigured PDBs.                                             | Medium   | 2      |
| WRK007 | Missing Health Probes            | No liveness or readiness probes. Risks silent failures.                    | Medium   | 2      |
| WRK008 | Deployment Selector Without Matching Pods | Deployment selectors that don't match any pods, resulting in 0 replicas. | Medium   | 2      |

## Usage Notes

- **Severity**:
  - **Low**: Cosmetic or cleanup.
  - **Medium**: May affect performance or reliability.
  - **High**: Causes downtime or creates security risk.

- **Weight**:
  - Scores range from 1 (low impact) to 3 (high impact).
  - Higher weight = more effect on cluster score.
  - Fixing high-weight checks improves your score faster.

- **Interpreting Reports**:
  - Passed checks = nothing to fix, no items listed.
  - Failed checks = affected resources + suggested fixes.
  - Use links in the report to investigate and resolve.