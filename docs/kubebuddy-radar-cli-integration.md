# KubeBuddy CLI + Radar Integration (Pro)

Use this guide to upload KubeBuddy JSON scan results into KubeBuddy Radar for:

- run history
- score trends
- run-to-run compare
- artifact freshness analysis (image/chart/app where detectable)

## Deterministic Artifact Inventory (Pro)

When Radar mode is enabled (`-RadarUpload` or `-RadarCompare`), KubeBuddy now builds a deterministic artifact inventory from Kubernetes workload specs and labels:

- container images (repo/tag/digest)
- Helm charts (from `helm.sh/chart` and Helm labels/annotations)
- app name/version labels (for example `app.kubernetes.io/name`, `app.kubernetes.io/version`)

This inventory is added to JSON under `artifacts` and is also shown in HTML/TXT reports only for Radar-mode runs.
KubeBuddy performs a direct Radar catalog lookup during report flow and enriches reports with:

- latest known version from Radar catalog
- status (`up_to_date`, `minor_behind`, `major_behind`, `unknown`)
- freshness summary counts

Matching/precedence rules:

- Helm charts are matched first and treated as primary version source.
- Workloads marked as Helm-managed inherit Helm chart version status.
- Helm-managed image/app rows are omitted from standalone HTML/TXT tables to reduce noise.
- For semver values, KubeBuddy prefers latest stable in the same minor track first (for example `1.19.x`) before global latest.

## What Gets Uploaded

Only the JSON report payload is uploaded.

- `Invoke-KubeBuddy -jsonReport -RadarUpload ...`
- HTML and TXT outputs are local artifacts only
- Radar upload is non-blocking, so report generation still completes if upload fails
- Radar now prefers `report.artifacts` for freshness processing and falls back to check-item parsing for older reports
- local JSON/HTML/TXT reports are enriched with direct Radar version lookup data (no async queue wait required)

## Authentication

Radar API access uses WordPress Application Passwords (Basic auth).

Set env vars before running KubeBuddy:

```powershell
$env:KUBEBUDDY_RADAR_API_USER = "<wordpress-username>"
$env:KUBEBUDDY_RADAR_API_PASSWORD = "<wordpress-app-password>"
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

Use custom Radar endpoint and custom credential env-var names:

```powershell
Invoke-KubeBuddy `
  -jsonReport `
  -RadarUpload `
  -RadarApiBaseUrl "https://radar.example.com/api/kb-radar/v1" `
  -RadarApiUserEnv "MY_RADAR_USER_ENV" `
  -RadarApiPasswordEnv "MY_RADAR_PASS_ENV"
```

## Docker Entry Point Support (`run.ps1`)

When running the container image, configure Radar via env vars:

```bash
-e JSON_REPORT="true" \
-e RADAR_UPLOAD="true" \
-e RADAR_COMPARE="true" \
-e RADAR_ENVIRONMENT="prod" \
-e KUBEBUDDY_RADAR_API_USER="<wordpress-username>" \
-e KUBEBUDDY_RADAR_API_PASSWORD="<wordpress-app-password>"
```

Rules enforced by `run.ps1`:

- `RADAR_UPLOAD=true` or `RADAR_COMPARE=true` requires `JSON_REPORT=true`

## Config File Defaults (`kubebuddy-config.yaml`)

```yaml
radar:
  enabled: false
  api_base_url: "https://radar.kubebuddy.io/api/kb-radar/v1"
  environment: "prod"
  api_user_env: "KUBEBUDDY_RADAR_API_USER"
  api_password_env: "KUBEBUDDY_RADAR_API_PASSWORD"
  upload_timeout_seconds: 30
  upload_retries: 2
```

CLI flags override config values for that run.

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
  - freshness table with status and confidence

If a metric is missing from uploaded JSON, UI shows `n/a`.

## Notes

- AKS metadata fields in JSON now fall back to CLI values (`-SubscriptionId`, `-ResourceGroup`, `-ClusterName`) when source values are null.
- Cluster run retention defaults to 90 days in Radar v1.
