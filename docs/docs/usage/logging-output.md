---
title: Logging and Output
parent: Usage
nav_order: 3
layout: default
---

# Logging and Output

KubeBuddy provides detailed output and logging for each operation. You can use the `-Verbose` flag to see detailed information about cluster reachability, user and context removal, and more.

## Available Logging Options

| Logging Type   | Command Example | Description |
|---------------|----------------|-------------|
| Verbose Logs | `Invoke-KubeBuddy -Verbose` | Shows detailed action logs, such as cluster checks and cleanup actions. |
| Capture Logs | `Invoke-KubeBuddy -Verbose *>&1 | Tee-Object -FilePath "$HOME/KubeBuddy.log"` | Saves logs for later review. |

## 1. Using Verbose Logging

Use the `-Verbose` flag for detailed logging during the cleanup process:

```powershell
Invoke-KubeBuddy -KubeConfigPath "$HOME\.kube\config" -Verbose
```

### Verbose Output Example

```
VERBOSE: Checking reachability for cluster: aks-prod-cluster at https://example-cluster-url
VERBOSE: Cluster aks-prod-cluster is reachable via HTTPS.
VERBOSE: Removing unreachable cluster: aks-old-cluster
VERBOSE: Removed associated user: aks-old-user
VERBOSE: Backup of kubeconfig created: C:\Users\username\.kube\config.backup
```

## 2. Capturing Logs to a File

For longer operations or troubleshooting, you can capture logs to a file for later analysis:

```powershell
Invoke-KubeBuddy -KubeConfigPath "$HOME\.kube\config" -Verbose *>&1 | Tee-Object -FilePath "$HOME/KubeBuddy.log"
```

This will save all logs, including errors and warnings, to `KubeBuddy.log`.

## 3. Summary Output

After running KubeBuddy, a summary is displayed showing how many clusters were checked, removed, or retained:

```
╔════════════════════════════════════════════════╗
║               KubeBuddy Summary                 ║
╠════════════════════════════════════════════════╣
║  Clusters Checked:    26                       ║
║  Clusters Removed:     2                       ║
║  Clusters Kept:       24                       ║
╚════════════════════════════════════════════════╝
```

## 4. Logging for Merging Kubeconfig Files

When merging multiple kubeconfig files, verbose logging provides insight into the process:

```
VERBOSE: Merging kubeconfig files: config1.yaml, config2.yaml
VERBOSE: Writing merged config to: C:\Users\username\.kube\config
```

This helps track which files are being processed and whether any conflicts occur.

## 5. Common Error Messages

If an error occurs, KubeBuddy provides detailed error messages. Below are some common ones and their solutions:

| Error Message | Meaning | Solution |
|--------------|---------|----------|
| `ERROR: No clusters are reachable. Use '-Force' to proceed.` | No clusters responded to the reachability check. | Add `-Force` to continue with cleanup. |
| `ERROR: KubeConfig file not found at specified path.` | The kubeconfig path provided is incorrect. | Verify the path and ensure the file exists. |
| `ERROR: Failed to load powershell-yaml module.` | The required module is missing. | Run `Install-Module -Name powershell-yaml -Force -Scope CurrentUser`. |

For more information, refer to the [KubeBuddy Usage](../usage) page.

