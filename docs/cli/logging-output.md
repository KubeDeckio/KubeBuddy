---
title: Logging and Output
parent: Usage
nav_order: 6
layout: default
---

# Logging and Output

KubeBuddy prints progress to the terminal while it runs and can also write HTML, JSON, text, and CSV reports.

## Console Output

During a run, KubeBuddy shows:

- the banner
- major phases such as Kubernetes, AKS, Prometheus, AI, Radar, and report writing
- per-check `Checking` and `Checked` lines
- inline finding counts when a check returns results

Example:

```text
[Starting] Preparing native KubeBuddy run
[Kubernetes] [041/095] Checking PROM001 - High CPU Pods (Prometheus)
[Kubernetes] [041/095] Checked PROM001 - High CPU Pods (Prometheus) (3 findings)
[Reports] writing /path/to/kubebuddy-report-20260413-134408.html
```

The PowerShell wrapper streams the same native output, so `Invoke-KubeBuddy` shows the Go binary progress directly in the terminal.

## Save Console Output

PowerShell:

```powershell
Invoke-KubeBuddy | Out-File "KubeBuddyOutput.log"
```

Bash:

```bash
kubebuddy run --html-report --yes | tee kubebuddy-output.log
```

## Report Outputs

KubeBuddy can generate:

- HTML
- JSON
- TXT
- CSV

Examples:

```bash
kubebuddy run --html-report --json-report --yes --output-path ./reports
```

```powershell
Invoke-KubeBuddy -HtmlReport -jsonReport -OutputPath ./reports
```

If `--output-path` or `-OutputPath` points to a directory, KubeBuddy writes timestamped report files there.

If it points to a specific filename in the PowerShell wrapper, the wrapper renames the generated report to match the requested base name.

## Completion Output

At the end of a successful run, KubeBuddy prints where the reports were written.

Example:

```text
[Reports] writing /path/to/kubebuddy-report-20260413-134408.html
[Reports] writing /path/to/kubebuddy-report-20260413-134408.json
reports written to /path/to/reports
```

## Common Errors

| Error | Meaning | What to do |
| --- | --- | --- |
| `missing input file or live AKS target (--subscription-id, --resource-group, --cluster-name)` | `scan-aks` was run without AKS JSON input or live AKS target flags. | Supply `--input` or all three AKS live collection flags. |
| `KUBECONFIG environment variable not set` | Container-mode run is missing kubeconfig wiring. | Set `KUBECONFIG` and mount the kubeconfig into the container. |
| `AKS mode is enabled but missing: CLUSTER_NAME, RESOURCE_GROUP or SUBSCRIPTION_ID` | `run-env` AKS mode is missing required env vars. | Set the missing AKS environment variables. |
| `prometheus bearer token env "<name>" is empty` | Bearer-token Prometheus mode was selected, but the token env var was not set. | Export the named token env var before running. |
| `Unable to locate the native KubeBuddy CLI` | The PowerShell wrapper could not find the bundled binary, a binary on `PATH`, or an override path. | Reinstall the module, ensure the platform is supported, or set `KUBEBUDDY_BINARY`. |

## Related Docs

- [Getting Started](getting-started.md)
- [Parameters](parameters.md)
- [PowerShell Usage](powershell-usage.md)
- [Docker Usage](docker-usage.md)
