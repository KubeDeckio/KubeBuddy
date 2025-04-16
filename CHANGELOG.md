# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.0.16] - 2025-04-16

### Fixed
- **CRD JSON Parsing Error**: Fixed an issue when fetching Custom Resource Definitions (CRDs) where `ConvertFrom-Json` failed due to key casing conflicts (`proxyUrl` vs `proxyURL`). CRDs are now parsed using `-AsHashtable` to avoid this conflict and allow consistent key access.
- **AKS Parameter Logic**: Fixed incorrect AKS metadata fetch behavior. Previously, AKS metadata was fetched even if the `-AKS` switch was not passed. Now the call only runs when `-AKS` is explicitly set.



## [0.0.15] - 2025-04-14

### Added
- **Docker Container Support for KubeBuddy**:
  - Created a **multi-stage Dockerfile** to build the KubeBuddy container image:
    - **Build stage**: Uses `mcr.microsoft.com/powershell:7.5-Ubuntu-22.04` for reliable setup of `kubectl`, `powershell-yaml`, `Azure CLI`, and the `KubeBuddy` module.
    - **Runtime stage**: Uses `mcr.microsoft.com/powershell:7.5-Ubuntu-22.04` to avoid dependency issues and ensure compatibility with the Azure CLI and kubeconfig setups.
  - **Added `adduser` and `coreutils`** to the build stage for file operations and permissions setup.
  - **Added support for passing Azure SPN details and kubeconfig** via environment variables and volume mounts, allowing for a smoother integration with AKS and other Kubernetes clusters.
  - **Support for an optional thresholds YAML file**: The file can be mounted at `/home/kubeuser/.kube/kubebuddy-config.yaml` (equivalent to `$HOME/.kube/kubebuddy-config.yaml` for the container user). This file allows customizing thresholds for alerts (e.g., CPU usage, pod age).
  - **Created the `/app/Reports` directory** during the build process (rather than copying from the host) to ensure a clean, fresh output directory for reports.
  - **Copied KubeBuddy module files** (`KubeBuddy.psm1`, `KubeBuddy.psd1`, `Private`, and `Public`) from the Git repository to `/usr/local/share/powershell/Modules/KubeBuddy/`, preserving module structure.
  - **Ensured reports are accessible** by mounting `/app/Reports` to a local volume for clean report generation.
- **AKS-Specific Checks**:
  - Added a check to see if **Vertical Pod Autoscaler (VPA)** is enabled, as it is now part of Azure Advisor recommendations.
- **Kubernetes checks**
  - Introduced new **RBAC checks**:
    - **Check-RBACMisconfigurations**: Detects missing `roleRef` in `RoleBindings` and `ClusterRoleBindings`.
    - **Check-RBACOverexposure**: Flags ServiceAccounts with excessive permissions like `cluster-admin` or wildcard access, and identifies roles with dangerous verbs (e.g., `create`, `update`, `delete`).
    - **Check-OrphanedRoles**: Flags `RoleBindings`/`ClusterRoleBindings` with no subjects and `Roles`/`ClusterRoles` with no rules.
  - Added **Severity** and **Recommendation** columns to RBAC check outputs to provide actionable insights and prioritize findings.

### Fixed
- **AKS Results**: Fixed URL to be a clickable link in the AKS results.
- **ServiceAccount Detection**: Corrected handling of the `namespace` field in `RoleBinding` and `ClusterRoleBinding` subjects within `Check-RBACMisconfigurations`.
- **Azure CLI Compatibility**: Fixed Azure CLI installation by switching to Ubuntu 22.04, ensuring compatibility with the Azure CLI and its dependencies.
- **Validation Logic in `run.ps1`**:
  - Corrected AKS mode validation to ensure `$ClusterName`, `$ResourceGroup`, and `$SubscriptionId` are only required when AKS mode is enabled.
  - Fixed validation check logic by adding parentheses to group conditions properly.
  - Updated `$Aks` to default to `$false` unless `AKS_MODE` is explicitly set to `"true"`.

## [0.0.14] - 2025-04-10

### Added
- **Added cluster health checks and scoring:**
  - Pod health evaluation based on Running and Ready conditions.
  - Node health assessment using Ready condition status.
  - Resource utilization scoring from `kubectl top nodes` data.
  - Comprehensive health report with total score and detected issues.
- **Added event analysis for cluster health:**
  - Analyzes Kubernetes events to identify critical errors and warnings.
  - Reports significant issues (e.g., pod failures, scheduling issues) in the health summary.
- **Improved cluster validation:**
  - Introduced robust validation for `kubectl` availability and connectivity to the current Kubernetes context.
  - Added AKS connectivity checks using `az aks show`, ensuring the cluster exists and the user is authenticated.
- **Enhanced error handling:**
  - Clearer user feedback on failed or unauthorized cluster access with user-friendly `Write-Host` messages instead of raw exceptions.
  - Fail-fast logic now halts script execution gracefully if core checks fail.
- **New `Get-KubeData` logic:**
  - Now verifies communication with the Kubernetes API server before fetching resources.
  - Graceful fallback if kubectl is present but cluster access is misconfigured.
- **Added support for silent script termination without full exception stack traces using `Write-Host` and `return`.**

### Changed
- Replaced all direct `throw` calls in nested modules with friendly error messages and early exit patterns to improve UX.
- Reorganized cluster validation into a single pre-check block within `Get-KubeData` for clarity and maintainability.

