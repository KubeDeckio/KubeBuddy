---
title: Docker Usage
parent: Usage
nav_order: 2
layout: default
---

# Docker Usage

Use **KubeBuddy powered by KubeDeck** in Docker to scan your cluster and generate reports.

## 🔧 Prerequisites

- You’re connected to a Kubernetes cluster/context.
- Docker is running.
- `~/.kube/config` exists and has access.
- Azure CLI is installed (for AKS).
- Image is built or pulled: `kubebuddy:0.0.15`.

### Build the Image

```bash
docker build -t kubebuddy:0.0.15 .
```

## 🌐 Environment Variables

| Variable              | Type   | Default | Description |
|-----------------------|--------|---------|-------------|
| `KUBECONFIG_PATH`     | String | —       | Path to kubeconfig inside container |
| `HTML_REPORT`         | String | false   | `"true"` to output HTML |
| `JSON_REPORT`         | String | false   | `"true"` to output JSON |
| `TXT_REPORT`          | String | false   | `"true"` to output TXT |
| `AKS_MODE`            | String | false   | `"true"` to run AKS checks |
| `CLUSTER_NAME`        | String | —       | Required for AKS mode |
| `RESOURCE_GROUP`      | String | —       | Required for AKS mode |
| `SUBSCRIPTION_ID`     | String | —       | Required for AKS mode |
| `AZURE_TOKEN`         | String | —       | Required for AKS mode |
| `EXCLUDE_NAMESPACES`  | String | false   | `"true"` to skip system namespaces |
| `TERM`                | String | —       | Set `"xterm"` to suppress TERM warnings |

## 📄 1. Basic Usage

```powershell
docker run --rm `
  -e KUBECONFIG_PATH="/kube/config" `
  -e HTML_REPORT="true" `
  -v $HOME/.kube/config:/kube/config:ro `
  -v $HOME/kubebuddy-report:/app/Reports `
  kubebuddy:0.0.15
```

➡️ Output saved to:  
`$HOME/kubebuddy-report/kubebuddy-report-YYYYMMDD-HHMMSS.html`  
[Sample HTML](../../../assets/examples/html-report-sample.html)

## 📊 2. AKS Check + Report

```powershell
docker run --rm `
  -e KUBECONFIG_PATH="/kube/config" `
  -e HTML_REPORT="true" `
  -e AKS_MODE="true" `
  -e CLUSTER_NAME="<cluster>" `
  -e RESOURCE_GROUP="<group>" `
  -e SUBSCRIPTION_ID="<sub-id>" `
  -e AZURE_TOKEN="$azureToken" `
  -v $HOME/.kube/config:/kube/config:ro `
  -v $HOME/kubebuddy-report:/app/Reports `
  kubebuddy:0.0.15
```

## ⚙️ 3. Custom Thresholds

Mount config at `/home/kubeuser/.kube/kubebuddy-config.yaml`.

```yaml
thresholds:
  cpu_warning: 50
  cpu_critical: 75
  pod_age_warning: 15
  pod_age_critical: 40
```

```powershell
docker run --rm `
  -e KUBECONFIG_PATH="/kube/config" `
  -e HTML_REPORT="true" `
  -v $HOME/.kube/config:/kube/config:ro `
  -v $HOME/.kube/kubebuddy-config.yaml:/home/kubeuser/.kube/kubebuddy-config.yaml:ro `
  -v $HOME/kubebuddy-report:/app/Reports `
  kubebuddy:0.0.15
```

## 🚫 4. Skip System Namespaces

In your config:

```yaml
excluded_namespaces:
  - kube-system
  - coredns
  - calico-system
```

Then:

```powershell
docker run --rm `
  -e KUBECONFIG_PATH="/kube/config" `
  -e HTML_REPORT="true" `
  -e EXCLUDE_NAMESPACES="true" `
  -v $HOME/.kube/config:/kube/config:ro `
  -v $HOME/kubebuddy-report:/app/Reports `
  kubebuddy:0.0.15
```

## 🔇 5. Suppress TERM Warnings

```powershell
docker run --rm `
  -e KUBECONFIG_PATH="/kube/config" `
  -e HTML_REPORT="true" `
  -e TERM="xterm" `
  -v ~/.kube/config:/kube/config:ro `
  -v ~/kubebuddy-report:/app/Reports `
  kubebuddy:0.0.15
```
