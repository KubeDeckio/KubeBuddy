---
title: Install
layout: default
---

# Install

Choose one install method:

- Homebrew if you want the simplest native install
- PowerShell Gallery if you want `Invoke-KubeBuddy`
- build from source if you are developing locally

## Recommended: Homebrew

```bash
brew tap KubeDeckio/homebrew-kubebuddy
brew install kubebuddy
kubebuddy version
```

Use this on macOS or Linux when you want the native CLI on `PATH`.

## PowerShell Gallery

```powershell
Install-Module -Name KubeBuddy -Repository PSGallery -Scope CurrentUser
Invoke-KubeBuddy
```

The PSGallery module bundles the native binary for supported platforms. You do not need to install the Go binary separately for normal use.

## Bundled Checks

The native binary includes a built-in copy of the default check catalog. When a `checks/` directory is present next to the binary or in the working tree, KubeBuddy loads those filesystem checks first. If the external files are missing, it falls back to the embedded catalog, which keeps PowerShell Gallery and standalone binary installs working on fresh machines.

You can inspect the active catalog source with:

```bash
kubebuddy checks
```

## Build From Source

```bash
go build -o kubebuddy ./cmd/kubebuddy
./kubebuddy version
```

Use this when working from the repo or testing local changes.

## Requirements

- `kubectl` configured for the cluster you want to scan
- read access to the cluster
- for AKS:
  - Azure auth for local native/PowerShell runs
  - or service principal credentials for containerized runs

## Next Step

Go to [Getting Started](getting-started.md).
