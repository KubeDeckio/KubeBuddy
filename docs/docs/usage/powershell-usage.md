---
title: PowerShell Usage
parent: Usage
nav_order: 1
layout: default
---

# PowerShell Usage

If you're using **KubeBuddy** via PowerShell, this guide will help you monitor and analyze your Kubernetes clusters. Below are detailed instructions and examples for various commands.

## 🔧 Prerequisites

Before running KubeBuddy, ensure you:
- Are **connected to a Kubernetes cluster/context**.
- Have **kubectl** installed and configured.
- Have **Azure CLI (az cli)** installed if using AKS features.
- Are **logged into Azure** and using the correct subscription for AKS monitoring.

## Available Commands

The following table provides a quick reference for KubeBuddy commands:

| Action | Command Example |
|---------------------------|----------------|
| Run a cluster health check | `Invoke-KubeBuddy` |
| Generate an HTML report | `Invoke-KubeBuddy -HtmlReport` |
| Generate a text report | `Invoke-KubeBuddy -txtReport` |
| Run AKS best practices check and HTML report | `Invoke-KubeBuddy -HtmlReport -aks -SubscriptionId $SubscriptionId -ResourceGroup $ResourceGroup -ClusterName $ClusterName` |
| Run AKS best practices check and text report | `Invoke-KubeBuddy -txtReport -aks -SubscriptionId $SubscriptionId -ResourceGroup $ResourceGroup -ClusterName $ClusterName` |

## 1. Running a Cluster Health Check

To check the health of your Kubernetes cluster:

```powershell
Invoke-KubeBuddy
```

This command provides a detailed menu-driven interface that allows you to navigate through various monitoring options. It analyzes node status, resource usage, workloads, and RBAC security settings. The interactive menu lets you explore different categories, such as pod health, event summaries, and networking insights, making it easier to assess and troubleshoot your Kubernetes cluster.

## 2. Generating Reports

To generate an HTML report:

```powershell
Invoke-KubeBuddy -HtmlReport
```
![Screenshot of KubeBuddy HTML Report](../../../assets/images/report-examples/html-report-sample.png)

<a href="../../../assets/examples/html-report-sample.html" target="_blank" rel="noopener noreferrer">View Sample HTML Report</a>



For a text-based report:

```powershell
Invoke-KubeBuddy -txtReport
```
![Screenshot of KubeBuddy Text Report](../../../assets/images/report-examples/text-report-sample.png)

<a href="../../../assets/examples/text-report-sample.txt" target="_blank" rel="noopener noreferrer">View Sample txt Report</a>

## 3. Running an AKS Health Check alongside the HTML report

To check best practices for an Azure Kubernetes Service (AKS) cluster, ensure you are logged into Azure and using the correct subscription:

```powershell
az login
az account set --subscription <subscription-id>
Invoke-KubeBuddy -HtmlReport -aks -SubscriptionId $SubscriptionId -ResourceGroup $ResourceGroup -ClusterName $ClusterName
```
![Screenshot of KubeBuddy HTML + AKS Report](../../../assets/images/report-examples/html-aks-report-sample.png)

<a href="../../../assets/examples/html-report-sample.html" target="_blank" rel="noopener noreferrer">View Sample HTML Report</a>


## 4. Running an AKS Health Check alongside the txt report

To check best practices for an Azure Kubernetes Service (AKS) cluster, ensure you are logged into Azure and using the correct subscription:

```powershell
az login
az account set --subscription <subscription-id>
Invoke-KubeBuddy -txtReport -aks -SubscriptionId $SubscriptionId -ResourceGroup $ResourceGroup -ClusterName $ClusterName
```
![Screenshot of KubeBuddy Text Report](../../../assets/images/report-examples/text-aks-report-sample.png)

<a href="../../../assets/examples/text-report-sample.txt" target="_blank" rel="noopener noreferrer">View Sample text Report</a>


---

## 5. Configuring Thresholds

KubeBuddy supports customizable thresholds via the `kubebuddy-config.yaml` file. You can place this file in `~/.kube/kubebuddy-config.yaml` or specify a custom path. A sample configuration looks like this:

```yaml
thresholds:
  cpu_warning: 50
  cpu_critical: 75
  mem_warning: 50
  mem_critical: 75
  restarts_warning: 3
  restarts_critical: 5
  pod_age_warning: 15
  pod_age_critical: 40
```

Adjust these values to suit your environment’s needs. If `kubebuddy-config.yaml` is missing, KubeBuddy uses default threshold values.

---

## 6. Additional Parameters

Below are optional parameters you can use with `Invoke-KubeBuddy`:

| Parameter                 | Type      | Default                              | Description                                                                                  |
|---------------------------|----------|--------------------------------------|----------------------------------------------------------------------------------------------|
| `-OutputPath`            | String   | `$HOME\kubebuddy-report`             | Folder where report files are saved. If not present, KubeBuddy creates it automatically.      |
| `-Aks`                   | Switch   | (N/A)                                | Runs AKS best practices checks. Requires `-SubscriptionId`, `-ResourceGroup`, `-ClusterName`. |
| `-SubscriptionId`        | String   | (None)                               | Azure subscription ID (used with `-Aks`).                                                    |
| `-ResourceGroup`         | String   | (None)                               | Azure resource group (used with `-Aks`).                                                     |
| `-ClusterName`           | String   | (None)                               | AKS cluster name (used with `-Aks`).                                                         |
| `-HtmlReport`            | Switch   | (N/A)                                | Generates an HTML report in `$OutputPath\kubebuddy-report.html`.                             |
| `-txtReport`             | Switch   | (N/A)                                | Generates a text report in `$OutputPath\kubebuddy-report.txt`.                              |


✅ **Next Steps:** Explore more commands in the [PowerShell Usage Guide](powershell-usage).

