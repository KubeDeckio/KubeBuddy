# Cluster Configs (Pro)

Cluster Configs are private per-user KubeBuddy scan profiles stored in Radar.

Use them to keep:

- cluster identity and provider metadata
- excluded namespaces
- excluded checks
- trusted registries
- Prometheus defaults
- output defaults
- Radar upload/compare defaults

Radar stores the detailed settings encrypted at rest and serves the page/API with `Cache-Control: no-store`.

Cluster grouping is based on cluster identity. The config UI does not expose a separate Radar environment field.

## WordPress page

Create a page at `/cluster-configs/` with:

```text
[radar_cluster_configs]
```

## What the page does

- list saved cluster profiles
- create/edit/delete profiles
- offer starter profiles from existing uploaded cluster reports when no profiles exist yet
- generate the `Invoke-KubeBuddy` command for a selected profile
- generate and download a `kubebuddy-config.yaml`
- create a Radar API key inline for that profile when you want the downloaded YAML to include actual credentials

Radar does not run the scan itself. It only stores the profile and builds the command/config. Execution still happens locally in KubeBuddy CLI or Docker.

Existing WordPress application passwords can be selected by name, but WordPress does not expose their secret again. If you need the downloaded config to include the real password value, create a new key from the Cluster Configs page and save that profile.

## CLI usage

Fetch a saved profile directly in KubeBuddy:

```powershell
Invoke-KubeBuddy `
  -RadarFetchConfig `
  -RadarConfigId "ccfg_12345678-1234-1234-1234-123456789abc"
```

Explicit CLI flags still override fetched config values for that run.

## API endpoints

All endpoints below require authenticated Pro access.

- `GET /cluster-configs`
- `POST /cluster-configs`
- `GET /cluster-configs/{config_id}`
- `PUT /cluster-configs/{config_id}`
- `DELETE /cluster-configs/{config_id}`
- `GET /cluster-configs/{config_id}/command`
- `GET /cluster-configs/{config_id}/config-file`
- `GET /cluster-configs/bootstrap-candidates`
- `POST /cluster-configs/bootstrap-from-reports`

## Security model

- owner-only access
- no page caching
- no REST caching
- encrypted settings at rest
- no kubeconfig or cloud credentials stored in Radar
