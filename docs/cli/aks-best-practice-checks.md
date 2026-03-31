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

## AKS Automatic Migration Readiness

When you run KubeBuddy with `-Aks`, the AKS report section now also derives an **AKS Automatic Migration Readiness** view from existing shared Kubernetes and AKS checks.

This readiness view is designed for **moving workloads to a new AKS Automatic cluster**, not for converting the current cluster in place.

### What it does

- Reuses existing Kubernetes and AKS checks rather than running a separate AKS Automatic engine.
- Marks findings as **blockers** or **warnings** using AKS Automatic relevance metadata on shared checks.
- Resolves affected resources back to the source workload where possible:
  - `Deployment/foo via Pod/foo-...`
  - `StatefulSet/bar via Pod/bar-...`
  - Helm-managed workloads are annotated so you can see chart ownership in remediation examples.
- Skips the readiness section entirely if the source AKS cluster is already `sku.name = Automatic`.

### Where it appears

- **HTML report**: a collapsed `AKS Automatic Migration Readiness` section inside the existing **AKS Best Practices** tab.
- **Text report / CLI output**: a derived readiness summary with blockers, warnings, build notes, and action items.
- **JSON report**:
  - `metadata.aksAutomaticSummary`
  - `aksAutomaticReadiness.summary`
  - `aksAutomaticReadiness.blockers`
  - `aksAutomaticReadiness.warnings`
  - `aksAutomaticReadiness.alignment`
  - `aksAutomaticReadiness.actionPlan`
- **Standalone HTML action plan**: a separate `*-aks-automatic-action-plan.html` artifact when migration actions are present.

### What the action plan contains

- **Suggested Migration Sequence**: an ordered runbook view that starts with blocker remediation, then warning review, then target-cluster creation and cutover.
- **Fix Before Migration**: blocker-driven actions that should be completed before deploying workloads to a new AKS Automatic cluster.
- **Warnings to Review**: warning-driven actions that do not block migration by themselves but reduce drift and post-cutover rework.
- **Affected resources tables**: per-action resource tables showing namespace, owning workload, observed resource, and Helm source where detected.
- **Manifest examples**: YAML snippets for common remediation patterns such as image tags, requests, probes, spread constraints, Gateway API routes, and securityContext changes.
- **Microsoft Learn links** for creating a new AKS Automatic cluster by:
  - Azure portal
  - Azure CLI
  - Bicep
  - Terraform via the official AzAPI `managedClusters` reference

### Observed AKS Automatic behavior modeled by KubeBuddy

KubeBuddy now classifies AKS Automatic readiness using observed admission behavior from real AKS Automatic cluster tests.

- **Blockers** currently include patterns such as:
  - privileged containers
  - host network / host PID / host IPC
  - host ports
  - hostPath volumes
  - unconfined seccomp
  - non-default `procMount`
  - unsupported AppArmor values
  - missing resource requests
  - `latest` or unpinned image tags
  - added unsupported Linux capabilities
  - replicated workloads missing spread constraints
  - duplicate Service selectors
  - in-tree Azure storage provisioners
- **Warnings** currently include:
  - missing probes
  - missing explicit seccomp profile
  - running as root
  - Ingress usage that should be reviewed for Gateway API migration planning

### Shared checks added or updated for AKS Automatic readiness

The AKS Automatic readiness view is built on top of shared checks. Recent additions and updates include:

- `WRK005` – Missing Resource Requests
- `WRK014` – Missing Memory Limits
- `WRK015` – Replicated Workloads Missing Spread Constraints
- `NET013` – Ingress Present Without Gateway API Adoption
- `NET018` – Duplicate Service Selectors
- updated AKS Automatic metadata on image tag, security, storage, probes, and AKS alignment checks

### Ingress and Gateway API

KubeBuddy now highlights Ingress usage as part of AKS Automatic migration planning.

- If a cluster still relies on legacy Ingress patterns and has not adopted Gateway API resources, the readiness output emits a migration warning.
- The standalone action plan includes a dedicated ingress migration action with:
  - Gateway API planning steps
  - a `Gateway` / `HTTPRoute` manifest example
  - Microsoft Learn references for AKS application routing with Gateway API

This is intended to help teams plan for modern AKS ingress patterns rather than assuming an NGINX-based ingress controller on the destination cluster.

### Important scope note

This feature answers the question:

> Can these workloads and current usage patterns be moved to a **new AKS Automatic cluster**, and what must be changed first?

It does **not** attempt to fully redesign the destination platform for you, and it does **not** treat every AKS best-practice issue as an AKS Automatic migration blocker.

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
| AKSBP013  | No B-Series VMs in Node Pools             | High     |
| AKSBP014  | Use v5 or Newer SKU VMs for Node Pools    | Medium   |

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
