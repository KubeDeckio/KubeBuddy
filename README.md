<p align="center">
  <img src="./images/KubeBuddy.png" />
</p>

<h1 align="center" style="font-size: 100px;">
  <b>KubeBuddy</b>
</h1>

</br>

[![Publish Module to PowerShell Gallery](https://github.com/KubeDeckio/KubeBuddy/actions/workflows/publish-psgal.yml/badge.svg)](https://github.com/KubeDeckio/KubeBuddy/actions/workflows/publish-psgal.yml)
![PowerShell Gallery Version](https://img.shields.io/powershellgallery/v/KubeBuddy.svg)
![PowerShell Downloads](https://img.shields.io/powershellgallery/dt/KubeBuddy.svg)
![GitHub Downloads (all assets, all releases)](https://img.shields.io/github/downloads/kubedeckio/kubebuddy/total?logo=homebrew&logoColor=%23FBB040&label=Brew%20Downloads)
![License](https://img.shields.io/github/license/KubeDeckIo/KubeBuddy.svg)

**Container Details**

<!-- Option 2: flexbox for modern browsers -->
<div style="display: flex; gap: 0.5rem; align-items: center;">
  <img src="https://ghcr-badge.egpl.dev/kubedeckio/kubebuddy/latest_tag?color=%2344cc11&ignore=latest&label=current+version&trim=" alt="current version">
  <img src="https://ghcr-badge.egpl.dev/kubedeckio/kubebuddy/tags?color=%2344cc11&ignore=latest&n=3&label=image+tags&trim="         alt="image tags">
  <img src="https://ghcr-badge.egpl.dev/kubedeckio/kubebuddy/size?color=%2344cc11&tag=latest&label=image+size&trim="          alt="image size">
</div>

</br>

**KubeBuddy** is a Kubernetes and AKS scanning CLI that helps you inspect cluster health, workloads, networking, security, and platform configuration without installing anything into the cluster. It generates **HTML**, **JSON**, **text**, and **CSV** reports so you can use it interactively or in automation.

## Documentation

For complete installation, usage, and advanced configuration instructions, visit the **[KubeBuddy Documentation](https://kubebuddy.kubedeck.io)**.


## Features

- **Cluster Health Monitoring:** Checks node status, resource usage, and pod conditions.
- **Workload Analysis:** Identifies failing pods, restart loops, and stuck jobs.
- **Event Reporting:** Summarizes Kubernetes events to highlight errors and warnings.
- **RBAC & Security Checks:** Identifies excessive permissions and misconfigurations.
- **Storage & Networking Insights:** Analyzes persistent volumes, services, and network policies.
- **Customizable Thresholds:** Configure warning/critical levels in `kubebuddy-config.yaml`.
- **HTML, Text & CSV Reports:** Generates clean reports for analysis and sharing. CSV output includes check ID, name, severity, status, message, recommendation, and URL — ideal for spreadsheets, dashboards, and audit logs.
- **Native CLI Runtime:** Build or ship a single `kubebuddy` binary for local, CI, and container workflows.
- **PowerShell Compatibility:** Keep using the PowerShell module flow where needed during the transition.
- **AKS Best Practices Check:** Runs the native AKS best-practice catalog against live AKS clusters or AKS JSON input.
- **KubeBuddy Radar Upload (Pro):** Upload JSON scan runs to Radar for trend history, run comparisons, and fleet reporting.
- **Radar Cluster Config Fetch (Pro):** Pull a saved Radar cluster profile into the CLI and reuse the same settings locally or in Docker.


## Installation

### **Native CLI**

Build the native CLI from source:

```bash
go build -o kubebuddy ./cmd/kubebuddy
```

Run it directly:

```bash
./kubebuddy version
```

### **Homebrew**

Install the native CLI with Homebrew:

```bash
brew tap KubeDeckio/homebrew-kubebuddy
brew install kubebuddy
```

Then verify it:

```bash
kubebuddy version
```

### **PowerShell Gallery**

To install **KubeBuddy** using PowerShell:

```powershell
Install-Module -Name KubeBuddy -Repository PSGallery -Scope CurrentUser
```

The PowerShell module is now a compatibility wrapper over the native `kubebuddy` binary and ships the bundled binary for supported platforms. In normal use, `Invoke-KubeBuddy` should work immediately after install. Set `KUBEBUDDY_BINARY` only if you want to force a specific binary path.

### **Platform Support**
- **Native CLI:** Works anywhere the Go-built binary and your Kubernetes tooling are available.
- **PowerShell Module:** Works on **Windows**, **macOS**, and **Linux**.

For additional installation methods, refer to the **[KubeBuddy Documentation](https://kubebuddy.kubedeck.io).**


## Usage

### **Native CLI Commands**
Launch the guided Buddy flow:
```bash
./kubebuddy guided
```

Run the full KubeBuddy engine from the native CLI:
```bash
./kubebuddy run --html-report --yes --output-path ./reports
```

Run the native Kubernetes probe:
```bash
./kubebuddy probe
```

Run a native Kubernetes summary:
```bash
./kubebuddy summary
```

Run the declarative native scan path:
```bash
./kubebuddy scan --output json
```

Run AKS YAML checks against an AKS JSON document:
```bash
./kubebuddy scan-aks --input ./aks-cluster.json --output html
```

### **PowerShell Command**
Run **KubeBuddy** in PowerShell:
```powershell
Invoke-KubeBuddy
```

Run **KubeBuddy** in PowerShell with the option to do an AKS Health Check:
```powershell
Invoke-KubeBuddy -aks -SubscriptionId <subscriptionID> -ResourceGroup <resourceGroup> -ClusterName <clusterName>
```

### **Generate Reports**
- **HTML Report:**
  ```bash
  ./kubebuddy run --html-report --yes --output-path ./reports
  ```

  or

  ```powershell
  Invoke-KubeBuddy -HtmlReport
  ```
- **Text Report:**
  ```bash
  ./kubebuddy run --txt-report --yes --output-path ./reports
  ```

  or

  ```powershell
  Invoke-KubeBuddy -txtReport
  ```
- **CSV Report:**
  ```bash
  ./kubebuddy run --csv-report --yes --output-path ./reports
  ```

  or

  ```powershell
  Invoke-KubeBuddy -CsvReport
  ```
  Exports scan results to a `.csv` file with columns: `ID`, `Name`, `Category`, `Severity`, `Status`, `Message`, `Recommendation`, `URL`. Useful for spreadsheets, dashboards, or audit logs.
- **Add AKS Best Practices section to HTML report:**
  ```bash
  ./kubebuddy run --html-report --aks --subscription-id <subscriptionID> --resource-group <resourceGroup> --cluster-name <clusterName> --yes --output-path ./reports
  ```

  or

  ```powershell
  Invoke-KubeBuddy -HtmlReport -aks -SubscriptionId <subscriptionID> -ResourceGroup <resourceGroup> -ClusterName <clusterName>
  ```
- **Add AKS Best Practices section to Text report:**
  ```bash
  ./kubebuddy run --txt-report --aks --subscription-id <subscriptionID> --resource-group <resourceGroup> --cluster-name <clusterName> --yes --output-path ./reports
  ```

  or

  ```powershell
  Invoke-KubeBuddy -txtReport -aks -SubscriptionId <subscriptionID> -ResourceGroup <resourceGroup> -ClusterName <clusterName>
  ```
- **Add AKS Best Practices to CSV report:**
  ```bash
  ./kubebuddy run --csv-report --aks --subscription-id <subscriptionID> --resource-group <resourceGroup> --cluster-name <clusterName> --yes --output-path ./reports
  ```

  or

  ```powershell
  Invoke-KubeBuddy -CsvReport -aks -SubscriptionId <subscriptionID> -ResourceGroup <resourceGroup> -ClusterName <clusterName>
  ```

### **Upload to KubeBuddy Radar (Pro)**

```bash
export KUBEBUDDY_RADAR_API_USER="<your-wordpress-username>"
export KUBEBUDDY_RADAR_API_PASSWORD="<your-wordpress-app-password>"

./kubebuddy run --json-report --radar-upload --radar-environment prod --yes --output-path ./reports
```

or

```powershell
$env:KUBEBUDDY_RADAR_API_USER = "<your-wordpress-username>"
$env:KUBEBUDDY_RADAR_API_PASSWORD = "<your-wordpress-app-password>"

Invoke-KubeBuddy -jsonReport -RadarUpload -RadarEnvironment "prod"
```

Upload + compare in one run:

```bash
./kubebuddy run --json-report --radar-upload --radar-compare --radar-environment prod --yes --output-path ./reports
```

or

```powershell
Invoke-KubeBuddy -jsonReport -RadarUpload -RadarCompare -RadarEnvironment "prod"
```

Fetch a saved Radar cluster config and run with it:

```bash
./kubebuddy run --radar-fetch-config --radar-config-id "<cluster-config-id>" --yes
```

or

```powershell
Invoke-KubeBuddy -RadarFetchConfig -RadarConfigId "<cluster-config-id>"
```


## Configuration

**KubeBuddy** uses a YAML configuration file (`kubebuddy-config.yaml`) to define thresholds, exclusions, trusted registries, and Radar defaults:

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

excluded_namespaces:
  - kube-system
  - gatekeeper-system

trusted_registries:
  - mcr.microsoft.com/

excluded_checks:
  - SEC014
```

This file should be placed at:
```
~/.kube/kubebuddy-config.yaml
```

If missing, **KubeBuddy** falls back to default settings.


## Changelog

All notable changes to this project are documented in the **[CHANGELOG](./CHANGELOG.md).**


## License

This project is licensed under the **MIT License**. See the [LICENSE](./LICENSE) file for more details.
