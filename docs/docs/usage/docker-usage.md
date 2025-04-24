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

- SPN must have **Cluster Admin** or **KubeBuddy Reader** role. See [Setup for AKS](#setup-for-aks-required-for-aks_mode).


## 🐳 Pull the Docker Image

### Bash
```bash
export tagId="latest"
docker pull ghcr.io/kubedeckio/kubebuddy:$tagId
```

### PowerShell
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

### Bash
```bash
docker run -it --rm \
  -e KUBECONFIG="/home/kubeuser/.kube/config" \
  -e HTML_REPORT="true" \
  -v $HOME/.kube/config:/tmp/kubeconfig-original:ro \
  -v $HOME/kubebuddy-report:/app/Reports \
  ghcr.io/kubedeckio/kubebuddy:$tagId
```

### PowerShell
```powershell
docker run -it --rm `
  -e KUBECONFIG="/home/kubeuser/.kube/config" `
  -e HTML_REPORT="true" `
  -v $HOME/.kube/config:/tmp/kubeconfig-original:ro `
  -v $HOME/kubebuddy-report:/app/Reports `
  ghcr.io/kubedeckio/kubebuddy:$tagId
```

You can switch report format by setting `HTML_REPORT`, `JSON_REPORT`, or `TXT_REPORT` to `"true"`.

## ☁️ Run with AKS Checks

### Bash
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

### PowerShell
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

Change report format by modifying the relevant `*_REPORT` environment variable.

## ⚙️ Custom Configuration

To customize thresholds, namespaces, and checks, mount a `kubebuddy-config.yaml` file into the container:

```bash
docker run -it --rm \
  -e KUBECONFIG="/home/kubeuser/.kube/config" \
  -e HTML_REPORT="true" \
  -v $HOME/.kube/config:/tmp/kubeconfig-original:ro \
  -v $HOME/.kube/kubebuddy-config.yaml:/home/kubeuser/.kube/kubebuddy-config.yaml:ro \
  -v $HOME/kubebuddy-report:/app/Reports \
  ghcr.io/kubedeckio/kubebuddy:$tagId
```

See [Configuration File](./kubebuddy-config) for config details.


## 🛠️ Setup for AKS (Required for `AKS_MODE`)

### 1. Create SPN
```bash
az ad sp create-for-rbac --name kubebuddy-spn --output json
```

### 2. Create Role

See [Configuration File](./kubebuddy-config#2-create-the-kubebuddy-reader-role) for JSON.

```bash
az role definition create --role-definition KubeBuddyReader.json
```

### 3. Assign Role
```bash
az role assignment create --role "KubeBuddy Reader" --assignee <client-id> --scope <aks-id>
az role assignment create --role "Azure Kubernetes Service Cluster User Role" --assignee <client-id> --scope <aks-id>
```

### 4. Get Kubeconfig
```bash
az aks get-credentials --resource-group <group> --name <cluster> --subscription <sub-id>
```


## ✅ Summary

- Run KubeBuddy in Docker with or without AKS-specific checks.
- Choose Bash or PowerShell based on your environment.
- Use `kubebuddy-config.yaml` to customize thresholds and exclusions.

→ See [Configuration File](./kubebuddy-config) for full config reference.
