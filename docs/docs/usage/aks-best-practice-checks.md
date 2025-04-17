---
title: AKS Best Practices Checks
parent: Usage
nav_order: 3
layout: default
---

# AKS Best Practice Checks

KubeBuddy powered by KubeDeck evaluates various aspects of your **Azure Kubernetes Service (AKS)** setup, highlighting potential issues and confirming best practices.

## 🔍 Checks Overview

Below is a categorized list of key AKS checks, ordered by **ID and Category**:

### Best Practices

| ID    | Check                                   | Severity |
|-------|-----------------------------------------|----------|
| AKSBP001 | Allowed Container Images Policy        | High     |
| AKSBP002 | No Privileged Containers Policy        | High     |
| AKSBP003 | Multiple Node Pools                    | Medium   |
| AKSBP004 | Azure Linux as Host OS                 | High     |
| AKSBP005 | Ephemeral OS Disks Enabled             | Medium   |
| AKSBP006 | Non-Ephemeral Disks with Adequate Size | Medium   |
| AKSBP007 | System Node Pool Taint                 | High     |
| AKSBP008 | Auto Upgrade Channel Configured        | Medium   |
| AKSBP009 | Node OS Upgrade Channel Configured     | Medium   |
| AKSBP010 | Customized MC_ Resource Group Name     | Medium   |

### Disaster Recovery

| ID    | Check                                   | Severity |
|-------|-----------------------------------------|----------|
| AKSDR001 | Agent Pools with Availability Zones    | High     |
| AKSDR002 | Control Plane SLA                      | Medium   |

### Identity & Access

| ID    | Check                                   | Severity |
|-------|-----------------------------------------|----------|
| AKSIAM001| RBAC Enabled                           | High     |
| AKSIAM002| Managed Identity                       | High     |
| AKSIAM003| Workload Identity Enabled              | Medium   |
| AKSIAM004| Managed Identity Used                  | High     |
| AKSIAM005| AAD RBAC Authorization Integrated      | High     |
| AKSIAM006| AAD Managed Authentication Enabled     | High     |
| AKSIAM007| Local Accounts Disabled                | High     |

### Monitoring & Logging

| ID    | Check                                   | Severity |
|-------|-----------------------------------------|----------|
| AKSMON001| Azure Monitor                          | High     |
| AKSMON002| Managed Prometheus Enabled             | High     |

### Networking

| ID    | Check                                   | Severity |
|-------|-----------------------------------------|----------|
| AKSNET001| Authorized IP Ranges                   | High     |
| AKSNET002| Network Policy Check                   | Medium   |
| AKSNET003| Web App Routing Enabled                | Low      |
| AKSNET004| Azure CNI Networking Recommended       | Medium   |

### Resource Management

| ID    | Check                                   | Severity |
|-------|-----------------------------------------|----------|
| AKSRES001| Cluster Autoscaler                     | Medium   |
| AKSRES002| AKS Built-in Cost Tooling Enabled      | Medium   |
| AKSRES003| Vertical Pod Autoscaler (VPA) is enabled| Medium   |

### Security

| ID    | Check                                   | Severity |
|-------|-----------------------------------------|----------|
| AKSSEC001| Private Cluster                        | High     |
| AKSSEC002| Azure Policy Add-on                    | Medium   |
| AKSSEC003| Defender for Containers                | High     |
| AKSSEC004| OIDC Issuer Enabled                    | Medium   |
| AKSSEC005| Azure Key Vault Integration            | High     |
| AKSSEC006| Image Cleaner Enabled                  | Medium   |
| AKSSEC007| Kubernetes Dashboard Disabled          | High     |

Each check provides insights into security, performance, and cost optimization.