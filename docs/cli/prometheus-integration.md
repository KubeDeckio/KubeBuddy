---
title: Prometheus Integration
parent: Usage
nav_order: 5
layout: default
---

# 📊 Prometheus Integration

KubeBuddy can enrich its cluster health reports by querying Prometheus directly, whether running in-cluster or as an external endpoint.

## 🔍 Why Integrate Prometheus?

By pulling time-series data you can detect:

- API server latency (p99)  
- Node/pod CPU & memory usage  
- Pod restart patterns  
- Disk, network and capacity pressure  
- Node sizing opportunities (underutilized vs saturated nodes using p95 trends)
- Pod/container sizing opportunities (p95-based request and memory limit recommendations)

## ✅ Supported Prometheus Modes

| Mode     | Description                                           | Auth Required | Typical Use Case                      |
|----------|-------------------------------------------------------|---------------|---------------------------------------|
| `local`  | In-cluster Prometheus (e.g. kube-prometheus-stack)     | ❌            | No auth needed inside the cluster     |
| `basic`  | External Prometheus with HTTP Basic auth              | ✅            | Behind an ingress or firewall         |
| `bearer` | External Prometheus secured by bearer token           | ✅            | OAuth proxy, API gateway, etc.        |
| `azure`  | Azure Monitor Managed Prometheus (AKS + Monitor)      | ✅ AAD token  | AKS + Azure Monitor workspace         |

## 🔐 How to Authenticate

For the native Go CLI, the auth model is:

- `local`: no extra auth inputs
- `azure`: uses existing Azure auth from the current shell or environment
- `bearer`: uses `--prometheus-bearer-token-env` to read a bearer token from an environment variable
- `basic`: reads `PROMETHEUS_USERNAME` and `PROMETHEUS_PASSWORD` from the environment

The PowerShell wrapper maps onto the same runtime, but can also help populate those environment variables for you.

## Native CLI Examples

### Local (no auth)

```bash
kubebuddy run \
  --html-report \
  --include-prometheus \
  --prometheus-url "http://prometheus.monitoring.svc:9090" \
  --prometheus-mode local \
  --yes
```

### Bearer Token

```bash
export PROMETHEUS_TOKEN="<your-token>"

kubebuddy run \
  --include-prometheus \
  --prometheus-url "https://prom.example.com" \
  --prometheus-mode bearer \
  --prometheus-bearer-token-env PROMETHEUS_TOKEN \
  --yes
```

### Azure Monitor (AAD)

```bash
az login

kubebuddy run \
  --include-prometheus \
  --prometheus-url "https://<workspace>.prometheus.monitor.azure.com" \
  --prometheus-mode azure \
  --yes
```

### Basic Auth

```bash
export PROMETHEUS_USERNAME="admin"
export PROMETHEUS_PASSWORD="s3cr3t"

kubebuddy run \
  --include-prometheus \
  --prometheus-url "https://prom.example.com" \
  --prometheus-mode basic \
  --yes
```

## PowerShell Wrapper Examples

### Local (no auth)
```powershell
Invoke-KubeBuddy `
  -HtmlReport `
  -IncludePrometheus `
  -PrometheusUrl "http://prometheus.monitoring.svc:9090" `
  -PrometheusMode local
````

### Basic Auth

```powershell
$env:PROMETHEUS_USERNAME = "admin"
$env:PROMETHEUS_PASSWORD = "s3cr3t"

Invoke-KubeBuddy `
  -IncludePrometheus `
  -PrometheusUrl "https://prom.example.com" `
  -PrometheusMode basic
```

### Bearer Token

```powershell
$env:PROMETHEUS_TOKEN = "<your-token>"
Invoke-KubeBuddy `
  -IncludePrometheus `
  -PrometheusUrl "https://prom.example.com" `
  -PrometheusMode bearer `
  -PrometheusBearerTokenEnv PROMETHEUS_TOKEN
```

### Azure Monitor (AAD)

```powershell
# Ensure AZURE_CLIENT_ID / SECRET / TENANT_ID are set
Invoke-KubeBuddy `
  -IncludePrometheus `
  -PrometheusUrl "https://<workspace>.prometheus.monitor.azure.com" `
  -PrometheusMode azure
```

## 🧪 Example Query

> p99 API-server latency over last hour
> `histogram_quantile(0.99, rate(apiserver_request_duration_seconds_bucket[5m]))`


## ⏱️ Time-Window Configuration

Rather than being fixed, the look-back window is now driven by your YAML’s `Range.Duration`. You can specify minutes (`m`), hours (`h`), or days (`d`):

```yaml
Prometheus:
  Query: 'sum(rate(container_cpu_usage_seconds_total{container!="",pod!=""}[5m])) by (pod)'
  Range:
    Step:    "5m"
    Duration: "24h"    # supports "m"=minutes, "h"=hours, "d"=days
```

KubeBuddy will translate that into `start = now - 24h` (or 30m, or 2d, etc.) automatically.


## ▶️ CLI Usage

Use any combination of report outputs:

```powershell
# HTML report with Prometheus
$promCred = Get-Credential

Invoke-KubeBuddy `
  -HtmlReport `
  -IncludePrometheus `
  -PrometheusUrl "https://prometheus.example.com" `
  -PrometheusMode basic `
  -PrometheusCredential $promCred `
  -OutputPath "C:\reports\cluster.html"
