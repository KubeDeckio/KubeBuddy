# API Reference

## Base URL

```
https://radar.kubebuddy.io/api/kb-radar/v1
```

## Authentication

All API endpoints require authentication. Use HTTP Basic Auth (WordPress Application Passwords) for API clients, or a logged-in browser session with a REST nonce.

**Getting your API key:**
- Go to Account → Developer API Access
- Create a key and copy it (shown once)
- Keys are WordPress Application Passwords tied to your user
- Use your WordPress username + the generated key

**Example header:**

```
Authorization: Basic base64(username:app_password)
```

**Note:** The API key limit depends on your plan level:
- Pro: 3 keys
- Pro Plus: 10 keys

## Response format

Most responses include structured data with consistent formatting. Response structure varies by endpoint but follows these patterns:

**Paginated lists** (projects, releases):
```json
{
  "page": 1,
  "per_page": 20,
  "total": 128,
  "total_pages": 7,
  "items": [...]
}
```

**Simple responses** (stats, dashboard):
```json
{
  "success": true,
  "total_projects": 286,
  "total_releases": 4021
}
```

## Endpoint matrix

### Catalog Endpoints
These endpoints are publicly cacheable for performance. Authentication is optional - anonymous users get cached responses, authenticated users can access subscription status via separate endpoints.

| Endpoint | Purpose | Auth Required |
| --- | --- | --- |
| `GET /projects` | List projects (paginated, searchable) | No* |
| `GET /projects/{id}` | Get single project with full details | No* |
| `GET /projects/{id}/releases` | Get project releases (paginated by type) | No* |
| `GET /stats` | Global platform statistics | No* |
| `GET /recent-releases` | Recent release highlights (filterable) | No* |
| `GET /popular-projects` | Most followed projects | No* |
| `GET /my-subscriptions` | Get your subscribed project IDs (lightweight) | Yes |

*Publicly accessible and cached at CDN edge. Provide authentication to bypass cache if needed.

### User Data Endpoints
These endpoints return personalized data for the authenticated user.

| Endpoint | Purpose | Auth Required |
| --- | --- | --- |
| `GET /subscriptions` | Your tracked projects | Yes |
| `GET /feed` | Release feed from your subscriptions | Yes |
| `GET /dashboard` | Account metadata and plan info | Yes |
| `GET /dashboard-activity` | Recent releases for dashboard | Yes |
| `GET /dashboard-logs` | Your delivery logs | Yes |

### Subscription Management
Manage your project subscriptions and settings.

| Endpoint | Purpose | Auth Required |
| --- | --- | --- |
| `POST /toggle-sub` | Subscribe/unsubscribe from a project | Yes |
| `POST /update-settings` | Update subscription settings | Yes |
| `POST /test-notification` | Test webhook/notification delivery | Yes |

### Label Management
Organize subscriptions with custom labels (Pro feature).

| Endpoint | Purpose | Auth Required |
| --- | --- | --- |
| `GET /labels` | List your custom labels | Yes |
| `POST /labels` | Create a new label | Yes |
| `PUT /labels/{id}` | Update a label | Yes |
| `DELETE /labels/{id}` | Delete a label | Yes |
| `POST /subscriptions/{subscription_id}/labels` | Attach labels to subscription | Yes |
| `DELETE /subscriptions/{subscription_id}/labels/{label_id}` | Remove label from subscription | Yes |

### API Key Management
Manage your API keys (requires Pro or Pro Plus plan).

| Endpoint | Purpose | Auth Required |
| --- | --- | --- |
| `GET /api-keys` | List your application passwords | Yes (Pro+) |
| `POST /api-keys` | Create new application password | Yes (Pro+) |
| `DELETE /api-keys/{uuid}` | Revoke application password | Yes (Pro+) |

### Cluster Reports (Pro)
Private run history for uploaded KubeBuddy JSON reports.

