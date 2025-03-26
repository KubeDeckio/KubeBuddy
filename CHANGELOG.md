# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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