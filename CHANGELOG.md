# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

* **AKS Automatic migration readiness derived from shared checks**
  * Added a derived AKS Automatic migration readiness view to HTML, text, CLI, and JSON outputs when running KubeBuddy with `-Aks`.
  * Added a standalone `*-aks-automatic-action-plan.html` artifact focused on migration work, with a suggested migration sequence, blocker-driven actions, warning-driven actions, and Microsoft Learn links for creating a new AKS Automatic cluster.
  * Added JSON output fields for `metadata.aksAutomaticSummary` and `aksAutomaticReadiness.*`.
  * Added affected-resource resolution back to owning workloads and Helm-managed sources where possible so findings point users to the manifest or chart that actually needs to change.
  * Added skip logic so the readiness view is not generated when the source AKS cluster already uses `sku.name = Automatic`.
  * Added structured affected-resource tables and manifest examples to the standalone action plan.

* **New shared Kubernetes checks used by AKS Automatic readiness**
  * Added `WRK014` for missing memory limits.
  * Added `WRK015` for replicated workloads missing anti-affinity or topology spread constraints.
  * Added AKS Automatic migration relevance to `NET013` for Ingress-to-Gateway API planning.
  * Added `NET018` for duplicate Service selectors.
  * Added `SEC020` for workloads that do not explicitly configure a seccomp profile.

### Changed

* **AKS Automatic readiness now follows observed cluster admission behavior**
  * Updated shared checks and AKS Automatic metadata to reflect observed AKS Automatic behavior rather than treating all AKS best-practice issues as migration blockers.
  * `WRK005` now focuses on missing resource requests, while missing memory limits remain a separate best-practice warning via `WRK014`.
  * `POD007` now detects both `:latest` images and images without an explicit version tag.
  * Added AKS Automatic blocker/warning metadata to relevant shared checks for host namespaces, privileged containers, hostPath, hostPort, seccomp, procMount, AppArmor, Linux capabilities, probes, storage provisioners, and AKS alignment checks.
  * Updated the standalone action plan layout from a compact table to full-width action cards for readability.
  * Split standalone migration actions into blocker and warning sections so only blocker items are treated as mandatory before migration.
  * Added Gateway API migration guidance for clusters still relying on Ingress assumptions.
  * Removed the target-cluster build section from the rendered AKS Automatic reports so the feature stays focused on migration blockers and warnings.

### Docs

* Updated documentation for:
  * AKS Automatic migration readiness under the AKS usage page
  * shared checks reference entries for the new and updated checks
  * changelog notes for the new reports and action-plan artifacts


## [0.0.25] - 2026-03-12

### Added

* **Radar report upload support for storage and comparison**
  * Added support to upload KubeBuddy JSON scan reports to Radar so teams can keep report history over time.
  * Uploaded reports can now be used for comparison workflows and trend tracking across cluster runs.
  * https://radar.kubebuddy.io

* **Radar profile pull support in KubeBuddy CLI**
  * Added `-RadarFetchConfig` and `-RadarConfigId` so KubeBuddy can pull a saved profile before running checks.
  * Added `run.ps1` support for Radar config pull so containerized runs can use the same profile-driven workflow.

* **Improved cluster metadata in JSON output**
  * Added stronger propagation of cluster name, AKS resource group, and subscription metadata into generated JSON report payloads.

### Changed

* **Cluster identity consistency in CLI flows**
  * Updated CLI data flow to prioritize explicit cluster identity fields so scan metadata stays consistent across runs.

* **Namespace exclusion output behavior**
  * Improved how excluded namespaces are represented in JSON output and downstream report-processing flows.

### Fixed

* **AKS cached metadata reuse**
  * Fixed cached AKS metadata behavior to reduce incorrect value carry-over between different cluster runs.

* **Gateway API noise in scan output**
  * Reduced noisy output when Gateway API CRDs are not installed by suppressing unnecessary missing resource-type errors.

## [0.0.24] - 2026-02-26

### Enhanced

* **Comprehensive AKS check improvements and message quality**
  * Improved all AKS best-practice checks with more actionable recommendations (Azure CLI snippets, implementation guidance, and remediation context).
  * Expanded AKS failure messages with clearer risk/impact context (security, availability, performance, and compliance implications).

### Technical Details

* **AKS check files updated**:
  * Private/aks/checks/SecurityChecks.ps1
  * Private/aks/checks/IdentityAndAccessChecks.ps1
  * Private/aks/checks/NetworkingChecks.ps1
  * Private/aks/checks/ResourceManagementChecks.ps1
  * Private/aks/checks/BestPracticesChecks.ps1
  * Private/aks/checks/DisasterRecoveryChecks.ps1
  * Private/aks/checks/MonitoringLoggingChecks.ps1

### Added

* **Radar report upload support for storage and comparison**
  * Added support to upload KubeBuddy JSON scan reports to Radar so teams can keep report history over time.
  * Uploaded reports can now be used for comparison workflows and trend tracking across cluster runs.