| Endpoint | Purpose | Auth Required |
| --- | --- | --- |
| `POST /cluster-reports` | Upload JSON report run | Yes (Pro+) |
| `GET /cluster-reports` | List your cluster reports | Yes (Pro+) |
| `GET /cluster-reports/{run_id}` | Get single run metadata (and optional report) | Yes (Pro+) |
| `GET /cluster-reports/compare` | Compare latest two runs or specific target run | Yes (Pro+) |
| `GET /cluster-reports/trends` | Score + failed-check trend points | Yes (Pro+) |
| `GET /cluster-reports/{run_id}/freshness` | Artifact freshness analysis | Yes (Pro+) |

### Cluster Configs (Pro)
Private per-user KubeBuddy scan profiles stored encrypted at rest.

| Endpoint | Purpose | Auth Required |
| --- | --- | --- |
| `GET /cluster-configs` | List your saved cluster configs | Yes (Pro+) |
| `POST /cluster-configs` | Create a cluster config | Yes (Pro+) |
| `GET /cluster-configs/{config_id}` | Get a single cluster config | Yes (Pro+) |
| `PUT /cluster-configs/{config_id}` | Update a cluster config | Yes (Pro+) |
| `DELETE /cluster-configs/{config_id}` | Delete a cluster config | Yes (Pro+) |
| `GET /cluster-configs/{config_id}/command` | Build the CLI/Docker command preview | Yes (Pro+) |
| `GET /cluster-configs/{config_id}/config-file` | Generate `kubebuddy-config.yaml` content | Yes (Pro+) |
| `GET /cluster-configs/bootstrap-candidates` | List starter profile candidates derived from existing cluster reports | Yes (Pro+) |
| `POST /cluster-configs/bootstrap-from-reports` | Create starter profiles from existing cluster reports | Yes (Pro+) |

## Endpoint details

### GET /projects

List all projects with pagination support and search capabilities. Returns basic project metadata including latest version and release count.

**Authentication:** Optional. Anonymous requests are cached at CDN edge for 1 hour. Authenticated requests get personalized cache.

**Performance:** This endpoint is optimized for speed with CDN caching. For subscription status, see GET /my-subscriptions.

**Query params:**
- `page` (integer, default 1) - Page number for pagination
- `per_page` (integer, default 20, max 100) - Results per page
- `search` (string, optional) - Search term for project name, description, category, or repo URL
- `cncf_status` (string, optional) - Filter by "graduated", "incubating", "sandbox", or "open-source"
- `include_releases` (string, optional) - Set to "true" to include full release history (slow, not cached)

**Example requests:**

```bash
# Anonymous request (cached at edge)
curl "https://radar.kubebuddy.io/api/kb-radar/v1/projects?page=1&per_page=3"

# Basic pagination with auth
curl -u "username:app_password" \
  "https://radar.kubebuddy.io/api/kb-radar/v1/projects?page=1&per_page=3"

# Search for projects
curl "https://radar.kubebuddy.io/api/kb-radar/v1/projects?search=kubernetes"

# Filter by CNCF status
curl "https://radar.kubebuddy.io/api/kb-radar/v1/projects?cncf_status=graduated&per_page=10"
```

**Response:**

```json
{
  "page": 1,
  "per_page": 3,
  "total": 256,
  "total_pages": 86,
  "items": [
    {
      "id": 12,
      "name": "Argo CD",
      "description": "Declarative GitOps CD for Kubernetes",
      "category": "CI/CD",
      "cncf_status": "graduated",
      "homepage": "https://argo-cd.readthedocs.io",
      "docs_url": "https://argo-cd.readthedocs.io/en/stable/",
      "repo_url": "https://github.com/argoproj/argo-cd",
      "helm_chart_repo": null,
      "logo_url": "https://radar.kubebuddy.io/logos/argo-cd.png",
      "updated_at": "2024-06-02 10:35:20",
      "latest_version": "v2.10.4",
      "latest_published_at": "2024-06-02 10:35:20"
    }
  ]
}
```

**Note:** The `is_subscribed` field has been removed for caching performance. Use GET /my-subscriptions to fetch subscription status separately.

### GET /projects/{id}

Get comprehensive details about a single project, including complete release history grouped by type (app/helm/pre).

**Path params:** `id` (project ID)

**Example:**

```bash
curl -u "username:app_password" \
  "https://radar.kubebuddy.io/api/kb-radar/v1/projects/12"
```

