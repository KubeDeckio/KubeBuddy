---
title: Home
nav_order: 1
layout: home
---

# Kubernetes Says Your Cluster is Healthy. <br>It's Probably Not.

**KubeBuddy powered by KubeDeck** runs complete health, security, and configuration checks on your Kubernetes cluster from your terminal—no agents, no Helm charts, no guesswork.

## What It Does

Run **KubeBuddy powered by KubeDeck** and get a full picture of your cluster:

- **Node and Pod Health**: Spot failing nodes, pending pods, restarts.
- **Workload Issues**: Detect jobs stuck in loops or pods stuck terminating.
- **Security Gaps**: Check RBAC roles, bindings, and risky permissions.
- **AKS-Specific Checks**: Follow Microsoft’s AKS best practices with one command.
- **Event Summaries**: Surface recent errors, warnings, and crash loops.
- **Storage and Networking**: Review PVCs, services, and network policies.
- **HTML and CLI Reports**: Shareable output for audits and debugging.

> **All checks run outside the cluster. No setup required inside Kubernetes.**  
> Works on any Kubernetes cluster. PowerShell 7+ required.

## Why Use KubeBuddy powered by KubeDeck?

Most tools give you metrics. **KubeBuddy powered by KubeDeck** gives you answers.

| What You Use Today | What You Miss |
|--------------------|----------------|
| `kubectl get pods` | Why they're failing |
| Readiness probes   | Underlying service issues |
| Dashboards         | Misconfigured RBAC, silent errors |
| Manual reviews     | Automation, consistent checks |

**KubeBuddy powered by KubeDeck** runs a deep scan and tells you what's wrong, what’s risky, and what’s misconfigured—across the whole cluster.

## Who It's For

- **SREs** running post-incident reviews  
- **Platform teams** doing regular audits  
- **DevOps engineers** automating cluster checks in CI/CD  
- **Anyone** managing production clusters without internal tools

## Install and Run

```powershell
Install-Module -Name KubeBuddy -Repository PSGallery -Scope CurrentUser
```

KubeBuddy runs on macOS, Linux, and Windows with PowerShell 7+.