* **Radar profile pull support in KubeBuddy CLI**
  * Added `-RadarFetchConfig` and `-RadarConfigId` so KubeBuddy can pull a saved profile before running checks.
  * Added `run.ps1` support for Radar config pull so containerized runs can use the same profile-driven workflow.

* **Improved cluster metadata in JSON output**
  * Added stronger propagation of cluster name, AKS resource group, and subscription metadata into generated JSON report payloads.

### Changed

* **Minimum Prometheus history gate for sizing recommendations**
  * `PROM006` and `PROM007` now require at least **7 days** of Prometheus history before recommendations are emitted.
  * When history is insufficient, reports show explicit informational rows indicating required vs available days.
  * Improved history-span detection to use cluster-level coverage queries, reducing false low `Available Days` values in high pod-churn environments.

* **PROM007 output simplification and UX**
  * Reduced pod sizing findings columns to core current-vs-recommended CPU/memory request/limit values.
  * Removed action/rationale columns from findings table; CPU-limit rationale remains in the recommendation section.
  * Kept multi-profile comparison support and improved profile selector behavior in HTML reports.
  * Updated sizing analysis to a fixed 7-day window for Prometheus reliability, and surfaced the active window in check summaries.
  * Added PROM007 findings filters for `Namespace` and `Profile` in HTML; pagination now respects these filters.
  * Updated PROM007 current request/limit values to read directly from live pod specs, improving reliability when kube-state-metrics resource series are unavailable.
  * Updated all HTML paginations to compact mode with ellipses for large page counts, reducing oversized pager rows.
  * Updated PROM007 to suppress rows where recommendations do not materially differ from current values, and sort remaining rows by highest potential sizing impact first.
  * Optimized Prometheus sizing queries to reduce query-memory pressure (429 responses): added label aggregation for pod sizing and fixed lower-cost 7-day query windows.

* **AKS best-practice output improvements**
  * Added `ObservedValue` to AKS check results and surfaced it in CLI, text, HTML, and JSON outputs.
  * Updated AKS HTML view to group findings by category in collapsible sections for easier remediation workflows.
  * Removed the extra outer "Show Findings" wrapper so category sections are visible immediately.

* **Multi-output report generation**
  * Updated `Invoke-KubeBuddy` to support generating multiple outputs (`-HtmlReport`, `-txtReport`, `-jsonReport`) in a single run using one shared data collection pass.
  * Added YAML check-result caching across output modes to avoid re-running checks when generating HTML + JSON in the same invocation.

* **Networking deprecation handling**
  * Switched data collection/check flow to prefer `EndpointSlice` and avoid always querying deprecated `v1 Endpoints` on modern Kubernetes versions.
  * Retained legacy `Endpoints` fallback only when needed.

* **HTML dark-mode readability fixes**
  * Improved contrast for overview cards and summary surfaces:
    * black text on orange backgrounds
    * black text on blue info/default cards
    * fixed warning progress-bar label contrast
    * fixed low-contrast hover text in passed/failed status box
    * improved Top-5 `+ pts` text visibility
  * fixed compatibility warning banner text contrast on orange backgrounds
  * updated PROM007 filter labels/dropdowns and pagination controls to use on-brand styling with light/dark theme support

* **Namespace exclusion controls**
  * `-ExcludeNamespaces` now correctly honors configured `excluded_namespaces`.
  * Added `-AdditionalExcludedNamespaces` to merge extra runtime namespaces with configured exclusions for a single invocation.

### Fixed

* **Module import parser issue**
  * Fixed truncated syntax in `Private/aks/checks/NetworkingChecks.ps1` that prevented `Import-Module .\KubeBuddy.psm1 -Force`.
* **WRK001 findings table rendering**
  * Removed `Format-Table` from `WRK001` script output so HTML/JSON render proper columns instead of PowerShell formatting metadata fields.
* **Recommendation URL rendering stability**
  * Fixed a null-array indexing error in recommendation docs-link display-name parsing when a URL has an empty/short path.
* **PROM007 memory unit conversion**
  * Fixed decimal memory quantity conversion (`K/M/G/T/P/E`) to MiB for current request/limit display, correcting values like `1500M` from `1.5 Mi` to ~`1430.5 Mi`.
* **AKS cached object reuse error**
  * Fixed duplicate-member error by making AKS `KubeData` note-property assignment idempotent (`Add-Member -Force`) during multi-output runs.
* **Secret reference false positives (`SEC016`)**
  * Updated check logic to ignore optional secret references (`optional: true`) for `secretKeyRef`, `envFrom.secretRef`, and `volume.secret`.
* **Prometheus timeout resiliency**
  * Standardized Prometheus query behavior to use configurable timeout and retry settings across summary metrics, YAML Prometheus checks, and sizing insights (`PROM006`/`PROM007`).
  * Added consistent retry logging so timeout failures are clearer in CLI output.
