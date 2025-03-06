---
title: Krew Plugin Usage
parent: Usage
nav_order: 2
layout: default
---

# Krew Plugin Usage

If you're using **KubeBuddy** via Krew as a `kubectl` plugin (Linux/macOS), this guide will help you clean up, manage, and optimize your `kubeconfig` files.

## Available Commands

The following table provides a quick reference for KubeBuddy commands when used as a Krew plugin:

| Action                    | Command Example |
|---------------------------|----------------|
| Remove unreachable clusters | `kubectl KubeBuddy -kubeconfig "$HOME/.kube/config" -exclusionlist "cluster1,cluster2"` |
| Merge kubeconfig files | `kubectl KubeBuddy -mergeconfigs "config1.yaml" "config2.yaml" -destinationconfig "$HOME/.kube/config"` |
| List clusters | `kubectl KubeBuddy -kubeconfig "$HOME/.kube/config" -listclusters` |
| List contexts | `kubectl KubeBuddy -kubeconfig "$HOME/.kube/config" -listcontexts` |
| Export specific contexts | `kubectl KubeBuddy -exportcontexts "context1,context2" -destinationconfig "$HOME/.kube/filtered-config"` |
| Run in dry-run mode | `kubectl KubeBuddy -kubeconfig "$HOME/.kube/config" -dryrun` |
| Enable verbose logging | `kubectl KubeBuddy -kubeconfig "$HOME/.kube/config" -verbose` |

## 1. Backup and Restore

KubeBuddy automatically creates a backup before modifying your kubeconfig file unless `-dryrun` is enabled. If you need to restore the original kubeconfig, locate the backup file:

```bash
$HOME/.kube/config.backup
```

You can also create a manual backup before running KubeBuddy:

```bash
cp "$HOME/.kube/config" "$HOME/.kube/config.backup"
```

## 2. Cleaning Up Unreachable Clusters

If your `kubeconfig` contains outdated or unreachable clusters, KubeBuddy can remove them automatically. The following command will clean up all unreachable clusters while keeping those listed in `-exclusionlist`:

```bash
kubectl KubeBuddy -kubeconfig "$HOME/.kube/config" -exclusionlist "cluster1,cluster2"
```

By default, KubeBuddy will create a backup of your `kubeconfig` before making changes. If you only want to preview the changes, use the `-dryrun` option.

## 3. Handling Current Context

If the cluster associated with your `current-context` is removed during cleanup, KubeBuddy will unset it. If this happens, set a new context manually:

```bash
kubectl config use-context <new-context>
```

To check your current context before running KubeBuddy:

```bash
kubectl config current-context
```

## 4. Merging Multiple Kubeconfig Files

If you manage multiple Kubernetes environments, you may need to merge several kubeconfig files into one. Use the following command to combine them:

```bash
kubectl KubeBuddy -mergeconfigs "config1.yaml" "config2.yaml" -destinationconfig "$HOME/.kube/config"
```

To preview the merge process without making changes:

```bash
kubectl KubeBuddy -mergeconfigs "config1.yaml" "config2.yaml" -destinationconfig "$HOME/.kube/config" -dryrun
```

## 5. Exporting Specific Contexts

You might need to extract specific contexts from a large kubeconfig file to create a smaller, focused configuration. The following command exports only the specified contexts:

```bash
kubectl KubeBuddy -kubeconfig "$HOME/.kube/config" -exportcontexts "context1,context2" -destinationconfig "$HOME/.kube/filtered-config"
```

This is useful when sharing configuration files without exposing unnecessary clusters.

## 6. Using Dry Run Mode

Use the `-dryrun` option to simulate the cleanup process without making changes. This helps you understand what will be removed before running the actual cleanup:

```bash
kubectl KubeBuddy -kubeconfig "$HOME/.kube/config" -exclusionlist "cluster1" -dryrun
```

Dry Run Mode also applies to merging kubeconfig files. Run the following command to preview a merge:

```bash
kubectl KubeBuddy -mergeconfigs "config1.yaml" "config2.yaml" -destinationconfig "$HOME/.kube/config" -dryrun
```

## 7. Listing Clusters

To display all clusters in your kubeconfig without modifying it:

```bash
kubectl KubeBuddy -kubeconfig "$HOME/.kube/config" -listclusters
```

## 8. Listing Contexts

To see all available contexts in your kubeconfig:

```bash
kubectl KubeBuddy -kubeconfig "$HOME/.kube/config" -listcontexts
```

## 9. Enabling Verbose Logging

For detailed logging, use the `-verbose` flag:

```bash
kubectl KubeBuddy -kubeconfig "$HOME/.kube/config" -verbose
```

This provides additional details on each step, such as cluster reachability checks and file modifications.

For more information on logging and output, refer to the [Logging and Output](../logging-output) page.