### Fixed
- Fixed inconsistent behavior where failed parallel resource fetches did not always halt script execution as expected.
- Corrected exit behavior from AKS metadata fetch section to avoid crashing on partial failure.
- **Fixed `Check-IngressHealth` function to reliably detect and report ingress issues:**
  - Corrected ingress fetching logic to work consistently with or without pre-fetched `KubeData`.
  - Added checks for missing ingress class, TLS secret validation, duplicate host/path detection, and invalid path types, beyond just service existence.

## [0.0.13] - 2025-04-08

### Added
- **11 new checks** added to the JSON and HTML reports:
  - Resource configuration:  
    - `Check-ResourceQuotas`  
    - `Check-NamespaceLimitRanges`  
    - `Check-MissingResourceLimits`  
    - `Check-HPAStatus`  
    - `Check-PodDisruptionBudgets`  
    - `Check-MissingHealthProbes`
  - Workload health:  
    - `Check-DeploymentIssues`  
    - `Check-StatefulSetIssues`
  - Networking  
    - `Check-IngressHealth`
  - RBAC and identity:  
    - `Check-OrphanedRoles`  
    - `Check-OrphanedServiceAccounts`
- HTML report now includes collapsible recommendations for all checks
- Ingress health check detects references to missing backend services
- New logic in the HTML report to add pagination when needed

### Changed
- `Check-OrphanedRoles` filtering updated to properly exclude namespaces during binding resolution
- JSON report mode now uses `$KubeData` cache to speed up execution by avoiding duplicate `kubectl` calls
- HTML report section order and navigation updated to include new categories and findings

### Fixed
- Fixed logic for HTML checks showing no findings — now prints the ✅ message consistently
- Corrected orphaned role detection to handle exclusion before usage analysis

## [0.0.12] - 2025-03-30

### Added
- Major performance improvement: report generation is now significantly faster due to parallelised kubectl resource fetching in `Get-KubeData`. This applies to **HTML, text, and new JSON reports only**, not interactive checks.
- Added support for `-Json` output across key functions and checks, enabling structured machine-readable exports.
- New `-Yes` parameter added to bypass interactive prompts in non-interactive or CI contexts.
- Improved HTML report with optional hiding of ✅ sections when no issues are found.

### Fixed
- Fixed incorrect exclusion of stuck jobs due to filtering logic.

### Changed
- Error output during resource fetch and report generation is now cleaner and more informative.

## [0.0.11] - 2025-03-28

### Fixed
- Table output now displays correctly when pagination is enabled.

## [0.0.10] - 2025-03-26

### Added
- Added `Check-PodsRunningAsRoot` to identify pods that run with UID 0 or no `runAsUser` set.
- Added `Check-PrivilegedContainers` to detect containers running with `privileged: true`.
- Added `Check-HostPidAndNetwork` to find pods using `hostPID` or `hostNetwork`.
- Added `Check-RBACOverexposure` to flag direct or indirect access to `cluster-admin` privileges, including wildcard permissions via custom roles.
- Added `-ExcludeNamespaces` switch to most checks and report generators.  
  - Automatically uses custom list from `kubebuddy-config.yaml` if present.
  - Falls back to default list of common system namespaces.
- Integrated all the above checks into:
  - The **RBAC & Security** interactive menu
  - The **HTML report** with collapsible sections
  - The floating sidebar navigation (TOC)
- Added contextual tooltips to HTML report headers for better inline explanation of metrics and checks.

### Fixed
- Quitting from sub menus does not **kill** the PowerShell session now.

### Changed
- Updated `Show-RBACMenu` to include the new security checks as menu options.
- Updated HTML report to include additional security findings in the **Security** section.

## [0.0.9] - 2025-03-20

### Added
- Added support for specifying **custom report filenames** with `-OutputPath`, allowing users to save reports with specific names instead of the default timestamped filename.
- Reports now **automatically include timestamps (`YYYYMMDD-HHMMSS`)** when saved in a directory, preventing accidental overwrites.
- The documentation has been updated to reflect these changes.

### Fixed
- Improved cross-platform **path handling** for PowerShell scripts, ensuring compatibility with both Windows and Linux file structures.
- Ensured that **directories are created correctly** when specifying an output path.

## [0.0.8] - 2025-03-20

### Fixed
- Fixed an issue with where we were importing modules twice.

## [0.0.7] - 2025-03-20

### Fixed
- Fixed an issue with folder case to allow linux to import the correct modules.

## [0.0.6] - 2025-03-19

### Fixed
- Fixed issue where `$moduleVersion` was not being correctly updated in the `kubebuddy.ps1` script when setting the version dynamically.
- Corrected the PowerShell script logic to handle version updates reliably using `$tagVersion`.
- Resolved an error where the replace operation in the script failed due to incorrect concatenation of the `$tagVersion` variable.

## [0.0.5] - 2025-03-19

### Added
- AKS best practices check with -aks, -SubscriptionId, -ResourceGroup, and -ClusterName, performing 34 different configuration and security checks tailored for Azure Kubernetes Service.

## [0.0.4] - 2025-03-12

### Added
- Added new logo to html report.

## [0.0.3] - 2025-03-06

### Added
- Initial release of **KubeBuddy**, providing snapshot-based monitoring, resource usage insights, and health checks for Kubernetes clusters.