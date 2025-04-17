---
title: Checks
parent: Usage
nav_order: 3
layout: default
---

# Kubernetes Checks Reference

KubeBuddy performs a comprehensive set of checks to identify common issues and misconfigurations in Kubernetes clusters. These checks are used to generate detailed cluster reports, helping you assess cluster health and prioritize remediation. This page provides a complete reference for all checks, including their ID, name, description, category, severity, and weight in the cluster health score.

## Overview

Each check targets a specific aspect of your Kubernetes cluster, such as node health, pod status, or security configurations. The checks are defined in YAML files located in the `yamlChecks/` directory, allowing you to customize or disable them as needed. The table below organizes checks by category and provides details to help you understand their purpose and impact.

## Checks by Category

The following table lists all KubeBuddy checks, grouped by category for easier navigation. Use the **Category** column to identify the area of the cluster each check evaluates, **Severity** to gauge its potential impact, and **Weight** to understand its contribution to the overall cluster health score.

| Category            | ID       | Name                                       | Description                                                                                     | Severity | Weight |
|---------------------|----------|--------------------------------------------|-------------------------------------------------------------------------------------------------|----------|--------|
| **Configuration**   | CFG001   | Orphaned ConfigMaps                        | Identifies ConfigMaps not referenced by any pods or workloads, indicating potential cleanup opportunities. | Medium   | 1      |
|                     | CFG002   | Duplicate ConfigMap Names                  | Detects ConfigMaps with identical names across different namespaces, which may cause confusion.  | Medium   | 1      |
|                     | CFG003   | Large ConfigMaps                           | Flags ConfigMaps exceeding recommended size thresholds, which could impact performance.          | Medium   | 2      |
| **Events**          | EVENT001 | Grouped Warning Events                     | Summarizes recurring Kubernetes warning events by type to highlight potential issues.            | Low      | 1      |
|                     | EVENT002 | Full Warning Event Log                     | Provides a detailed log of all recent warning-level events for in-depth troubleshooting.         | Low      | 1      |
| **Jobs**            | JOB001   | Stuck Kubernetes Jobs                      | Detects jobs stuck in start or completion phases due to controller issues, requiring intervention. | High     | 2      |
|                     | JOB002   | Failed Kubernetes Jobs                     | Identifies jobs that failed or exceeded their backoff limit, indicating potential errors.        | High     | 2      |
| **Networking**      | NET001   | Services Without Endpoints                 | Flags Services with no backing endpoints, which may indicate misconfiguration or downtime.       | Medium   | 2      |
|                     | NET002   | Publicly Accessible Services               | Identifies Services exposed via LoadBalancer or NodePort, which could pose security risks.       | High     | 2      |
|                     | NET003   | Ingress Health Validation                  | Detects misconfigured or error-prone Ingress resources affecting external access.                | Medium   | 2      |
| **Nodes**           | NODE001  | Node Readiness and Conditions              | Verifies that all cluster nodes are in a ready state and free from critical conditions.          | High     | 3      |
|                     | NODE002  | Node Resource Pressure                     | Evaluates CPU, memory, and disk usage on nodes against thresholds to prevent resource bottlenecks. | High     | 3      |
| **Namespaces**      | NS001    | Empty Namespaces                           | Identifies namespaces with no active resources, which may be candidates for cleanup.             | Low      | 1      |
|                     | NS002    | Missing or Weak ResourceQuotas             | Flags namespaces without resource quotas or with ineffective limits, risking resource overuse.  | Medium   | 2      |
|                     | NS003    | Missing LimitRanges                        | Detects namespaces lacking default LimitRange definitions, which can lead to resource abuse.     | Medium   | 2      |
| **Pods**            | POD001   | Pods with High Restarts                    | Flags pods with excessive restart counts, indicating potential instability.                     | Medium   | 2      |
|                     | POD002   | Long Running Pods                          | Identifies pods running longer than expected without restarts, which may indicate staleness.     | Medium   | 2      |
|                     | POD003   | Failed Pods                                | Detects pods in a failed state due to crashes or scheduling errors, requiring attention.         | High     | 3      |
|                     | POD004   | Pending Pods                               | Identifies pods stuck in a pending state, often due to resource or scheduling issues.            | Medium   | 2      |
|                     | POD005   | CrashLoopBackOff Pods                      | Flags pods in a CrashLoopBackOff state, indicating repeated crashes needing resolution.          | High     | 3      |
|                     | POD006   | Leftover Debug Pods                        | Detects lingering debug or ephemeral containers, which may consume unnecessary resources.        | Medium   | 2      |
|                     | POD007   | Container Images with Latest Tag           | Flags containers using the `latest` tag, which can cause inconsistent deployments.               | Low      | 1      |
| **RBAC**            | RBAC001  | RBAC Misconfigurations                     | Identifies common RBAC misconfigurations or missing bindings that could disrupt access control.  | High     | 3      |
|                     | RBAC002  | RBAC Overexposure                          | Flags roles with excessive privileges, such as wildcard access, posing security risks.           | High     | 3      |
|                     | RBAC003  | Orphaned ServiceAccounts                   | Detects unused or unbound ServiceAccounts, which may indicate cleanup opportunities.             | Medium   | 2      |
|                     | RBAC004   | Orphaned and Ineffective Roles             | Identifies roles not used by any bindings, which can be safely removed.                         | Medium   | 2      |
| **Security**        | SEC001   | Orphaned Secrets                           | Detects Secrets not mounted or referenced, indicating potential cleanup needs.                   | Medium   | 2      |
|                     | SEC002   | Pods Using hostPID or hostNetwork          | Flags pods using host-level networking or PID namespaces, which could expose vulnerabilities.    | High     | 3      |
|                     | SEC003   | Pods Running as Root                       | Identifies containers running as root, increasing security risks if compromised.                 | High     | 3      |
|                     | SEC004   | Privileged Containers                      | Detects containers with `privileged: true`, which can grant excessive permissions.               | High     | 3      |
|                     | SEC005   | Pods Using hostIPC                         | Flags pods sharing IPC with the host, potentially exposing vulnerabilities.                      | Medium   | 2      |
| **Storage**         | PVC001   | Unused Persistent Volume Claims            | Identifies PVCs not bound or mounted by any pod, indicating potential cleanup opportunities.     | Medium   | 2      |
| **Workloads**       | WRK001   | DaemonSets Not Fully Running               | Verifies that all DaemonSet pods are scheduled and ready, ensuring workload coverage.            | High     | 2      |
|                     | WRK002   | Deployment Missing Replicas                | Detects deployments with fewer replicas than desired, indicating scaling issues.                 | High     | 2      |
|                     | WRK003   | StatefulSet Incomplete Rollout             | Flags StatefulSets not fully rolled out, which may disrupt stateful applications.                | Medium   | 2      |
|                     | WRK004   | HPA Misconfiguration or Inactivity         | Identifies HPA objects not targeting valid workloads or inactive, affecting auto-scaling.        | Medium   | 2      |
|                     | WRK005   | Missing Resource Requests or Limits        | Flags containers without CPU or memory requests/limits, risking resource contention.             | High     | 3      |
|                     | WRK006   | PDB Coverage and Effectiveness             | Evaluates PodDisruptionBudgets for proper coverage and toleration settings.                      | Medium   | 2      |
|                     | WRK007   | Missing Readiness and Liveness Probes      | Detects workloads without readiness or liveness probes, risking undetected failures.             | Medium   | 2      |

