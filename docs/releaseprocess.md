---
title: Release Process
parent: Documentation
nav_order: 4
layout: default
hide:
  - navigation
---

# Release Process

KubeBuddy now ships as a **Go-first release**:

- native `kubebuddy` binaries for macOS and Linux
- a hardened container image
- a backwards-compatible PowerShell Gallery wrapper that forwards to the native binary

## Release Outputs

Each tagged release should publish:

- `kubebuddy_<version>_darwin_amd64.tar.gz`
- `kubebuddy_<version>_darwin_arm64.tar.gz`
- `kubebuddy_<version>_linux_amd64.tar.gz`
- `kubebuddy_<version>_linux_arm64.tar.gz`
- `kubebuddy-psgallery-v<version>.tar.gz`
- `checksums.txt`

The PowerShell Gallery package remains a wrapper surface. It is not the primary runtime.

## Build Artifacts Locally

From the repo root:

```bash
./scripts/build-release-artifacts.sh v0.0.4
```

That writes release artifacts to `./dist`.

## Release Steps

1. Update `CHANGELOG.md`.
2. Tag the release:

   ```bash
   git tag v0.0.4
   git push origin v0.0.4
   ```

3. GitHub Actions should then:
   - build native release archives
   - publish the GitHub release assets
   - update the Homebrew tap formula
   - publish the PowerShell Gallery wrapper module
   - build and push the container image

If you trigger the release workflows manually, provide the full tag such as `v0.0.4` in the workflow input.

## Pre-Release Validation

Before tagging, validate:

```bash
go test ./...
docker build -t kubebuddy-release-smoke .
```

Recommended smoke tests:

- native binary:

  ```bash
  ./kubebuddy version
  ./kubebuddy run --html-report --yes --output-path ./reports
  ```

- PowerShell wrapper:

  ```powershell
  $env:KUBEBUDDY_BINARY = "/path/to/kubebuddy"
  Import-Module ./KubeBuddy.psm1 -Force
  Invoke-KubeBuddy -HtmlReport -yes -OutputPath ./reports
  ```

- container image:

  ```bash
  docker run --rm \
    -e KUBECONFIG=/app/.kube/config \
    -e HTML_REPORT=true \
    -v $HOME/.kube/config:/tmp/kubeconfig-original:ro \
    -v $PWD/reports:/app/Reports \
    kubebuddy-release-smoke
  ```

## Container Notes

The runtime image is Go-native and hardened. It keeps:

- `kubebuddy`
- `kubectl`
- `kubelogin`

It no longer depends on the PowerShell runtime.

For AKS and Azure-authenticated Prometheus in containers, prefer service principal credentials:

- `AZURE_CLIENT_ID`
- `AZURE_CLIENT_SECRET`
- `AZURE_TENANT_ID`

## PowerShell Gallery Notes

`Invoke-KubeBuddy` is still the public command, but it now wraps the native CLI.

Recommended PowerShell usage:

```powershell
$env:KUBEBUDDY_BINARY = "/usr/local/bin/kubebuddy"
Install-Module KubeBuddy -Scope CurrentUser
Invoke-KubeBuddy -HtmlReport -yes
```

If `KUBEBUDDY_BINARY` is not set, the wrapper looks for `kubebuddy` on `PATH`.
