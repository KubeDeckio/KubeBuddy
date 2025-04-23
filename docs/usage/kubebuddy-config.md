---
title: Configuration File
parent: Usage
nav_order: 2
layout: default
---

# kubebuddy Configuration

KubeBuddy powered by KubeDeck uses a YAML configuration file to customize its behavior, allowing you to tailor monitoring, health checks, and security scans to your Kubernetes environment. This file enables fine-grained control over thresholds, namespaces, trusted registries, and specific checks, ensuring that KubeBuddy aligns with your operational needs and policies.

The configuration file is located at:
`~/.kube/kubebuddy-config.yaml`

If the file is missing or a specific section is not defined, KubeBuddy falls back to sensible defaults, ensuring consistent behavior out of the box.

This guide provides a detailed explanation of each configuration section, including practical use cases, example configurations, and best practices for optimizing KubeBuddy in your Kubernetes clusters, including Azure Kubernetes Service (AKS).

## Configuration Overview

The `kubebuddy-config.yaml` file supports the following sections:
- **Thresholds**: Customize resource usage and health check thresholds for nodes, pods, jobs, and events.
- **Excluded Namespaces**: Skip specific namespaces (e.g., system namespaces) from monitoring and checks.
- **Trusted Registries**: Define trusted container image registries to flag unapproved sources.
- **Excluded Checks**: Disable specific checks to tailor KubeBuddy’s analysis to your environment.

Each section is optional, and KubeBuddy applies default values when configurations are not specified. Below, we dive into each section with detailed explanations, examples, and scenarios to help you configure KubeBuddy effectively.

## 1. Thresholds

The `thresholds` section allows you to define custom limits for health checks on Kubernetes resources, such as nodes, pods, jobs, and events. These thresholds determine when KubeBuddy flags a resource as in a warning or critical state based on metrics like CPU usage, memory consumption, pod restarts, or event frequency.

### Purpose
Thresholds are critical for aligning KubeBuddy’s monitoring with your cluster’s operational requirements. For example, a high-performance cluster might tolerate higher CPU usage before triggering a warning, while a cost-sensitive environment might need stricter limits to optimize resource utilization.

### Supported Metrics
The following metrics can be customized:
- **CPU and Memory Usage**: Percentage-based thresholds for warning and critical states.
- **Pod Restarts**: Number of restarts that trigger warnings or critical alerts.
- **Pod Age**: Age (in days) of pods that may indicate stale or problematic deployments.
- **Job Status**: Duration (in hours) for stuck or failed jobs.
- **Event Counts**: Number of error or warning events that trigger alerts.

### Default Behavior
If the `thresholds` section is missing or incomplete, KubeBuddy uses built-in defaults, which are designed for general-purpose Kubernetes clusters. These defaults are conservative to avoid false positives but may need adjustment for specific workloads (e.g., batch processing, machine learning, etc.).

### Configuration Example
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
  stuck_job_hours: 2
  failed_job_hours: 2
  event_errors_warning: 10
  event_errors_critical: 20
  event_warnings_warning: 50
  event_warnings_critical: 100
```

### Use Case
Suppose you’re managing an AKS cluster for a web application with strict performance requirements. You might set higher CPU thresholds to avoid unnecessary alerts during traffic spikes:

```yaml
thresholds:
  cpu_warning: 70
  cpu_critical: 90
  mem_warning: 60
  mem_critical: 85
```

For a batch-processing cluster, you might lower the stuck_job_hours threshold to detect stalled jobs faster:

```yaml
thresholds:
  stuck_job_hours: 1
  failed_job_hours: 1