**Response:**

```json
{
  "product": {
    "id": 12,
    "name": "Argo CD",
    "description": "Declarative GitOps CD for Kubernetes",
    "category": "CI/CD",
    "cncf_status": "graduated",
    "repo_url": "https://github.com/argoproj/argo-cd",
    "homepage": "https://argo-cd.readthedocs.io",
    "logo_url": "https://radar.kubebuddy.io/logos/argo-cd.png",
    "releases": {
      "app": [
        {
          "id": 1234,
          "product_id": 12,
          "version": "v2.10.4",
          "type": "app",
          "release_notes": "<p>Bug fixes and performance improvements...</p>",
          "url": "https://github.com/argoproj/argo-cd/releases/tag/v2.10.4",
          "published_at": "2024-06-02 10:35:20",
          "created_at": "2024-06-02 11:00:00",
          "has_security_fix": false,
          "cve_list": null,
          "security_severity": "none",
          "security_summary": null,
          "cve_links": null
        }
      ],
      "helm": [],
      "pre": []
    }
  }
}
```

### GET /projects/{id}/releases

Get paginated releases for a specific project, filtered by release type.

**Path params:** `id` (project ID)

**Query params:**
- `type` (string, default "app") - Release type: "app", "helm", or "pre"
- `page` (integer, default 1) - Page number
- `per_page` (integer, default 20, max 100) - Results per page

**Example:**

```bash
curl -u "username:app_password" \
  "https://radar.kubebuddy.io/api/kb-radar/v1/projects/12/releases?type=app&page=1&per_page=5"
```

**Response:**

```json
{
  "page": 1,
  "per_page": 5,
  "total": 45,
  "total_pages": 9,
  "items": [
    {
      "id": 1234,
      "product_id": 12,
      "version": "v2.10.4",
      "type": "app",
      "release_notes": "<p>Bug fixes and improvements</p>",
      "url": "https://github.com/argoproj/argo-cd/releases/tag/v2.10.4",
      "published_at": "2024-06-02 10:35:20",
      "has_security_fix": false,
      "security_severity": "none"
    }
  ]
}
```

### GET /stats

Get global platform statistics including total projects, releases, and security fix counts. Useful for dashboards and overview metrics.

**Authentication:** Optional. Responses are cached.

**Example:**

```bash
curl "https://radar.kubebuddy.io/api/kb-radar/v1/stats"
```

**Response:**

```json
{
  "success": true,
  "total_projects": 286,
  "total_releases": 4021,
  "total_security_fixes": 127
}
```

### GET /my-subscriptions

Get the list of project IDs you're subscribed to. This is a lightweight endpoint designed for hydrating subscription status on cached project lists.

**Authentication:** Required (returns empty array for anonymous users).

**Use case:** Fetch this after loading `/projects` to determine which projects the user is subscribed to without slowing down the initial catalog load.

**Example:**

```bash
curl -u "username:app_password" \
  "https://radar.kubebuddy.io/api/kb-radar/v1/my-subscriptions"
```

**Response:**

```json
{
  "subscribed_ids": [12, 45, 78, 103, 156]
}
```

**Performance tip:** Call this endpoint in parallel with rendering the UI. The project list loads from cache instantly, then subscription buttons update ~100ms later.

```json
{
  "success": true,
  "total_projects": 286,
  "total_releases": 4021,
  "total_security_fixes": 82
}
```

### GET /recent-releases

Get recent stable releases across all tracked projects. Supports filtering by category and security status. Includes AI-parsed release notes with security information.

**Query params:**
- `limit` (integer, default 2, max 20) - Number of releases to return
- `category` (string, optional) - Filter by category (e.g., "CI/CD", "Networking", "Storage", "Service Mesh", "Monitoring")
- `security_only` (string, optional) - Set to "1" to show only releases with security fixes

**Examples:**

```bash
# Basic recent releases
curl -u "username:app_password" \
  "https://radar.kubebuddy.io/api/kb-radar/v1/recent-releases?limit=5"

# Security releases only
curl -u "username:app_password" \
  "https://radar.kubebuddy.io/api/kb-radar/v1/recent-releases?limit=10&security_only=1"

# Recent CI/CD tool releases
curl -u "username:app_password" \
  "https://radar.kubebuddy.io/api/kb-radar/v1/recent-releases?limit=10&category=CI/CD"
```

