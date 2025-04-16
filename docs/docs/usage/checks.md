---
title: Checks
parent: Usage
nav_order: 3
layout: default
---

# Kubernetes Checks Reference

This page lists all the checks KubeBuddy performs when generating a cluster report. Each check targets common issues or misconfigurations in Kubernetes clusters. The table includes the check ID, name, description, severity level, and weighting used in the overall cluster health score.

| ID      | Name                                       | Description                                                                                     | Severity | Weight |
|---------|--------------------------------------------|-------------------------------------------------------------------------------------------------|----------|--------|
| CFG001  | Orphaned ConfigMaps                        | Detects ConfigMaps not referenced by any pods or workloads.                                     | Medium   | 1      |
| CFG002  | Duplicate ConfigMap Names                  | Finds ConfigMaps with identical names in different namespaces.                                  | Medium   | 1      |
| CFG003  | Large ConfigMaps                           | Flags ConfigMaps exceeding a recommended size threshold.                                        | Medium   | 2      |
| EVENT001| Grouped Warning Events                     | Summarizes frequent Kubernetes warning events by type.                                          | Low      | 1      |
| EVENT002| Full Warning Event Log                     | Outputs a complete log of all recent warning-level events.                                      | Low      | 1      |
| JOB001  | Stuck Kubernetes Jobs                      | Detects jobs stuck in start or completion due to controller issues.                             | High     | 2      |
| JOB002  | Failed Kubernetes Jobs                     | Flags jobs that failed or exceeded their backoff limit.                                         | High     | 2      |
| NET001  | Services Without Endpoints                 | Identifies Services that have no backing endpoints.                                             | Medium   | 2      |
| NET002  | Publicly Accessible Services               | Flags Services exposed via LoadBalancer or NodePort types.                                     | High     | 2      |
| NET003  | Ingress Health Validation                  | Detects Ingress resources that are misconfigured or return errors.                              | Medium   | 2      |
| NODE001 | Node Readiness and Conditions              | Checks if all cluster nodes are ready and free from critical conditions.                        | High     | 3      |
| NODE002 | Node Resource Pressure                     | Evaluates node-level CPU, memory, and disk usage against thresholds.                            | High     | 3      |
| NS001   | Empty Namespaces                           | Flags namespaces with no active resources.                                                      | Low      | 1      |
| NS002   | Missing or Weak ResourceQuotas             | Detects namespaces without resource quotas or with ineffective limits.                          | Medium   | 2      |
| NS003   | Missing LimitRanges                        | Flags namespaces missing default LimitRange definitions.                                        | Medium   | 2      |
| POD001  | Pods with High Restarts                    | Finds pods with restart counts exceeding recommended limits.                                    | Medium   | 2      |
| POD002  | Long Running Pods                          | Flags pods running longer than expected without restarts.                                       | Medium   | 2      |
| POD003  | Failed Pods                                | Detects pods in failed phase due to crashes or scheduling errors.                               | High     | 3      |
| POD004  | Pending Pods                               | Identifies pods stuck in pending state.                                                         | Medium   | 2      |
| POD005  | CrashLoopBackOff Pods                      | Flags pods in a CrashLoopBackOff state.                                                         | High     | 3      |
| POD006  | Leftover Debug Pods                        | Detects debugging or ephemeral containers left running.                                         | Medium   | 2      |
| POD007  | Container images do not use latest tag     | Flags containers using the `latest` tag which may cause inconsistency.                         | Low      | 1      |
| RBAC001 | RBAC Misconfigurations                     | Detects common RBAC misconfigurations or missing bindings.                                      | High     | 3      |
| RBAC002 | RBAC Overexposure                          | Flags roles with excessive privileges (e.g., wildcard access).                                  | High     | 3      |
| RBAC003 | Orphaned ServiceAccounts                   | Finds unused or unbound ServiceAccounts.                                                        | Medium   | 2      |
| RBAC004 | Orphaned and Ineffective Roles             | Identifies roles not used by any bindings.                                                      | Medium   | 2      |
| SEC001  | Orphaned Secrets                           | Detects Secrets that are not mounted or referenced anywhere.                                    | Medium   | 2      |
| SEC002  | Pods using hostPID or hostNetwork          | Flags pods using host-level networking or PID namespaces.                                       | High     | 3      |
| SEC003  | Pods Running as Root                       | Detects containers that run as root user.                                                       | High     | 3      |
| SEC004  | Privileged Containers                      | Identifies containers with `privileged: true` securityContext.                                  | High     | 3      |
| SEC005  | Pods Using hostIPC                         | Detects pods sharing IPC with the host, which can expose vulnerabilities.                       | Medium   | 2      |
| PVC001  | Unused Persistent Volume Claims            | Flags PVCs that are not bound or mounted by any pod.                                            | Medium   | 2      |
| WRK001  | DaemonSets Not Fully Running               | Checks if all DaemonSet pods are scheduled and ready.                                           | High     | 2      |
| WRK002  | Deployment Missing Replicas                | Detects deployments with fewer replicas than desired.                                           | High     | 2      |
| WRK003  | StatefulSet Incomplete Rollout             | Flags StatefulSets not fully rolled out.                                                        | Medium   | 2      |
| WRK004  | HPA Misconfiguration or Inactivity         | Detects HPA objects not targeting valid workloads or inactive.                                  | Medium   | 2      |
| WRK005  | Missing Resource Requests or Limits        | Flags containers missing CPU or memory requests/limits.                                         | High     | 3      |
| WRK006  | PDB Coverage and Effectiveness             | Evaluates PodDisruptionBudgets for coverage and toleration settings.                            | Medium   | 2      |
| WRK007  | Missing Readiness and Liveness Probes      | Detects workloads missing readiness or liveness probes.                                         | Medium   | 2      |

## Usage Notes

- **Severity** indicates how much the issue could impact your cluster.
- **Weight** affects the cluster health score. Higher weight checks contribute more.
- You can selectively disable checks by editing the YAML definitions in `yamlChecks/`.

This list is current as of your latest YAML check definitions.
