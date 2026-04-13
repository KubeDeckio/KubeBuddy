# Contributing to KubeBuddy

KubeBuddy is now a Go-first project.

The supported contributor workflow is:

- native Go runtime development
- YAML check authoring under `checks/`
- PowerShell wrapper maintenance only where backwards compatibility requires it
- docs and release automation updates alongside code changes

## Getting Started

### Fork and Clone

```bash
git clone https://github.com/<your-username>/KubeBuddy.git
cd KubeBuddy
git remote add upstream https://github.com/KubeDeckio/KubeBuddy.git
```

### Development Requirements

- Go toolchain matching [go.mod](/Users/pixelrobots/Documents/Git/KubeBuddy/go.mod)
- `kubectl` for local cluster testing
- Docker for container testing
- PowerShell 7 only if you are validating the PSGallery wrapper

### Optional Tools

- Azure CLI for local AKS testing
- GitHub CLI for release and registry workflows
- Homebrew if you want to validate the tap locally

## Project Layout

- Native CLI entrypoint: [cmd/kubebuddy](/Users/pixelrobots/Documents/Git/KubeBuddy/cmd/kubebuddy)
- Runtime code: [internal](/Users/pixelrobots/Documents/Git/KubeBuddy/internal)
- Kubernetes checks: [checks/kubernetes](/Users/pixelrobots/Documents/Git/KubeBuddy/checks/kubernetes)
- AKS checks: [checks/aks](/Users/pixelrobots/Documents/Git/KubeBuddy/checks/aks)
- PowerShell wrapper surface: [Public/kubebuddy.ps1](/Users/pixelrobots/Documents/Git/KubeBuddy/Public/kubebuddy.ps1), [KubeBuddy.psm1](/Users/pixelrobots/Documents/Git/KubeBuddy/KubeBuddy.psm1)
- Docs: [docs](/Users/pixelrobots/Documents/Git/KubeBuddy/docs)
- Release scripts: [scripts](/Users/pixelrobots/Documents/Git/KubeBuddy/scripts)

## Branching

Create a branch for each change:

```bash
git checkout -b feature/my-change
```

Use clear names that describe the work.

## What to Test

At a minimum, run:

```bash
go test ./...
```

If you changed the PowerShell wrapper, also run:

```powershell
Invoke-Pester ./Tests/Invoke-KubeBuddy.Tests.ps1
```

If you changed the container or release flow, validate:

```bash
docker build -t kubebuddy-release-smoke .
```

If you changed reports, generate a real report locally:

```bash
go run ./cmd/kubebuddy run --html-report --yes --output-path ./reports
```

## Contributing Checks

Use the current native model:

- add Kubernetes checks under `checks/kubernetes`
- add AKS checks under `checks/aks`
- prefer declarative YAML first
- use native Go handlers only when the logic is too complex for a clean declarative rule

For full guidance, use [docs/creating-Checks.md](/Users/pixelrobots/Documents/Git/KubeBuddy/docs/creating-Checks.md).

## Pull Requests

Before opening a PR:

- keep the scope focused
- update docs if user-facing behavior changed
- update tests when behavior changed
- update the changelog when the change is release-relevant

When you open the PR, include:

- what changed
- how you tested it
- any follow-up work or tradeoffs

## Code Standards

- Keep the Go runtime as the source of truth.
- Do not reintroduce the old PowerShell runtime model.
- Keep PowerShell changes limited to the wrapper or PSGallery packaging unless there is a strong reason otherwise.
- Prefer small, explicit functions and predictable data models.
- Keep checks readable; do not force complex procedural logic into unreadable YAML.

## Release-Oriented Changes

If your change affects packaging or release behavior, check:

- [docs/releaseprocess.md](/Users/pixelrobots/Documents/Git/KubeBuddy/docs/releaseprocess.md)
- [scripts/build-release-artifacts.sh](/Users/pixelrobots/Documents/Git/KubeBuddy/scripts/build-release-artifacts.sh)
- [scripts/render-homebrew-formula.sh](/Users/pixelrobots/Documents/Git/KubeBuddy/scripts/render-homebrew-formula.sh)
- [.github/workflows/publish-release.yml](/Users/pixelrobots/Documents/Git/KubeBuddy/.github/workflows/publish-release.yml)

## Code of Conduct

Please follow [CODE_OF_CONDUCT.md](/Users/pixelrobots/Documents/Git/KubeBuddy/CODE_OF_CONDUCT.md).
