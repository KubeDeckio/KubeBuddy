---
title: AKS Best Practices Checks
parent: Usage
nav_order: 2
layout: default
---

# AKS Best Practice Checks

KubeBuddy evaluates various aspects of your **Azure Kubernetes Service (AKS)** setup, highlighting potential issues and confirming best practices.

## 🔍 Checks Overview

Below is a categorized list of key AKS checks, ordered by **ID and Category**:

### Best Practices
| ID    | Check                                   | Severity |
|-------|-----------------------------------------|----------|
| BP001 | Allowed Container Images Policy        | High     |
| BP002 | No Privileged Containers Policy        | High     |
| BP003 | Multiple Node Pools                    | Medium   |
| BP004 | Azure Linux as Host OS                 | High     |
| BP005 | Ephemeral OS Disks Enabled             | Medium   |
| BP006 | Non-Ephemeral Disks with Adequate Size | Medium   |
| BP007 | System Node Pool Taint                 | High     |
| BP008 | Auto Upgrade Channel Configured        | Medium   |
| BP009 | Node OS Upgrade Channel Configured     | Medium   |
| BP010 | Customized MC_ Resource Group Name     | Medium   |

### Disaster Recovery
| ID    | Check                                   | Severity |
|-------|-----------------------------------------|----------|
| DR001 | Agent Pools with Availability Zones    | High     |
| DR002 | Control Plane SLA                      | Medium   |

### Identity & Access
| ID    | Check                                   | Severity |
|-------|-----------------------------------------|----------|
| IAM001| RBAC Enabled                           | High     |
| IAM002| Managed Identity                       | High     |
| IAM003| Workload Identity Enabled              | Medium   |
| IAM004| Managed Identity Used                  | High     |
| IAM005| AAD RBAC Authorization Integrated      | High     |
| IAM006| AAD Managed Authentication Enabled     | High     |
| IAM007| Local Accounts Disabled                | High     |

### Monitoring & Logging
| ID    | Check                                   | Severity |
|-------|-----------------------------------------|----------|
| MON001| Azure Monitor                          | High     |
| MON002| Managed Prometheus Enabled             | High     |

### Networking
| ID    | Check                                   | Severity |
|-------|-----------------------------------------|----------|
| NET001| Authorized IP Ranges                   | High     |
| NET002| Network Policy Check                   | Medium   |
| NET003| Web App Routing Enabled                | Low      |
| NET004| Azure CNI Networking Recommended       | Medium   |

### Resource Management
| ID    | Check                                   | Severity |
|-------|-----------------------------------------|----------|
| RES001| Cluster Autoscaler                     | Medium   |
| RES002| AKS Built-in Cost Tooling Enabled      | Medium   |

### Security
| ID    | Check                                   | Severity |
|-------|-----------------------------------------|----------|
| SEC001| Private Cluster                        | High     |
| SEC002| Azure Policy Add-on                    | Medium   |
| SEC003| Defender for Containers                | High     |
| SEC004| OIDC Issuer Enabled                    | Medium   |
| SEC005| Azure Key Vault Integration            | High     |
| SEC006| Image Cleaner Enabled                  | Medium   |
| SEC007| Kubernetes Dashboard Disabled          | High     |

Each check provides insights into security, performance, and cost optimization.