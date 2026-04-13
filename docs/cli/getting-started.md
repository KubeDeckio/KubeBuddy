---
title: Getting Started
layout: default
---

# Getting Started

This is the quickest path from install to first report.

## 1. Verify Cluster Access

```bash
kubebuddy probe
```

If that succeeds, KubeBuddy can reach your current Kubernetes context.

## 2. Run a Quick Summary

```bash
kubebuddy summary
```

This gives you a fast resource count before a full scan.

## 3. Run a Full Report

```bash
kubebuddy run --html-report --json-report --yes --output-path ./reports
```

That writes full report files to `./reports`.

## 4. Run a Direct CLI Scan

```bash
kubebuddy scan --output text
```

Use this when you want immediate terminal output instead of report files.

## 5. Run AKS Checks

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

```bash
kubebuddy run \
  --html-report \
  --include-prometheus \
  --prometheus-url <prometheus-url> \
  --prometheus-mode azure \
  --yes \
  --output-path ./reports
```

## Common Entry Points

- `kubebuddy run`
  Full report generation workflow.
- `kubebuddy scan`
  Direct scan output to terminal/stdout.
- `kubebuddy scan-aks`
  AKS-specific check execution.
- `kubebuddy run-env`
  Environment-variable-driven flow used by the container image.

## Next Docs

- [Install](install.md)
- [Parameters](parameters.md)
- [Docker Usage](docker-usage.md)
- [Prometheus Integration](prometheus-integration.md)
