# KubeBuddy CLI + Radar Integration (Pro)

Use this guide to upload KubeBuddy JSON scan results into KubeBuddy Radar and to pull saved Radar cluster configs into KubeBuddy for:

- run history
- score trends
- run-to-run compare
- saved cluster configs
- generated commands and YAML config files

For the Radar web experience itself, including Cluster Reports, Cluster Configs, and the Radar API reference, use the Radar section in these docs:

- [KubeBuddy Radar Overview](radar/index.md)

## What Gets Uploaded

Only the JSON report payload is uploaded.

- `kubebuddy run --json-report --radar-upload ...`
- `Invoke-KubeBuddy -jsonReport -RadarUpload ...`
- HTML and TXT outputs are local artifacts only
- Radar now prefers the uploaded `report` payload and derives report/compare data from it asynchronously after upload

## Authentication

Radar API access uses WordPress Application Passwords (Basic auth).

Set env vars before running KubeBuddy:

```powershell
$env:KUBEBUDDY_RADAR_API_USER = "<wordpress-username>"
$env:KUBEBUDDY_RADAR_API_PASSWORD = "<wordpress-app-password>"
```

```bash
export KUBEBUDDY_RADAR_API_USER="<wordpress-username>"
export KUBEBUDDY_RADAR_API_PASSWORD="<wordpress-app-password>"
```

## Native CLI Examples

Upload JSON run:

```bash
kubebuddy run \
  --json-report \
  --radar-upload \
  --radar-environment prod \
  --yes \
  --output-path ./reports
```

Upload + compare current run with previous run:

```bash
kubebuddy run \
  --json-report \
  --radar-upload \
  --radar-compare \
  --radar-environment prod \
  --yes \
  --output-path ./reports
```

Fetch a saved Radar cluster config:

```bash
kubebuddy run \
  --radar-fetch-config \
  --radar-config-id "ccfg_12345678-1234-1234-1234-123456789abc" \
  --html-report \
  --yes \
  --output-path ./reports
```

## PowerShell Examples

Upload JSON run:

```powershell
Invoke-KubeBuddy `
  -jsonReport `
  -RadarUpload `
  -RadarEnvironment "prod"
```

Upload + compare current run with previous run:

```powershell
Invoke-KubeBuddy `
  -jsonReport `
  -RadarUpload `
  -RadarCompare `
  -RadarEnvironment "prod"
```

Fetch a saved Radar cluster config into the CLI:

```powershell
Invoke-KubeBuddy `
  -RadarFetchConfig `
  -RadarConfigId "ccfg_12345678-1234-1234-1234-123456789abc"
```

Fetch a Radar cluster config and override one value locally:

```powershell
Invoke-KubeBuddy `
  -RadarFetchConfig `
  -RadarConfigId "ccfg_12345678-1234-1234-1234-123456789abc" `
  -HtmlReport `
  -OutputPath ./reports
```

Use custom Radar endpoint and custom credential env-var names:

```powershell
Invoke-KubeBuddy `
  -jsonReport `
  -RadarUpload `
  -RadarApiBaseUrl "https://radar.example.com/api/kb-radar/v1" `
  -RadarApiUserEnv "MY_RADAR_USER_ENV" `
  -RadarApiSecretEnv "MY_RADAR_PASS_ENV"
```

## Docker Entry Point Support (`kubebuddy run-env`)

When running the container image, configure Radar via env vars:

```bash
-e JSON_REPORT="true" \
-e RADAR_UPLOAD="true" \
-e RADAR_COMPARE="true" \
-e RADAR_FETCH_CONFIG="true" \
-e RADAR_CONFIG_ID="ccfg_12345678-1234-1234-1234-123456789abc" \
-e RADAR_ENVIRONMENT="prod" \
-e KUBEBUDDY_RADAR_API_USER="<wordpress-username>" \
-e KUBEBUDDY_RADAR_API_PASSWORD="<wordpress-app-password>"
```

Rules enforced by the Go-native container entrypoint:

- `RADAR_UPLOAD=true` or `RADAR_COMPARE=true` requires `JSON_REPORT=true`
- `RADAR_FETCH_CONFIG=true` fetches the saved Radar cluster profile and applies it to the native run before checks start

## Config File Defaults (`kubebuddy-config.yaml`)

```yaml
radar:
  enabled: false
  api_base_url: "https://radar.kubebuddy.io/api/kb-radar/v1"
  environment: "prod"
  api_user: "<optional-wordpress-username>"
  api_password: "<optional-wordpress-app-password>"
  api_user_env: "KUBEBUDDY_RADAR_API_USER"
  api_password_env: "KUBEBUDDY_RADAR_API_PASSWORD"
  upload_timeout_seconds: 30
  upload_retries: 2
```

CLI flags override config values for that run.
`--radar-upload`, `--radar-compare`, and `--radar-fetch-config` also force Radar on for that run even if `radar.enabled` is `false`.

## Radar-managed Cluster Configs (Pro)

Radar now supports private per-user cluster profiles stored encrypted at rest. These profiles are designed to hold:

- AKS metadata like subscription ID, resource group, and cluster name
- Prometheus defaults
- excluded namespaces
- excluded checks
- trusted registries
- output defaults
- Radar upload/compare defaults

The Radar UI can:

- save multiple cluster profiles
- generate the `Invoke-KubeBuddy` command for a selected profile
- generate and download a `kubebuddy-config.yaml`

The CLI can:

- fetch the profile with `--radar-fetch-config --radar-config-id` or `-RadarFetchConfig -RadarConfigId`
- apply the fetched YAML config to the run
- keep explicit CLI flags as the highest-precedence overrides

## Radar UI Output

After upload, Radar surfaces data in:

- `/dashboard/`:
  - latest score
  - score trend line (30d / 90d)
  - failed checks trend
  - quick link to Cluster Reports
- `/cluster-reports/`:
  - run list and processing status
  - compare summary (new/resolved/regressed findings)
  - report detail rendered directly from uploaded JSON while enrichment finishes in the background
- `/cluster-configs/`:
  - saved cluster profiles
  - generated command preview
  - generated YAML config preview/download

## Notes

- AKS metadata fields in JSON now fall back to CLI values (`-SubscriptionId`, `-ResourceGroup`, `-ClusterName`) when source values are null.
- Cluster run retention defaults to 90 days in Radar v1.
- Radar cluster config pages and APIs are private and sent with `Cache-Control: no-store`.
