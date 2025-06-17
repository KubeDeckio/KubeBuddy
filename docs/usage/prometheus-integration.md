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

## ✅ Supported Prometheus Modes

| Mode     | Description                                           | Auth Required | Typical Use Case                      |
|----------|-------------------------------------------------------|---------------|---------------------------------------|
| `local`  | In-cluster Prometheus (e.g. kube-prometheus-stack)     | ❌            | No auth needed inside the cluster     |
| `basic`  | External Prometheus with HTTP Basic auth              | ✅            | Behind an ingress or firewall         |
| `bearer` | External Prometheus secured by bearer token           | ✅            | OAuth proxy, API gateway, etc.        |
| `azure`  | Azure Monitor Managed Prometheus (AKS + Monitor)      | ✅ AAD token  | AKS + Azure Monitor workspace         |

## 🔐 How to Authenticate

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
Invoke-KubeBuddy `
  -IncludePrometheus `
  -PrometheusUrl "https://prom.example.com" `
  -PrometheusMode basic `
  -PrometheusUsername "admin" `
  -PrometheusPassword "s3cr3t"
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
Invoke-KubeBuddy `
  -HtmlReport `
  -IncludePrometheus `
  -PrometheusUrl "https://prometheus.example.com" `
  -PrometheusMode basic `
  -PrometheusUsername "admin" `
  -PrometheusPassword "s3cr3t" `
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