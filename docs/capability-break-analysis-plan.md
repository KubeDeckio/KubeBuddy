# Capability Break Analysis Plan

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

## Capability Break Feature

Add a second analysis layer over normal findings. It should not replace checks; it should correlate findings into security boundary failures.

Initial capability breaks:

| ID | Name | Boundary | Main signal sources |
| --- | --- | --- | --- |
| CB-001 | Container Isolation Failure | Workload boundary | `SEC002`, `SEC004`, `SEC010`, `SEC012`, `SEC017`, `SEC021`, `SEC023`, `SEC029`, `POD011`, `POD013` |
| CB-002 | Namespace Isolation Failure | Identity boundary | `RBAC002`, `RBAC007`, `RBAC008`, `RBAC010`, `NET004`, `NET021` |
| CB-003 | RBAC Boundary Failure | Identity boundary | `RBAC002`, `RBAC005`, `RBAC006`, `RBAC007`, `RBAC009`, `RBAC010` |
| CB-004 | ServiceAccount Trust Failure | Identity boundary | `SEC015`, `SEC018`, `POD008`, `RBAC009`, `RBAC010` |
| CB-005 | Admission Control Failure | Control-plane boundary | `SEC007`, `SEC024`, `SEC025`, `SEC026`, `SEC030` |
| CB-006 | Node Trust Failure | Infrastructure boundary | `SEC010`, `SEC029`, `SEC036`, `POD013` |
| CB-007 | Secret Exposure Chain Failure | Identity boundary | `SEC008`, `SEC022`, `SEC031`, `SEC032`, `SEC033`, `RBAC006`, `RBAC010` |
| CB-008 | Supply Chain and CI/CD Trust Failure | Control-plane boundary | `SEC014`, `SEC028`, `SEC034`, `SEC035`, `SEC036` |
| CB-009 | Multi-Tenant Isolation Failure | Identity boundary | `RBAC008`, `RBAC010`, `NET004`, `NET021` |
| CB-010 | Cloud Identity Bridge Failure | Infrastructure boundary | `NET021`, `NET022`, cloud workload identity findings when added |

Each capability break should include status, confidence, exploitability, fix priority, evidence links, validation proof, attack graph JSON, and safe validation commands.

## Compound Break Feature

Initial compound rules:

| ID | Name | Requires |
| --- | --- | --- |
| COMPOUND-1 | Container Escape to Cluster Admin | `CB-001`, `CB-003` |
| COMPOUND-2 | ServiceAccount Token to Full Cluster Control | `CB-004`, `CB-003` |
| COMPOUND-3 | Container Escape to Cloud Account Takeover | `CB-001`, `CB-010` |
| COMPOUND-4 | Policy Bypass to Persistent Node Compromise | `CB-005`, `CB-001` |
| COMPOUND-5 | Full Cluster Compromise via Triple Boundary Failure | `CB-001`, `CB-003`, `CB-007` |
| COMPOUND-6 | Namespace Escape via RBAC Wildcard | `CB-002`, `CB-003` |
| COMPOUND-7 | CI/CD Pipeline to Cluster Takeover | `CB-008`, `CB-004` |
| COMPOUND-8 | Multi-Tenant Escape via Shared Identity | `CB-009`, `CB-002` |
| COMPOUND-9 | Cloud Identity Bridge with RBAC Escalation | `CB-010`, `CB-003` |
| COMPOUND-10 | Container Runtime Socket to Node Takeover | `CB-006`, `CB-001` |

## Implementation Steps

1. Add Go models in `internal/scan` for capability breaks, proof signals, graph nodes, graph edges, and compound breaks.
2. Add a deterministic analyzer that accepts completed `CheckResult` values and returns `CapabilityBreakAnalysis`.
3. Add unit tests with synthetic findings for every capability break and compound break.
4. Extend JSON output first so the contract is stable before UI work.
5. Extend HTML/text reports with a new `Attack Paths` or `Capability Breaks` section.
6. Add Headlamp plugin parity using shared generated metadata and TypeScript analyzer functions.
7. Add `Copy Validation Commands` actions in HTML and Headlamp. Commands must be safe/read-only or server-side dry-run by default.
8. Add docs in `docs/cli/checks.md` and a user-facing page explaining how to interpret capability breaks.

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