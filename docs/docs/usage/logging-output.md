---
title: Logging and Output
parent: Usage
nav_order: 4
layout: default
---

# Logging and Output

KubeBuddy powered by KubeDeck provides concise console output and optional reports for deeper analysis. You can capture these outputs or generate reports to share with your team or review later.

## 1. Real-Time Console Output

When you run `Invoke-KubeBuddy`, progress and key findings appear directly in your console. You’ll see checks for:

- **Cluster health**
- **Security or RBAC warnings**
- **Any issues with pods or workloads** (if applicable)

To save console output to a file:

```powershell
Invoke-KubeBuddy | Out-File "KubeBuddyOutput.log"
```

## 2. Generating Reports

KubeBuddy powered by KubeDeck can generate **HTML** or **text-based** reports. These typically include node health, workload issues, and any security alerts found during checks.

- **HTML Report:**

  ```powershell
  Invoke-KubeBuddy -HtmlReport
  ```
  
  This creates an HTML file (e.g., `kube_report.html`) you can open in a browser.

- **Text Report:**

  ```powershell
  Invoke-KubeBuddy -txtReport
  ```
  
  This creates a plain text file (e.g., `kube_report.txt`) which is handy for quick reference.

## 3. Completion Message

After checks finish, KubeBuddy powered by KubeDeck prints a final message indicating the process has completed and, if applicable, confirms the report path. For example:

```
KubeBuddy powered by KubeDeck has finished analyzing your cluster.
HTML report generated at /path/to/kube_report.html
```

This message provides a concise overview of what happened and where to find more details.

## 4. Common Error Messages

If an error occurs, KubeBuddy powered by KubeDeck provides detailed messages to help you troubleshoot. Below are a few examples:

| Error Message                                                       | Meaning                                                                   | Solution                                                                                                        |
|--------------------------------------------------------------------|---------------------------------------------------------------------------|-----------------------------------------------------------------------------------------------------------------|
| `ERROR: No clusters detected. Ensure you are connected to a cluster.` | KubeBuddy powered by KubeDeck could not find an active Kubernetes context.                    | Use `kubectl config current-context` to confirm a valid cluster connection.                                      |
| `ERROR: Authentication required for Azure operations.`             | You are not logged into Azure for AKS checks.                             | Run `az login` and use `az account set --subscription <subscription-id>` to select the correct subscription.     |
| `ERROR: Kubectl not found in system PATH.`                         | `kubectl` is either not installed or not in your PATH environment.        | Install `kubectl` by following [the official documentation](https://kubernetes.io/docs/tasks/tools/).           |
For more details on usage and specific command options, visit the [KubeBuddy powered by KubeDeck Usage](../usage) page.