**Response:**

```json
{
  "success": true,
  "releases": [
    {
      "id": 1234,
      "name": "Argo CD",
      "logo_url": "https://radar.kubebuddy.io/logos/argo-cd.png",
      "category": "CI/CD",
      "cncf_status": "graduated",
      "repo_url": "https://github.com/argoproj/argo-cd",
      "version": "v2.10.4",
      "type": "app",
      "published_at": "2024-06-02 10:35:20",
      "release_notes": "<p>Bug fixes and performance improvements...</p>",
      "has_security_fix": true,
      "security_severity": "high"
    }
  ]
}
```

### GET /popular-projects

Get the most followed projects ranked by subscriber count. Shows active projects with recent release activity.

**Query params:**
- `limit` (integer, default 10, max 50) - Number of projects to return

**Example:**

```bash
curl -u "username:app_password" \
  "https://radar.kubebuddy.io/api/kb-radar/v1/popular-projects?limit=5"
```

**Response:**

```json
{
  "success": true,
  "projects": [
    {
      "id": 12,
      "name": "Argo CD",
      "category": "CI/CD",
      "cncf_status": "graduated",
      "logo_url": "https://radar.kubebuddy.io/logos/argo-cd.png",
      "repo_url": "https://github.com/argoproj/argo-cd",
      "subscriber_count": 220,
      "last_release_at": "2024-06-02 10:35:20",
      "releases_30d": 3
    }
  ]
}
```

### GET /subscriptions

Get all projects you're tracking. Includes subscription settings, labels, and latest release information.

**Example:**

```bash
curl -u "username:app_password" \
  "https://radar.kubebuddy.io/api/kb-radar/v1/subscriptions"
```

**Response:**

```json
{
  "subscriptions": [
    {
      "id": 45,
      "user_id": 123,
      "product_id": 12,
      "webhook_url": null,
      "slack_webhook": null,
      "teams_webhook": null,
      "generic_webhook": null,
      "email_enabled": true,
      "email_frequency": "per_app",
      "release_types_filter": "app,helm",
      "webhook_release_types": "app",
      "use_global_webhooks": false,
      "notifications_paused": false,
      "created_at": "2024-01-15 08:30:00",
      "name": "Argo CD",
      "logo_url": "https://radar.kubebuddy.io/logos/argo-cd.png",
      "description": "Declarative GitOps CD for Kubernetes",
      "repo_url": "https://github.com/argoproj/argo-cd",
      "latest_release": {
        "id": 1234,
        "version": "v2.10.4",
        "published_at": "2024-06-02 10:35:20",
        "has_security_fix": false
      },
      "labels": [
        {
          "id": 5,
          "label_name": "Production",
          "label_color": "#ff0000",
          "subscription_count": 3
        }
      ]
    }
  ],
  "subscription_count": 1
}
```

### GET /feed

Get recent releases from your tracked projects. Personalized release activity feed.

**Query params:**
- `days` (integer, default 7) - Number of days to look back

**Example:**

```bash
curl -u "username:app_password" \
  "https://radar.kubebuddy.io/api/kb-radar/v1/feed?days=7"
```

**Response:**

```json
{
  "success": true,
  "releases": [
    {
      "product_id": 12,
      "name": "Argo CD",
      "version": "v2.10.4",
      "published_at": "2024-06-02 10:35:20",
      "type": "app",
      "has_security_fix": false
    }
  ]
}
```

### GET /dashboard

Get comprehensive account information including plan details, subscription limits, global webhook settings, and all subscriptions.

**Example:**

```bash
curl -u "username:app_password" \
  "https://radar.kubebuddy.io/api/kb-radar/v1/dashboard"
```

**Response:**

