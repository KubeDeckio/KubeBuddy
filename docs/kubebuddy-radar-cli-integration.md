# KubeBuddy CLI + Radar Integration (Design Draft)

## Purpose
Define how `KubeBuddy` CLI can integrate with `KubeBuddy Radar` to:

- detect outdated runtime assets (container images, Helm charts, optional app versions)
- upload run results for history/trends/comparisons
- retrieve historical context back into CLI
- support a paid tier model for storage and API access

## Scope (V1)

### In CLI
- New checks:
  - `RAD001`: Outdated container images
  - `RAD002`: Outdated Helm charts
- Optional upload mode:
  - `Invoke-KubeBuddy -RadarUpload`
- Optional history pull:
  - `Invoke-KubeBuddy -RadarCompare` (current vs previous run)

### In Radar API
- Accept KubeBuddy JSON run uploads
- Persist runs securely per tenant
- Return trends and run comparisons

## High-Level Architecture
1. CLI runs checks locally.
2. CLI generates standard report JSON.
3. If `-RadarUpload` is enabled, CLI sends JSON to Radar API.
4. Radar stores raw report + normalized finding indexes.
5. Dashboard uses stored runs for trend/comparison views.
6. CLI can call compare endpoint for delta output.

## CLI Additions

### New flags
- `-RadarUpload`
- `-RadarApiBaseUrl "https://radar.kubebuddy.io/api/kb-radar/v1"`
- `-RadarProjectKey "<project-slug-or-id>"`
- `-RadarEnvironment "prod|staging|dev"`
- `-RadarApiKeyEnv "KUBEBUDDY_RADAR_API_KEY"`
- `-RadarCompare` (compare against latest prior run)

### Config file extension (`~/.kube/kubebuddy-config.yaml`)
```yaml
radar:
  enabled: false
  api_base_url: "https://radar.kubebuddy.io/api/kb-radar/v1"
  project_key: "my-aks-prod"
  environment: "prod"
  api_key_env: "KUBEBUDDY_RADAR_API_KEY"
  upload_timeout_seconds: 30
  upload_retries: 2
```

### Upload behavior
- Non-blocking by default:
  - check/report generation must succeed even if upload fails.
- If upload fails:
  - print warning in CLI
  - include upload error note in report metadata

## Radar API Contract (Proposed V1)
Base URL:
`/api/kb-radar/v1`

### 1) Upload run
`POST /cluster-runs`

Headers:
- `Authorization: Basic base64(username:app_password)` (aligns with current Radar auth)
- `Content-Type: application/json`

Request body:
```json
{
  "source": "kubebuddy-cli",
  "source_version": "0.0.24",
  "project_key": "my-aks-prod",
  "environment": "prod",
  "cluster": {
    "name": "aks-prod-uks",
    "provider": "aks",
    "region": "uksouth"
  },
  "run": {
    "started_at": "2026-02-26T11:14:10Z",
    "finished_at": "2026-02-26T11:18:34Z",
    "duration_seconds": 264
  },
  "report": {
    "format_version": "1.0",
    "health_score": 69.77,
    "checks": []
  }
}
```

Response:
```json
{
  "success": true,
  "run_id": "crun_01JABC...",
  "ingested_at": "2026-02-26T11:18:35Z"
}
```

### 2) List runs
`GET /cluster-runs?project_key=my-aks-prod&environment=prod&page=1&per_page=20`

### 3) Get single run
`GET /cluster-runs/{run_id}`

### 4) Compare runs
`GET /cluster-runs/compare?project_key=my-aks-prod&environment=prod&from=crun_...&to=crun_...`

Returns:
- score delta
- new findings
- resolved findings
- regressed findings

### 5) Trend summary
`GET /cluster-runs/trends?project_key=my-aks-prod&environment=prod&window_days=30`

Returns:
- health score trend
- fail count trend by severity
- top recurring checks

## Secure Data Storage Model

### Data classification
- Raw report JSON may contain sensitive operational data (namespaces, image refs, pod names).
- Treat all uploaded run payloads as confidential tenant data.

### Storage pattern
- `cluster_runs` (metadata + pointers)
- `cluster_run_payloads` (encrypted JSON blob)
- `cluster_run_findings` (normalized index for query speed)

### Security controls
- TLS in transit
- encryption at rest for payload blobs
- per-tenant row isolation
- API audit logging (who uploaded/read what and when)
- retention policy (e.g., 30/90/365 days by plan)
- deletion endpoint for compliance

## Outdated Artifact Checks (Radar-backed)

### `RAD001` Outdated container images
Detection strategy:
- parse image references from workloads
- resolve digest/tag metadata from registry sources
- compare running version age vs latest stable

Output:
- namespace/workload/container/image/current/latest/release_age_days
- recommendation severity by staleness window

### `RAD002` Outdated Helm charts
Detection strategy:
- collect installed chart name/version
- compare with known latest chart version from Radar catalog

Output:
- namespace/release/chart/current/latest/delta

## Paid Tier Boundary (Recommended)

### Free
- local checks only
- no historical storage
- no API trend/compare

### Pro / Pro Plus
- API upload enabled
- run history retention
- trend dashboards
- compare endpoints
- team API access / automation limits

Rationale:
- storage + query + API costs are ongoing
- premium value is historical intelligence, not just one-time scanning

## Dashboard Enhancements (Radar)
- Cluster run timeline per project/environment
- Score trend chart and check-fail trend chart
- "What changed since last run" panel
- Top regression cards
- Drill-down into raw findings for each run

## CLI Enhancements (optional after V1)
- `-RadarCompare` prints:
  - score delta
  - new/resolved/regressed checks
  - top 5 regressions
- `-RadarRunId` for explicit compare target

## Rollout Plan
1. Define JSON schema + API endpoints (`cluster-runs` + compare + trends).
2. Implement upload path in CLI (feature-flagged).
3. Add storage tables and secure retention controls in Radar.
4. Build dashboard trend + compare pages.
5. Add CLI compare command.
6. Add billing/plan enforcement for upload/history endpoints.

## Open Decisions
- Auth model long-term:
  - stay with WP App Passwords, or add scoped service tokens for CI?
- Max payload size and compression:
  - recommend gzip support for report upload.
- PII/secret scrubbing:
  - define exact fields to redact before upload.
- Multi-cluster naming:
  - enforce stable `project_key + environment + cluster.name` identity.

## Suggested Next Deliverables
1. Finalize API request/response schema as `openapi.yaml`.
2. Add a minimal CLI prototype:
   - upload current JSON report to `/cluster-runs`
   - print returned `run_id`
3. Add Radar DB migration for `cluster_runs` + payload storage.
