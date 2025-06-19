# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).


## [0.0.23] – 2025-06-18

### Added

* **Automatic dark mode**: The HTML report now respects your browser’s `prefers-color-scheme` setting and will automatically switch to a dark theme when your system is in dark mode.

* **Expanded Storage Checks:** Introduced a comprehensive set of new checks to enhance Kubernetes storage monitoring and optimization:
    * **PV001: Orphaned Persistent Volumes:** Detects Persistent Volumes not bound to any Persistent Volume Claim, helping to reclaim unused storage.
    * **PVC002: PVCs Using Default StorageClass:** Flags PVCs that implicitly rely on a default `storageClassName`, encouraging explicit configuration for better clarity and portability.
    * **PVC003: ReadWriteMany PVCs on Incompatible Storage:** Warns about PVCs requesting `ReadWriteMany` access mode when the underlying storage is typically block-based and doesn't support concurrent writes from multiple nodes, preventing potential data corruption.
    * **PVC004: Unbound Persistent Volume Claims:** Flags PVCs stuck in a `Pending` phase, often indicating issues with the StorageClass, available PVs, or the storage provisioner.
    * **SC001: Deprecated StorageClass Provisioners:** Identifies StorageClasses using deprecated or legacy in-tree provisioners, recommending migration to CSI drivers for future compatibility.
    * **SC002: StorageClass Prevents Volume Expansion:** Detects StorageClasses that do not allow volume expansion, which can limit dynamic scaling of stateful applications.
    * **SC003: High Cluster Storage Usage:** Monitors the overall percentage of used storage across the cluster, alerting when usage exceeds predefined thresholds (80%). _Uses Prometheus_.

* **Expanded Networking Checks:** Added several new checks to identify common misconfigurations and security risks in Kubernetes networking:
    * **NET005: Ingress Host/Path Conflicts:** Detects Ingress resources with overlapping host and path combinations, which can lead to unpredictable traffic routing.
    * **NET006: Ingress Using Wildcard Hosts:** Flags Ingress resources using wildcard hostnames (`*.example.com`), which may provide broader access than intended and should be reviewed.
    * **NET007: Service TargetPort Mismatch:** Identifies Services where the `targetPort` does not match any `containerPort` in the backing pods, preventing effective traffic delivery.
    * **NET008: ExternalName Service to Internal IP:** Highlights `ExternalName` type Services configured to point to private IP ranges, potentially indicating an unusual or misconfigured internal routing pattern.
    * **NET009: Overly Permissive Network Policy:** Warns about NetworkPolicies that define `policyTypes` but lack specific rules (allowing all traffic for that type) or include overly broad `ipBlock` definitions like `0.0.0.0/0`.
    * **NET010: Network Policy Overly Permissive IPBlock:** Specifically identifies NetworkPolicies that utilize `0.0.0.0/0` in their `ipBlock` rules, granting unrestricted access which poses a significant security risk.
    * **NET011: Network Policy Missing PolicyTypes:** Flags NetworkPolicies that do not explicitly define `policyTypes`, improving clarity and ensuring consistent behavior across different Kubernetes versions and CNI plugins.
    * **NET012: Pod HostNetwork Usage:** Identifies pods configured with `hostNetwork: true`, which allows direct access to the node's network interfaces, bypassing Kubernetes network isolation and potentially increasing security risk.

* **Pod Density per Node check (NODE003):**
    * Calculates pod density as `(running pods ÷ max‑pods capacity) × 100`.
    * Alerts when percentage crosses warning (80% default) or critical (90% default) thresholds.

* **Workload Label Consistency Check (WRK009):**

    * Ensures that Deployment selectors match the labels on their Pod templates and that Services targeting those Deployments use consistent label selectors.
    * Helps catch silent routing issues or monitoring mismatches caused by label typos or misalignment.
    * Applies to Deployments and their associated Pods and Services.

## [0.0.22] – 2025-06-04

### Added

