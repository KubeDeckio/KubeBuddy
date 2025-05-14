---
title: Prometheus Integration
parent: Usage
nav_order: 3
layout: default
---

# 📊 Prometheus Integration

KubeBuddy can enrich its cluster health reports by querying Prometheus directly, whether running in, cluster or as an external endpoint.


## 🔍 Why Integrate Prometheus?

By pulling time-series data you can detect:

- API server latency (p99)
- Node/pod CPU & memory usage
- Pod restart patterns
- Disk, network and capacity pressure


## ✅ Supported Prometheus Modes

| Mode     | Description                                           | Auth Required | Typical Use Case                      |
|----------|-------------------------------------------------------|---------------|---------------------------------------|
| `local`  | In-cluster Prometheus (e.g. kube-prometheus-stack)    | ❌             | No auth needed inside the cluster     |
| `basic`  | External Prometheus with HTTP Basic auth              | ✅             | Behind an ingress or firewall         |
| `bearer` | External Prometheus secured by bearer token           | ✅             | OAuth proxy, API gateway, etc.        |
| `azure`  | Azure Monitor Managed Prometheus (AKS + Monitor)      | ✅ AAD token   | AKS + Azure Monitor workspace         |


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

KubeBuddy will surface that metric under “Control Plane → Configuration” in the HTML report.


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

## 📘 Related Docs

* [Azure Monitor Prometheus Overview](https://learn.microsoft.com/azure/azure-monitor/prometheus-metrics-overview)
* [Prometheus HTTP API](https://prometheus.io/docs/prometheus/latest/querying/api/)
* [KubeBuddy Thresholds & Defaults](./thresholds.md)
