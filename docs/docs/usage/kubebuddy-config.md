---
title: Configuration File
parent: Usage
nav_order: 2
layout: default
---

# `kubebuddy-config.yaml` Configuration

KubeBuddy powered by KubeDeck supports a config file at:

```
~/.kube/kubebuddy-config.yaml
```

Use this file to customize thresholds, namespaces, trusted registries, and excluded checks.


## Thresholds

Used by node, pod, job, and event health checks. If missing, built-in defaults apply.

```yaml
thresholds:
  cpu_warning: 50
  cpu_critical: 75
  mem_warning: 50
  mem_critical: 75
  restarts_warning: 3
  restarts_critical: 5
  pod_age_warning: 15
  pod_age_critical: 40
  stuck_job_hours: 2
  failed_job_hours: 2
  event_errors_warning: 10
  event_errors_critical: 20
  event_warnings_warning: 50
  event_warnings_critical: 100
```


## Excluded Namespaces

You can exclude system or irrelevant namespaces from checks like pods, secrets, configmaps, and RBAC.

```yaml
excluded_namespaces:
  - kube-system
  - kube-public
  - kube-node-lease
  - local-path-storage
  - coredns
  - calico-system
```

This works with the `-ExcludeSystem` switch.


## Trusted Registries

Controls what container image sources are considered trusted. Images from unlisted sources are flagged.

```yaml
trusted_registries:
  - mcr.microsoft.com/
  - mycompanyregistry.com/
  - ghcr.io/approved-org/
```

### Notes:
- Only prefix matching is used (e.g. `mcr.microsoft.com/` matches all images from that registry).
- If `trusted_registries` is missing, only `mcr.microsoft.com/` is trusted.


## Excluded Checks

Skip specific checks entirely. You can still run these manually from the interactive UI.

```yaml
excluded_checks:
  - SEC014
  - WRK008
```

Each entry must exactly match a check ID.


## Full Example

```yaml
thresholds:
  cpu_warning: 60
  cpu_critical: 85

excluded_namespaces:
  - kube-system
  - local-path-storage

trusted_registries:
  - mcr.microsoft.com/
  - docker.io/mycompany/

excluded_checks:
  - SEC007
  - WRK011
```

Place this file at:
```
~/.kube/kubebuddy-config.yaml
```