## Usage Notes

- **Severity**:
  - **Low**: Minor issues with limited impact, often related to optimization or cleanup.
  - **Medium**: Issues that could affect performance, stability, or security if left unaddressed.
  - **High**: Critical issues that may cause outages, security vulnerabilities, or significant resource problems.
  - Use severity to prioritize remediation efforts, focusing on High-severity checks first.

- **Weight**:
  - Each check contributes to the cluster health score based on its weight (1–3).
  - Higher-weight checks (e.g., 3) have a greater impact on the score, reflecting their importance to cluster health.
  - For example, `NODE001` (weight 3) affects the score more than `EVENT001` (weight 1).

- **Customization**:
  - Checks are defined in YAML files in the `yamlChecks/` directory.
  - To disable a check, remove or comment out its YAML definition or set a flag in the file (refer to the documentation for details).
  - You can also modify thresholds, conditions, or recommendations in the YAML files to tailor checks to your cluster’s needs.
  - Example: To skip `POD007` (latest tag check), edit its YAML file or exclude it from processing.

- **Interpreting Results**:
  - Checks with no issues return a “Passed” status and do not list items in the report.
  - Failed checks provide detailed items (e.g., affected resources) and recommendations for resolution.
  - Review the report’s recommendations and linked URLs for actionable steps to address issues.

## Next Steps

- **Run a Report**: Use KubeBuddy to generate a cluster report and review the results for each check.
- **Prioritize Fixes**: Focus on High-severity and high-weight checks to improve cluster health.
- **Customize Checks**: Adjust YAML definitions to align with your cluster’s requirements or exclude irrelevant checks.
- **Monitor Regularly**: Schedule periodic reports to catch new issues early.

For more details on running reports or customizing checks, see the [Usage](/usage) section.