---
title: Install
layout: default
---

# Install

KubeBuddy supports three install paths:

- native binary
- Homebrew
- PowerShell Gallery wrapper

The native binary is the primary runtime.

## Choose a Method

=== "Homebrew"

    ```bash
    brew tap KubeDeckio/homebrew-kubebuddy
    brew install kubebuddy
    kubebuddy version
    ```

    Use this when you want the easiest packaged install on macOS or Linux.

=== "Native Binary"

    ```bash
    go build -o kubebuddy ./cmd/kubebuddy
    ./kubebuddy version
    ```

    Use this when you are building from source or testing local changes.

=== "PowerShell Gallery"

    ```powershell
    Install-Module -Name KubeBuddy -Repository PSGallery -Scope CurrentUser
    Invoke-KubeBuddy
    ```

    The PowerShell module ships the native binary for supported platforms. `Invoke-KubeBuddy` should work immediately after install. Use `$env:KUBEBUDDY_BINARY` only if you need to force a different binary.

## Requirements

- `kubectl` configured for the cluster you want to scan
- cluster read access
- for AKS:
  - Azure auth for local runs, or
  - service principal credentials for containerized runs

## After Install

Continue with:

- [Getting Started](getting-started.md)
- [Native CLI Usage](native-cli-usage.md)
- [PowerShell Usage](powershell-usage.md)
