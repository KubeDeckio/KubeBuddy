---
title: Usage
parent: Documentation
nav_order: 2
layout: default
hide:

---

# 🚀 KubeBuddy powered by KubeDeck Usage

KubeBuddy powered by KubeDeck helps you **monitor, analyze, and report** on your Kubernetes environments with ease. Whether you're tracking cluster health, reviewing security configurations, or troubleshooting workloads, KubeBuddy provides structured insights.

## 🔥 Choose Your Environment

### 🖥️ PowerShell (Windows/Linux/macOS)

Use the PowerShell module to:
- Monitor node health and usage.
- Detect failing pods, restart loops, and stuck jobs.
- Review Kubernetes events by severity.
- Inspect RBAC roles and security configs.
- Generate HTML or text reports.

📌 **[PowerShell Usage](powershell-usage.md)** – Step-by-step guide for PowerShell users.


### 🐳 Docker (Cross-platform)

Run KubeBuddy in a container to:
- Run scans in isolated environments without installing PowerShell.
- Mount your kubeconfig for access to any cluster.
- Use HTML, JSON, or TXT outputs for automation or offline viewing.
- Run AKS-specific checks with SPN credentials.

📌 **[Docker Usage](docker-usage.md)** – Guide for using KubeBuddy with Docker.

### 🔐 Kubernetes Permissions

Use this guide to configure least-privilege RBAC for non-AKS clusters and avoid using `cluster-admin` for routine scans.

📌 **[Kubernetes Scan Permissions](kubernetes-permissions.md)** – Required Kubernetes RBAC access for complete scans.

## 🧠 AI Recommendations (OpenAI)

KubeBuddy now supports AI-powered recommendation generation using OpenAI (ChatGPT) via the [PSAI PowerShell module](https://x.com/dfinke).

### How it Works

When KubeBuddy detects issues in your cluster, it can prompt an AI agent to generate:

- A brief **text summary** of recommended actions
- A rich **HTML block** with actionable suggestions, formatted for inclusion in reports

These recommendations are embedded directly in the **HTML**, **text**, and **JSON** reports.

### Requirements

To enable AI enrichment, you must provide an OpenAI API key:

```powershell
$env:OpenAIKey = "<your-openai-api-key>"
```

You can generate a key from:  
🔗 https://platform.openai.com/account/api-keys

> If no key is provided (`$env:OpenAIKey` is empty), KubeBuddy will skip AI enrichment and fallback to static/manual recommendations.

### Where AI Output Appears

- **HTML Report**: AI-generated actions appear in a collapsible card labeled `(AI Enhanced)` under each check that supports it.
- **Text Report**: Recommendations are marked with the prefix `AI Generated Recommendation:` if they were created by the AI.
- **JSON Report**: The recommendation object includes:
  ```json
  {
    "text": "...",
    "html": "...",
    "source": "AI"
  }
  ```

