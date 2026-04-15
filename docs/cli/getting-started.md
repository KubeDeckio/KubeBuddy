---
title: Getting Started
layout: default
---

# Getting Started

This is the shortest path from install to a real report.

## 1. Verify Access

```bash
kubebuddy probe
```

If that succeeds, KubeBuddy can reach your current Kubernetes context.

## 2. Optional: Inspect the Cluster Quickly

```bash
kubebuddy summary
```

This gives you a fast count of common resources before a full run.

## 3. Generate Your First Report

```bash
kubebuddy run --html-report --json-report --yes --output-path ./reports
```

That writes reports into `./reports`.

## 3a. Use The Guided Buddy Flow

If you want the old menu-style experience, use the guided command:

```bash
kubebuddy guided
```

This walks you through report type, AKS options, Prometheus, exclusions, and output path using the Buddy prompt flow.

## 4. Use Direct Terminal Output Instead

```bash
kubebuddy scan --output text
```

Use `scan` when you want output in the terminal. Use `run` when you want report files.

## 5. Add AKS Checks

```bash
kubebuddy run \
  --aks \
  --subscription-id <subscription-id> \
  --resource-group <resource-group> \
  --cluster-name <cluster-name> \
  --html-report \
  --yes \
  --output-path ./reports
```

## 6. Add Prometheus

If you are using Azure Managed Prometheus, make sure Azure auth is already available in your environment. Local shells commonly use `az login`; CI and containers commonly use service principal variables.

```bash
kubebuddy run \
  --html-report \
  --include-prometheus \
  --prometheus-url <prometheus-url> \
  --prometheus-mode azure \
  --yes \
  --output-path ./reports
```

For bearer-token mode:

```bash
export MY_PROM_TOKEN="<token>"

kubebuddy run \
  --html-report \
  --include-prometheus \
  --prometheus-url <prometheus-url> \
  --prometheus-mode bearer \
  --prometheus-bearer-token-env MY_PROM_TOKEN \
  --yes \
  --output-path ./reports
```

## Where To Go Next

- [Native CLI](native-cli-usage.md) for native command usage
- [PowerShell](powershell-usage.md) for `Invoke-KubeBuddy`
- [Docker](docker-usage.md) for container runs
- [Config File](kubebuddy-config.md) for repeatable scan defaults
- [Parameters](parameters.md) for the full flag reference