```json
{
  "subscriptions": [...],
  "is_pro": true,
  "subscription_count": 8,
  "subscription_limit": 10,
  "user_email": "user@example.com",
  "user_login": "username",
  "pms_status": "active",
  "pms_trial_end": null,
  "pms_is_cancelled": false,
  "slack_webhook": null,
  "teams_webhook": null,
  "generic_webhook": "https://example.com/webhook",
  "webhook_release_types": "app,helm",
  "labels": [
    {
      "id": 5,
      "label_name": "Production",
      "label_color": "#ff0000",
      "subscription_count": 3
    }
  ]
}
```

### GET /api-keys

List all application passwords (API keys) for your account. Shows key metadata but not the actual passwords (those are only shown once at creation).

**Requires:** Pro or Pro Plus plan

**Example:**

```bash
curl -u "username:app_password" \
  "https://radar.kubebuddy.io/api/kb-radar/v1/api-keys"
```

**Response:**

```json
{
  "keys": [
    {
      "uuid": "08f5c3f1-1f1c-4b3f-9c6f-7a9a1f0ddf7a",
      "name": "Production CI",
      "created": "2024-06-02 10:35:20"
    },
    {
      "uuid": "12a8d9e2-3b4c-5d6e-7f8g-9h0i1j2k3l4m",
      "name": "Development",
      "created": "2024-05-15 14:20:10"
    }
  ],
  "limit": 3,
  "count": 2,
  "remaining": 1
}
```

### POST /api-keys

Create a new application password for API access. The password is only shown once in the response - save it securely.

**Requires:** Pro or Pro Plus plan

**Request body:**
```json
{
  "name": "Production CI"
}
```

**Example:**

```bash
curl -u "username:app_password" \
  -H "Content-Type: application/json" \
  -d '{"name":"Production CI"}' \
  "https://radar.kubebuddy.io/api/kb-radar/v1/api-keys"
```

**Response:**

```json
{
  "success": true,
  "password": "abcd efgh ijkl mnop qrst uvwx",
  "item": {
    "uuid": "08f5c3f1-1f1c-4b3f-9c6f-7a9a1f0ddf7a",
    "name": "Production CI",
    "created": "2024-06-02 10:35:20"
  }
}
```

**Important:** Save the `password` value immediately - it cannot be retrieved again.

### DELETE /api-keys/{uuid}

Revoke an application password so it can no longer be used for authentication.

**Requires:** Pro or Pro Plus plan

**Path params:** `uuid` (the unique identifier of the key to revoke)

**Example:**

```bash
curl -u "username:app_password" \
  -X DELETE \
  "https://radar.kubebuddy.io/api/kb-radar/v1/api-keys/08f5c3f1-1f1c-4b3f-9c6f-7a9a1f0ddf7a"
```

**Response:**

```json
{
  "success": true
}
```

### POST /toggle-sub

Subscribe or unsubscribe from a project. Toggling creates a subscription if it doesn't exist, or removes it if it does.

**Request body:**
```json
{
  "product_id": 12
}
```

**Example:**

```bash
curl -u "username:app_password" \
  -H "Content-Type: application/json" \
  -d '{"product_id":12}' \
  "https://radar.kubebuddy.io/api/kb-radar/v1/toggle-sub"
```

**Response:**

```json
{
  "success": true,
  "subscribed": true,
  "subscription_id": 45
}
```

### POST /update-settings

Update subscription settings including notification preferences, webhooks, and release type filters.

**Request body:**
```json
{
  "subscription_id": 45,
  "email_enabled": true,
  "email_frequency": "per_app",
  "release_types_filter": "app,helm",
  "slack_webhook": "https://hooks.slack.com/...",
  "webhook_release_types": "app"
}
```

**Example:**

```bash
curl -u "username:app_password" \
  -H "Content-Type: application/json" \
  -d '{"subscription_id":45,"email_enabled":true,"email_frequency":"daily"}' \
  "https://radar.kubebuddy.io/api/kb-radar/v1/update-settings"
```

**Response:**

```json
{
  "success": true
}
```

### GET /labels

Get all custom labels for the authenticated user. Labels are used to organize and filter subscriptions.

**Example:**

```bash
curl -u "username:app_password" \
  "https://radar.kubebuddy.io/api/kb-radar/v1/labels"
```

**Response:**

