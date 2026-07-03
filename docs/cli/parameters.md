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
| `--additional-excluded-namespaces` | Additional namespaces to exclude; also enables namespace exclusion for the run |
| `--excluded-checks` | Comma-separated check IDs to exclude for this run |
| `--include-prometheus` | Include Prometheus data |
| `--prometheus-url` | Prometheus URL |
| `--prometheus-mode` | Prometheus auth mode |
| `--prometheus-bearer-token-env` | Env var containing the Prometheus bearer token |
| `--aks` | Enable AKS mode |
| `--subscription-id` | AKS subscription ID |
| `--resource-group` | AKS resource group |
| `--cluster-name` | AKS cluster name |
| `--use-aks-rest-api` | Use the AKS REST API path |
| `--gke` | Enable GKE mode |
| `--project-id` | GCP project ID for GKE live collection |
| `--location` | GKE zone or region |
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
| `--additional-excluded-namespaces` | Additional namespaces to exclude; also enables namespace exclusion for the run |
| `--excluded-checks` | Comma-separated check IDs to exclude for this scan |
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
| `gcp` | Google Application Default Credentials in the current environment |
| `bearer` | `--prometheus-bearer-token-env <ENV_NAME>` and the named env var must contain the token |
| `basic` | `PROMETHEUS_USERNAME` and `PROMETHEUS_PASSWORD` environment variables |

`--include-prometheus` enables both Prometheus-backed checks and the optional report metrics snapshot. If the checks can run but the snapshot cannot be built, JSON output will keep `metrics: null` and explain the reason in `metadata.prometheusSnapshotStatus` and `metadata.prometheusSnapshotReason`.

## `kubebuddy scan-aks`

AKS YAML checks against a live AKS cluster or AKS JSON document.

| Flag | Description |
| --- | --- |
| `--checks-dir` | Directory containing AKS check YAML files |
| `--config-path` | KubeBuddy config file path for excluded AKS checks and shared defaults |
| `--excluded-checks` | Comma-separated AKS check IDs to exclude for this scan |
| `--input` | Path to an AKS cluster JSON document |
| `--subscription-id` | AKS subscription ID |
| `--resource-group` | AKS resource group |
| `--cluster-name` | AKS cluster name |
| `--output` | Output format: `text`, `json`, `csv`, or `html` |

## `kubebuddy scan-gke`

GKE YAML checks against a live GKE cluster or GKE JSON document.

| Flag | Description |
| --- | --- |
| `--checks-dir` | Directory containing GKE check YAML files |
| `--config-path` | KubeBuddy config file path for excluded GKE checks and shared defaults |
| `--excluded-checks` | Comma-separated GKE check IDs to exclude for this scan |
| `--input` | Path to a GKE cluster JSON document |
| `--project-id` | GCP project ID for live collection |
| `--location` | GKE cluster zone or region |
| `--cluster-name` | GKE cluster name |
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
| `EXCLUDED_CHECKS` | Comma-separated check IDs to exclude |
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
| `AI_PROVIDER` | Optional AI provider alias: `openai`, `azure-openai`, `foundry`, `gemini`, `anthropic`, or `openai-compatible` |
| `AI_API_KEY` | AI provider API key |
| `AI_BASE_URL` | Optional OpenAI-compatible chat completions base URL |
| `AI_MODEL` | AI model or deployment name |
| `OpenAIKey` | Legacy OpenAI API key for native AI enrichment |
| `OPENAI_API_KEY` | Alternative OpenAI API key for native AI enrichment |
| `OPENAI_BASE_URL` | Optional OpenAI-compatible base URL |
| `KUBEBUDDY_OPENAI_MODEL` | Legacy model name for OpenAI-compatible enrichment |
| `AZURE_OPENAI_ENDPOINT` | Azure OpenAI resource endpoint, for example `https://<resource>.openai.azure.com` |
| `AZURE_OPENAI_API_KEY` | Azure OpenAI API key for native AI enrichment |
| `AZURE_OPENAI_AUTH_TOKEN` | Azure OpenAI bearer token alternative to `AZURE_OPENAI_API_KEY` |
| `AZURE_OPENAI_DEPLOYMENT` | Azure OpenAI deployment name used as the model |
| `KUBEBUDDY_AZURE_OPENAI_DEPLOYMENT` | Alternative Azure OpenAI deployment-name variable |
| `AZURE_OPENAI_BASE_URL` | Optional Azure OpenAI base URL override |
| `FOUNDRY_ENDPOINT` | Microsoft Foundry endpoint, for example `https://<resource>.services.ai.azure.com` |
| `FOUNDRY_API_KEY` | Microsoft Foundry API key |
| `FOUNDRY_MODEL` | Microsoft Foundry model deployment name |
| `GEMINI_API_KEY` | Google Gemini API key |
| `GEMINI_MODEL` | Gemini model name |
| `ANTHROPIC_API_KEY` | Anthropic API key for the native Claude SDK path |
| `ANTHROPIC_MODEL` | Claude model name |

## AI Enrichment

Native AI enrichment is environment-driven.

| Input | Description |
| --- | --- |
| `AI_PROVIDER` | Provider alias: `openai`, `azure-openai`, `foundry`, `gemini`, `anthropic`, or `openai-compatible` |
| `AI_API_KEY` | Provider API key. This is the preferred generic key variable. |
| `AI_BASE_URL` | Optional OpenAI-compatible chat completions base URL. Use this for custom gateways and providers not listed here. |
| `AI_MODEL` | Model or deployment name. This is the preferred generic model variable. |
| `OpenAIKey` / `OPENAI_API_KEY` | OpenAI-compatible key aliases kept for existing users |
| `OPENAI_BASE_URL` | OpenAI-compatible base URL alias; defaults to `https://api.openai.com/v1/` |
| `AZURE_OPENAI_ENDPOINT` | Enables Azure OpenAI mode when paired with `AZURE_OPENAI_API_KEY` or `AZURE_OPENAI_AUTH_TOKEN` |
| `AZURE_OPENAI_API_KEY` / `AZURE_OPENAI_AUTH_TOKEN` | Azure OpenAI API key or bearer token |
| `AZURE_OPENAI_DEPLOYMENT` | Azure OpenAI deployment name |
| `FOUNDRY_ENDPOINT` / `FOUNDRY_API_KEY` / `FOUNDRY_MODEL` | Microsoft Foundry endpoint, key, and model deployment aliases |
| `GEMINI_API_KEY` / `GEMINI_MODEL` | Google Gemini key and model aliases using Gemini's OpenAI-compatible endpoint |
| `ANTHROPIC_API_KEY` / `ANTHROPIC_MODEL` | Anthropic/Claude key and model aliases using the native Anthropic SDK |

KubeBuddy sends AI enrichment through OpenAI-compatible chat completions for OpenAI, Azure OpenAI, Microsoft Foundry, Gemini, and custom gateways. The `anthropic` provider uses the native Anthropic Messages API. Provider aliases set defaults for API key, base URL, and model; use `AI_BASE_URL` for any other OpenAI-compatible service or gateway.

## PowerShell Wrapper Notes

The PowerShell wrapper still maps old parameter names onto the native CLI.

Examples:

- `-HtmlReport` -> `--html-report`
- `-jsonReport` -> `--json-report`
- `-CsvReport` -> `--csv-report`
- `-txtReport` -> `--txt-report`
- `-OutputPath` -> `--output-path`

For full PowerShell examples, use [PowerShell Usage](powershell-usage.md).
