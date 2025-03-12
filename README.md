
<p align="center">
  <img src="./images/KubeBuddy.png" />
</p>

<h1 align="center" style="font-size: 100px;">
  <b>KubeBuddy</b>
</h1>

</br>

[![Publish Module to PowerShell Gallery](https://github.com/KubeDeckio/KubeBuddy/actions/workflows/publish-psgal.yml/badge.svg)](https://github.com/KubeDeckio/KubeBuddy/actions/workflows/publish-psgal.yml)
![PowerShell Gallery Version](https://img.shields.io/powershellgallery/v/KubeBuddy.svg)
![Downloads](https://img.shields.io/powershellgallery/dt/KubeBuddy.svg)
![License](https://img.shields.io/github/license/KubeDeckIo/KubeBuddy.svg)

---

**KubeBuddy** is a PowerShell-based Kubernetes assistant that helps you monitor cluster health, workloads, networking, security, and more. It generates **HTML** and **text-based reports** to help you quickly assess your Kubernetes environment.

## Documentation

For complete installation, usage, and advanced configuration instructions, visit the **[KubeBuddy Documentation](https://docs.kubebuddy.io)**.

---

## Features

- **Cluster Health Monitoring:** Checks node status, resource usage, and pod conditions.
- **Workload Analysis:** Identifies failing pods, restart loops, and stuck jobs.
- **Event Reporting:** Summarizes Kubernetes events to highlight errors and warnings.
- **RBAC & Security Checks:** Identifies excessive permissions and misconfigurations.
- **Storage & Networking Insights:** Analyzes persistent volumes, services, and network policies.
- **Customizable Thresholds:** Configure warning/critical levels in `kubebuddy-config.yaml`.
- **HTML & Text Reports:** Generates clean reports for analysis and sharing.
- **PowerShell Support:** Install via PowerShell Gallery and run on Windows, macOS, or Linux.

---

## Installation

### **PowerShell Gallery**

To install **KubeBuddy** using PowerShell:

```powershell
Install-Module -Name KubeBuddy -Repository PSGallery -Scope CurrentUser
```

### **Platform Support**
- **PowerShell Module:** Works on **Windows**, **macOS**, and **Linux**.

For additional installation methods, refer to the **[KubeBuddy Documentation](https://docs.kubebuddy.io).**

---

## Usage

### **PowerShell Command**
Run **KubeBuddy** in PowerShell:
```powershell
Invoke-KubeBuddy
```

### **Generate Reports**
- HTML Report:
  ```powershell
  Invoke-KubeBuddy -HtmlReport
  ```
- Text Report:
  ```powershell
  Invoke-KubeBuddy -txtReport
  ```

---

## Configuration

**KubeBuddy** uses a YAML configuration file (`kubebuddy-config.yaml`) to define thresholds:

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

This file should be placed at:
```
~/.kube/kubebuddy-config.yaml
```

If missing, **KubeBuddy** falls back to default settings.

---

## Changelog

All notable changes to this project are documented in the **[CHANGELOG](./CHANGELOG.md).**

---

## License

This project is licensed under the **MIT License**. See the [LICENSE](./LICENSE) file for more details.