```json
{
  "labels": [
    {
      "id": 5,
      "label_name": "Production",
      "label_color": "#ff0000",
      "subscription_count": 3
    },
    {
      "id": 6,
      "label_name": "Monitoring",
      "label_color": "#00ff00",
      "subscription_count": 5
    }
  ]
}
```

### POST /labels

Create a new custom label.

**Request body:**
```json
{
  "label_name": "Production",
  "label_color": "#ff0000"
}
```

**Example:**

```bash
curl -u "username:app_password" \
  -H "Content-Type: application/json" \
  -d '{"label_name":"Production","label_color":"#ff0000"}' \
  "https://radar.kubebuddy.io/api/kb-radar/v1/labels"
```

**Response:**

```json
{
  "success": true,
  "label_id": 5
}
```

### PUT /labels/{id}

Update an existing label's name or color.

**Path params:** `id` (label ID)

**Request body:**
```json
{
  "label_name": "Production Env",
  "label_color": "#cc0000"
}
```

**Example:**

```bash
curl -u "username:app_password" \
  -X PUT \
  -H "Content-Type: application/json" \
  -d '{"label_name":"Production Env","label_color":"#cc0000"}' \
  "https://radar.kubebuddy.io/api/kb-radar/v1/labels/5"
```

**Response:**

```json
{
  "success": true
}
```

### DELETE /labels/{id}

Delete a custom label. This removes the label from all subscriptions.

**Path params:** `id` (label ID)

**Example:**

```bash
curl -u "username:app_password" \
  -X DELETE \
  "https://radar.kubebuddy.io/api/kb-radar/v1/labels/5"
```

**Response:**

```json
{
  "success": true
}
```

### POST /subscriptions/{subscription_id}/labels

Attach one or more labels to a subscription.

**Path params:** `subscription_id` (subscription ID)

**Request body:**
```json
{
  "label_ids": [5, 6]
}
```

**Example:**

```bash
curl -u "username:app_password" \
  -H "Content-Type: application/json" \
  -d '{"label_ids":[5,6]}' \
  "https://radar.kubebuddy.io/api/kb-radar/v1/subscriptions/45/labels"
```

**Response:**

```json
{
  "success": true
}
```

### DELETE /subscriptions/{subscription_id}/labels/{label_id}

Remove a specific label from a subscription.

**Path params:** 
- `subscription_id` (subscription ID)
- `label_id` (label ID to remove)

**Example:**

```bash
curl -u "username:app_password" \
  -X DELETE \
  "https://radar.kubebuddy.io/api/kb-radar/v1/subscriptions/45/labels/5"
```

**Response:**

```json
{
  "success": true
}
```

## API key management

- Keys are managed via `GET/POST/DELETE /api-keys` endpoints
- New keys are shown once at creation time - save them securely
- Revoke and recreate keys to rotate credentials
- Key limits by plan: Pro (3 keys), Pro Plus (10 keys)
- Keys are WordPress Application Passwords tied to your user account

## Best practices

### Security
- Always use HTTPS for API requests
- Store API keys securely (environment variables, secrets management)
- Rotate keys regularly (every 90 days recommended)
- Revoke unused keys immediately
- Use dedicated keys for each integration/environment

