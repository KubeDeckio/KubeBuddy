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

| YAML Section Value  | Report Tab Name       |
| ------------------- | --------------------- |
| `Nodes`             | Nodes                 |
| `Namespaces`        | Namespaces            |
| `Workloads`         | Workloads             |
| `Pods`              | Pods                  |
| `Jobs`              | Jobs                  |
| `Networking`        | Networking            |
| `Storage`           | Storage               |
| `Configuration`     | Configuration Hygiene |
| `Security`          | Security              |
| `Kubernetes Events` | Kubernetes Events     |

Use this when defining or updating checks to control where they appear in the report.

## Checks by Category

Each table includes:

- **ID** – Identifier for the check
- **Name** – Short label
- **Description** – What it checks and why it matters
- **Severity** – Low / Medium / High / Warning / Info
- **Weight** – Contribution to health score

### Performance

| ID      | Name                                | Description                                                                             | Severity | Weight |
| ------- | ----------------------------------- | --------------------------------------------------------------------------------------- | -------- | ------ |
| PROM001 | High CPU Pods (Prometheus)          | Checks for pods with sustained high CPU usage over the last 24 hours using Prometheus.  | Warning  | 3      |
| PROM002 | High Memory Usage Pods (Prometheus) | Detects pods with high memory usage over the last 24 hours based on Prometheus metrics. | Warning  | 3      |

### Configuration

| ID     | Name                      | Description                                               | Severity | Weight |
| ------ | ------------------------- | --------------------------------------------------------- | -------- | ------ |
| CFG001 | Orphaned ConfigMaps       | Unused ConfigMaps that can be removed.                    | Medium   | 1      |
| CFG002 | Duplicate ConfigMap Names | Same name used in different namespaces—creates confusion. | Medium   | 1      |
| CFG003 | Large ConfigMaps          | Oversized ConfigMaps that may affect performance.         | Medium   | 2      |

### Events

| ID       | Name                   | Description                                                 | Severity | Weight |
| -------- | ---------------------- | ----------------------------------------------------------- | -------- | ------ |
| EVENT001 | Grouped Warning Events | Groups frequent warnings to help identify recurring issues. | Low      | 1      |
| EVENT002 | Full Warning Event Log | Lists all recent warning events.                            | Low      | 1      |

### Jobs

| ID     | Name                   | Description                                                    | Severity | Weight |
| ------ | ---------------------- | -------------------------------------------------------------- | -------- | ------ |
| JOB001 | Stuck Kubernetes Jobs  | Jobs stuck in start or finish states due to controller issues. | High     | 2      |
| JOB002 | Failed Kubernetes Jobs | Jobs that failed or hit backoff limits.                        | High     | 2      |

### Networking

| ID | Name | Description | Severity | Weight |
|---|---|---|---|---|
| NET001 | Services Without Endpoints | Identifies services that have no backing endpoints, which means no pods are matched. | critical | 2 |
| NET002 | Publicly Accessible Services | Detects services of type LoadBalancer or NodePort that are potentially exposed to the internet. | critical | 4 |
| NET003 | Ingress Health Validation | Validates ingress definitions for missing classes, invalid backends, missing TLS secrets, duplicate host/path entries, and incorrect path types. | critical | 3 |
| NET004 | Namespace Missing Network Policy | Detects namespaces that have running pods but no associated NetworkPolicy resources. This could allow unrestricted pod-to-pod communication. | warning | 3 |
| NET005 | Ingress Host/Path Conflicts | Identifies Ingress resources that define conflicting host and path combinations, leading to unpredictable routing. | critical | 5 |
| NET006 | Ingress Using Wildcard Hosts | Identifies Ingress resources that utilize wildcard hosts (e.g., '\*https://www.google.com/search?q=.example.com'), which may offer broader exposure than intended. | medium | 2 |
| NET007 | Service TargetPort Mismatch | Identifies services whose 'targetPort' does not match any 'containerPort' in the backing pods, preventing traffic delivery. | critical | 4 |
| NET008 | ExternalName Service to Internal IP | Identifies 'ExternalName' type services pointing to private IP ranges, which might indicate a misconfiguration or an unusual routing pattern. | medium | 2 |
| NET009 | Overly Permissive Network Policy | Identifies NetworkPolicies that define 'policyTypes' but have no rules, effectively allowing all traffic for that type, or containing overly broad 'ipBlock' rules. | high | 4 |
| NET010 | Network Policy Overly Permissive IPBlock | Flags NetworkPolicies that include '0.0.0.0/0' in their 'ipBlock' rules, effectively allowing traffic to/from all IPs for that rule, which can be a security risk. | high | 5 |
| NET011 | Network Policy Missing PolicyTypes | Detects NetworkPolicies that do not explicitly define 'policyTypes'. While defaulting to Ingress in some older versions, explicit definition improves clarity and future compatibility across different CNI plugins and Kubernetes versions. | low | 1 |
| NET012 | Pod HostNetwork Usage | Identifies pods configured to use 'hostNetwork: true', which allows direct access to the node's network interfaces, bypassing Kubernetes networking. | high | 4 |
| PROM003 | High Network Receive Rate (Prometheus) | Detects pods receiving large amounts of network traffic over the last 24 hours. | Medium | 2 |

