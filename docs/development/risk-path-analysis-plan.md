# Risk Paths Plan

This document is the working reference for adding k8scan-style attack-path analysis to KubeBuddy and the Headlamp plugin.

## Current Baseline

The first missing-check batch adds raw findings that strengthen later attack-path analysis:

- `SEC031` Secret Material Pattern Detected
- `SEC032` TLS Secret Certificate Expiry
- `SEC033` Sensitive Data in ConfigMap
- `SEC034` End-of-Life Base Image
- `SEC035` Image Not Pinned to Digest
- `SEC036` Docker-in-Docker Container Detected
- `NET021` Cloud Metadata API Egress Exposure
- `NET022` Endpoint Points to Cloud Metadata IP
- `RBAC007` Anonymous or Broad Authenticated Subject Binding
- `RBAC008` Cross-Namespace ServiceAccount Binding
- `RBAC009` Default ServiceAccount with Dangerous Permissions
- `RBAC010` Sensitive ServiceAccount Bound to Workload
- `WRK017` Single Replica Workload
- `WRK018` Recreate Deployment Strategy
- `WRK019` Deployment Revision History Disabled
- `WRK020` Workload DNS and Host Alias Overrides
- `WRK021` Missing Workload PriorityClass
- `POD011` Shared Process Namespace Enabled
- `POD012` Zero Termination Grace Period
- `POD013` Bidirectional Mount Propagation

Control-plane static pod checks and kubelet config checks are intentionally deferred until KubeBuddy can confirm collection coverage across managed clusters and local clusters without producing noisy false positives.

## Risk Path Feature

Add a second analysis layer over normal findings. It should not replace checks; it should correlate findings into risk area failures.

Use `RISK###` as the public report/export ID prefix for direct risk paths. This keeps the feature aligned with KubeBuddy's existing short check families such as `SEC`, `RBAC`, `NET`, and `WRK`, while making it clear that risk paths are a separate analysis layer.

Initial risk areas:

| ID | Name | Risk area | Main signal sources |
| --- | --- | --- | --- |
| RISK001 | Container Isolation Risk | Workload boundary | `SEC002`, `SEC004`, `SEC010`, `SEC012`, `SEC017`, `SEC021`, `SEC023`, `SEC029`, `POD011`, `POD013` |
| RISK002 | Namespace Isolation Risk | Identity boundary | `RBAC002`, `RBAC007`, `RBAC008`, `RBAC010`, `NET004`, `NET021` |
| RISK003 | RBAC Privilege Risk | Identity boundary | `RBAC002`, `RBAC005`, `RBAC006`, `RBAC007`, `RBAC009`, `RBAC010` |
| RISK004 | ServiceAccount Trust Risk | Identity boundary | `SEC015`, `SEC018`, `POD008`, `RBAC009`, `RBAC010` |
| RISK005 | Admission Control Risk | Control-plane boundary | `SEC007`, `SEC024`, `SEC025`, `SEC026`, `SEC030` |
| RISK006 | Node Trust Risk | Infrastructure boundary | `SEC010`, `SEC029`, `SEC036`, `POD013` |
| RISK007 | Secret Exposure Risk | Identity boundary | `SEC008`, `SEC022`, `SEC031`, `SEC032`, `SEC033`, `RBAC006`, `RBAC010` |
| RISK008 | Supply Chain and CI/CD Trust Risk | Control-plane boundary | `SEC014`, `SEC028`, `SEC034`, `SEC035`, `SEC036` |
| RISK009 | Multi-Tenant Isolation Risk | Identity boundary | `RBAC008`, `RBAC010`, `NET004`, `NET021` |
| RISK010 | Cloud Identity Bridge Risk | Infrastructure boundary | `NET021`, `NET022`, cloud workload identity findings when added |

Each direct risk path should include status, confidence, exploitability, fix priority, evidence links, validation proof, attack graph JSON, and safe validation commands.


## Risk Path Expansion Backlog

Prioritize new paths only after the current Risk Paths UX has been tested against real cluster exports. Each new path should ship with Go analyzer tests, Headlamp parity, HTML report rendering, JSON output coverage, and validation-proof commands.

### Phase 1 - High Signal Paths

| ID | Name | Why add it | UX notes |
| --- | --- | --- | --- |
| RISK004 | ServiceAccount Trust Risk | Correlates automounted tokens, default service accounts, and sensitive service accounts bound to workloads. | Show the impacted ServiceAccount and workload relationship first. |
| RISK005 | Admission Control Risk | Explains when cluster policy controls may not stop risky manifests. | Validation proof should use dry-run/server-side commands only. |
| RISK007 | Secret Exposure Risk | Connects secret material findings with identities that can read or abuse them. | Never print secret values; show names, types, counts, and RBAC paths only. |
| RISK008 | Supply Chain and CI/CD Trust Risk | Groups mutable images, weak provenance, and Docker-in-Docker style build risk. | Keep remediation focused on pinning, provenance, and build isolation. |

