---
title: Native CLI Usage
---

# Native CLI Usage

Use the native `kubebuddy` binary when you want the primary local runtime for KubeBuddy.

This page covers command usage. It does not repeat install steps from [Install](install.md) or first-run guidance from [Getting Started](getting-started.md).

## Core Commands

### Full Report Workflow

```bash
kubebuddy run --html-report --yes --output-path ./reports
```

Add other formats as needed:

```bash
kubebuddy run --json-report --csv-report --txt-report --yes --output-path ./reports
```

### Direct Scan Output

```bash
kubebuddy scan --output text
```

Structured output:

```bash
kubebuddy scan --output json
kubebuddy scan --output csv
kubebuddy scan --output html
```

### AKS Checks

Live AKS:

```bash
kubebuddy scan-aks \
  --subscription-id <subscription-id> \
  --resource-group <resource-group> \
  --cluster-name <cluster-name> \
  --output json
```

From an AKS JSON document:

```bash
kubebuddy scan-aks --input ./aks-cluster.json --output json
```

### Cluster Access Checks

```bash
kubebuddy probe
kubebuddy summary
```

### Check Catalog

```bash
kubebuddy checks
kubebuddy checks --checks-dir checks/aks
```

### Container-Style Entry Point

```bash
kubebuddy run-env
```

This uses the same env-driven runtime shape as the container image.

## Common Native Workflows

### Run AKS and Kubernetes Together

```bash
kubebuddy run \
  --aks \
  --subscription-id <subscription-id> \
  --resource-group <resource-group> \
  --cluster-name <cluster-name> \
  --html-report \
  --json-report \
  --yes \
  --output-path ./reports
```

### Add Prometheus

Azure auth mode:

```bash
az login

kubebuddy run \
  --html-report \
  --include-prometheus \
  --prometheus-url "https://<workspace>.prometheus.monitor.azure.com" \
  --prometheus-mode azure \
  --yes \
  --output-path ./reports
```

Bearer token mode:

```bash
export MY_PROM_TOKEN="<token>"

kubebuddy run \
  --html-report \
  --include-prometheus \
  --prometheus-url "https://prom.example.com" \
  --prometheus-mode bearer \
  --prometheus-bearer-token-env MY_PROM_TOKEN \
  --yes \
  --output-path ./reports
```

## Related Pages

- [Config File](kubebuddy-config.md)
- [Prometheus Integration](prometheus-integration.md)
- [Parameters](parameters.md)
