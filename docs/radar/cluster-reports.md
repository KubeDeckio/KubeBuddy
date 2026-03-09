# Cluster Reports (Pro)

Cluster Reports stores KubeBuddy JSON scan history per user so you can track score trend, compare runs, and review freshness insights.

## Scope

- Upload source: KubeBuddy CLI JSON reports
- Visibility: uploader only
- Auth: HTTP Basic with WordPress username + Application Password
- Retention default: 90 days

## UI Pages

Create this page in WordPress:

- `/cluster-reports/` with shortcode:

```text
[radar_cluster_reports]
```

Dashboard integration:

- `/dashboard/` includes a Cluster Reports Overview card
- score trend line (30d / 90d)
- latest score and delta vs previous
- failed-check trend
- CTA: `View Cluster Reports`

When fields are missing in uploaded JSON, UI shows `n/a` with tooltip `Value not present in uploaded report`.

## API Endpoints

Base URL:

```text
https://radar.kubebuddy.io/api/kb-radar/v1
```

All endpoints below are Pro-gated and private (`Cache-Control: no-store`).

### POST /cluster-reports

Upload a single run.

Required fields:

- `cluster.name` (or `report.metadata.clusterName`)
- `report` (full KubeBuddy JSON object)

Optional fields:

- `environment` (default `prod`)
- `cluster.name`
- `run.started_at`
- `run.finished_at`

Example:

```json
{
  "environment": "prod",
  "cluster": {
    "name": "bluegreen-test-uks"
  },
  "run": {
    "started_at": "2026-03-06T20:20:27Z",
    "finished_at": "2026-03-06T20:22:00Z"
  },
  "report": {
    "metadata": {
      "clusterName": "bluegreen-test-uks",
      "score": 79.0
    },
    "checks": {}
  }
}
```

Response:

```json
{
  "success": true,
  "run_id": "crun_123e4567-e89b-12d3-a456-426614174000",
  "ingested_at": "2026-03-06T20:22:01+00:00",
  "processing_status": "queued"
}
```

### GET /cluster-reports

List runs for authenticated user.

Query params:

- `cluster_name` (optional, defaults to your latest uploaded cluster)
- `environment` (optional)
- `page` (default `1`)
- `per_page` (default `20`, max `100`)

### GET /cluster-reports/{run_id}

Get one run metadata.

Query params:

- `include_report=true` (optional, includes decrypted report payload)

### GET /cluster-reports/compare

Compare latest two runs (or specific `to_run_id`) within a cluster/environment.

Query params:

- `cluster_name` + `environment` (for latest-vs-previous)
- `to_run_id` (optional explicit target run)

Response includes:

- `score_delta`
- `new_findings`, `resolved_findings`, `regressed_findings`

### GET /cluster-reports/trends

Trend points for score + failed checks.

Query params:

- `cluster_name` (optional, defaults to your latest uploaded cluster)
- `environment` (optional)
- `window_days` (`1-365`, default `30`)

### GET /cluster-reports/{run_id}/freshness

Returns detected artifacts and freshness status:

- `up_to_date`
- `minor_behind`
- `major_behind`
- `unknown`

Each item includes current version, latest version (if known), confidence, and recommendation text.

## Security Model

- Payload JSON is encrypted at rest before DB write (AES-256-GCM).
- Normalized findings/artifacts are stored for fast compare/trend/freshness queries.
- Audit logs are recorded for upload/read/compare/freshness actions.

## Admin Insights

WordPress admin now includes a dedicated `Subscription Intelligence` page (`KubeBuddy Radar -> Subscription Intelligence`) with:

- most popular subscribed projects
- free users near/at limit
- per-user plan and usage snapshot

Use this to identify upgrade candidates and product demand trends.
