# KubeBuddy CLI

<div class="kb-docs-hero">
  <div class="kb-docs-kicker">CLI</div>
  <p>KubeBuddy CLI is the main way to run KubeBuddy. Install the native binary with Homebrew or from source, run scans locally or in Docker, and keep the PowerShell wrapper only when you need backwards compatibility.</p>
</div>

<div class="kb-docs-link-grid">
  <a class="kb-docs-link-card" href="install/">
    <strong>Install</strong>
    <span>Choose between Homebrew, native binary builds, and the PowerShell Gallery wrapper.</span>
  </a>
  <a class="kb-docs-link-card" href="getting-started/">
    <strong>Getting Started</strong>
    <span>Go from install to your first scan and report with the shortest path.</span>
  </a>
  <a class="kb-docs-link-card" href="native-cli-usage/">
    <strong>Native CLI</strong>
    <span>Use the native <code>kubebuddy</code> binary for probing, summaries, scans, and full report runs.</span>
  </a>
  <a class="kb-docs-link-card" href="parameters/">
    <strong>Parameters</strong>
    <span>Reference the current CLI flags for <code>run</code>, <code>scan</code>, and AKS workflows.</span>
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

## Start Here

- [Install](install.md)
- [Getting Started](getting-started.md)
- [Parameters](parameters.md)

## What It Does

- Scans Kubernetes and AKS from outside the cluster
- Finds node, pod, workload, network, RBAC, and storage issues
- Supports AKS best-practice checks when you need provider-specific coverage
- Generates HTML, JSON, CSV, and terminal output from the same run
- Pulls Prometheus metrics when available for richer diagnostics

## Choose Your Runtime

### Native CLI

Use the native binary to:

- install with Homebrew on supported macOS and Linux systems
- install from source when building locally
- probe cluster access before a run
- execute the full KubeBuddy engine from a single CLI
- generate HTML, JSON, CSV, or text reports
- run declarative native scans and AKS YAML scans
- reuse the same runtime locally and in Docker

[Native CLI Usage](native-cli-usage.md)

### PowerShell

Use the module to:

- preserve existing `Invoke-KubeBuddy` workflows
- keep PSGallery-based installs working
- use the native runtime behind the same PowerShell command surface

[PowerShell Usage](powershell-usage.md)

### Docker

Use Docker to:

- run scans without installing KubeBuddy directly on the host
- mount kubeconfig for access to any cluster
- generate HTML, JSON, CSV, or TXT output for automation
- run AKS-specific checks with the required credentials

[Docker Usage](docker-usage.md)

## Related Guides

- [Install](install.md)
- [Getting Started](getting-started.md)
- [Native CLI Usage](native-cli-usage.md)
- [Parameters](parameters.md)
- [Prometheus Integration](prometheus-integration.md)
- [Checks](checks.md)
- [AKS Best Practices](aks-best-practice-checks.md)
- [Logging Output](logging-output.md)
- [Kubernetes Permissions](kubernetes-permissions.md)
- [Radar Integration (Pro)](kubebuddy-radar-cli-integration.md)

## AI Recommendations

KubeBuddy can enrich findings with AI-generated guidance when you provide an OpenAI API key.

PowerShell:

```powershell
$env:OpenAIKey = "<your-openai-api-key>"
```

Bash:

```bash
export OpenAIKey="<your-openai-api-key>"
```

AI guidance can appear in:

- HTML reports
- text output
- JSON report recommendation fields
