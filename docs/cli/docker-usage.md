---
title: Docker Usage
parent: Usage
nav_order: 2
layout: default
---

# Docker Usage

Run **KubeBuddy powered by KubeDeck** in a Docker container to scan your Kubernetes cluster and generate security, configuration, and best-practice reports — no local installation required.

This is ideal for DevOps, SRE, or security teams managing AKS or any CNCF-compliant Kubernetes cluster.

!!! info "WSL and SELinux Notes"
    - On **WSL**, avoid symbolic links when mounting `~/.kube/config`. Docker may try to copy the directory rather than the file. Use the actual file path.
    - On **SELinux-enabled Linux distros**, append `:Z` to the `:ro` volume mounts to avoid permission issues, e.g. `:ro,Z`.


## 🚀 TL;DR (Quick Start — Version Pinned)

=== "Bash"

    ```bash
    export tagId="v0.0.23"  # Replace with the desired version

    docker run -it --rm \
      -e KUBECONFIG="/home/kubeuser/.kube/config" \
      -e HTML_REPORT="true" \
      -v $HOME/.kube/config:/tmp/kubeconfig-original:ro \
      -v $HOME/kubebuddy-report:/app/Reports \
      ghcr.io/kubedeckio/kubebuddy:$tagId
    ```

=== "PowerShell"

    ```powershell
    $tagId = "v0.0.23"

    docker run -it --rm `
      -e KUBECONFIG="/home/kubeuser/.kube/config" `
      -e HTML_REPORT="true" `
      -v $HOME/.kube/config:/tmp/kubeconfig-original:ro `
      -v $HOME/kubebuddy-report:/app/Reports `
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

For generic Kubernetes (non-AKS) scans, see [Kubernetes Scan Permissions](kubernetes-permissions.md) for the required read-only RBAC setup.

### (Optional) GitHub CLI

To programmatically fetch the latest released version of KubeBuddy:

* Install GitHub CLI:

  ```bash
  gh --version
  ```

