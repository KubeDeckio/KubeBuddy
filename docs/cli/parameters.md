---
title: Parameters
layout: default
---

# Parameters

This page summarizes the current CLI parameters for the native Go runtime.

## `kubebuddy run`

Full report workflow.

| Flag | Description |
| --- | --- |
| `--html-report` | Generate the HTML report |
| `--txt-report` | Generate the text report |
| `--json-report` | Generate the JSON report |
| `--csv-report` | Generate the CSV report |
| `--output-path` | Report output path |
| `--outputpath` | Legacy alias for `--output-path` |
| `--yes` | Skip interactive confirmation prompts |
| `--config-path` | KubeBuddy config file path |
| `--exclude-namespaces` | Exclude configured namespaces |
| `--additional-excluded-namespaces` | Additional namespaces to exclude |
| `--include-prometheus` | Include Prometheus data |
| `--prometheus-url` | Prometheus URL |
| `--prometheus-mode` | Prometheus auth mode |
| `--prometheus-bearer-token-env` | Env var containing the Prometheus bearer token |
| `--aks` | Enable AKS mode |
| `--subscription-id` | AKS subscription ID |
| `--resource-group` | AKS resource group |
| `--cluster-name` | AKS cluster name |
| `--use-aks-rest-api` | Use the AKS REST API path |
| `--radar-upload` | Upload JSON scan results to Radar |
| `--radar-compare` | Compare the uploaded run in Radar |
| `--radar-fetch-config` | Fetch Radar cluster config before running |
| `--radar-config-id` | Radar cluster config id |
| `--radar-api-base-url` | Radar API base URL |
| `--radar-environment` | Radar environment name |
| `--radar-api-user-env` | Env var containing the Radar API user |
| `--radar-api-secret-env` | Env var containing the Radar API secret |

## `kubebuddy scan`

Direct Kubernetes scan output.

| Flag | Description |
| --- | --- |
| `--checks-dir` | Directory containing Kubernetes check YAML files |
| `--config-path` | KubeBuddy config file path |
| `--exclude-namespaces` | Exclude configured namespaces |
| `--additional-excluded-namespaces` | Additional namespaces to exclude |
| `--include-prometheus` | Include Prometheus data |
| `--prometheus-url` | Prometheus URL |
| `--prometheus-mode` | Prometheus auth mode |
| `--prometheus-bearer-token-env` | Env var containing the bearer token |
| `--output` | Output format: `text`, `json`, `csv`, or `html` |

## `kubebuddy scan-aks`

AKS YAML checks against a live AKS cluster or AKS JSON document.

| Flag | Description |
| --- | --- |
| `--checks-dir` | Directory containing AKS check YAML files |
| `--input` | Path to an AKS cluster JSON document |
| `--subscription-id` | AKS subscription ID |
| `--resource-group` | AKS resource group |
| `--cluster-name` | AKS cluster name |
| `--output` | Output format: `text`, `json`, `csv`, or `html` |

## `kubebuddy checks`

Inspect the current check catalog.

| Flag | Description |
| --- | --- |
| `--checks-dir` | Directory containing check YAML files |

## `kubebuddy probe`

No additional flags.

## `kubebuddy summary`

No additional flags.

## `kubebuddy assets`

No additional flags.

## PowerShell Wrapper Notes

The PowerShell wrapper still maps old parameter names onto the native CLI.

Examples:

- `-HtmlReport` -> `--html-report`
- `-jsonReport` -> `--json-report`
- `-CsvReport` -> `--csv-report`
- `-txtReport` -> `--txt-report`
- `-OutputPath` -> `--output-path`

For full PowerShell examples, use [PowerShell Usage](powershell-usage.md).
