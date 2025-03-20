# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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