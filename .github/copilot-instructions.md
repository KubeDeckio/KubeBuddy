# KubeBuddy Contributor Instructions

## Kubernetes Check YAML

KubeBuddy Kubernetes checks live under `checks/kubernetes/*.yaml`.

When adding or changing a check:

- Prefer generated expression logic for simple resource checks.
- Use `native_handler` only when the check needs cross-resource joins, thresholds, custom filtering, or logic that cannot be represented by the YAML expression/operator fields.
- Do not add provider-only checks to `checks/kubernetes`; AKS and GKE checks belong in their provider folders.
- Keep recommendations useful in both the CLI report and the Headlamp plugin.

## Headlamp Plugin Compatibility

The Headlamp plugin generates its Kubernetes check catalog from `checks/kubernetes`, excluding `prometheus.yaml`.

After changing Kubernetes YAML checks, run from `headlamp-plugin`:

```bash
npm run generate:checks
npm exec tsc -- --noEmit
npm run build
```

If a YAML check declares `native_handler`, the Headlamp plugin must implement a matching key in `src/index.tsx` inside `nativeHandlers`.

The script `headlamp-plugin/scripts/validate-native-handlers.mjs` fails generation when a YAML `native_handler` is missing from the plugin.

## Complex Check Rule

If a new Kubernetes YAML check needs any of the following, add or update a Headlamp native handler:

- comparing multiple Kubernetes resource kinds
- filtering provider-managed resources
- using scan configuration or thresholds
- deriving findings from status arrays, selectors, labels, RBAC rules, or pod containers
- using data not present on the checked resource itself

Do not rely on the Headlamp plugin to auto-create native handlers. It only generates catalog metadata.
