---
title: Go Migration Spec
hide:
  - navigation
---

# Go Migration Spec

This document defines the migration contract for moving KubeBuddy from its current PowerShell-first implementation to a Go runtime with full feature parity.

## Non-Negotiable Outcomes

- Feature parity is the release bar.
- The final runtime must not depend on PowerShell for normal execution.
- The HTML report must preserve the current theme, content layout, interaction model, and functionality.
- The existing report CSS and JS remain the source of truth during migration.
- Kubernetes and AKS checks should be YAML-defined wherever they are rule-like.
- Documentation is part of the release scope, not follow-up work.

## Scope

The Go runtime must cover all current KubeBuddy capabilities implemented across:

- [Public/kubebuddy.ps1](/Users/pixelrobots/Documents/Git/KubeBuddy/Public/kubebuddy.ps1)
- [Private/get-kubedata.ps1](/Users/pixelrobots/Documents/Git/KubeBuddy/Private/get-kubedata.ps1)
- [Private/yamlChecks-function.ps1](/Users/pixelrobots/Documents/Git/KubeBuddy/Private/yamlChecks-function.ps1)
- [Private/aks/aks-functions.ps1](/Users/pixelrobots/Documents/Git/KubeBuddy/Private/aks/aks-functions.ps1)
- [Private/aks/checks](/Users/pixelrobots/Documents/Git/KubeBuddy/Private/aks/checks)
- [Private/get-prometheusdata.ps1](/Users/pixelrobots/Documents/Git/KubeBuddy/Private/get-prometheusdata.ps1)
- [Private/radar-functions.ps1](/Users/pixelrobots/Documents/Git/KubeBuddy/Private/radar-functions.ps1)
- [Private/radar-artifact-inventory.ps1](/Users/pixelrobots/Documents/Git/KubeBuddy/Private/radar-artifact-inventory.ps1)
- [Private/aks-automatic-readiness.ps1](/Users/pixelrobots/Documents/Git/KubeBuddy/Private/aks-automatic-readiness.ps1)
- [Private/Create-htmlReport.ps1](/Users/pixelrobots/Documents/Git/KubeBuddy/Private/Create-htmlReport.ps1)
- [Private/Create-CsvReport.ps1](/Users/pixelrobots/Documents/Git/KubeBuddy/Private/Create-CsvReport.ps1)
- [Private/create-jsonReport.ps1](/Users/pixelrobots/Documents/Git/KubeBuddy/Private/create-jsonReport.ps1)
- [run.ps1](/Users/pixelrobots/Documents/Git/KubeBuddy/run.ps1)

## Architecture

The Go codebase should converge on this layout:

```text
cmd/kubebuddy
internal/cli
internal/config
internal/model
internal/collector/kubernetes
internal/collector/aks
internal/collector/prometheus
internal/collector/radar
internal/checks
internal/checks/functions
internal/reports
internal/automatic
internal/assets
```

## Check Authoring Direction

Checks should be YAML-defined where possible.

YAML should contain:

- check metadata
- severity and category
- field paths
- operators
- thresholds and expected values
- remediation text
- report display hints
- automatic-readiness metadata

Go should contain:

- data collection
- schema validation
- expression evaluation helpers
- cross-resource correlation
- report rendering
- API integrations

### Rule Types

Supported rule patterns should include:

- equals and not-equals
- contains and not-contains
- numeric comparisons
- exists and missing
- any and all
- count-where
- len
- coalesce
- Prometheus-backed checks

The migration should not support arbitrary embedded PowerShell or general-purpose scripting in check YAML.

## HTML Report Compatibility Contract

The HTML report is a compatibility surface.

Rules:

- Preserve the current CSS from [Private/html/report-styles.css](/Users/pixelrobots/Documents/Git/KubeBuddy/Private/html/report-styles.css).
- Preserve the current JS from [Private/html/report-scripts.js](/Users/pixelrobots/Documents/Git/KubeBuddy/Private/html/report-scripts.js).
- Preserve DOM shape, IDs, classes, section order, tab behavior, and JS hooks.
- Replace PowerShell HTML string construction with Go templating only.
- Treat visual and interaction regressions as release blockers.

Verification:

- DOM snapshot tests
- report fixture tests
- screenshot comparison for representative reports

## Phased Delivery

### Phase 1: Contract and Scaffolding

- establish Go module and package layout
- embed current report assets unchanged
- define migration spec
- define YAML rule schema direction

### Phase 2: Canonical Model and Rule Engine

- define the normalized runtime model
- load and validate YAML checks
- implement deterministic rule evaluation
- add parity fixtures for current checks

### Phase 3: Collectors

- Kubernetes collector
- AKS collector
- Prometheus collector
- Radar collector

### Phase 4: Reports

- JSON renderer
- CSV renderer
- text renderer
- HTML renderer using current CSS and JS

### Phase 5: Automatic Readiness

- port AKS automatic migration readiness logic
- port action-plan generation
- validate output against current fixtures

### Phase 6: Runtime and Delivery

- CLI flags and config file parity
- container entrypoint parity
- release workflow updates
- documentation rewrite

## Release Gates

The migration is complete only when all of these are true:

- current checks execute under the Go engine
- AKS checks reach parity with current pass and fail outcomes on fixtures
- report outputs are equivalent in structure and behavior
- Radar flows work end to end
- Prometheus flows work end to end
- container mode replaces [run.ps1](/Users/pixelrobots/Documents/Git/KubeBuddy/run.ps1)
- docs reflect the Go runtime as the primary product surface

## Risk Areas

- hidden PowerShell behavior in the existing YAML engine
- HTML markup drift that breaks current JS
- AKS auth and context edge cases
- Radar payload compatibility
- automatic-readiness output parity

## Current Status

This branch has started:

- Go module bootstrap
- Cobra CLI bootstrap
- embedded report assets with tests
- YAML check schema scaffolding
- compatibility loader for the current YAML check catalog
- initial AKS YAML conversion catalog for security, identity, monitoring, and networking checks
- migration contract documentation
