---
title: Docker Usage
parent: Usage
nav_order: 2
layout: default
---

# Docker Usage

Run **KubeBuddy powered by KubeDeck** in a Docker container to scan your Kubernetes cluster and generate security, configuration, and best-practice reports — no local installation required.

This is ideal for DevOps, SRE, or security teams managing AKS or any CNCF-compliant Kubernetes cluster.


## 🚀 TL;DR (Quick Start — Version Pinned)

```bash
export tagId="v0.0.19"  # Replace with the desired version

docker run -it --rm \
  -e KUBECONFIG="/home/kubeuser/.kube/config" \
  -e HTML_REPORT="true" \
  -v $HOME/.kube/config:/tmp/kubeconfig-original:ro \
  -v $HOME/kubebuddy-report:/app/Reports \
  ghcr.io/kubedeckio/kubebuddy:$tagId
```

> ❗ **Always use a pinned version tag. Avoid `latest` to ensure reliability and reproducibility.**


## 🔧 Prerequisites

* Docker installed and running:

  ```bash
  docker --version
  ```

* Valid Kubernetes context:

  ```bash
  kubectl config current-context
  ```

* Kubeconfig must exist:

  ```bash
  ls ~/.kube/config
  ```

### For AKS Users

* Azure CLI installed and logged in:

  ```bash
  az login
  az --version
  ```

* A Service Principal (SPN) with **Cluster Admin** or **KubeBuddy Reader** role

> 📘 See the full [AKS Configuration & Best Practices Setup](aks-best-practice-checks.md) for SPN creation and role setup.

### (Optional) GitHub CLI

To programmatically fetch the latest released version of KubeBuddy:

* Install GitHub CLI:

  ```bash
  gh --version
  ```

* [Installation instructions](https://cli.github.com/)

Example usage:

```bash
gh release list -R kubedeckio/kubebuddy --limit 1
export tagId="v0.0.19"  # replace with latest version
```

Alternatively, visit the [Releases page](https://github.com/kubedeckio/kubebuddy/releases) manually.


## 🐳 Pull the Docker Image

Always pull a specific version — **do not use `latest`**.

### 🔍 Find and Pull the Latest Tagged Version

Use GitHub CLI:

```bash
gh release list -R kubedeckio/kubebuddy --limit 1
export tagId="v0.0.19"  # Replace with latest version from output
docker pull ghcr.io/kubedeckio/kubebuddy:$tagId
```

Or pull manually from the [Releases page](https://github.com/kubedeckio/kubebuddy/releases).


## 🌐 Environment Variables

Set these to control behavior inside the container:

### 🔹 Required (General)

| Variable                                       | Description                                 |
| ---------------------------------------------- | ------------------------------------------- |
| `KUBECONFIG`                                   | Path to the kubeconfig inside the container |
| One of the report flags (below) must be `true` |                                             |

### 📄 Report Format Flags (One or More Required)

| Variable      | Description               |
| ------------- | ------------------------- |
| `HTML_REPORT` | `"true"` to generate HTML |
| `TXT_REPORT`  | `"true"` for plain text   |
| `JSON_REPORT` | `"true"` for JSON output  |

### ☁️ AKS Mode (Optional, for AKS Clusters)

| Variable              | Description                     |
| --------------------- | ------------------------------- |
| `AKS_MODE`            | `"true"` to enable AKS checks   |
| `CLUSTER_NAME`        | AKS cluster name                |
| `RESOURCE_GROUP`      | AKS resource group              |
| `SUBSCRIPTION_ID`     | Azure subscription ID           |
| `AZURE_CLIENT_ID`     | SPN client ID                   |
| `AZURE_CLIENT_SECRET` | SPN client secret               |
| `AZURE_TENANT_ID`     | Azure tenant ID                 |
| `USE_AKS_REST_API`    | `"true"` to use Azure REST APIs |

### 🔧 Optional

| Variable             | Description                               |
| -------------------- | ----------------------------------------- |
| `EXCLUDE_NAMESPACES` | `"true"` to skip system namespaces        |
| `TERM`               | `"xterm"` to prevent CLI rendering issues |


## ▶️ Run KubeBuddy (Generic Kubernetes)

\=== "Bash"

```bash
export tagId="v0.0.19"

docker run -it --rm \
  -e KUBECONFIG="/home/kubeuser/.kube/config" \
  -e HTML_REPORT="true" \
  -v $HOME/.kube/config:/tmp/kubeconfig-original:ro \
  -v $HOME/kubebuddy-report:/app/Reports \
  ghcr.io/kubedeckio/kubebuddy:$tagId
```

\=== "PowerShell"

```powershell
$tagId = "v0.0.19"

docker run -it --rm `
  -e KUBECONFIG="/home/kubeuser/.kube/config" `
  -e HTML_REPORT="true" `
  -v $HOME/.kube/config:/tmp/kubeconfig-original:ro `
  -v $HOME/kubebuddy-report:/app/Reports `
  ghcr.io/kubedeckio/kubebuddy:$tagId
```


## ☁️ Run KubeBuddy with AKS Integration

\=== "Bash"

```bash
export tagId="v0.0.19"

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

\=== "PowerShell"

```powershell
$tagId = "v0.0.19"

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


## ⚙️ Custom Configuration File

You can mount a `kubebuddy-config.yaml` file for advanced options:

```bash
docker run -it --rm \
  -e KUBECONFIG="/home/kubeuser/.kube/config" \
  -e HTML_REPORT="true" \
  -v $HOME/.kube/config:/tmp/kubeconfig-original:ro \
  -v $HOME/.kube/kubebuddy-config.yaml:/home/kubeuser/.kube/kubebuddy-config.yaml:ro \
  -v $HOME/kubebuddy-report:/app/Reports \
  ghcr.io/kubedeckio/kubebuddy:$tagId
```

→ See [Configuration File Options](./kubebuddy-config.md) for all available settings.


## 🔐 Security Tips

* **Never pass secrets in plain CLI commands**. Use `--env-file` or a secrets manager where possible.
* Ensure your kubeconfig contains only the context(s) you want to scan.
* On Windows, use full paths (e.g., `C:/Users/yourname/.kube/config`) instead of `$HOME`.


## 📘 AKS Setup Notes

To use `AKS_MODE`, you must:

* Create a Service Principal (SPN)
* Assign it the correct role (e.g., Cluster Admin or custom Reader role)
* Provide SPN credentials as environment variables

👉 See [AKS Configuration & Best Practices](aks-best-practice-checks.md) for step-by-step setup.
