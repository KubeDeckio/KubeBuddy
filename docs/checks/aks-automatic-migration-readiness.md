# AKS Automatic Migration Readiness

When you run KubeBuddy with `-Aks`, the AKS report section also derives an **AKS Automatic Migration Readiness** view from existing shared Kubernetes and AKS checks.

This readiness view is designed for **moving workloads to a new AKS Automatic cluster**, not for converting the current cluster in place.

## What it does

- Reuses existing Kubernetes and AKS checks rather than running a separate AKS Automatic engine.
- Marks findings as **blockers** or **warnings** using AKS Automatic relevance metadata on shared checks.
- Resolves affected resources back to the source workload where possible:
  - `Deployment/foo via Pod/foo-...`
  - `StatefulSet/bar via Pod/bar-...`
- Annotates Helm-managed workloads so you can see chart ownership in remediation output.
- Skips the readiness section entirely if the source AKS cluster is already `sku.name = Automatic`.

## Where it appears

- **HTML report**: a collapsed `AKS Automatic Migration Readiness` section inside the existing **AKS Best Practices** tab.
- **Text report / CLI output**: a derived readiness summary with blockers, warnings, and action items.
- **JSON report**:
  - `metadata.aksAutomaticSummary`
  - `aksAutomaticReadiness.summary`
  - `aksAutomaticReadiness.blockers`
  - `aksAutomaticReadiness.warnings`
  - `aksAutomaticReadiness.alignment`
  - `aksAutomaticReadiness.actionPlan`
- **Standalone HTML action plan**: a separate `*-aks-automatic-action-plan.html` artifact when migration actions are present.

## How readiness is classified

- **Blockers** are issues that should be fixed before moving workloads to a new AKS Automatic cluster.
- **Warnings** are issues that do not block migration by themselves, but can cause drift, runtime warnings, or post-cutover cleanup.
- KubeBuddy keeps using the existing shared checks as the source of truth and derives the AKS Automatic view from those results.

## What the action plan contains

- **Suggested Migration Sequence**: an ordered runbook view that starts with blocker remediation, then warning review, then destination-cluster creation and cutover.
- **Fix Before Migration**: blocker-driven actions that should be completed before deploying workloads to a new AKS Automatic cluster.
- **Warnings to Review**: warning-driven actions that do not block migration by themselves but reduce drift and post-cutover rework.
- **Affected resources tables**: per-action resource tables showing namespace, owning workload, observed resource, and Helm source where detected.
- **Manifest examples**: YAML snippets for common remediation patterns such as image tags, requests, probes, spread constraints, Gateway API routes, and `securityContext` changes.
- **Microsoft Learn links** for creating a new AKS Automatic cluster by Azure portal, Azure CLI, Bicep, and Terraform via the official AzAPI `managedClusters` reference.

## Observed AKS Automatic behavior modeled by KubeBuddy

KubeBuddy classifies AKS Automatic readiness using documented behavior plus observed admission behavior from real AKS Automatic cluster tests.

- **Blockers** currently include patterns such as:
  - privileged containers
  - host network / host PID / host IPC
  - host ports
  - hostPath volumes
  - unconfined seccomp
  - non-default `procMount`
  - unsupported AppArmor values
  - missing resource requests
  - `latest` or unpinned image tags
  - added unsupported Linux capabilities
  - replicated workloads missing spread constraints
  - duplicate Service selectors
  - in-tree Azure storage provisioners
- **Warnings** currently include:
  - missing probes
  - missing explicit seccomp profile
  - running as root
  - Ingress usage that should be reviewed for Gateway API migration planning

## Shared checks used for the readiness view

The AKS Automatic readiness view is built on top of shared checks. Relevant additions and updates include:

- `WRK005` – Missing Resource Requests
- `WRK014` – Missing Memory Limits
- `WRK015` – Replicated Workloads Missing Spread Constraints
- `NET013` – Ingress Present Without Gateway API Adoption
- `NET018` – Duplicate Service Selectors
- updated AKS Automatic metadata on image tag, security, storage, probes, and AKS alignment checks

## Ingress and Gateway API

KubeBuddy highlights Ingress usage as part of AKS Automatic migration planning.

- If a cluster still relies on legacy Ingress patterns and has not adopted Gateway API resources, the readiness output emits a migration warning.
- The standalone action plan includes a dedicated ingress migration action with:
  - Gateway API planning steps
  - a `Gateway` / `HTTPRoute` manifest example
  - Microsoft Learn references for AKS application routing with Gateway API

This helps teams plan for modern AKS ingress patterns rather than assuming an NGINX-based ingress controller on the destination cluster.

## Important scope note

This feature answers the question:

> Can these workloads and current usage patterns be moved to a **new AKS Automatic cluster**, and what must be changed first?

It does **not** attempt to fully redesign the destination platform, and it does **not** treat every AKS best-practice issue as an AKS Automatic migration blocker.
