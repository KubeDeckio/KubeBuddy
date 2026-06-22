# KubeBuddy Headlamp Plugin

Manual KubeBuddy checks surfaced inside Headlamp for the active Kubernetes cluster.

This plugin is frontend-only. It uses Headlamp's authenticated Kubernetes resource data and evaluates Kubernetes-only KubeBuddy checks in the active browser page. A scan stops if the page is closed or refreshed. It does not run PowerShell, `kubectl`, the Go CLI, AKS checks, GKE checks, or Prometheus checks.

## Current scope

- Manual scan page at `/kubebuddy`
- Last completed cluster score in the Headlamp app bar
- Kubernetes checks based on `checks/kubernetes/*`
- Weighted score using KubeBuddy check weights
- Findings grouped by section with resource links back into Headlamp
- Live scan progress and browser-side scan logs

## Development

```bash
npm install
npm run start
npm run build
npm run lint
npm run tsc
```

Run `npm run start` from this folder while Headlamp is running, then open the KubeBuddy item in the cluster sidebar.

## Notes

The check metadata and behavior should stay aligned with the Kubernetes catalog under `../checks/kubernetes`. If the Go engine later exposes a browser-safe API or WASM evaluator, this plugin can switch from local TypeScript evaluators to the canonical engine without changing the Headlamp page structure.
