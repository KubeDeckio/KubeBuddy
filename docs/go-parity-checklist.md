---
title: Go Parity Checklist
hide:
  - navigation
---

# Go Parity Checklist

This checklist breaks the migration into release-blocking parity areas. The migration is not complete until every item here is done.

## CLI and Runtime

- Recreate `Invoke-KubeBuddy` behavior in the Go CLI.
- Preserve current report output path behavior.
- Preserve config file override behavior.
- Preserve excluded namespace behavior.
- Preserve AKS mode flags and validation.
- Preserve Prometheus flags and auth modes.
- Preserve Radar fetch, upload, and compare flows.
- Replace [run.ps1](/Users/pixelrobots/Documents/Git/KubeBuddy/run.ps1) with a Go container entrypoint.

## Data Collection

- Port Kubernetes data collection from [Private/get-kubedata.ps1](/Users/pixelrobots/Documents/Git/KubeBuddy/Private/get-kubedata.ps1).
- Port AKS cluster collection from [Private/aks/aks-functions.ps1](/Users/pixelrobots/Documents/Git/KubeBuddy/Private/aks/aks-functions.ps1).
- Port Prometheus data collection from [Private/get-prometheusdata.ps1](/Users/pixelrobots/Documents/Git/KubeBuddy/Private/get-prometheusdata.ps1).
- Port Radar collection and payload logic from [Private/radar-functions.ps1](/Users/pixelrobots/Documents/Git/KubeBuddy/Private/radar-functions.ps1).

## Checks

- Support all existing Kubernetes YAML checks.
- Load and classify the current mixed declarative and script-backed Kubernetes YAML catalog.
- Convert AKS rule files under [Private/aks/checks](/Users/pixelrobots/Documents/Git/KubeBuddy/Private/aks/checks) into YAML definitions.
- Preserve check IDs, categories, severities, URLs, and recommendation text.
- Preserve excluded-check behavior from config.
- Preserve Prometheus-backed checks.

## Reporting

- Preserve terminal output coverage.
- Preserve JSON report fields and structure.
- Preserve CSV report columns and ordering.
- Preserve HTML theme, layout, JS behavior, CSS, and section flow.
- Preserve AKS sections in reports.
- Preserve Radar-compatible JSON payloads.

## Automatic Readiness

- Port logic from [Private/aks-automatic-readiness.ps1](/Users/pixelrobots/Documents/Git/KubeBuddy/Private/aks-automatic-readiness.ps1).
- Preserve action plan generation.
- Preserve automatic relevance, scope, and reason mappings.

## Docs

- Rewrite CLI docs for the Go runtime.
- Rewrite Docker docs for the Go container entrypoint.
- Rewrite check authoring docs for YAML-only rule authoring.
- Update install and release docs for Go builds and releases.
- Refresh examples and screenshots where output changed structurally.

## Tests

- Add fixture-based parity tests for Kubernetes-only scans.
- Add fixture-based parity tests for AKS scans.
- Add fixture-based parity tests for Prometheus-enabled scans.
- Add fixture-based parity tests for Radar flows.

## Local Comparison Workflow

Use the local comparator when validating native parity against a PowerShell report artifact:

```bash
python3 ./tmp/compare_reports.py /path/to/powershell-report.json /path/to/go-report.json
```

The script compares:

- `Total`
- `Status`
- `Severity`
- `ObservedValue`
- `FailMessage`
- normalized `Items`

For live Prometheus-backed checks, compare reports generated close together in time. A moving 24h query window can produce small item-count differences even when the implementation logic is aligned.
- Add golden tests for JSON, CSV, text, and HTML reports.
