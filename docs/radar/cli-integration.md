# KubeBuddy CLI Integration

This page shows how to connect both the native `kubebuddy` CLI and the PowerShell wrapper `Invoke-KubeBuddy` to Radar cluster-reports and cluster-configs endpoints.

## Authentication

Radar uses HTTP Basic auth with WordPress Application Passwords:

- username: your WordPress username
- password: your WordPress Application Password (from Account page)

Set credentials as env vars for KubeBuddy:

```powershell
$env:KUBEBUDDY_RADAR_API_USER = "<wordpress-username>"
$env:KUBEBUDDY_RADAR_API_PASSWORD = "<wordpress-app-password>"
```

## Native CLI Usage

Upload JSON run:

```bash
kubebuddy run \
  --json-report \
  --radar-upload \
  --radar-environment prod \
  --yes \
  --output-path ./reports
```

Upload + compare:

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

## PowerShell CLI Usage

Upload JSON run:

```powershell
Invoke-KubeBuddy `
  -jsonReport `
  -RadarUpload `
  -RadarEnvironment "prod"
```

Upload + compare:

```powershell
Invoke-KubeBuddy `
  -jsonReport `
  -RadarUpload `
  -RadarCompare `
  -RadarEnvironment "prod"
```

Optional overrides:

- `-RadarApiBaseUrl` (default `https://radar.kubebuddy.io/api/kb-radar/v1`)
- `-RadarApiUserEnv` (default `KUBEBUDDY_RADAR_API_USER`)
- `-RadarApiSecretEnv` (default `KUBEBUDDY_RADAR_API_PASSWORD`)

Fetch a saved Radar cluster config:

```powershell
Invoke-KubeBuddy `
  -RadarFetchConfig `
  -RadarConfigId "ccfg_12345678-1234-1234-1234-123456789abc"
```

## Docker Entrypoint Usage (`kubebuddy run-env`)

Use these env vars:

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

Validation rules:

- `RADAR_UPLOAD`/`RADAR_COMPARE` requires `JSON_REPORT=true`
- `RADAR_FETCH_CONFIG=true` fetches the saved Radar cluster profile and applies it to the native run before checks start

## Direct API Example (for debugging)

```powershell
$pair = "$($env:KUBEBUDDY_RADAR_API_USER):$($env:KUBEBUDDY_RADAR_API_PASSWORD)"
$token = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($pair))

Invoke-RestMethod `
  -Method Get `
  -Uri "https://radar.kubebuddy.io/api/kb-radar/v1/cluster-reports?page=1&per_page=5" `
  -Headers @{ Authorization = "Basic $token" }
```

See [Cluster Reports (Pro)](cluster-reports.md), [Cluster Configs (Pro)](cluster-configs.md), and [API Reference](api-reference.md) for full endpoint details.
