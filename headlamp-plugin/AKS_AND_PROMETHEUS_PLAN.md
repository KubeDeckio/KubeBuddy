# AKS-Aware Checks and Prometheus Support

This note captures a future direction for the KubeBuddy Headlamp plugin.

## Current Position

The Headlamp plugin currently runs Kubernetes-only KubeBuddy checks using resource data available through Headlamp. This keeps the plugin portable across Kubernetes clusters and avoids requiring cloud credentials.

Prometheus checks are not currently included in the Headlamp plugin. The CLI supports Prometheus explicitly, but the Headlamp plugin does not yet query a Prometheus API.

## Managed Prometheus in AKS Desktop

AKS Desktop appears to support Azure Managed Prometheus mainly through AKS capability detection and remediation, not by directly running PromQL from the Headlamp frontend.

The AKS Desktop approach uses Azure CLI integration from the desktop app to:

- detect whether Azure Monitor managed Prometheus is enabled with `az aks show`
- read `azureMonitorProfile.metrics.enabled`
- enable the addon with `az aks update --enable-azure-monitor-metrics`

This is different from querying Azure Managed Prometheus. Azure Managed Prometheus uses an Azure Monitor workspace endpoint and requires Microsoft Entra authentication for PromQL API calls.

## Proposed Plugin Model

Keep the scan model layered:

- Kubernetes checks: always available when Headlamp can read cluster resources.
- AKS checks: available when the cluster is AKS and Azure CLI/Azure auth is available.
- Prometheus checks: available when a Prometheus query endpoint is configured and reachable.

The UI should clearly show whether each layer is:

- Available
- Not configured
- Not supported in this environment
- Blocked by missing Azure login or permissions

## AKS Best-Practice Checks

If an AKS-aware path is added, KubeBuddy can add checks that are not possible from Kubernetes resources alone.

Potential checks:

- Azure RBAC enabled
- Microsoft Entra ID integration enabled
- Azure Monitor managed Prometheus enabled
- Container Insights enabled
- Network policy configured
- Network plugin mode identified
- KEDA addon enabled where relevant
- VPA addon enabled where relevant
- AKS SKU/tier reviewed
- Upgrade channel or node OS upgrade settings reviewed
- Defender/security-related AKS settings reviewed if exposed by `az aks show`

## Provider-Aware Suppression

AKS data can also reduce false positives in existing Kubernetes checks.

Examples:

- Suppress AKS-managed RBAC roles and bindings.
- Detect AKS-managed namespaces and addons instead of relying only on hardcoded namespace lists.
- Distinguish provider-owned resources from user-owned resources in findings.
- Improve recommendations with AKS-specific commands and links.

## Prometheus Options

There are three practical Prometheus paths.

### In-Cluster Prometheus

Query an in-cluster Prometheus service through Headlamp's Kubernetes API proxy.

This works well for self-managed Prometheus installations such as kube-prometheus-stack because the browser talks to the Kubernetes API, and Kubernetes handles service proxying and RBAC.

### Azure Managed Prometheus

Querying Azure Managed Prometheus directly requires an Azure Monitor workspace query endpoint and Microsoft Entra bearer token.

This should not be implemented by storing client secrets or long-lived tokens in the browser plugin.

Safer options:

- use a backend/proxy that handles Azure authentication
- use Headlamp Desktop/Azure CLI integration if a secure token flow is available
- only detect and enable the AKS addon from the plugin, leaving PromQL querying for a later backend-supported design

### Reusing a Headlamp Prometheus Plugin

A third-party Headlamp Prometheus plugin can chart in-cluster Prometheus data by storing a service address such as `namespace/service:port` and using Headlamp's API proxy.

KubeBuddy could optionally read compatible Prometheus plugin configuration to avoid duplicate setup, but should not depend on another plugin being installed.

## Implementation Notes

Suggested future implementation order:

1. Add an AKS capability detector behind a clear "AKS checks" availability state.
2. Use Azure CLI only when running in Headlamp Desktop and `runCommand` is available.
3. Add AKS-only checks as a separate section in the report.
4. Improve AKS-managed resource suppression in RBAC and namespace checks.
5. Add in-cluster Prometheus support using the Kubernetes API proxy.
6. Revisit Azure Managed Prometheus querying only if there is a secure auth/proxy design.

The Kubernetes-only scan path should remain the default and should continue to work without Azure credentials.
