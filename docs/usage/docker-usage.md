---
title: Docker Usage
parent: Usage
nav_order: 2
layout: default
---

# Docker Usage

Run **KubeBuddy powered by KubeDeck** in Docker to scan your Kubernetes cluster and generate reports. This guide covers both generic Kubernetes clusters and AKS clusters using SPN credentials.

## 🔧 Prerequisites

- Docker installed and running:
  ```bash
  docker --version
  ```

- Valid Kubernetes context:
  ```bash
  kubectl config current-context
  ```

- Kubeconfig must exist:
  ```bash
  ls ~/.kube/config
  ```

### For AKS

- Azure CLI installed and logged in:
  ```bash
  az login
  az --version
  ```

- SPN must have **Cluster Admin** or **KubeBuddy Reader** role.

> 📘 See the full [AKS Configuration & Best Practices Setup](aks-configuration-and-best-practices-checks.md) guide for SPN creation, role definition, and AKS prerequisites.


## 🐳 Pull the Docker Image

=== "Bash"
    ```bash
    export tagId="latest"
    docker pull ghcr.io/kubedeckio/kubebuddy:$tagId
    ```

=== "PowerShell"
    ```powershell
    $tagId = "latest"
    docker pull ghcr.io/kubedeckio/kubebuddy:$tagId
    ```

## 🌐 Environment Variables

| Variable              | Description                          |
|-----------------------|--------------------------------------|
| `KUBECONFIG`          | Path to kubeconfig inside container  |
| `HTML_REPORT`         | Set to `"true"` for HTML report      |
| `JSON_REPORT`         | Set to `"true"` for JSON report      |
| `TXT_REPORT`          | Set to `"true"` for plain text       |
| `AKS_MODE`            | Enable AKS-specific checks           |
| `CLUSTER_NAME`        | AKS cluster name                     |
| `RESOURCE_GROUP`      | AKS resource group                   |
| `SUBSCRIPTION_ID`     | Azure subscription ID                |
| `AZURE_CLIENT_ID`     | SPN client ID                        |
| `AZURE_CLIENT_SECRET` | SPN client secret                    |
| `AZURE_TENANT_ID`     | Azure tenant ID                      |
| `USE_AKS_REST_API`    | Use Azure REST API (optional)        |
| `EXCLUDE_NAMESPACES`  | `"true"` to skip system namespaces   |
| `TERM`                | Set to `"xterm"` to avoid warnings   |

## ▶️ Run KubeBuddy (Non-AKS)

=== "Bash"
    ```bash
    docker run -it --rm \
      -e KUBECONFIG="/home/kubeuser/.kube/config" \
      -e HTML_REPORT="true" \
      -v $HOME/.kube/config:/tmp/kubeconfig-original:ro \
      -v $HOME/kubebuddy-report:/app/Reports \
      ghcr.io/kubedeckio/kubebuddy:$tagId
    ```

=== "PowerShell"
    ```powershell
    docker run -it --rm `
      -e KUBECONFIG="/home/kubeuser/.kube/config" `
      -e HTML_REPORT="true" `
      -v $HOME/.kube/config:/tmp/kubeconfig-original:ro `
      -v $HOME/kubebuddy-report:/app/Reports `
      ghcr.io/kubedeckio/kubebuddy:$tagId
    ```

To switch report type, set:

- `HTML_REPORT=true`
- `JSON_REPORT=true`
- `TXT_REPORT=true`

## ☁️ Run with AKS Checks

=== "Bash"
    ```bash
    docker run -it --rm \
      -e KUBECONFIG="/home/kubeuser/.kube/config" \
      -e HTML_REPORT="true" \
      -e AKS_MODE="true" \
      -e CLUSTER_NAME="<cluster>" \
      -e RESOURCE_GROUP="<group>" \
      -e SUBSCRIPTION_ID="<sub-id>" \
      -e AZURE_CLIENT_ID="<client-id>" \
      -e AZURE_CLIENT_SECRET="<client-secret>" \
      -e AZURE_TENANT_ID="<tenant-id>" \
      -e USE_AKS_REST_API="true" \
      -v $HOME/.kube/config:/tmp/kubeconfig-original:ro \
      -v $HOME/kubebuddy-report:/app/Reports \
      ghcr.io/kubedeckio/kubebuddy:$tagId
    ```

=== "PowerShell"
    ```powershell
    docker run -it --rm `
      -e KUBECONFIG="/home/kubeuser/.kube/config" `
      -e HTML_REPORT="true" `
      -e AKS_MODE="true" `
      -e CLUSTER_NAME="<cluster>" `
      -e RESOURCE_GROUP="<group>" `
      -e SUBSCRIPTION_ID="<sub-id>" `
      -e AZURE_CLIENT_ID="<client-id>" `
      -e AZURE_CLIENT_SECRET="<client-secret>" `
      -e AZURE_TENANT_ID="<tenant-id>" `
      -e USE_AKS_REST_API="true" `
      -v $HOME/.kube/config:/tmp/kubeconfig-original:ro `
      -v $HOME/kubebuddy-report:/app/Reports `
      ghcr.io/kubedeckio/kubebuddy:$tagId
    ```

Change `HTML_REPORT` to `JSON_REPORT` or `TXT_REPORT` for other formats.

## ⚙️ Custom Configuration

Mount your `kubebuddy-config.yaml` file:

```bash
docker run -it --rm \
  -e KUBECONFIG="/home/kubeuser/.kube/config" \
  -e HTML_REPORT="true" \
  -v $HOME/.kube/config:/tmp/kubeconfig-original:ro \
  -v $HOME/.kube/kubebuddy-config.yaml:/home/kubeuser/.kube/kubebuddy-config.yaml:ro \
  -v $HOME/kubebuddy-report:/app/Reports \
  ghcr.io/kubedeckio/kubebuddy:$tagId
```

→ See [Configuration File](./kubebuddy-config.md) for all options.

## 🛠️ Setup for AKS (Required for `AKS_MODE`)

To use AKS-specific features in Docker (via `AKS_MODE`), you need to set up a Service Principal (SPN), assign roles, and configure access to your cluster.

👉 See the full [AKS Configuration & Best Practices Setup](aks-configuration-and-best-practices-checks.md) guide for step-by-step instructions.