### Phase 2 - Contextual Paths

| ID | Name | Why add it | Dependency |
| --- | --- | --- | --- |
| RISK006 | Node Trust Risk | Highlights runtime socket, hostPath, mount propagation, and node persistence paths. | Needs careful false-positive tuning for platform components. |
| RISK009 | Multi-Tenant Isolation Risk | Combines namespace, RBAC, and network findings for shared clusters. | Needs namespace ownership/context labels if available. |
| RISK010 | Cloud Identity Bridge Risk | Correlates metadata endpoint exposure with cloud identity paths. | Add cloud workload identity checks first. |

### Compound Path Backlog

| ID | Name | Requires | Priority |
| --- | --- | --- | --- |
| CHAIN003 | Container Escape to Cloud Account Takeover | `RISK001`, `RISK010` | High once cloud identity checks exist |
| CHAIN004 | Policy Bypass to Persistent Node Compromise | `RISK005`, `RISK001` | Medium |
| CHAIN005 | Full Cluster Compromise via Triple Risk Path | `RISK001`, `RISK003`, `RISK007` | High after RISK007 |
| CHAIN006 | Namespace Escape via RBAC Wildcard | `RISK002`, `RISK003` | High |
| CHAIN007 | CI/CD Pipeline to Cluster Takeover | `RISK008`, `RISK004` | Medium |
| CHAIN008 | Multi-Tenant Escape via Shared Identity | `RISK009`, `RISK002` | Medium |
| CHAIN009 | Cloud Identity Bridge with RBAC Escalation | `RISK010`, `RISK003` | High once RISK010 exists |
| CHAIN010 | Container Runtime Socket to Node Takeover | `RISK006`, `RISK001` | Medium |

### Acceptance Criteria for Each New Boundary

- Triggered and clear test cases in `internal/scan`.
- JSON fixtures prove `directRiskPaths` or `combinedRiskPaths` include evidence, validation proof, and attack graph nodes.
- Headlamp and HTML report show the same ID, name, verdict, proof commands, evidence links, and attack graph labels.
- Validation proof commands are read-only or server-side dry-run and never expose secret values.
- False-positive notes are documented when platform workloads commonly trigger the signals.
## Combined Risk Path Feature

Initial compound rules:

| ID | Name | Requires |
| --- | --- | --- |
| CHAIN001 | Container Escape to Cluster Admin | `RISK001`, `RISK003` |
| CHAIN002 | ServiceAccount Token to Full Cluster Control | `RISK004`, `RISK003` |
| CHAIN003 | Container Escape to Cloud Account Takeover | `RISK001`, `RISK010` |
| CHAIN004 | Policy Bypass to Persistent Node Compromise | `RISK005`, `RISK001` |
| CHAIN005 | Full Cluster Compromise via Triple Risk Path | `RISK001`, `RISK003`, `RISK007` |
| CHAIN006 | Namespace Escape via RBAC Wildcard | `RISK002`, `RISK003` |
| CHAIN007 | CI/CD Pipeline to Cluster Takeover | `RISK008`, `RISK004` |
| CHAIN008 | Multi-Tenant Escape via Shared Identity | `RISK009`, `RISK002` |
| CHAIN009 | Cloud Identity Bridge with RBAC Escalation | `RISK010`, `RISK003` |
| CHAIN010 | Container Runtime Socket to Node Takeover | `RISK006`, `RISK001` |

## Implementation Steps

1. Add Go models in `internal/scan` for risk areas, proof signals, graph nodes, graph edges, and combined risk paths.
2. Add a deterministic analyzer that accepts completed `CheckResult` values and returns `DirectRiskPathAnalysis`.
3. Add unit tests with synthetic findings for every direct risk path and combined risk path.
4. Extend JSON output first so the contract is stable before UI work.
5. Extend HTML/text reports with a new `Risk Paths` section.
6. Add Headlamp plugin parity using shared generated metadata and TypeScript analyzer functions.
7. Add `Copy Validation Commands` actions in HTML and Headlamp. Commands must be safe/read-only or server-side dry-run by default.
8. Add docs in `docs/checks/index.md` and a user-facing page explaining how to interpret risk areas.

## Safety Rules for Validation Commands

- Do not auto-run proof-of-concept commands.
- Prefer `kubectl auth can-i`, `kubectl get`, `kubectl describe`, and `kubectl apply --dry-run=server`.
- Do not print Secret values. Counting or listing Secret names is acceptable.
- Commands that exec into pods must inspect metadata or file presence only, not exfiltrate credentials.
- Label commands as validation proof, not exploitation steps.

## Verification Target

```powershell
go test ./internal/scan ./internal/checks
npm run generate:checks
npm exec tsc -- --noEmit
npm run build
```
