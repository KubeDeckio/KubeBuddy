---
title: Contributing
parent: Documentation
nav_order: 3
layout: default
hide:
  - navigation
---

# Contributing

KubeBuddy is now maintained as a Go-first project.

The main contribution paths are:

- native runtime code in Go
- YAML check definitions under `checks/`
- docs and release automation
- PowerShell wrapper compatibility where needed

## Development Setup

Required tools:

- Go matching the version in `go.mod`
- `kubectl`
- Docker for container validation

Optional tools:

- PowerShell 7 for wrapper validation
- Azure CLI for local AKS testing
- GitHub CLI for release and registry workflows

## Main Repo Areas

- Native CLI: [cmd/kubebuddy](/Users/pixelrobots/Documents/Git/KubeBuddy/cmd/kubebuddy)
- Runtime packages: [internal](/Users/pixelrobots/Documents/Git/KubeBuddy/internal)
- Kubernetes checks: [checks/kubernetes](/Users/pixelrobots/Documents/Git/KubeBuddy/checks/kubernetes)
- AKS checks: [checks/aks](/Users/pixelrobots/Documents/Git/KubeBuddy/checks/aks)
- PowerShell wrapper: [Public/kubebuddy.ps1](/Users/pixelrobots/Documents/Git/KubeBuddy/Public/kubebuddy.ps1)
- Release scripts: [scripts](/Users/pixelrobots/Documents/Git/KubeBuddy/scripts)

## Basic Validation

Run:

```bash
go test ./...
```

If you changed the wrapper:

```powershell
Invoke-Pester ./Tests/Invoke-KubeBuddy.Tests.ps1
```

If you changed report rendering:

```bash
go run ./cmd/kubebuddy run --html-report --yes --output-path ./reports
```

If you changed the container:

```bash
docker build -t kubebuddy-release-smoke .
```

## Writing Checks

Use the native check model:

- declarative YAML where possible
- Prometheus blocks for metric-driven checks
- native Go handlers for complex logic

Do not add new PowerShell `Script:` checks.

For the current format, see [Creating Checks](creating-Checks.md).

## Pull Requests

Good PRs do these things:

- stay focused
- explain what changed and why
- include validation steps
- update docs when the user-facing behavior changes
- update the changelog when the change is release-relevant

## Release Work

If you touch packaging or distribution, also review:

- [Release Process](releaseprocess.md)
- [Install](cli/install.md)
- [Native CLI Usage](cli/native-cli-usage.md)

## Code of Conduct

Please follow the [Code of Conduct](https://github.com/KubeDeckio/KubeBuddy/blob/main/CODE_OF_CONDUCT.md).
