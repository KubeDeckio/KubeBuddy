# KubeBuddy Headlamp Plugin

Run KubeBuddy Kubernetes checks from inside Headlamp for the active cluster.

Plugin version: 0.2.0
Includes KubeBuddy checks from v0.0.33.

The plugin uses Kubernetes resource data already available to Headlamp and evaluates browser-safe KubeBuddy checks in the current Headlamp page. It shows a summary score, failed checks, recommendations, affected resources, and export options without installing anything into the cluster.

## Screenshot

![KubeBuddy Headlamp plugin scan summary](https://raw.githubusercontent.com/KubeDeckio/KubeBuddy/refs/heads/main/docs/images/headlamp-plugin-scan.png)

## Install

Install from Headlamp Desktop:

1. Open Headlamp Desktop.
2. Go to Plugin Catalog.
3. Search for KubeBuddy.
4. Open the plugin details page and click Install.
5. Restart Headlamp if prompted.
6. Open KubeBuddy from the cluster sidebar.

Install with the Headlamp plugin CLI:

```bash
npx @kinvolk/headlamp-plugin install https://artifacthub.io/packages/headlamp/kubebuddy/kubebuddy-headlamp-plugin
```

Install in-cluster with the Headlamp plugin manager:

```yaml
config:
  watchPlugins: true

pluginsManager:
  enabled: true
  configContent: |
    plugins:
      - name: kubebuddy-headlamp-plugin
        source: https://artifacthub.io/packages/headlamp/kubebuddy/kubebuddy-headlamp-plugin
        version: 0.1.0
    installOptions:
      parallel: true
      maxConcurrent: 2
```

## What It Does

- Runs Kubernetes checks from the KubeBuddy check catalog inside Headlamp.
- Shows a weighted cluster score and severity summary.
- Groups findings by section and check.
- Links affected resources back into Headlamp where possible.
- Supports namespace exclusions before scanning.
- Supports check and severity filtering.
- Exports JSON reports and CSV findings.
- Imports and exports supported `kubebuddy-config.yaml` settings.

## Scope

The plugin currently supports Kubernetes checks that can run safely in the browser with data Headlamp can already read.

Included checks cover areas such as:

- workloads
- pods
- nodes
- jobs
- networking
- storage
- namespaces
- configuration hygiene
- security
- RBAC
- Kubernetes events

Not included in the Headlamp plugin:

- AKS checks that require Azure API access
- GKE checks that require Google Cloud API access
- Prometheus checks
- PowerShell execution
- `kubectl` execution
- the native Go CLI engine

Use the native KubeBuddy CLI when you need the full engine, cloud-provider checks, Prometheus checks, or standalone HTML reports.

## Running A Scan

Open KubeBuddy from the Headlamp cluster sidebar, configure namespace exclusions, and start a scan.

The scan runs in the current Headlamp page. Keep the page open until it completes. If the page is closed, refreshed, or navigated away during a scan, the browser-side scan stops.

After a scan completes:

- the Summary tab shows score, severity counts, namespace exclusions, and top failed checks
- the Findings tab shows grouped finding cards
- finding cards can be expanded to view recommendations and affected resources
- reports can be exported as JSON or CSV

## Configuration

The Config page supports importing and exporting `kubebuddy-config.yaml` for settings that make sense in the browser plugin.

Supported settings include:

- namespace exclusions
- excluded checks
- trusted registries
- allowed load balancer namespaces
- expected pod security profile
- threshold values used by supported checks

Importing YAML updates the structured controls on the page. Changes are not saved until you choose Save Config.

CLI-only settings are preserved where possible during import/export, but they are not executed by the plugin.

## Versioning

The plugin is released with the main KubeBuddy release because it is generated from the same Kubernetes check catalog. The plugin package version can move independently from the KubeBuddy CLI version, but every published plugin package states which KubeBuddy release/checks it includes.

Example:

```text
KubeBuddy release: v0.0.31
Headlamp plugin version: 0.1.0
Includes KubeBuddy checks from v0.0.33
```

## Development

```bash
npm install
npm run start
npm run build
npm run lint
npm run tsc
npm run package
```

Run `npm run start` from this folder while Headlamp is running, then open the KubeBuddy item in the cluster sidebar.

The check metadata and behavior should stay aligned with the Kubernetes catalog under `../checks/kubernetes`.
