# KubeBuddy CLI

<div class="kb-docs-hero">
  <div class="kb-docs-kicker">CLI</div>
  <p>KubeBuddy CLI is the local scanning tool for Kubernetes and AKS. Run the native binary directly, use the same runtime in Docker, or keep the PowerShell path where you still need it.</p>
</div>

<div class="kb-docs-link-grid">
  <a class="kb-docs-link-card" href="native-cli-usage/">
    <strong>Native CLI</strong>
    <span>Use the native <code>kubebuddy</code> binary for probing, summaries, scans, and full report runs.</span>
  </a>
  <a class="kb-docs-link-card" href="powershell-usage/">
    <strong>PowerShell</strong>
    <span>Use the module directly on Windows, macOS, or Linux and run full scans from your terminal.</span>
  </a>
  <a class="kb-docs-link-card" href="docker-usage/">
    <strong>Docker</strong>
    <span>Run KubeBuddy in a container for isolated execution and easy CI or jump-host workflows.</span>
  </a>
  <a class="kb-docs-link-card" href="kubebuddy-config/">
    <strong>Config File</strong>
    <span>Save repeatable scan settings in <code>kubebuddy-config.yaml</code> and keep runs consistent.</span>
  </a>
  <a class="kb-docs-link-card" href="../radar/">
    <strong>KubeBuddy Radar</strong>
    <span>Connect the CLI to Radar when you want release tracking, alerts, and scan history in one place.</span>
  </a>
</div>

## What It Does

- Scans Kubernetes and AKS from outside the cluster
- Finds node, pod, workload, network, RBAC, and storage issues
- Supports AKS best-practice checks when you need provider-specific coverage
- Generates HTML, JSON, CSV, and terminal output from the same run
- Pulls Prometheus metrics when available for richer diagnostics

## Choose Your Runtime

### Native CLI

Use the native binary to:

- probe cluster access before a run
- execute the full KubeBuddy engine from a single CLI
- generate HTML, JSON, CSV, or text reports
- run declarative native scans and AKS YAML scans
- reuse the same runtime locally and in Docker

[Native CLI Usage](native-cli-usage.md)

### PowerShell

Use the module to:

- monitor node health and usage
- detect failing pods, restart loops, and stuck jobs
- review Kubernetes events by severity
- inspect RBAC roles and security config
- generate HTML, JSON, CSV, or text output

[PowerShell Usage](powershell-usage.md)

### Docker

Use Docker to:

- run scans without installing PowerShell locally
- mount kubeconfig for access to any cluster
- generate HTML, JSON, or TXT output for automation
- run AKS-specific checks with the required credentials

[Docker Usage](docker-usage.md)

## Related Guides

- [Native CLI Usage](native-cli-usage.md)
- [Prometheus Integration](prometheus-integration.md)
- [Checks](checks.md)
- [AKS Best Practices](aks-best-practice-checks.md)
- [Logging Output](logging-output.md)
- [Kubernetes Permissions](kubernetes-permissions.md)
- [Radar Integration (Pro)](kubebuddy-radar-cli-integration.md)

## AI Recommendations

KubeBuddy can enrich findings with AI-generated guidance when you provide an OpenAI API key.

Set:

```powershell
$env:OpenAIKey = "<your-openai-api-key>"
```

AI guidance can appear in:

- HTML reports
- text output
- JSON report recommendation fields
