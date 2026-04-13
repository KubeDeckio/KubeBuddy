---
title: Native CLI Usage
---

# Native CLI Usage

The native `kubebuddy` binary is the main local runtime for KubeBuddy. Use it directly on your workstation, in CI, or as the container entrypoint.

## Build the CLI

Build from the repository root:

```bash
go build -o kubebuddy ./cmd/kubebuddy
```

Check the binary:

```bash
./kubebuddy version
```

## Install with Homebrew

If you want a packaged install on macOS or Linux, use the KubeBuddy tap:

```bash
brew tap KubeDeckio/homebrew-kubebuddy
brew install kubebuddy
kubebuddy version
```

Homebrew installs the native CLI directly. It does not install the PowerShell wrapper.

## Common Workflows

### Run the Full KubeBuddy Engine

```bash
./kubebuddy run --html-report --yes --output-path ./reports
```

Add JSON, CSV, or text output as needed:

```bash
./kubebuddy run --json-report --csv-report --yes --output-path ./reports
```

Run AKS mode:

```bash
./kubebuddy run \
  --aks \
  --subscription-id <subscription-id> \
  --resource-group <resource-group> \
  --cluster-name <cluster-name> \
  --html-report \
  --yes \
  --output-path ./reports
```

### Run the Container-Style Workflow

```bash
./kubebuddy run-env
```

This uses the same environment-variable-driven flow as the Docker image, including `HTML_REPORT`, `JSON_REPORT`, `AKS_MODE`, `RADAR_UPLOAD`, and the mounted kubeconfig path.

Example:

```bash
export KUBECONFIG=/home/kubeuser/.kube/config
export HTML_REPORT=true
./kubebuddy run-env
```

### Probe Cluster Access

Use the native CLI to verify that KubeBuddy can reach your current Kubernetes context:

```bash
./kubebuddy probe
```

Example output:

```text
context: docker-desktop
nodes: 1
pods: 10
namespaces: default, kube-system
```

### Inspect Check Catalog

```bash
./kubebuddy checks
```

This shows the current split between declarative, Prometheus, and compatibility-backed checks.

To inspect the native AKS YAML catalog instead:

```bash
./kubebuddy checks --checks-dir checks/aks
```

### Collect a Basic Cluster Summary

```bash
./kubebuddy summary
```

This returns a native summary of common Kubernetes resource counts for the current context.

### Run a Cluster Scan

```bash
./kubebuddy scan
```

This runs the native Kubernetes scan path directly from the Go CLI.

For structured output:

```bash
./kubebuddy scan --output json
```

CSV output:

```bash
./kubebuddy scan --output csv
```

HTML output:

```bash
./kubebuddy scan --output html
```

### Run Native AKS YAML Checks

```bash
./kubebuddy scan-aks --input ./aks-cluster.json
```

This evaluates the AKS YAML check catalog against an AKS cluster JSON document.

For structured output:

```bash
./kubebuddy scan-aks --input ./aks-cluster.json --output json
```

CSV output:

```bash
./kubebuddy scan-aks --input ./aks-cluster.json --output csv
```

HTML output:

```bash
./kubebuddy scan-aks --input ./aks-cluster.json --output html
```

### Inspect Embedded Report Assets

```bash
./kubebuddy assets
```

This confirms the current HTML report CSS and JavaScript are embedded into the runtime.

## Notes

- Use `run` when you want full report generation and file outputs.
- Use `scan` and `scan-aks` when you want direct CLI output.
- The HTML report keeps the existing CSS, JavaScript, theme, and layout behavior.