```

### Best Practices

- **Start with Defaults**: Use the default thresholds initially and adjust based on observed cluster behavior.
- Monitor Trends: Use tools like Azure Monitor or Prometheus to analyze resource usage before setting thresholds.
- **Environment-Specific Tuning**: Tailor thresholds for different clusters (e.g., production vs. development) by maintaining separate configuration files.
- **Document Changes**: Note why specific thresholds were chosen to aid troubleshooting and team collaboration.

## 2. Excluded Namespaces

The excluded_namespaces section allows you to skip specific Kubernetes namespaces from KubeBuddy’s checks, such as those for pods, secrets, ConfigMaps, and RBAC. This is particularly useful for ignoring system namespaces or third-party namespaces that are not relevant to your monitoring scope.

### Purpose
Excluding namespaces reduces noise in reports and focuses KubeBuddy on namespaces you control. For example, system namespaces like kube-system often contain pods and resources managed by Kubernetes itself, which may not require the same scrutiny as application namespaces.

### Integration with -ExcludeNamespaces
The `-ExcludeNamespaces` switch in KubeBuddy’s PowerShell commands (`Invoke-KubeBuddy -ExcludeNamespaces`) automatically applies the excluded_namespaces list. If the list is not defined, KubeBuddy uses a default set of namespaces.

### Configuration Example

```yaml
excluded_namespaces:
  - kube-system
  - kube-public
  - kube-node-lease
  - local-path-storage
  - coredns
  - calico-system
```

### Use Case
In an AKS cluster, you might exclude namespaces managed by Azure or networking components to focus on your application workloads:

```yaml
excluded_namespaces:
  - kube-system
  - azure-monitor
  - calico-system
  - my-third-party-tool
```

This ensures KubeBuddy’s reports and alerts are relevant to your team’s responsibilities.

### Best Practices
- **Review Namespaces**: Identify all system or third-party namespaces in your cluster using kubectl get namespaces.
- **Update Regularly**: Add new namespaces to the exclusion list as you integrate new tools or services.
- **Test Exclusions**: Run KubeBuddy with `-ExcludeNamespaces` and verify that the excluded namespaces are skipped as expected.

## 3. Trusted Registries
The `trusted_registries` section defines which container image registries are considered safe for your cluster. KubeBuddy flags pods using images from unlisted registries, helping you enforce security policies and prevent the use of unapproved or potentially malicious images.

### Purpose
Container images from untrusted sources can introduce vulnerabilities or compliance risks. By specifying trusted registries, you ensure that KubeBuddy highlights any deviations from your approved image sources, such as developers pulling images from public registries like docker.io without vetting.

### Default Behavior
If `trusted_registries` is not defined, KubeBuddy trusts only mcr.microsoft.com/ (Microsoft Container Registry) by default, as it’s commonly used for AKS and Azure-related images.

### Configuration Example
```yaml
trusted_registries:
  - mcr.microsoft.com/
  - mycompanyregistry.com/
  - ghcr.io/approved-org/
```
!!! note
    - **Prefix Matching**: Registry entries use prefix matching. For example, `mcr.microsoft.com/` matches all images from that registry (e.g., `mcr.microsoft.com/aks/aks-engine`).
    - **Security Checks**: The Untrusted Image Registries check (e.g., `SEC014`) uses this list to identify non-compliant pods.
    - **Impact**: Images from untrusted registries are flagged in reports and the interactive UI, allowing you to investigate and remediate.

### Use Case
A company with a private registry might configure KubeBuddy to trust only their internal registry and a specific open-source registry:

```yaml
trusted_registries:
  - mycompanyregistry.com/
  - ghcr.io/trusted-open-source/
```

If a developer deploys a pod using an image from docker.io/unknown-org/, KubeBuddy will flag it in the reports, prompting a security review.

### Best Practices
- **Limit Trusted Registries**: Include only registries you actively vet or control to minimize risks.
- **Audit Regularly**: Periodically review trusted registries to ensure they align with your security policies.
Integrate with CI/CD: Enforce trusted registries in your CI/CD pipelines (e.g., Azure DevOps) to prevent untrusted images from being deployed.

## 4. Excluded Checks
The excluded_checks section allows you to disable specific KubeBuddy checks that are not relevant to your environment. This is useful for tailoring KubeBuddy’s analysis to your cluster’s architecture, policies, or operational constraints.

### Purpose
Some checks may not apply due to your cluster’s configuration or security requirements. For example, a check for RBAC misconfigurations (SEC007) might be irrelevant if your cluster uses a custom authorization model. Excluding checks reduces false positives and focuses reports on actionable issues.

### Configuration Example

```yaml
excluded_checks:
  - SEC014
  - WRK008
