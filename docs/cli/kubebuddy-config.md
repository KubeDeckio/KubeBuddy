---
title: Configuration File
parent: Usage
nav_order: 2
layout: default
---

# kubebuddy Configuration

KubeBuddy uses a YAML configuration file to keep scan behavior consistent across runs and clusters. The Go-native runtime and the PowerShell wrapper both read the same `kubebuddy-config.yaml` model.

Supported sections:

- `thresholds`
- `excluded_namespaces`
- `trusted_registries`
- `excluded_checks`
- `radar`

## Default Location

By default KubeBuddy looks for:

```text
~/.kube/kubebuddy-config.yaml
```

You can override that with:

- CLI: `--config-path /path/to/kubebuddy-config.yaml`
- PowerShell wrapper: `Invoke-KubeBuddy -ConfigPath /path/to/kubebuddy-config.yaml`
- Environment variable: `KUBEBUDDY_CONFIG=/path/to/kubebuddy-config.yaml`
- Container env: `KUBEBUDDY_CONFIG_PATH=/path/to/kubebuddy-config.yaml`

If the file is missing, unreadable, or partially defined, KubeBuddy falls back to built-in defaults.

## Full Example

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
  pods_per_node_warning: 80
  pods_per_node_critical: 90
  storage_usage_threshold: 80
  node_sizing_downsize_cpu_p95: 30
  node_sizing_downsize_mem_p95: 35
  node_sizing_upsize_cpu_p95: 80
  node_sizing_upsize_mem_p95: 85
  pod_sizing_profile: balanced
  pod_sizing_compare_profiles: true
  pod_sizing_target_cpu_utilization: 65
  pod_sizing_target_mem_utilization: 75
  pod_sizing_cpu_request_floor_mcores: 25
  pod_sizing_mem_request_floor_mib: 128
  pod_sizing_mem_limit_buffer_percent: 20
  prometheus_timeout_seconds: 60
  prometheus_query_retries: 2
  prometheus_retry_delay_seconds: 2

excluded_namespaces:
  - kube-system
  - kube-public
  - kube-node-lease
  - calico-system
  - gatekeeper-system

trusted_registries:
  - mcr.microsoft.com/
  - ghcr.io/approved-org/
  - mycompanyregistry.azurecr.io/

excluded_checks:
  - SEC014
  - WRK011

radar:
  enabled: false
  api_base_url: "https://radar.kubebuddy.io/api/kb-radar/v1"
  environment: "prod"
  api_user: ""
  api_password: ""
  api_user_env: "KUBEBUDDY_RADAR_API_USER"
  api_password_env: "KUBEBUDDY_RADAR_API_PASSWORD"
  upload_timeout_seconds: 30
  upload_retries: 2
```

## Thresholds

The `thresholds` section tunes health, event, sizing, and Prometheus retry behavior.

Core thresholds:

```yaml
thresholds:
  cpu_warning: 50
  cpu_critical: 75
  mem_warning: 50
  mem_critical: 75
  disk_warning: 60
  disk_critical: 80
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
  pods_per_node_warning: 80
  pods_per_node_critical: 90
  storage_usage_threshold: 80
```

Sizing thresholds:

```yaml
thresholds:
  node_sizing_downsize_cpu_p95: 35
  node_sizing_downsize_mem_p95: 40
  node_sizing_upsize_cpu_p95: 80
  node_sizing_upsize_mem_p95: 85
  pod_sizing_profile: balanced
  pod_sizing_compare_profiles: true
  pod_sizing_target_cpu_utilization: 65
  pod_sizing_target_mem_utilization: 75
  pod_sizing_cpu_request_floor_mcores: 25
  pod_sizing_mem_request_floor_mib: 128
  pod_sizing_mem_limit_buffer_percent: 20
```

Prometheus client thresholds:

```yaml
thresholds:
  prometheus_timeout_seconds: 60
  prometheus_query_retries: 2
  prometheus_retry_delay_seconds: 2
```

`pod_sizing_profile` supports:

- `conservative`
- `balanced`
- `aggressive`

If you set a profile and do not override the related pod sizing values, KubeBuddy applies the same profile defaults that the old PowerShell runtime used.

## Excluded Namespaces

`excluded_namespaces` defines the namespace list that is applied when you opt into namespace exclusion.

Use it with:

- CLI: `kubebuddy run --exclude-namespaces`
- CLI: `kubebuddy scan --exclude-namespaces`
- PowerShell: `Invoke-KubeBuddy -ExcludeNamespaces`

You can extend the configured list at runtime with:

- CLI: `--additional-excluded-namespaces istio-system,azure-monitor`
- PowerShell: `-AdditionalExcludedNamespaces "istio-system","azure-monitor"`

Example:

```yaml
excluded_namespaces:
  - kube-system
  - kube-public
  - kube-node-lease
  - aks-istio-system
  - gatekeeper-system
```

Default exclusions, when no config file overrides them, are:

- `kube-system`
- `kube-public`
- `kube-node-lease`
- `local-path-storage`
- `kube-flannel`
- `tigera-operator`
- `calico-system`
- `coredns`
- `aks-istio-system`
- `gatekeeper-system`

## Trusted Registries

`trusted_registries` controls the allow-list used by `SEC014`.

Example:

```yaml
trusted_registries:
  - mcr.microsoft.com/
  - ghcr.io/approved-org/
  - mycompanyregistry.azurecr.io/
```

Registry matching is prefix-based. If `trusted_registries` is not defined, KubeBuddy trusts only:

```yaml
- mcr.microsoft.com/
```

## Excluded Checks

`excluded_checks` disables matching checks in both Kubernetes and AKS runs.

Example:

```yaml
excluded_checks:
  - SEC014
  - WRK011
  - AKSSEC001
```

Entries are matched by check ID, case-insensitively.

## Radar Defaults

The `radar` section provides defaults for the Radar client. Explicit CLI flags still win for that run.

Example:

```yaml
radar:
  enabled: true
  api_base_url: "https://radar.kubebuddy.io/api/kb-radar/v1"
  environment: "prod"
  api_user_env: "KUBEBUDDY_RADAR_API_USER"
  api_password_env: "KUBEBUDDY_RADAR_API_PASSWORD"
  upload_timeout_seconds: 30
  upload_retries: 2
```

Precedence:

1. CLI / PowerShell parameters
2. `kubebuddy-config.yaml`
3. built-in defaults

`-RadarUpload` and `-RadarCompare` still force Radar on for that run, even if `radar.enabled` is `false`.

## Usage Examples

Native CLI:

```bash
kubebuddy run --config-path ~/.kube/kubebuddy-config.yaml --html-report --yes
kubebuddy scan --config-path ~/.kube/kubebuddy-config.yaml --exclude-namespaces --output json
kubebuddy scan-aks --config-path ~/.kube/kubebuddy-config.yaml --subscription-id <sub> --resource-group <rg> --cluster-name <cluster> --output json
```

PowerShell wrapper:

```powershell
Invoke-KubeBuddy -ConfigPath ~/.kube/kubebuddy-config.yaml -HtmlReport
Invoke-KubeBuddy -ConfigPath ~/.kube/kubebuddy-config.yaml -ExcludeNamespaces -jsonReport
```

## Practical Notes

- `excluded_namespaces` is only applied when you opt into namespace exclusion with the relevant flag or switch.
- `trusted_registries` affects `SEC014`.
- `excluded_checks` applies to both Kubernetes and AKS catalogs.
- Radar config values act as defaults; CLI and wrapper flags override them.