* [Installation instructions](https://cli.github.com/)


## 🐳 Pull the Docker Image

Always pull a specific version — **do not use `latest`**.



### 🔍 Get the Latest Published Docker Image Tag

Use GitHub CLI to fetch the most recent image tag from the GitHub Container Registry (GHCR).

=== "Bash"

    ```bash
    export tagId=$(gh api \
      -H "Accept: application/vnd.github+json" \
      /users/kubedeckio/packages/container/kubebuddy/versions \
      --jq '.[0].metadata.container.tags[0]')

    docker pull ghcr.io/kubedeckio/kubebuddy:$tagId
    ```

=== "PowerShell"

    ```powershell
    $response = gh api `
      -H "Accept: application/vnd.github+json" `
      /users/kubedeckio/packages/container/kubebuddy/versions

    $json = $response | ConvertFrom-Json
    $tagId = $json[0].metadata.container.tags[0]

    docker pull ghcr.io/kubedeckio/kubebuddy:$tagId
    ```

> 🧠 This requires [GitHub CLI](https://cli.github.com/) to be installed and authenticated with the correct permissions.

Or pull manually from the [Container Registry](https://github.com/KubeDeckio/KubeBuddy/pkgs/container/kubebuddy).


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
| `CSV_REPORT`  | `"true"` for CSV output   |
| `TXT_REPORT`  | `"true"` for plain text   |
| `JSON_REPORT` | `"true"` for JSON output  |

### 📡 KubeBuddy Radar (Pro, Optional)

| Variable                 | Description                                                                 |
| ------------------------ | --------------------------------------------------------------------------- |
| `RADAR_UPLOAD`           | `"true"` to upload run data to KubeBuddy Radar                             |
| `RADAR_COMPARE`          | `"true"` to fetch compare summary after upload                             |
| `RADAR_API_BASE_URL`     | Radar API base URL (default: `https://radar.kubebuddy.io/api/kb-radar/v1`) |
| `RADAR_ENVIRONMENT`      | Environment label (for example `prod`, `staging`, `dev`)                   |
| `RADAR_API_USER_ENV`     | Env-var name containing Radar username (default: `KUBEBUDDY_RADAR_API_USER`) |
| `RADAR_API_PASSWORD_ENV` | Env-var name containing Radar app password (default: `KUBEBUDDY_RADAR_API_PASSWORD`) |

> ⚠️ When `RADAR_UPLOAD` or `RADAR_COMPARE` is enabled in Docker mode, set `JSON_REPORT="true"`.
> Radar uploads are always JSON payloads.

### 🤖 AI Recommendations (Optional)

| Variable    | Description                                                                   |
| ----------- | ----------------------------------------------------------------------------- |
| `OpenAIKey` | Your OpenAI API key. Sets `$env:OpenAIKey` inside the container for PSAI use. |

> ✅ If `OpenAIKey` is provided, KubeBuddy uses GPT (via [PSAI](https://www.powershellgallery.com/packages/PSAI)) to generate AI-powered recommendations for failing checks:
>     • **Short text summary** (shown in the plain-text report)
>     • **Rich HTML block** (included in the HTML report)
>
> 🔒 If the key is missing or invalid, AI generation is skipped silently (no errors).

#### How to Use

1. **Get an OpenAI key** from [platform.openai.com/account/api-keys](https://platform.openai.com/account/api-keys)
2. **Pass it into your Docker container** like this:

```bash
docker run -it --rm \
  -e OpenAIKey="sk-..." \
  -e HTML_REPORT="true" \
  -v $HOME/.kube/config:/tmp/kubeconfig-original:ro \
  -v $HOME/kubebuddy-report:/app/Reports \
  ghcr.io/kubedeckio/kubebuddy:$tagId
```

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

### 📈 Prometheus Integration (Optional)

| Variable                       | Description                                                                       |
| ------------------------------ | --------------------------------------------------------------------------------- |
| `INCLUDE_PROMETHEUS`           | `"true"` to fetch Prometheus metrics alongside Kubernetes data                    |
| `PROMETHEUS_URL`               | The HTTP(S) endpoint of your Prometheus server                                    |
| `PROMETHEUS_MODE`              | Authentication mode: `local`, `basic`, `bearer`, or `azure`                       |
| `PROMETHEUS_USERNAME`          | Username for Basic auth (when `PROMETHEUS_MODE=basic`)                            |
| `PROMETHEUS_PASSWORD`          | Password for Basic auth (when `PROMETHEUS_MODE=basic`)                            |
| `PROMETHEUS_BEARER_TOKEN_ENV`  | Name of the environment variable that contains your Bearer token (when `bearer`)  |

> ⚠️ **Notes**  
> - **Enable first**: nothing else works unless `INCLUDE_PROMETHEUS="true"`.  
> - **Bearer mode**: set both  
>   ```bash
>   -e MY_PROM_TOKEN="<token>" \
>   -e PROMETHEUS_BEARER_TOKEN_ENV="MY_PROM_TOKEN"
>   ```  
>   so that `Get-PrometheusHeaders` can read `$Env:MY_PROM_TOKEN`.  


### 🔧 Optional

| Variable             | Description                               |
| -------------------- | ----------------------------------------- |
| `EXCLUDE_NAMESPACES` | `"true"` to skip system namespaces        |
| `TERM`               | `"xterm"` to prevent CLI rendering issues |


## ▶️ Run KubeBuddy (Generic Kubernetes)

=== "Bash"

    ```bash
    export tagId="v0.0.23"

    docker run -it --rm \
      -e KUBECONFIG="/home/kubeuser/.kube/config" \
      -e HTML_REPORT="true" \
      -v $HOME/.kube/config:/tmp/kubeconfig-original:ro \
      -v $HOME/kubebuddy-report:/app/Reports \
      ghcr.io/kubedeckio/kubebuddy:$tagId
    ```

## 📄 Generate a CSV Report in Docker

=== "Bash"

    ```bash
    export tagId="v0.0.23"

    docker run -it --rm \
      -e KUBECONFIG="/home/kubeuser/.kube/config" \
      -e CSV_REPORT="true" \
      -v $HOME/.kube/config:/tmp/kubeconfig-original:ro \
      -v $HOME/kubebuddy-report:/app/Reports \
      ghcr.io/kubedeckio/kubebuddy:$tagId
    ```

=== "PowerShell"

    ```powershell
    $tagId = "v0.0.23"

    docker run -it --rm `
      -e KUBECONFIG="/home/kubeuser/.kube/config" `
      -e CSV_REPORT="true" `
      -v $HOME/.kube/config:/tmp/kubeconfig-original:ro `
      -v $HOME/kubebuddy-report:/app/Reports `
      ghcr.io/kubedeckio/kubebuddy:$tagId
    ```

## 📡 Run With Radar Upload (Pro)

=== "Bash"

    ```bash
    export tagId="v0.0.23"

    docker run -it --rm \
      -e KUBECONFIG="/home/kubeuser/.kube/config" \
      -e JSON_REPORT="true" \
      -e RADAR_UPLOAD="true" \
      -e RADAR_COMPARE="true" \
      -e RADAR_ENVIRONMENT="prod" \
      -e KUBEBUDDY_RADAR_API_USER="<wp-username>" \
      -e KUBEBUDDY_RADAR_API_PASSWORD="<wp-app-password>" \
      -v $HOME/.kube/config:/tmp/kubeconfig-original:ro \
      -v $HOME/kubebuddy-report:/app/Reports \
      ghcr.io/kubedeckio/kubebuddy:$tagId
    ```

=== "PowerShell"

    ```powershell
    $tagId = "v0.0.23"

    docker run -it --rm `
      -e KUBECONFIG="/home/kubeuser/.kube/config" `
      -e JSON_REPORT="true" `
      -e RADAR_UPLOAD="true" `
      -e RADAR_COMPARE="true" `
      -e RADAR_ENVIRONMENT="prod" `
      -e KUBEBUDDY_RADAR_API_USER="<wp-username>" `
      -e KUBEBUDDY_RADAR_API_PASSWORD="<wp-app-password>" `
      -v $HOME/.kube/config:/tmp/kubeconfig-original:ro `
      -v $HOME/kubebuddy-report:/app/Reports `
      ghcr.io/kubedeckio/kubebuddy:$tagId
    ```


## ☁️ Run KubeBuddy with AKS Integration

=== "Bash"

    ```bash
    export tagId="v0.0.23"

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
    $tagId = "v0.0.23"

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