```

!!! note
    - **Exact Match Required**: Each entry must match the exact check ID (e.g., SEC014 for the untrusted registries check).
    - **Manual Override**: Excluded checks can still be run manually via KubeBuddy’s interactive UI (`Invoke-KubeBuddy` without parameters).
    - **Impact**: Excluded checks are skipped during automated runs (e.g., with `-HtmlReport`) but do not affect other checks.

### Use Case
In a development cluster, you might exclude workload-related checks that enforce strict resource limits (WRK008) to allow more flexibility:

```yaml
excluded_checks:
  - WRK008
  - SEC007
```

In a production cluster, you might exclude a check that flags deprecated APIs (SEC015) if you’ve already mitigated those issues:

```yaml
excluded_checks:
  - SEC015
```

### Best Practices
- **Document Exclusions**: Record why specific checks are excluded to maintain transparency with your team.
- **Review Periodically**: Re-evaluate excluded checks when updating KubeBuddy or changing cluster configurations.
- **Test Impact**: Run KubeBuddy with and without exclusions to ensure critical issues aren’t missed.

## 5. Full Configuration Example
Below is a comprehensive example of a `kubebuddy-config.yaml` file that combines all sections for a production cluster:

```yaml
thresholds:
  cpu_warning: 60
  cpu_critical: 85
  mem_warning: 55
  mem_critical: 80
  restarts_warning: 2
  restarts_critical: 4
  pod_age_warning: 10
  pod_age_critical: 30
  stuck_job_hours: 1
  failed_job_hours: 1
  event_errors_warning: 5
  event_errors_critical: 15
  event_warnings_warning: 20
  event_warnings_critical: 50

excluded_namespaces:
  - kube-system
  - kube-public
  - kube-node-lease
  - azure-monitor
  - calico-system
  - local-path-storage

trusted_registries:
  - mcr.microsoft.com/
  - mycompanyregistry.com/
  - ghcr.io/approved-org/
  - docker.io/mycompany/

excluded_checks:
  - SEC007
  - WRK011
```

## 6. Applying the Configuration
To use the `kubebuddy-config.yaml` file, ensure it’s correctly formatted and placed in the default location (`~/.kube/kubebuddy-config.yaml`). Then, run KubeBuddy with any command, such as:

```powershell
Invoke-KubeBuddy -HtmlReport
```

KubeBuddy automatically loads the configuration and applies the specified thresholds, exclusions, and trusted registries. For AKS-specific checks, include the necessary parameters:

```powershell
Invoke-KubeBuddy -Aks -SubscriptionId <subscriptionID> -ResourceGroup <resourceGroup> -ClusterName <clusterName> -HtmlReport
```

### Verifying Configuration
To confirm that KubeBuddy is using your configuration:

- Run `Invoke-KubeBuddy` and check the interactive UI for applied thresholds.
- Generate a report (`-HtmlReport`) and verify that excluded namespaces and checks are skipped.
- Inspect the report for flagged untrusted registries to ensure the `trusted_registries` list is enforced.

## 7. Best Practices for Configuration Management

- **Version Control**: Store kubebuddy-config.yaml in a Git repository to track changes and collaborate with your team.
- **Validate Syntax**: Use a YAML linter (e.g., yamllint) to catch syntax errors before deploying the file.
- **Test Incrementally**: Apply changes to a non-production cluster first to validate their impact.
- **Integrate with CI/CD**: Automate configuration deployment as part of your cluster provisioning pipeline (e.g., using Azure DevOps or GitHub Actions).
- **Monitor Impact**: Use Azure Monitor or KubeBuddy’s reports to assess how configuration changes affect cluster health and alerts.

## 8. Troubleshooting Configuration Issues
If KubeBuddy isn’t behaving as expected with your configuration:

- **Check File Location**: Ensure the file is at `~/.kube/kubebuddy-config.yaml`
- **Validate YAML**: Use an online YAML validator
- **Inspect Defaults**: If a section is missing, confirm that the default behavior aligns with your expectations.

- **Test with Minimal Config**: Temporarily use a minimal `kubebuddy-config.yaml` to isolate problematic settings.