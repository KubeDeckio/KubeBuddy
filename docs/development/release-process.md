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

The Headlamp plugin has its own package version, starting at `0.1.0`. Normal KubeBuddy tag releases auto-increment the plugin patch version and attach the plugin package to the main KubeBuddy release. Out-of-band plugin-only releases are published with tags like `headlamp-plugin-v0.5.2`. Artifact Hub metadata should state both the plugin version and the KubeBuddy checks version included in the package.

## Headlamp Plugin Versioning

The Headlamp plugin version is read from `headlamp-plugin/package.json`. KubeBuddy tag releases auto-increment the plugin patch version by default. If you manually dispatch the full release workflow, you can provide `headlamp_plugin_version` as an input.

Use plugin semver like this:

- patch version for plugin fixes or check-catalog-only updates
- minor version for plugin UI/features
- major version later for breaking plugin behavior

The release helper updates `package.json`, `package-lock.json`, the plugin README, and Artifact Hub metadata together:

```bash
node scripts/prepare-headlamp-plugin-release.mjs v0.0.32 --plugin-version=0.1.1
```

For the first Headlamp plugin release:

```bash
node scripts/prepare-headlamp-plugin-release.mjs v0.0.31 --plugin-version=0.1.0
```

When the full GitHub release workflow runs from a tag, it bumps the plugin patch version, packages the plugin, calculates the final tarball checksum, updates `artifacthub-pkg.yml`, and commits that release metadata back to `main`.

## Out-of-Band Headlamp Plugin Release

Use the `Publish Headlamp Plugin` workflow when the Headlamp plugin needs a new version but the native KubeBuddy CLI does not.

Required inputs:

- `kubebuddy_checks_version`: the KubeBuddy checks version included in the plugin, for example `v0.0.37`
- `plugin_version`: the Headlamp plugin version to publish, for example `0.5.3`

The workflow publishes a GitHub release tag named `headlamp-plugin-v<plugin_version>` with only the Headlamp plugin tarball, then commits the updated plugin metadata back to `main`.

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