### Nodes

| ID      | Name                   | Description                                  | Severity | Weight |
| ------- | ---------------------- | -------------------------------------------- | -------- | ------ |
| NODE001 | Node Readiness         | Nodes not ready or with critical conditions. | High     | 3      |
| NODE002 | Node Resource Pressure | High usage of CPU, memory, or disk.          | High     | 3      |
| NODE003 | Max Pods per Node      | Node pod count exceeds configured threshold. | Warning  | 2      |

### Control Plane

| ID      | Name                    | Description                                                      | Severity | Weight |
| ------- | ----------------------- | ---------------------------------------------------------------- | -------- | ------ |
| PROM004 | API Server High Latency | Detects high latency in Kubernetes API server requests over 24h. | High     | 5      |

### Capacity

| ID      | Name                           | Description                                                                         | Severity | Weight |
| ------- | ------------------------------ | ----------------------------------------------------------------------------------- | -------- | ------ |
| PROM005 | Overcommitted CPU (Prometheus) | Checks if CPU requests on nodes exceed allocatable capacity over the last 24 hours. | Info     | 2      |

### Namespaces

| ID    | Name                           | Description                                       | Severity | Weight |
| ----- | ------------------------------ | ------------------------------------------------- | -------- | ------ |
| NS001 | Empty Namespaces               | No resources; can be cleaned up.                  | Low      | 1      |
| NS002 | Weak or Missing ResourceQuotas | No quotas or soft limits; risks resource overuse. | Medium   | 2      |
| NS003 | Missing LimitRanges            | No resource caps; enables excessive use.          | Medium   | 2      |

### Pods

| ID     | Name                      | Description                                            | Severity | Weight |
| ------ | ------------------------- | ------------------------------------------------------ | -------- | ------ |
| POD001 | High Restart Count        | Pods restarting too often; indicates instability.      | Medium   | 2      |
| POD002 | Long Running Pods         | Pods running longer than expected.                     | Medium   | 2      |
| POD003 | Failed Pods               | Pods in failed state.                                  | High     | 3      |
| POD004 | Pending Pods              | Pods stuck Pending—often resource/scheduling issues.   | Medium   | 2      |
| POD005 | CrashLoopBackOff          | Pods stuck restarting in CrashLoopBackOff.             | High     | 3      |
| POD006 | Leftover Debug Pods       | Debug pods not cleaned up.                             | Medium   | 2      |
| POD007 | Images Using `latest` Tag | Risk of inconsistent deployments due to floating tags. | Low      | 1      |

### RBAC

| ID      | Name                     | Description                          | Severity | Weight |
| ------- | ------------------------ | ------------------------------------ | -------- | ------ |
| RBAC001 | Misconfigurations        | Missing or incorrect role bindings.  | High     | 3      |
| RBAC002 | Overexposed Roles        | Roles with overly broad permissions. | High     | 3      |
| RBAC003 | Orphaned ServiceAccounts | Not in use; can be removed.          | Medium   | 2      |
| RBAC004 | Ineffective Roles        | Unused roles cluttering the system.  | Medium   | 2      |

### Security

