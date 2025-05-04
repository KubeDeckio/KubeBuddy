---
title: Prometheus Integration
parent: Usage
nav_order: 3
layout: default
---

# 📊 Prometheus Integration

KubeBuddy supports querying Prometheus metrics to enhance its cluster health and performance reports. This works across both **in-cluster Prometheus** and **Azure Monitor Prometheus** deployments.



## 🔍 Why Integrate Prometheus?

By querying Prometheus directly, KubeBuddy can extract time-series metrics for:

- API server latency (p99)
- Node and pod resource usage
- Pod restarts
- Cluster pressure indicators


## ✅ Supported Prometheus Modes

| Mode     | Description                                | Auth Required | Use Case                                 |
|----------|--------------------------------------------|---------------|-------------------------------------------|
| `local`  | In-cluster Prometheus (e.g., kube-prometheus-stack) | ❌            | Works inside cluster with no auth         |
| `basic`  | Prometheus behind an ingress with basic auth | ✅            | External Prometheus with username/password |
| `bearer` | Prometheus secured with a bearer token       | ✅            | External Prometheus (e.g., OAuth proxy)   |
| `azure`  | Azure Monitor Managed Prometheus             | ✅ AAD token   | AKS + Azure Monitor Workspace Prometheus  |


## 🔐 Authentication Methods

KubeBuddy supports multiple auth mechanisms:

### 🔹 Local (No Auth)
No credentials needed. KubeBuddy accesses Prometheus via service name:

```yaml
prometheus:
  enabled: true
  url: http://prometheus.monitoring.svc:9090
  mode: local
```


### 🔸 Basic Auth

```yaml
prometheus:
  enabled: true
  url: https://prometheus.example.com
  mode: basic
  username: admin
  password: secret
```


### 🟠 Bearer Token

```yaml
prometheus:
  enabled: true
  url: https://prometheus.example.com
  mode: bearer
  tokenEnv: PROMETHEUS_TOKEN
```

Then set the token via env var:

```bash
export PROMETHEUS_TOKEN="eyJhbGciOiJIUzI1..."
```


### 🔵 Azure Monitor Prometheus (AAD)

For AKS with Azure Monitor Managed Prometheus:

```yaml
prometheus:
  enabled: true
  url: https://<workspace-id>.prometheus.monitor.azure.com
  mode: azure
```

> 📌 KubeBuddy will use SPN credentials (`AZURE_CLIENT_ID`, etc) or `az` CLI if running locally.


## 🧪 Example Query (API Server p99 Latency)

PromQL:

```promql
histogram_quantile(0.99, rate(apiserver_request_duration_seconds_bucket[1h]))
```

This returns the 1-hour p99 request latency for GET requests to the Kubernetes API server.


## ▶️ CLI Usage (Manual Test)

=== "Bash"

```bash
export AZURE_CLIENT_ID="..."
export AZURE_CLIENT_SECRET="..."
export AZURE_TENANT_ID="..."
export SUBSCRIPTION_ID="..."
export RESOURCE_GROUP="..."
export CLUSTER_NAME="..."

docker run -it --rm \
  -e PROMETHEUS_MODE="azure" \
  -e PROMETHEUS_URL="https://<workspace>.prometheus.monitor.azure.com" \
  -e AZURE_CLIENT_ID \
  -e AZURE_CLIENT_SECRET \
  -e AZURE_TENANT_ID \
  -v ~/.kube/config:/tmp/kubeconfig-original:ro \
  ghcr.io/kubedeckio/kubebuddy:v0.0.19
```

=== "PowerShell"

```powershell
docker run -it --rm `
  -e PROMETHEUS_MODE="azure" `
  -e PROMETHEUS_URL="https://<workspace>.prometheus.monitor.azure.com" `
  -e AZURE_CLIENT_ID="..." `
  -e AZURE_CLIENT_SECRET="..." `
  -e AZURE_TENANT_ID="..." `
  -v $HOME/.kube/config:/tmp/kubeconfig-original:ro `
  ghcr.io/kubedeckio/kubebuddy:v0.0.19
```

---

## 🛠️ Configuration Reference

All fields can be set via `kubebuddy-config.yaml` or environment variables.

| Config Key | Env Var Equivalent | Description                                |
| ---------- | ------------------ | ------------------------------------------ |
| `enabled`  | —                  | Set to `true` to enable Prometheus support |
| `url`      | `PROMETHEUS_URL`   | Base URL of Prometheus server              |
| `mode`     | `PROMETHEUS_MODE`  | One of `local`, `basic`, `bearer`, `azure` |
| `username` | —                  | Basic auth username                        |
| `password` | —                  | Basic auth password                        |
| `tokenEnv` | —                  | Name of env var holding bearer token       |


## 📘 Related Docs

* [Azure Monitor Prometheus Docs](https://learn.microsoft.com/en-us/azure/azure-monitor/essentials/prometheus-metrics-overview)
* [Prometheus HTTP API](https://prometheus.io/docs/prometheus/latest/querying/api/)
* [KubeBuddy Configuration File](./kubebuddy-config.md)


## ❓ Questions or Feedback?

We’d love to hear how you're using Prometheus with KubeBuddy!
File an issue or open a discussion at
👉 [https://github.com/kubedeckio/kubebuddy](https://github.com/kubedeckio/kubebuddy)