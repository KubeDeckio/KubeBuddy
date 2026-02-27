# KubeBuddy CLI + Radar Integration (Design Draft)

## Purpose
Define how `KubeBuddy` CLI integrates with `KubeBuddy Radar` as a **paid feature** to:

- detect outdated runtime assets (container images, Helm charts)
- enrich local findings with Radar release intelligence
- optionally upload run results for history/trends/comparisons
- support privacy-first and upload-enabled operating modes

## Product Positioning
- Radar integration is **paid-only** (requires Radar API credentials).
- No Radar credentials = no Radar-backed checks/features.

## Platform and Entitlement Context
- Radar runs on WordPress.
- Membership and plan entitlements are managed with **Paid Memberships Pro (free plugin)**.
- CLI/API authentication uses **WordPress Application Passwords** (the Radar "API key" experience).
- Authorization checks use WordPress user identity + membership level on every request.

## Scope (V1)

### In CLI
- New checks:
  - `RAD001`: Outdated container images
  - `RAD002`: Outdated Helm charts
- New integration modes:
  - `-RadarEnrich` (default Radar mode): pull intelligence from Radar, compare locally, no report upload
  - `-RadarUpload` (optional): upload run JSON for history/trends/compare
  - `-RadarCompare` (optional): compare against previous uploaded run

### In Radar API
- Expose release intelligence data for CLI pull (existing Radar catalog/release data)
- Optionally accept KubeBuddy run uploads
- Optionally return trends and run comparisons

## Operating Modes

### Mode A (Recommended default): Pull-first, privacy-first
1. CLI runs checks locally.
2. CLI queries Radar for release intelligence.
3. CLI performs outdated checks locally.
4. No cluster findings payload is uploaded.

### Mode B (Optional): Upload-enabled
1. CLI runs checks locally.
2. CLI optionally uploads report JSON to Radar.
3. Radar stores run snapshots and computes trends/deltas.
4. CLI/dashboard can query compare/trend endpoints.

## High-Level Architecture
1. CLI discovers running workloads/images/charts.
2. CLI pulls Radar intelligence (latest known versions, release metadata, impact labels).
3. CLI computes `RAD001`/`RAD002` locally.
4. If `-RadarUpload` is enabled, CLI sends report JSON to Radar.
5. Radar stores raw report + normalized finding indexes.
6. CLI or dashboard can call compare/trend endpoints when upload mode is used.

## CLI Additions

### New flags
- `-RadarEnrich`
- `-RadarUpload`
- `-RadarApiBaseUrl "https://radar.kubebuddy.io/api/kb-radar/v1"`
- `-RadarProjectKey "<project-slug-or-id>"`
- `-RadarEnvironment "prod|staging|dev"`
- `-RadarApiKeyEnv "KUBEBUDDY_RADAR_API_KEY"`
- `-RadarCompare` (compare against latest prior uploaded run)

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
  mode: "enrich" # enrich | upload
