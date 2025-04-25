---
title: AKS Configuration & Best Practices Checks
parent: Usage
nav_order: 4
---

# Setup for AKS (Required for `AKS_MODE`)

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

> **Security Note**: Store `AZURE_CLIENT_SECRET` securely (e.g., in Azure Key Vault).

### 2. Create the KubeBuddy Reader Role

Create a custom Azure role to grant read-only access to all Kubernetes resources, including secrets.

**KubeBuddyReader.json**:

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

Replace `<your-subscription-id>` with your actual subscription ID.

```bash
az role definition create --role-definition KubeBuddyReader.json
```

> **Note**: If you do **not** want to create a custom role, your SPN must have **Cluster Admin** access for full Kubernetes resource visibility.

### 3. Assign Permissions

Assign both the KubeBuddy Reader and Azure Kubernetes Service Cluster User roles to the SPN.

=== "Bash"

    ```bash
    RESOURCE_GROUP="<group>"
    CLUSTER_NAME="<cluster>"
    SUBSCRIPTION_ID="<sub-id>"
    SPN_CLIENT_ID="<your-client-id>"

    AKS_ID=$(az aks show \
      --resource-group $RESOURCE_GROUP \
      --name $CLUSTER_NAME \
      --subscription $SUBSCRIPTION_ID \
      --query id --output tsv)

    az role assignment create --role "KubeBuddy Reader" --assignee $SPN_CLIENT_ID --scope $AKS_ID
    az role assignment create --role "Azure Kubernetes Service Cluster User Role" --assignee $SPN_CLIENT_ID --scope $AKS_ID
    ```

=== "PowerShell"

    ```powershell
    $ResourceGroup = "<group>"
    $ClusterName = "<cluster>"
    $SubscriptionId = "<sub-id>"
    $SpnClientId = "<your-client-id>"

    $AksId = az aks show `
      --resource-group $ResourceGroup `
      --name $ClusterName `
      --subscription $SubscriptionId `
      --query id --output tsv

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
az aks get-credentials \
  --resource-group rg-aks-0402-dev-uks \
  --name aks-0402-dev-uks \
  --subscription ee360ac1-ac8d-45c9-9bcf-76d19ae08a33
```


# AKS Best Practice Checks

KubeBuddy powered by KubeDeck evaluates various aspects of your **Azure Kubernetes Service (AKS)** setup, highlighting potential issues and confirming best practices.

## Checks Overview

Below is a categorized list of key AKS checks, ordered by **ID and Category**.

### Best Practices

| ID        | Check                                     | Severity |
|-----------|-------------------------------------------|----------|
| AKSBP001  | Allowed Container Images Policy           | High     |
| AKSBP002  | No Privileged Containers Policy           | High     |
| AKSBP003  | Multiple Node Pools                       | Medium   |
| AKSBP004  | Azure Linux as Host OS                    | High     |
| AKSBP005  | Ephemeral OS Disks Enabled                | Medium   |
| AKSBP006  | Non-Ephemeral Disks with Adequate Size    | Medium   |
| AKSBP007  | System Node Pool Taint                    | High     |
| AKSBP008  | Auto Upgrade Channel Configured           | Medium   |
| AKSBP009  | Node OS Upgrade Channel Configured        | Medium   |
| AKSBP010  | Customized MC_ Resource Group Name        | Medium   |
| AKSBP011  | System Node Pool Minimum Size             | High     |
| AKSBP012  | Node Pool Version Matches Control Plane   | Medium   |

### Disaster Recovery

| ID        | Check                        | Severity |
|-----------|------------------------------|----------|
| AKSDR001  | Agent Pools with AZs         | High     |
| AKSDR002  | Control Plane SLA            | Medium   |

### Identity & Access

| ID         | Check                                | Severity |
|------------|--------------------------------------|----------|
| AKSIAM001  | RBAC Enabled                         | High     |
| AKSIAM002  | Managed Identity                     | High     |
| AKSIAM003  | Workload Identity Enabled            | Medium   |
| AKSIAM004  | Managed Identity Used                | High     |
| AKSIAM005  | AAD RBAC Authorization Integrated    | High     |
| AKSIAM006  | AAD Managed Authentication Enabled   | High     |
| AKSIAM007  | Local Accounts Disabled              | High     |

### Monitoring & Logging

| ID         | Check                          | Severity |
|------------|--------------------------------|----------|
| AKSMON001  | Azure Monitor                  | High     |
| AKSMON002  | Managed Prometheus Enabled     | High     |

### Networking

| ID         | Check                           | Severity |
|------------|----------------------------------|----------|
| AKSNET001  | Authorized IP Ranges            | High     |
| AKSNET002  | Network Policy Check            | Medium   |
| AKSNET003  | Web App Routing Enabled         | Low      |
| AKSNET004  | Azure CNI Networking Recommended| Medium   |

### Resource Management

| ID         | Check                                | Severity |
|------------|--------------------------------------|----------|
| AKSRES001  | Cluster Autoscaler                   | Medium   |
| AKSRES002  | AKS Built-in Cost Tooling Enabled    | Medium   |
| AKSRES003  | Vertical Pod Autoscaler Enabled      | Medium   |

### Security

| ID         | Check                             | Severity |
|------------|-----------------------------------|----------|
| AKSSEC001  | Private Cluster                   | High     |
| AKSSEC002  | Azure Policy Add-on               | Medium   |
| AKSSEC003  | Defender for Containers           | High     |
| AKSSEC004  | OIDC Issuer Enabled               | Medium   |
| AKSSEC005  | Azure Key Vault Integration       | High     |
| AKSSEC006  | Image Cleaner Enabled             | Medium   |
| AKSSEC007  | Kubernetes Dashboard Disabled     | High     |
| AKSSEC008  | Pod Security Admission Enabled    | High     |


Each check provides insights into security, performance, and cost optimization.
