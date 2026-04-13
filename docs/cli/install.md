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
    $env:KUBEBUDDY_BINARY = "/usr/local/bin/kubebuddy"
    Invoke-KubeBuddy
    ```

    The PowerShell module is a wrapper over the native binary. It is for backwards compatibility, not a separate runtime.

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
