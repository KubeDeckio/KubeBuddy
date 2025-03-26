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
| Run KubeBuddy | `Invoke-KubeBuddy` |
| Generate an HTML report | `Invoke-KubeBuddy -HtmlReport` |
| Generate a text report | `Invoke-KubeBuddy -txtReport` |
| Generate reports with custom path | `Invoke-KubeBuddy -HtmlReport -OutputPath ./custom-report` |
| Run a KubeBuddy with an AKS Best Practices Check | `Invoke-KubeBuddy -Aks -SubscriptionId <subscriptionID> -ResourceGroup <resourceGroup> -ClusterName <clusterName>` |
| Run AKS best practices check and HTML report | `Invoke-KubeBuddy -HtmlReport -Aks -SubscriptionId $SubscriptionId -ResourceGroup $ResourceGroup -ClusterName $ClusterName` |
| Run AKS best practices check and text report | `Invoke-KubeBuddy -txtReport -Aks -SubscriptionId $SubscriptionId -ResourceGroup $ResourceGroup -ClusterName $ClusterName` |

## 1. Running KubeBuddy

To run KubeBuddy on your Kubernetes cluster:

```powershell
Invoke-KubeBuddy
```

This command provides a detailed menu-driven interface that allows you to navigate through various monitoring options. It analyzes node status, resource usage, workloads, and RBAC security settings.

## 2. Running KubeBuddy with an AKS Best Practices Check

To check best practices for an **Azure Kubernetes Service (AKS)** cluster:

```powershell
Invoke-KubeBuddy -Aks -SubscriptionId <subscriptionID> -ResourceGroup <resourceGroup> -ClusterName <clusterName>
```

You **must** provide your Azure Subscription ID, the **Resource Group** where your AKS cluster resides, and the **Cluster Name**.

## 3. Generating Reports

### **Generate an HTML Report**
```powershell
Invoke-KubeBuddy -HtmlReport
```
![Screenshot of KubeBuddy HTML Report](../../../assets/images/report-examples/html-report-sample.png)

<a href="../../../assets/examples/html-report-sample.html" target="_blank" rel="noopener noreferrer">View Sample HTML Report</a>

---

### **Generate a Text Report**
```powershell
Invoke-KubeBuddy -txtReport
```
![Screenshot of KubeBuddy Text Report](../../../assets/images/report-examples/text-report-sample.png)

<a href="../../../assets/examples/text-report-sample.txt" target="_blank" rel="noopener noreferrer">View Sample txt Report</a>

---

### **Customizing Report Output Path**
You can specify a **custom filename or directory** for the report using `-OutputPath`.

#### **Save report in a specific directory**
```powershell
Invoke-KubeBuddy -HtmlReport -OutputPath ./reports
```
✔️ Saves the **HTML** report as:
```
./reports/kubebuddy-report-YYYYMMDD-HHMMSS.html
```

```powershell
Invoke-KubeBuddy -txtReport -OutputPath ./reports
```
✔️ Saves the **TXT** report as:
```
./reports/kubebuddy-report-YYYYMMDD-HHMMSS.txt
```

---

#### **Generate report with a custom filename**
```powershell
Invoke-KubeBuddy -HtmlReport -OutputPath ./custom-report.html
```
✔️ Saves the **HTML** report as:
```
./custom-report.html
```

```powershell
Invoke-KubeBuddy -txtReport -OutputPath ./custom-report.txt
```
✔️ Saves the **TXT** report as:
```
./custom-report.txt
```



## 4. Running an AKS Health Check alongside the HTML report

To check best practices for an Azure Kubernetes Service (AKS) cluster, ensure you are logged into Azure and using the correct subscription:

```powershell
az login
az account set --subscription <subscription-id>
Invoke-KubeBuddy -HtmlReport -Aks -SubscriptionId $SubscriptionId -ResourceGroup $ResourceGroup -ClusterName $ClusterName
```
![Screenshot of KubeBuddy HTML + AKS Report](../../../assets/images/report-examples/html-aks-report-sample.png)

<a href="../../../assets/examples/html-report-sample.html" target="_blank" rel="noopener noreferrer">View Sample HTML Report</a>

---

## 5. Running an AKS Health Check alongside the txt report

To check best practices for an Azure Kubernetes Service (AKS) cluster:

```powershell
az login
az account set --subscription <subscription-id>
Invoke-KubeBuddy -txtReport -Aks -SubscriptionId $SubscriptionId -ResourceGroup $ResourceGroup -ClusterName $ClusterName
```
![Screenshot of KubeBuddy Text Report](../../../assets/images/report-examples/text-aks-report-sample.png)

<a href="../../../assets/examples/text-report-sample.txt" target="_blank" rel="noopener noreferrer">View Sample text Report</a>

---

## 6. Configuring Thresholds

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
  stuck_job_hours: 2
  failed_job_hours: 2
  event_errors_warning: 10
  event_errors_critical: 20
  event_warnings_warning: 50
  event_warnings_critical: 100
```

Adjust these values to fit your environment. If `kubebuddy-config.yaml` is missing, KubeBuddy uses default thresholds.

---

## 7. Excluding System Namespaces (Optional)

Some KubeBuddy checks (like secrets, configmaps, pods, and RBAC) allow you to exclude **system namespaces** using the `-ExcludeSystem` switch.

To customize which namespaces are excluded, define them in your `kubebuddy-config.yaml` file:

```yaml
excluded_namespaces:
  - kube-system
  - kube-public
  - kube-node-lease
  - local-path-storage
  - coredns
  - calico-system
```

If `excluded_namespaces` is not defined, KubeBuddy falls back to a default set.

To apply the exclusion in any CLI command:

```powershell
Invoke-KubeBuddy -HtmlReport -ExcludeSystem
```


## 8. Additional Parameters

| Parameter                 | Type      | Default                              | Description                                                                                  |
|---------------------------|----------|--------------------------------------|----------------------------------------------------------------------------------------------|
| `-OutputPath`            | String   | `$HOME/kubebuddy-report`             | Folder or file name where report files are saved. Supports custom filenames.                 |
| `-Aks`                   | Switch   | (N/A)                                | Runs AKS best practices checks. Requires `-SubscriptionId`, `-ResourceGroup`, `-ClusterName`. |
| `-SubscriptionId`        | String   | (None)                               | Azure subscription ID (used with `-Aks`).                                                    |
| `-ResourceGroup`         | String   | (None)                               | Azure resource group (used with `-Aks`).                                                     |
| `-ClusterName`           | String   | (None)                               | AKS cluster name (used with `-Aks`).                                                         |
| `-HtmlReport`            | Switch   | (N/A)                                | Generates an HTML report in `-OutputPath`.                                                   |
| `-txtReport`             | Switch   | (N/A)                                | Generates a text report in `-OutputPath`.                                                   |