* **Prometheus sizing history gate accuracy**
  * Updated `PROM006`/`PROM007` history coverage queries to use cluster-level series for day-span detection, avoiding false low `Available Days` values in high pod-churn environments.

### Docs

* Updated docs for:
  * Prometheus integration and sizing guidance (`PROM006` / `PROM007`)
  * new sizing thresholds and profile options in `kubebuddy-config.yaml`
  * checks reference entries for new Prometheus sizing checks


## [0.0.23] – 2025-06-18

### Added

* **Radar report upload support for storage and comparison**
  * Added support to upload KubeBuddy JSON scan reports to Radar so teams can keep report history over time.
  * Uploaded reports can now be used for comparison workflows and trend tracking across cluster runs.

* **Radar profile pull support in KubeBuddy CLI**
  * Added `-RadarFetchConfig` and `-RadarConfigId` so KubeBuddy can pull a saved profile before running checks.
  * Added `run.ps1` support for Radar config pull so containerized runs can use the same profile-driven workflow.

* **Improved cluster metadata in JSON output**
  * Added stronger propagation of cluster name, AKS resource group, and subscription metadata into generated JSON report payloads.

### Changed
- **Updated Recommendations for All Checks**:
  - Added links to relevant documentation in the recommendations for all checks across all categories (Best Practices, Disaster Recovery, Identity & Access, Monitoring & Logging, Networking, Resource Management, and Security), providing actionable guidance for each check.
- **Replaced Cluster Health Score Donut with Passed/Failed Chip**:
  - Removed the circular progress bar (donut) for the Cluster Health Score in the dashboard.
  - Replaced it with a chip-style element for "Passed / Failed Checks" (e.g., "45 / 92 Passed"), aligning with the existing chip design for consistency.
- **Updated Chip Color Logic in Dashboard**:
  - Adjusted the pass rate thresholds for the "Passed / Failed Checks" chip to better reflect cluster health:
    - Red (Critical): <48% pass rate (lowered from 50% to account for near-threshold states).
    - Yellow (Warning): 48%–79% pass rate.
    - Green (Healthy): ≥80% pass rate.
  - With the current pass rate of 48.91% (45/92), the chip now displays as yellow instead of red, aligning with the updated threshold.

### Fixed
- **NET003 Check**:
  - Fixed an issue with the `AKSNET003` ("Web App Routing Enabled") check to ensure it correctly evaluates the configuration and reports accurate results.

### Notes
- **HTML Report Update**:
  - Improved the visual design of the HTML report for better readability and user experience, as part of ongoing enhancements to the reporting interface.

## [0.0.17] - 2025-04-25

### Added
- **Migrated to YAML-based Checks**:
  - Replaced pure PowerShell checks with YAML-defined checks for better maintainability and scalability.
  - Each check now has a unique `ID` for easier identification and referencing in reports (e.g., `AKSNET001`, `NS001`).
- **New Alerts**:
  - Added new YAML-based alerts to enhance cluster monitoring.
- **Custom Checks HTML Tab**  
  Automatically gathers any YAML‑defined checks whose section names aren’t in the standard list (Nodes, Namespaces, Workloads, etc.) into a new “Custom Checks” tab. Only shows the tab if there’s at least one real `<tr>…</tr>` snippet.
- **Exclude Checks Support**  
  You can now explicitly exclude checks by their ID using the `ExcludedChecks` parameter. Excluded checks are skipped during evaluation and omitted from reports.
- **Multi-Architecture Docker Container**:
  - Updated the Dockerfile to support both `linux/amd64` and `linux/arm64` architectures using Docker Buildx.
  - Dynamically downloads architecture-specific `kubectl` and `kubelogin` binaries based on the target platform (`$TARGETARCH`).
- **Updated GitHub Action for Multi-Architecture Builds**:
  - Modified the GitHub Action workflow to use Docker Buildx for building and pushing multi-architecture images (`linux/amd64` and `linux/arm64`) to GHCR.
  - Added support for tagging and pushing a `latest` tag for multi-architecture images.

### Changed
- **Updated HTML Report**:
  - Replaced single-page layout with a tab-based interface for better structure and usability.
  - Improved visuals, section separation, and print/export support.
- **AKS Results in Text Report**:
  - Updated `Generate-K8sTextReport` to properly capture and write AKS results to the text report, including detailed check results and the summary table ("Summary & Rating").
  - Ensured the AKS summary table is consistently included in the text report output.
- **Improved Check Processing**:
  - Refactored `Invoke-AKSBestPractices` to return structured data for text reports, removing direct `Write-ToReport` calls and allowing the caller (`Generate-K8sTextReport`) to handle file writing.

### Fixed
- **Text Report AKS Summary Table**:
  - Fixed an issue where the AKS summary table was not appearing in the text report by ensuring the `TextOutput` property is correctly written to the file.
- **File Path Scoping in `Write-ToReport`**:
  - Updated `Write-ToReport` to accept a file path parameter, ensuring proper scoping and avoiding reliance on a global `$ReportFile` variable.S

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
