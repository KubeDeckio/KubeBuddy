# Release Process

KubeBuddy now ships as a **Go-first release**:

- native `kubebuddy` binaries for macOS and Linux
- native `kubebuddy` binaries for macOS, Linux, and Windows
- a hardened container image
- a backwards-compatible PowerShell Gallery wrapper that bundles and forwards to the native binary
- a Headlamp plugin built from the same Kubernetes check catalog as the release

## Release Outputs

Each tagged release should publish:

- `kubebuddy_<version>_darwin_amd64.tar.gz`
- `kubebuddy_<version>_darwin_arm64.tar.gz`
- `kubebuddy_<version>_linux_amd64.tar.gz`
- `kubebuddy_<version>_linux_arm64.tar.gz`
- `kubebuddy_<version>_windows_amd64.zip`
- `kubebuddy_<version>_windows_arm64.zip`
- `kubebuddy-psgallery-v<version>.tar.gz`
- `kubebuddy-headlamp-plugin-<plugin-version>.tar.gz`
- `checksums.txt`

The PowerShell Gallery package remains a wrapper surface, but it now bundles the native binaries for supported platforms so `Invoke-KubeBuddy` works immediately after install.

The Headlamp plugin has its own package version, starting at `0.1.0`, but it is released with the main KubeBuddy tag because the plugin check catalog is generated from `checks/kubernetes/*`. Artifact Hub metadata should state both the plugin version and the KubeBuddy checks version included in the package.

## Headlamp Plugin Versioning

The Headlamp plugin version is read from `headlamp-plugin/package.json`. It does not auto-increment on every KubeBuddy tag because the plugin follows its own semantic version:

- patch version for plugin fixes or check-catalog-only updates
- minor version for plugin UI/features
- major version later for breaking plugin behavior

Before tagging a KubeBuddy release, bump the plugin version only when the plugin package should publish a new version. The release helper updates `package.json`, `package-lock.json`, the plugin README, and Artifact Hub metadata together:

```bash
node scripts/prepare-headlamp-plugin-release.mjs v0.0.32 --plugin-version=0.1.1
```

For the first Headlamp plugin release:

```bash
node scripts/prepare-headlamp-plugin-release.mjs v0.0.31 --plugin-version=0.1.0
```

When the GitHub release workflow runs, it packages the plugin version from `headlamp-plugin/package.json`, calculates the final tarball checksum, updates `artifacthub-pkg.yml`, and commits that release metadata back to `main`.

If you manually dispatch the release workflow, you can also provide `headlamp_plugin_version` as an input. Tag-based releases should have the desired plugin version committed before the tag is created.

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
   - build and attach the Headlamp plugin package
   - update the Headlamp plugin Artifact Hub metadata

If you trigger the release workflows manually, provide the full tag such as `v0.0.4` in the workflow input.

## Pre-Release Validation

Before tagging, validate:

```bash
go test ./...
docker build -t kubebuddy-release-smoke .
cd headlamp-plugin
npm ci
npm exec tsc -- --noEmit
npm run build
npm run package
```

Recommended smoke tests:

- native binary:

  ```bash
  ./kubebuddy version
  ./kubebuddy run --html-report --yes --output-path ./reports
  ```

- PowerShell wrapper:

  ```powershell
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

It no longer depends on the PowerShell runtime.

For AKS and Azure-authenticated Prometheus in containers, prefer service principal credentials:

- `AZURE_CLIENT_ID`
- `AZURE_CLIENT_SECRET`
- `AZURE_TENANT_ID`

## PowerShell Gallery Notes

`Invoke-KubeBuddy` is still the public command, but it now wraps the native CLI.

Recommended PowerShell usage:

```powershell
Install-Module KubeBuddy -Scope CurrentUser
Invoke-KubeBuddy -HtmlReport -yes
```

Use `KUBEBUDDY_BINARY` only if you need to override the bundled binary with a specific path.