```

## API Contract (V1 direction)
Base URL:
`/api/kb-radar/v1`

### Authentication and Authorization
- Authentication: HTTP Basic Auth using WordPress username + Application Password.
- Authorization: membership-level and tenant access checks are enforced server-side.
- API requests must be denied if:
  - credentials are invalid,
  - membership level is not entitled to Radar API features,
  - requester does not belong to the target tenant/workspace.

### A) Intelligence pull endpoints (required for V1)
- Endpoint(s) to retrieve latest known version/release metadata for:
  - container image mapping
  - Helm chart mapping
- Return release date, stability/status, and impact labels where available.

### B) Upload/trend endpoints (optional in V1, required for full suite)
- `POST /cluster-runs`
- `GET /cluster-runs`
- `GET /cluster-runs/{run_id}`
- `GET /cluster-runs/compare`
- `GET /cluster-runs/trends`

## Dashboard UX (Cluster Health)
Add a new paid dashboard area under Radar for uploaded KubeBuddy run intelligence.

### Navigation
- Dashboard > Cluster Health
- Scope selector: `project_key` + `environment` + `cluster_name`

### V1 UI components
1. Cluster Summary Header
- last run timestamp
- run status (uploaded/failed)
- current health score

2. Health KPI Cards
- failing checks by severity (critical/warning/info)
- total findings
- score delta vs previous run

3. Run Timeline
- health score trend chart
- findings trend by severity
- run duration trend

4. Drift Panel (What Changed)
- new findings
- resolved findings
- regressed findings
- top 5 changed checks

5. Top Recurring Checks
- most frequent failing check IDs
- category and severity breakdown

6. Run Details View
- per-check findings for selected run
- filters: severity/category/check ID/namespace
- export link to stored run payload (authorized users only)

### UX behavior rules
- Empty state: show onboarding for first upload.
- Partial state: if compare data missing, still show latest run.
- Failure state: show upload error details without blocking rest of dashboard.
- Privacy state: if tenant disables payload retention, show summary-only mode.

## Outdated Artifact Checks (Radar-backed)

### `RAD001` Outdated container images
Detection strategy:
- parse image references from workloads
- map image to Radar project/release stream
- compare running tag/digest age vs latest known stable

Output fields:
- namespace/workload/container/image/current/latest/release_age_days/confidence

### `RAD002` Outdated Helm charts
Detection strategy:
- collect installed chart name/version
- map chart to Radar project/release stream
- compare current vs latest known stable

Output fields:
- namespace/release/chart/current/latest/delta/confidence

## Important Limitation: GitHub-release-only Source
Radar currently derives freshness from GitHub release data.

This is useful, but not universally accurate for all container/chart ecosystems.

Known gaps:
- image tags may not align with GitHub releases
- registry publishing cadence may differ from GitHub releases
- private/custom images may have no reliable external latest signal
- some chart sources may not map cleanly to Radar project identity

### Confidence model (recommended)
Include confidence in `RAD001`/`RAD002`:
- `high`: strong mapping + matching version stream
- `medium`: probable mapping, partial evidence
- `low`: weak mapping, heuristic only

## Upload Behavior
- Non-blocking by default:
  - local scan/report must succeed even if Radar calls fail.
- If Radar call fails:
  - print warning in CLI
  - include integration error note in report metadata

## Security and Compliance
- TLS in transit
- MySQL persistence for uploaded run data
- encryption at rest for stored payloads and sensitive fields
- per-tenant row isolation (strict account boundary)
- API audit logging
- retention policy by plan
- deletion endpoint for compliance (if upload mode used)

## Uploaded Data Storage Model (MySQL)

Uploaded KubeBuddy run data is stored in MySQL with tenant-aware design.

Recommended tables:
- `cluster_runs` (run metadata, tenant/user ownership, pointers)
- `cluster_run_payloads` (encrypted JSON payload blob)
- `cluster_run_findings` (normalized query index for dashboard/trends)
- `cluster_run_access_audit` (read/write access log)

Recommended key fields:
- `tenant_id`
- `owner_user_id`
- `project_key`
- `environment`
- `cluster_name`
- `created_at`, `updated_at`

## Access Control and Isolation

### Current model (single-account ownership)
- Every uploaded run is bound to a `tenant_id`.
- API queries must always filter by authenticated `tenant_id`.
- Cross-tenant access is denied by default.
- Dashboard queries must use the same `tenant_id` guardrail as API access.
- UI must never expose cross-tenant identifiers in selectors or links.

### Future model (team support)
- Add team/workspace membership and role-based access:
  - `owner`, `admin`, `editor`, `viewer`
- Access checks become:
  - authenticated principal has membership in tenant/workspace
  - role permits requested action (`read`, `upload`, `delete`, `manage`)
- Keep row-level filtering by `tenant_id` as non-negotiable baseline.
- UI behavior by role (planned):
  - `viewer`: read-only dashboard and run details
  - `editor`: upload/integration config + read
  - `admin`: retention, access policy, delete
  - `owner`: full billing + security controls

## Encryption Requirements

- Encrypt payload blobs before storage (application-level encryption).
- Store encryption metadata (key version, algorithm) with records.
- Rotate encryption keys safely with re-encryption workflow.
- Do not store plaintext secrets in uploaded payloads.
- Redact known sensitive fields before upload where feasible.

## Paid Feature Boundary
Radar integration is paid.

Includes:
- Radar API access for enrichment
- outdated checks (`RAD001`, `RAD002`)
- optional upload/trend/compare capabilities

Entitlement source:
- WordPress membership level from **Paid Memberships Pro (free plugin)**.
- Plan enforcement is performed at API request time, not only in the UI.

## Rollout Plan
1. Finalize image/chart mapping contract for pull endpoints.
2. Implement CLI `-RadarEnrich` using pull-first local comparison.
3. Add confidence scoring and clear caveats in reports.
4. Add optional `-RadarUpload` path + storage endpoints.
5. Add compare/trend APIs and dashboard views.
6. Add plan enforcement for all Radar integration endpoints.

## Open Decisions
- Mapping strategy:
  - deterministic project/image/chart mapping rules.
- Payload model in upload mode:
  - full report vs reduced normalized findings.
- Idempotency:
  - how retries avoid duplicate run ingestion.

## Suggested Next Deliverables
1. Define `RAD001`/`RAD002` mapping + confidence schema.
2. Add CLI prototype for pull-first enrichment (`-RadarEnrich`).
3. Add API spec for intelligence pull endpoint(s).
4. Add optional upload endpoint prototype (`POST /cluster-runs`).