### Performance
- Implement client-side caching (5-10 minute TTL)
- Use appropriate page sizes (don't fetch all 286 projects at once)
- Filter results at the API level rather than client-side
- Cache static data like project lists

### Error handling
- Implement retry logic with exponential backoff
- Handle rate limits gracefully (wait 60 seconds)
- Log errors with context for debugging
- Validate responses before processing

## Cluster Reports Details (Pro)

### POST /cluster-reports

Upload a KubeBuddy JSON report.

**Required JSON fields:**
- `cluster.name` (or `report.metadata.clusterName`)
- `report` (object, KubeBuddy JSON payload)

**Optional fields:**
- `environment` (default: `prod`)
- `cluster.name`
- `run.started_at`
- `run.finished_at`

```bash
curl -u "username:app_password" \
  -H "Content-Type: application/json" \
  -X POST "https://radar.kubebuddy.io/api/kb-radar/v1/cluster-reports" \
  -d '{
    "environment": "prod",
    "cluster": { "name": "bluegreen-test-uks" },
    "report": {
      "metadata": {
        "clusterName": "bluegreen-test-uks",
        "score": 79.0
      },
      "checks": {}
    }
  }'
```

### GET /cluster-reports

Query params:
- `cluster_name` (optional, defaults to your latest uploaded cluster)
- `environment` (optional)
- `page` (default `1`)
- `per_page` (default `20`, max `100`)

### GET /cluster-reports/{run_id}

Query params:
- `include_report=true` (optional, includes decrypted report payload)

### GET /cluster-reports/compare

Compares two runs and returns:
- `score_delta`
- `new_findings` / `resolved_findings` / `regressed_findings`

Query params:
- `cluster_name` + `environment` (latest-vs-previous mode)
- `to_run_id` (optional explicit target run id)

### GET /cluster-reports/trends

Query params:
- `cluster_name` (optional, defaults to your latest uploaded cluster)
- `environment` (optional)
- `window_days` (default `30`, min `1`, max `365`)

### GET /cluster-reports/{run_id}/freshness

Returns per-artifact statuses:
- `up_to_date`
- `minor_behind`
- `major_behind`
- `unknown`

Each item includes `current_version`, `latest_version`, `confidence`, `reason`, and `recommendation`.

## Cluster Configs Details (Pro)

### GET /cluster-configs

Returns the current user's saved cluster profiles.

### POST /cluster-configs

Creates a new saved cluster profile.

Expected JSON shape:

```json
{
  "name": "Production AKS",
  "cluster_name": "bluegreen-test-uks",
  "provider": "aks",
  "notes": "Main production profile",
  "settings": {
    "aks": {
      "subscriptionId": "00000000-0000-0000-0000-000000000000",
      "resourceGroup": "rg-prod-uks",
      "clusterName": "bluegreen-test-uks"
    },
    "prometheus": {
      "enabled": true,
      "url": "https://example.prometheus.monitor.azure.com",
      "mode": "azure"
    },
    "output": {
      "htmlReport": true,
      "jsonReport": true,
      "excludeNamespaces": true,
      "yes": true
    },
    "excluded_namespaces": ["kube-system"],
    "excluded_checks": ["SEC014"],
    "trusted_registries": ["mcr.microsoft.com/"],
    "radar": {
      "upload": true,
      "compare": true
    }
  }
}
```

### GET /cluster-configs/{config_id}

Returns one decrypted cluster profile for the owner.

### PUT /cluster-configs/{config_id}

Updates the profile and re-encrypts stored settings.

### DELETE /cluster-configs/{config_id}

Deletes the profile.

### GET /cluster-configs/{config_id}/command

Returns:

- `powershell_command`
- `docker_env`
- `yaml_filename`

### GET /cluster-configs/{config_id}/config-file

Returns generated `kubebuddy-config.yaml` content in JSON:

- `filename`
- `content`
- `content_type`

## Errors

Common HTTP status codes and their meanings:

### 400 Bad Request
Invalid request parameters or missing required fields.
```json
{
  "code": "rest_invalid_param",
  "message": "Invalid parameter(s): per_page"
}
```

### 401 Unauthorized
Missing or invalid authentication credentials.
```json
{
  "code": "rest_forbidden",
  "message": "Authentication required."
}
```

### 403 Forbidden
Authenticated but not authorized (plan restriction, permission issue).
```json
{
  "code": "rest_forbidden",
  "message": "API access requires a Pro plan."
}
```

### 404 Not Found
Resource doesn't exist (invalid project ID, endpoint, etc.).
```json
{
  "code": "rest_no_route",
  "message": "No route was found matching the URL"
}
```

### 500 Internal Server Error
Server-side error. If this persists, contact support with the request details.

## Support

Need help with the API?

- **Documentation:** [KubeBuddy Radar Docs](index.md)
- **Support:** Contact us through the website with your account details
- **Community:** Join discussions about integrations and use cases

When reporting issues, include:
- API endpoint and parameters used
- Authentication method (browser/API key)
- Full error response
- Expected vs. actual behavior
