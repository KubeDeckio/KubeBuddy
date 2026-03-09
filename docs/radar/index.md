# KubeBuddy Radar Docs

<div class="kb-docs-hero">
  <div class="kb-docs-kicker">Radar Docs</div>
  <p>Use these pages to connect KubeBuddy CLI to KubeBuddy Radar, upload private cluster reports, manage saved scan profiles, and integrate the Radar API into your workflows.</p>
</div>

<div class="kb-docs-link-grid">
  <a class="kb-docs-link-card" href="clients/cli/">
    <strong>CLI Integration</strong>
    <span>Upload JSON reports, compare runs, and pull saved cluster configs directly into KubeBuddy.</span>
  </a>
  <a class="kb-docs-link-card" href="cluster-reports/">
    <strong>Cluster Reports</strong>
    <span>Review scan history, trends, compare output, and the report experience inside Radar.</span>
  </a>
  <a class="kb-docs-link-card" href="cluster-configs/">
    <strong>Cluster Configs</strong>
    <span>Store encrypted scan profiles, generate commands, and download a ready-to-run config file.</span>
  </a>
  <a class="kb-docs-link-card" href="../kubebuddy-radar-cli-integration/">
    <strong>KubeBuddy CLI Usage</strong>
    <span>Jump to the CLI-first guide for PowerShell, Docker examples, and local report generation guidance.</span>
  </a>
</div>

<div class="kb-docs-callout">
  Radar is the control plane for saved configs, history, and private report browsing. KubeBuddy CLI remains the execution plane that runs locally against your cluster.
</div>

Note: All API endpoints require authentication (browser session + nonce or API key).

## Quick links

- [Getting Started](getting-started.md)
- [Cluster Reports (Pro)](cluster-reports.md)
- [Cluster Configs (Pro)](cluster-configs.md)
- [CLI Integration](cli-integration.md)
- [API Reference](api-reference.md)
- [Changelog](../changelog.md)

## Base URL

```
https://radar.kubebuddy.io/api/kb-radar/v1
```