| ID     | Name                                  | Description                                                             | Severity | Weight |
| ------ | ------------------------------------- | ----------------------------------------------------------------------- | -------- | ------ |
| SEC001 | Orphaned Secrets                      | Not used; safe to delete.                                               | Medium   | 2      |
| SEC002 | hostPID/hostNetwork Usage             | Shared host namespaces increase risk.                                   | High     | 3      |
| SEC003 | Pods Running as Root                  | Containers should avoid root for security.                              | High     | 3      |
| SEC004 | Privileged Containers                 | Grants unnecessary access.                                              | High     | 3      |
| SEC005 | hostIPC Usage                         | Sharing IPC namespace with host is a security risk.                     | Medium   | 2      |
| SEC006 | Pods Missing Secure Defaults          | Missing recommended `securityContext` fields (e.g. `runAsNonRoot`).     | Medium   | 3      |
| SEC007 | Missing Pod Security Admission Labels | Namespaces lacking `pod-security.kubernetes.io/enforce` labels.         | Low      | 1      |
| SEC008 | Secrets in Environment Variables      | Exposed via `env.valueFrom.secretKeyRef`; can leak via logs or `/proc`. | High     | 4      |
| SEC009 | Missing Capabilities Drop             | Containers not dropping all capabilities.                               | Medium   | 3      |
| SEC010 | HostPath Volume Usage                 | Use of `hostPath` volumes exposes host filesystem.                      | High     | 3      |
| SEC011 | Containers Running as UID 0           | Explicit `runAsUser: 0` even with securityContext.                      | High     | 3      |
| SEC012 | Added Linux Capabilities              | Use of extra Linux capabilities via `securityContext.capabilities.add`. | Medium   | 2      |
| SEC013 | EmptyDir Volume Usage                 | `emptyDir` volumes are non-persistent and cleared on restart.           | Low      | 1      |
| SEC014 | Untrusted Image Registries            | Pulling from unapproved registries.                                     | High     | 3      |
| SEC015 | Pods Using Default ServiceAccount     | Pods still use the default ServiceAccount with broad perms.             | Medium   | 3      |
| SEC016 | Non-Existent Secret References        | Pods referencing missing Secrets; causes runtime failures.              | High     | 4      |

### Storage

| ID     | Name                                       | Description                                                                                                                                                         | Severity | Weight |
| ------ | ------------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------- | -------- | ------ |
| PVC001 | Unused PVCs                                | Not mounted or bound; can be deleted.                                                                                                                               | Medium   | 2      |
| PV001  | Orphaned Persistent Volumes                | Detects Persistent Volumes that are not bound to any Persistent Volume Claim.                                                                                       | Warning  | 3      |
| PVC001 | Unused Persistent Volume Claims            | Detects PVCs not attached to any pod.                                                                                                                               | Warning  | 2      |
| PVC002 | PVCs Using Default StorageClass            | Detects PVCs that do not explicitly specify a storageClassName.                                                                                                     | Low      | 1      |
| PVC003 | ReadWriteMany PVCs on Incompatible Storage | Detects PVCs requesting ReadWriteMany access mode where the underlying storage is typically block-based and does not support concurrent writes from multiple nodes. | High     | 5      |
| PVC004 | Unbound Persistent Volume Claims           | Detects Persistent Volume Claims that are in a Pending phase and have not been bound to a Persistent Volume.                                                        | High     | 3      |
| SC001  | Deprecated StorageClass Provisioners       | Detects StorageClasses using deprecated or legacy in-tree provisioners, which should be migrated to CSI drivers.                                                    | High     | 4      |
| SC002  | StorageClass Prevents Volume Expansion     | Identifies StorageClasses that do not permit volume expansion, which can limit dynamic scaling of stateful applications.                                            | Medium   | 2      |
| SC003  | High Cluster Storage Usage                 | Monitors the overall percentage of used storage across the cluster.                                                                                                 | Warning  | 4      |

### Workloads

| ID     | Name                                           | Description                                                               | Severity | Weight |
| ------ | ---------------------------------------------- | ------------------------------------------------------------------------- | -------- | ------ |
| WRK001 | DaemonSets Not Fully Running                   | Some pods unscheduled or not ready.                                       | High     | 2      |
| WRK002 | Deployment Missing Replicas                    | Fewer replicas than specified.                                            | High     | 2      |
| WRK003 | Incomplete StatefulSet Rollout                 | Rollout not finished; may cause issues.                                   | Medium   | 2      |
| WRK004 | HPA Misconfig or Inactivity                    | HPA not working or pointing to nothing.                                   | Medium   | 2      |
| WRK005 | Missing Resource Requests/Limits               | No CPU/memory limits; risks noisy neighbor problems.                      | High     | 3      |
| WRK006 | PodDisruptionBudget Coverage                   | Missing or misconfigured PDBs.                                            | Medium   | 2      |
| WRK007 | Missing Health Probes                          | No liveness or readiness probes; risks silent failures.                   | Medium   | 2      |
| WRK008 | Deployment Selector Without Matching Pods      | Selectors that don’t match any pods, leading to 0 replicas.               | Medium   | 2      |
| WRK009 | Deployment, Pod, and Service Label Consistency | Mismatched labels between Deployments, Pods, or Services; breaks routing. | Medium   | 3      |


## Usage Notes

- **Severity**

  - **Low**: Cosmetic or cleanup
  - **Medium**: May affect performance or reliability
  - **High**: Causes downtime or poses security risk
  - **Warning/Info**: Advisory thresholds

- **Weight**

  - Scores range 1 (low impact) to 5 (high impact)
  - Higher weight = greater effect on cluster score

- **Interpreting Reports**
  - **Passed**: no items listed
  - **Failed**: lists affected resources + suggested fixes
  - Click IDs to jump to detailed recommendations in the report
