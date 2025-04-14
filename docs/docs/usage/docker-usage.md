---
title: Docker Usage
parent: Usage
nav_order: 2
layout: default
---

## Docker Usage

Run **KubeBuddy powered by KubeDeck** in a Docker container to scan your Kubernetes cluster and generate detailed reports. This guide covers running the container for both generic Kubernetes clusters and Azure Kubernetes Service (AKS) clusters using a Service Principal (SPN) with a custom **KubeBuddy Reader** role for read-only access to all resources, including secrets.



## 🔧 Prerequisites

### General Requirements

- **Docker**: Ensure Docker is installed and running.
  ```bash
  docker --version
  ```

- **Kubernetes Context**: Verify you’re connected to the correct cluster.
  ```bash
  kubectl config current-context
  ```

- **Kubeconfig**: Ensure `~/.kube/config` exists and grants access to your cluster.
  ```bash
  ls ~/.kube/config
  ```

Certainly! Here's how you can modify that part to include instructions on how to get and set the `$tagId`:

---

### **Docker Image**: Pull the KubeBuddy image

Before pulling the Docker image, you need to set the `$tagId` variable, which corresponds to the version tag of the image you wish to use. 

1. **Get the latest version tag** from the [KubeBuddy Docker Hub page](https://github.com/kubedeckio/kubebuddy) or the image registry.

2. **Set the `$tagId` variable**:

   In Bash:

   ```bash
   export tagPlaceholder="latest"  # Or replace with the specific version tag
   ```

   In PowerShell:

   ```powershell
   $tagId = "latest"  # Or replace with the specific version tag
   ```

3. **Pull the image** using the tag:

   ```bash
   docker pull ghcr.io/kubedeckio/kubebuddy:$tagId
   ```

This will download the latest version of the KubeBuddy image (or the specified version) to your local machine, ready for use.

### For AKS (Azure Kubernetes Service) Usage

- **Azure CLI**: Required to set up SPN credentials and roles for AKS clusters.
  ```bash
  az login
  az --version
  ```

### Permissions for AKS

- To run **KubeBuddy** with AKS-specific checks, your SPN requires **Cluster Admin** access or the **custom KubeBuddy Reader role**.
  - For **Cluster Admin**, your SPN must have **full permissions** on all Kubernetes resources.
  - Alternatively, you can create and assign the **KubeBuddy Reader role** for **read-only access** to Kubernetes resources, including secrets. 

  See the [Setup for AKS](#🛠️-setup-for-aks-required-for-aks_mode) section for details on configuring the role.

## 🌐 Environment Variables

| Variable              | Type   | Default | Description                                                                 |
|-----------------------|--------|---------|-----------------------------------------------------------------------------|
| `KUBECONFIG`          | String | —       | Path to kubeconfig inside container (default: `/home/kubeuser/.kube/config`)|
| `HTML_REPORT`         | String | false   | Set to `"true"` to generate an HTML report                                  |
| `JSON_REPORT`         | String | false   | Set to `"true"` to generate a JSON report                                  |
| `TXT_REPORT`          | String | false   | Set to `"true"` to generate a TXT report                                   |
| `AKS_MODE`            | String | false   | Set to `"true"` to enable AKS-specific checks                              |
| `CLUSTER_NAME`        | String | —       | AKS cluster name (required for `AKS_MODE`)                                 |
| `RESOURCE_GROUP`      | String | —       | AKS resource group (required for `AKS_MODE`)                               |
| `SUBSCRIPTION_ID`     | String | —       | Azure subscription ID (required for `AKS_MODE`)                           |
| `AZURE_CLIENT_ID`     | String | —       | SPN client ID (required for `AKS_MODE`)                                    |
| `AZURE_CLIENT_SECRET` | String | —       | SPN client secret (required for `AKS_MODE`)                                |
| `AZURE_TENANT_ID`     | String | —       | Azure tenant ID (required for `AKS_MODE`)                                  |
| `USE_AKS_REST_API`    | String | false   | Set to `"true"` to use Azure REST API for AKS metadata (optional, auto-enabled with SPN) |
| `EXCLUDE_NAMESPACES`  | String | false   | Set to `"true"` to skip system namespaces (e.g., `kube-system`, `coredns`)  |
| `TERM`                | String | —       | Set to `"xterm"` to suppress terminal warnings                             |



## 📄 1. Running KubeBuddy Container with Bash

### Here's an update to your section about switching to JSON or TXT reports, adding instructions for both formats:

---

### Basic Usage (Non-AKS Cluster)

Generate a report for any Kubernetes cluster without AKS-specific checks. By default, **KubeBuddy** generates an **HTML report**. You can switch to **JSON** or **TXT** reports by changing the environment variable.

#### HTML Report (Default):

```bash
docker run -it --rm \
  -e KUBECONFIG="/home/kubeuser/.kube/config" \
  -e HTML_REPORT="true" \
  -v $HOME/.kube/config:/tmp/kubeconfig-original:ro \
  -v $HOME/kubebuddy-report:/app/Reports \
  ghcr.io/kubedeckio/kubebuddy:$tagId
```

You can easily switch between the **HTML**, **JSON**, and **TXT** report formats by modifying the respective environment variable in the `docker run` command. Simply change the `-e` option to set one of the following:

- **HTML Report** (default):  
  Set `HTML_REPORT="true"` to generate an HTML report.
  
- **JSON Report**:  
  Set `JSON_REPORT="true"` to generate a JSON report.
  
- **TXT Report**:  
  Set `TXT_REPORT="true"` to generate a plain text report.

For example, if you want a **JSON report** instead of the default HTML report, you would update the `docker run` command to:

```bash
docker run -it --rm \
  -e KUBECONFIG="/home/kubeuser/.kube/config" \
  -e JSON_REPORT="true" \
  -v $HOME/.kube/config:/tmp/kubeconfig-original:ro \
  -v $HOME/kubebuddy-report:/app/Reports \
  ghcr.io/kubedeckio/kubebuddy:$tagId
```

This allows you to easily toggle between different report formats for each scan without changing anything else in your setup.

**Output**:  
Report saved to: `$HOME/kubebuddy-report/kubebuddy-report-YYYYMMDD-HHMMSS.txt`


### AKS Check + Report

Run with AKS-specific checks using SPN authentication and the KubeBuddy Reader role.

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

You can change the report format by simply adjusting the `-e` flag in the `docker run` command. Set `HTML_REPORT="true"`, `JSON_REPORT="true"`, or `TXT_REPORT="true"` to generate the respective report type. This flexibility allows you to easily switch between formats for each scan, without needing to alter any other settings. Just update the `-e` option as per the report format you want.

**Output**:  
Report saved to: `$HOME/kubebuddy-report/kubebuddy-report-YYYYMMDD-HHMMSS.html`



## ⚙️ 3. Custom Thresholds

Customize thresholds by mounting a `kubebuddy-config.yaml` file at `/home/kubeuser/.kube/kubebuddy-config.yaml`.

Example Config:

```yaml
thresholds:
  cpu_warning: 50
  cpu_critical: 75
  pod_age_warning: 15
  pod_age_critical: 40
```

**Command**:

```bash
docker run -it --rm \
  -e KUBECONFIG="/home/kubeuser/.kube/config" \
  -e HTML_REPORT="true" \
  -v $HOME/.kube/config:/tmp/kubeconfig-original:ro \
  -v $HOME/.kube/kubebuddy-config.yaml:/home/kubeuser/.kube/kubebuddy-config.yaml:ro \
  -v $HOME/kubebuddy-report:/app/Reports \
  ghcr.io/kubedeckio/kubebuddy:$tagId
```



## 📄 2. Running KubeBuddy Container with PowerShell

### Basic Usage (Non-AKS Cluster)

Generate a report for any Kubernetes cluster without AKS-specific checks.

```powershell
docker run -it --rm `
  -e KUBECONFIG="/home/kubeuser/.kube/config" `
  -e HTML_REPORT="true" `
  -v $HOME/.kube/config:/tmp/kubeconfig-original:ro `
  -v $HOME/kubebuddy-report:/app/Reports `
  ghcr.io/kubedeckio/kubebuddy:$tagId
```
You can easily switch between the **HTML**, **JSON**, and **TXT** report formats by modifying the respective environment variable in the `docker run` command. Simply change the `-e` option to set one of the following:

- **HTML Report** (default):  
  Set `HTML_REPORT="true"` to generate an HTML report.
  
- **JSON Report**:  
  Set `JSON_REPORT="true"` to generate a JSON report.
  
- **TXT Report**:  
  Set `TXT_REPORT="true"` to generate a plain text report.

For example, if you want a **JSON report** instead of the default HTML report, you would update the `docker run` command to:

```bash
docker run -it --rm \
  -e KUBECONFIG="/home/kubeuser/.kube/config" \
  -e JSON_REPORT="true" \
  -v $HOME/.kube/config:/tmp/kubeconfig-original:ro \
  -v $HOME/kubebuddy-report:/app/Reports \
  ghcr.io/kubedeckio/kubebuddy:$tagId
```

This allows you to easily toggle between different report formats for each scan without changing anything else in your setup.

### AKS Check + Report

Run with AKS-specific checks using SPN authentication and the KubeBuddy Reader role.

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

You can change the report format by simply adjusting the `-e` flag in the `docker run` command. Set `HTML_REPORT="true"`, `JSON_REPORT="true"`, or `TXT_REPORT="true"` to generate the respective report type. This flexibility allows you to easily switch between formats for each scan, without needing to alter any other settings. Just update the `-e` option as per the report format you want.


**Output**:  
Report saved to: `$HOME/kubebuddy-report/kubebuddy-report-YYYYMMDD-HHMMSS.html`



## 🛠️ Setup for AKS (Required for AKS_MODE)

For AKS clusters, you need a Service Principal (SPN) with permissions to read cluster metadata and all Kubernetes resources, including secrets. Follow these steps to create the SPN and assign the custom KubeBuddy Reader role.

### 1. Create the SPN

Run the following command to create an SPN named `kubebuddy-spn`:

```bash
az ad sp create-for-rbac --name kubebuddy-spn --output json
```

Example Output:

```json
{
  "appId": "87654321-4321-4321-4321-0987654321ba",
  "displayName": "kubebuddy-spn",
  "password": "<your-client-secret>",
  "tenant": "abcdef12-3456-7890-abcd-ef1234567890"
}
```

Save these values:

- `appId` → `AZURE_CLIENT_ID`
- `password` → `AZURE_CLIENT_SECRET`
- `tenant` → `AZURE_TENANT_ID`

**Security Note**: Store `AZURE_CLIENT_SECRET` securely (e.g., in Azure Key Vault).

### 2. Create the KubeBuddy Reader Role

Create a custom Azure role to grant read-only access to all Kubernetes resources, including secrets.

`KubeBuddyReader.json`:

```json
{
  "Name": "KubeBuddy Reader",
  "Description": "Grants read-only access to all Kubernetes resources in an AKS cluster, including secrets, for KubeBuddy reporting.",
  "Actions": [
    "Microsoft.Authorization/*/read",
    "Microsoft.Resources/subscriptions/operationresults/read",
    "Microsoft.Resources/subscriptions/read",
    "Microsoft.Resources/subscriptions/resourceGroups/read"
  ],
  "NotActions": [],
  "DataActions": [
    "Microsoft.ContainerService/managedClusters/apps/*/read",
    "Microsoft.ContainerService/managedClusters/autoscaling/*/read",
    "Microsoft.ContainerService/managedClusters/batch/*/read",
    "Microsoft.ContainerService/managedClusters/configmaps/read",
    "Microsoft.ContainerService/managedClusters/endpoints/read",
    "Microsoft.ContainerService/managedClusters/events/*/read",
    "Microsoft.ContainerService/managedClusters/extensions/*/read",
    "Microsoft.ContainerService/managedClusters/limitranges/read",
    "Microsoft.ContainerService/managedClusters/namespaces/read",
    "Microsoft.ContainerService/managedClusters/networking.k8s.io/*/read",
    "Microsoft.ContainerService/managedClusters/pods/*/read",
    "Microsoft.ContainerService/managedClusters/policy/*/read",
    "Microsoft.ContainerService/managedClusters/secrets/read",
    "Microsoft.ContainerService/managedClusters/services/read",
    "Microsoft.ContainerService/managedClusters/storage.k8s.io/*/read"
  ],
  "NotDataActions": [],
  "AssignableScopes": [
    "/subscriptions/<your-subscription-id>"
  ]
}
```

Replace `<your-subscription-id>` with your subscription ID.

Create the Role:

```bash
az role definition create --role-definition KubeBuddyReader.json
```

{: .important }
> **Note**: If you **do not** want to create a custom role, ensure your SPN has **Cluster Admin** access for full permissions on all Kubernetes resources.

### 3. Assign Permissions

Assign the KubeBuddy Reader and Azure Kubernetes Service Cluster User Role to the SPN, scoped to your AKS cluster.

Bash:

```bash
RESOURCE_GROUP="<group>"
CLUSTER_NAME="<cluster>"
SUBSCRIPTION_ID="<sub-id>"
SPN_CLIENT_ID="<your-client-id>"

# Get AKS resource ID
AKS_ID=$(az aks show --resource-group $RESOURCE_GROUP --name $CLUSTER_NAME --subscription $SUBSCRIPTION_ID --query id --output tsv)

# Assign roles
az role assignment create --role "KubeBuddy Reader" --assignee $SPN_CLIENT_ID --scope $AKS_ID
az role assignment create --role "Azure Kubernetes Service Cluster User Role" --assignee $SPN_CLIENT_ID --scope $AKS_ID
```

PowerShell:

```powershell
$ResourceGroup = "<group>"
$ClusterName = "<cluster>"
$SubscriptionId = "<sub-id>"
$SpnClientId = "<your-client-id>"

# Get AKS resource ID
$AksId = az aks show --resource-group $ResourceGroup --name $ClusterName --subscription $SubscriptionId --query id --output tsv

# Assign roles
az role assignment create --role "KubeBuddy Reader" --assignee $SpnClientId --scope $AksId
az role assignment create --role "Azure Kubernetes Service Cluster User Role" --assignee $SpnClientId --scope $AksId
```

### 4. Get Kubeconfig

Ensure your kubeconfig has access to the AKS cluster:

```bash
az aks get-credentials --resource-group <group> --name <cluster> --subscription <sub-id>
```

Example:

```bash
az aks get-credentials --resource-group rg-aks-0402-dev-uks --name aks-0402-dev-uks --subscription ee360ac1-ac8d-45c9-9bcf-76d19ae08a33
```