* **AI Recommendations with PSAI Integration**
  KubeBuddy now supports AI-powered recommendations, leveraging OpenAI's ChatGPT via the excellent [PSAI module by @dfinke](https://x.com/dfinke):

  * When checks return findings, KubeBuddy automatically prompts GPT to generate:

    * A **short plain-text summary** of recommended actions
    * A **detailed HTML block** with actionable advice and documentation links
  * These recommendations are:

    * Embedded in the **HTML report** as collapsible "Recommended Actions" cards (with `AI Enhanced` labels)
    * Shown in the **text report** with a clear prefix: `AI Generated Recommendation:`
    * Included in the **JSON output** under the `Recommendation` object, with `.text`, `.html`, and `.source` fields (`source = "AI"`)
  * Graceful fallback: if no `OpenAIKey` is set or the AI call fails, checks fall back to static/manual recommendations or omit the section entirely

## [0.0.21] – 2025-05-29

### Fixes

* Fixed an issue where the code would not actually run the checks.

## [0.0.20] – 2025-05-29

### What’s New

* **Prometheus integration**
  We’ve wired KubeBuddy up to Prometheus so you can get real-time node and API-server metrics:

  * **CPU & Memory Usage** (PROM001 & PROM002): track average usage across all nodes over the last 24 hours.
  * **Memory Saturation** (PROM003): see how much of each node’s allocatable memory is actually in use.
  * **API Server Latency** (PROM004): alert you if request latency spikes beyond healthy thresholds.
  * **CPU Overcommitment** (PROM005): flag any nodes whose pods are asking for more CPU than they can deliver.
  * **New per-node Prometheus view**: click into any node’s card to see its individual metrics and time-series charts right in your report.
  * Plus new `KubeData` settings (URL, mode, credentials, headers, etc.) to configure your Prometheus connection securely.

* **Top 5 Impprovements**: The Overview page now surfaces the five checks whose remediation yields the greatest cluster-health score gain, showing estimated points gain per issue.

* **“Hero” Issue-Summary cards**
  Right at the top of your HTML report you’ll now see a row of big, color-coded cards showing how many checks failed at each severity level (Critical, Warning, Info).

  * Click a card and it smoothly expands inline to list every failing check in that category.
  * Built entirely with our new `.hero-metrics`, `.metric-card`, `.expand-content` and `.scrollable-content` CSS, plus a tiny `toggleExpand()` script for the show-and-hide behaviour.

### Improvements

* **HTML report polish**

  * Hover over any check header to see a handy info-icon tooltip with the full description.
  * Long “Findings” and “Recommendations” sections are now tucked into collapsible panels to keep your report neat.
  * Each recommendation is wrapped in a stylish card with a banner and auto-linked “Docs:” reference.
  * All tables live inside a `<div class="table-container">` and are built by hand to ensure proper HTML-escaping and XSS safety.

* **Under-the-hood tweaks for Prometheus checks**

  * All Prometheus parameters (`Url`, `Mode`, `Username`, etc.) are now predeclared so they work correctly inside PowerShell’s parallel runspaces.
  * Threshold lookups in parallel blocks now use `$using:thresholds`.
  * If you haven’t set a Prometheus URL or headers, KubeBuddy will quietly skip those checks (no noisy errors).

### Fixes

* **Null-value errors** eliminated by:

  * Checking that each threshold key actually exists before casting.
  * Verifying your `PrometheusHeaders` hashtable isn’t null or empty before poking its keys or making HTTP calls.


## [0.0.19] - 2025-05-02

### Fixed

* **Check Execution Bug Fixes**:

  * Fixed an issue where certain security checks (e.g., `SEC010`) would not report results even when violations were present. 


## [0.0.18] - 2025-05-02

### Added
- **New AKS Best Practice Checks**:
  - Added `AKSBP013`: "No B-Series VMs in Node Pools" to ensure node pools do not use burstable B-series VMs, which can lead to inconsistent performance in production workloads (Severity: High).
  - Added `AKSBP014`: "Use v5 or Newer SKU VMs for Node Pools" to enforce the use of v5 or newer VM SKUs for better performance and reliability during updates (Severity: Medium).
- Total checks now at **92** across all categories.

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