---
title: Parameters
layout: default
---

# Parameters

This page summarizes the current CLI parameters and environment-driven runtime inputs for the native Go runtime.

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
| `--config-path` | KubeBuddy config file path for thresholds, excluded namespaces, trusted registries, excluded checks, and Radar defaults |
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

## `kubebuddy guided`

Interactive Buddy-style workflow for choosing report mode and runtime options from a terminal menu.

No additional flags today.

## `kubebuddy scan`

Direct Kubernetes scan output.

| Flag | Description |
| --- | --- |
| `--checks-dir` | Directory containing Kubernetes check YAML files |
| `--config-path` | KubeBuddy config file path for thresholds, excluded namespaces, trusted registries, and excluded checks |
| `--exclude-namespaces` | Exclude configured namespaces |
| `--additional-excluded-namespaces` | Additional namespaces to exclude |
| `--include-prometheus` | Include Prometheus data |
| `--prometheus-url` | Prometheus URL |
| `--prometheus-mode` | Prometheus auth mode |
| `--prometheus-bearer-token-env` | Env var containing the bearer token |
| `--output` | Output format: `text`, `json`, `csv`, or `html` |

## Prometheus Auth Inputs

Prometheus auth is a mix of flags and environment-driven credentials.

| Mode | Inputs |
| --- | --- |
| `local` | No extra auth inputs |
| `azure` | Existing Azure auth in the current environment |
| `bearer` | `--prometheus-bearer-token-env <ENV_NAME>` and the named env var must contain the token |
| `basic` | `PROMETHEUS_USERNAME` and `PROMETHEUS_PASSWORD` environment variables |

## `kubebuddy scan-aks`

AKS YAML checks against a live AKS cluster or AKS JSON document.

| Flag | Description |
| --- | --- |
| `--checks-dir` | Directory containing AKS check YAML files |
| `--config-path` | KubeBuddy config file path for excluded AKS checks and shared defaults |
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

## `kubebuddy run-env`

Container-oriented entrypoint that reads configuration from environment variables and then runs the normal native report flow.

| Environment Variable | Description |
| --- | --- |
| `HTML_REPORT` | Enable HTML report output |
| `TXT_REPORT` | Enable text report output |
| `JSON_REPORT` | Enable JSON report output |
| `CSV_REPORT` | Enable CSV report output |
| `KUBECONFIG` | Path to the kubeconfig file inside the container |
| `KUBEBUDDY_CONFIG_PATH` | Optional KubeBuddy config file path |
| `EXCLUDE_NAMESPACES` | Enable configured namespace exclusions |
| `ADDITIONAL_EXCLUDED_NAMESPACES` | Comma-separated additional namespaces to exclude |
| `INCLUDE_PROMETHEUS` | Enable Prometheus-backed checks |
| `PROMETHEUS_URL` | Prometheus endpoint URL |
| `PROMETHEUS_MODE` | Prometheus auth mode such as `azure` or `bearer` |
| `PROMETHEUS_BEARER_TOKEN_ENV` | Name of the env var containing the bearer token when using bearer auth |
| `AKS_MODE` | Enable live AKS collection mode |
| `SUBSCRIPTION_ID` | AKS subscription ID |
| `RESOURCE_GROUP` | AKS resource group |
| `CLUSTER_NAME` | AKS cluster name |
| `USE_AKS_REST_API` | Use the AKS REST API path |
| `RADAR_UPLOAD` | Upload the JSON report to Radar |
| `RADAR_COMPARE` | Compare the uploaded run in Radar |
| `RADAR_FETCH_CONFIG` | Fetch Radar config before running |
| `RADAR_CONFIG_ID` | Radar cluster config id |
| `RADAR_API_BASE_URL` | Radar API base URL |
| `RADAR_ENVIRONMENT` | Radar environment name |
| `RADAR_API_USER_ENV` | Name of the env var containing the Radar API user |
| `RADAR_API_SECRET_ENV` | Name of the env var containing the Radar API secret |
| `RADAR_API_PASSWORD_ENV` | Legacy alias for `RADAR_API_SECRET_ENV` |
| `OpenAIKey` | OpenAI API key for native AI enrichment |

## AI Enrichment

Native AI enrichment is environment-driven.

| Input | Description |
| --- | --- |
| `OpenAIKey` | OpenAI API key used for AI-generated recommendation enrichment on failing checks |

## PowerShell Wrapper Notes

The PowerShell wrapper still maps old parameter names onto the native CLI.

Examples:

- `-HtmlReport` -> `--html-report`
- `-jsonReport` -> `--json-report`
- `-CsvReport` -> `--csv-report`
- `-txtReport` -> `--txt-report`
- `-OutputPath` -> `--output-path`

For full PowerShell examples, use [PowerShell Usage](powershell-usage.md).
