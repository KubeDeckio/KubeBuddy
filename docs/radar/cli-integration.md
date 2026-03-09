# KubeBuddy CLI Integration

This page shows how to connect `Invoke-KubeBuddy` to Radar cluster-reports and cluster-configs endpoints.

## Authentication

Radar uses HTTP Basic auth with WordPress Application Passwords:

- username: your WordPress username
- password: your WordPress Application Password (from Account page)

Set credentials as env vars for KubeBuddy:

```powershell
$env:KUBEBUDDY_RADAR_API_USER = "<wordpress-username>"
$env:KUBEBUDDY_RADAR_API_PASSWORD = "<wordpress-app-password>"
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
- `-RadarApiPasswordEnv` (default `KUBEBUDDY_RADAR_API_PASSWORD`)

Fetch a saved Radar cluster config:

```powershell
Invoke-KubeBuddy `
  -RadarFetchConfig `
  -RadarConfigId "ccfg_12345678-1234-1234-1234-123456789abc"
```

## Docker Entrypoint Usage (`run.ps1`)

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