```

```powershell
# Text report with Prometheus
Invoke-KubeBuddy `
  -txtReport `
  -IncludePrometheus `
  -PrometheusUrl "http://prometheus.monitoring.svc:9090" `
  -PrometheusMode local `
  -OutputPath "/home/user/kube.txt"
```

```powershell
# JSON report, Azure Monitor mode
Invoke-KubeBuddy `
  -jsonReport `
  -IncludePrometheus `
  -PrometheusUrl "https://<workspace>.prometheus.monitor.azure.com" `
  -PrometheusMode azure `
  -OutputPath "/reports/cluster.json"
```

## 📐 Node Sizing Insights

When Prometheus integration is enabled, KubeBuddy runs `PROM006` and classifies each node using fixed **7-day p95** CPU/memory usage:

- `Underutilized`: candidate for smaller SKU or scale-in
- `Right-sized`: keep current sizing
- `Saturated`: candidate for larger SKU or scale-out

`PROM006` now also includes:
- **Current Allocatable (vCPU/Gi)** from node allocatable capacity
- **Suggested Target Capacity (vCPU/Gi)** estimated from p95 utilization with safety headroom

Minimum data rule:
- KubeBuddy requires at least **7 days of Prometheus history** before emitting node sizing recommendations.
- If history is below 7 days, reports include an explicit **Insufficient Prometheus history** row instead of recommendations.

The check surfaces in the **Nodes** tab and in JSON/text output like any other check.

In HTML reports, Overview now includes a **Rightsizing at a Glance** section that summarizes:
- Node sizing distribution (`Underutilized` / `Saturated` / `Right-sized`)
- Pod sizing action counts from `PROM007`
- Impact buckets and quick links to `PROM006` and `PROM007`

### Optional Threshold Overrides

You can tune the classification in `~/.kube/kubebuddy-config.yaml`:

```yaml
thresholds:
  node_sizing_downsize_cpu_p95: 35
  node_sizing_downsize_mem_p95: 40
  node_sizing_upsize_cpu_p95: 80
  node_sizing_upsize_mem_p95: 85
```

## 📦 Pod Sizing Insights

When Prometheus integration is enabled, KubeBuddy also runs `PROM007` for per-container recommendations using fixed **7-day p95** usage:

- CPU request recommendation (millicores)
- Memory request recommendation (MiB)
- Memory limit recommendation (MiB)
- CPU limit recommendation defaults to `none`

Minimum data rule:
- KubeBuddy requires at least **7 days of Prometheus history** before emitting pod sizing recommendations.
- If history is below 7 days, reports include an explicit **Insufficient Prometheus history** row instead of recommendations.

### Why CPU limit defaults to `none`

By default, KubeBuddy recommends no CPU limit because:

- CPU is compressible; requests already control fair scheduling.
- Hard CPU limits can trigger CFS throttling and add latency jitter.
- In many production workloads, setting requests (without limits) gives better tail latency.

Set CPU limits only when strict tenant caps are required.

### Optional Pod Sizing Threshold Overrides

```yaml
thresholds:
  pod_sizing_profile: balanced   # conservative|balanced|aggressive
  pod_sizing_compare_profiles: true  # HTML/JSON include all 3 profiles by default
  pod_sizing_target_cpu_utilization: 65
  pod_sizing_target_mem_utilization: 75
  pod_sizing_cpu_request_floor_mcores: 25
  pod_sizing_mem_request_floor_mib: 128
  pod_sizing_mem_limit_buffer_percent: 20
```

Profile behavior:
- `conservative`: higher requests/floors (more headroom)
- `balanced`: default behavior (`CPU floor: 25m`)
- `aggressive`: lower requests/floors (higher packing efficiency, `CPU floor: 10m`)

Comparison mode:
- `pod_sizing_compare_profiles` is enabled by default to emit all three profile results in JSON and HTML.
- Set `pod_sizing_compare_profiles: false` if you want only the active profile.
- HTML report includes a profile selector on `PROM007` findings so you can switch between profiles.
- Text/CLI remain focused on the single active profile.

## 🐳 Docker Usage with Prometheus

For full Docker details, see the [Docker Usage](docker-usage.md) guide.  Here’s a minimal Prometheus-enabled example:

```bash
export tagId="v0.0.19"

docker run -it --rm \
  -e KUBECONFIG="/home/kubeuser/.kube/config" \
  -e HTML_REPORT="true" \
  -e INCLUDE_PROMETHEUS="true" \
  -e PROMETHEUS_URL="https://prom.example.com" \
  -e PROMETHEUS_MODE="basic" \
  -e PROMETHEUS_USERNAME="admin" \
  -e PROMETHEUS_PASSWORD="s3cr3t" \
  -v $HOME/.kube/config:/tmp/kubeconfig-original:ro \
  -v $HOME/kubebuddy-report:/app/Reports \
  ghcr.io/kubedeckio/kubebuddy:$tagId
```

## 📘 Related Docs

* [Azure Monitor Prometheus Overview](https://learn.microsoft.com/azure/azure-monitor/prometheus-metrics-overview)
* [Prometheus HTTP API](https://prometheus.io/docs/prometheus/latest/querying/api/)
