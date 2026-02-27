---
title: Kubernetes Scan Permissions
parent: Usage
nav_order: 7
layout: default
---

# Kubernetes Scan Permissions

KubeBuddy does **not** require `cluster-admin`, but it does need broad **read-only** access across the cluster.

KubeBuddy reads:
- workload objects (pods, deployments, daemonsets, statefulsets, jobs)
- platform objects (nodes, namespaces, events, services, ingresses, endpointslices)
- storage/network objects (pv, pvc, storageclasses, networkpolicies)
- RBAC objects (roles, rolebindings, clusterroles, clusterrolebindings, serviceaccounts)
- `secrets` (for security checks)
- CRDs and custom resource instances
- `metrics.k8s.io` node metrics (`kubectl top nodes`)

## Recommended: Read-Only ClusterRole

Apply this role and binding for the identity used by KubeBuddy:

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: kubebuddy-reader
rules:
  - apiGroups: [""]
    resources:
      - pods
      - nodes
      - namespaces
      - events
      - jobs
      - services
      - endpoints
      - configmaps
      - secrets
      - persistentvolumes
      - persistentvolumeclaims
      - serviceaccounts
    verbs: ["get", "list", "watch"]
  - apiGroups: ["apps"]
    resources: ["deployments", "daemonsets", "statefulsets", "replicasets"]
    verbs: ["get", "list", "watch"]
  - apiGroups: ["batch"]
    resources: ["jobs", "cronjobs"]
    verbs: ["get", "list", "watch"]
  - apiGroups: ["networking.k8s.io"]
    resources: ["ingresses", "networkpolicies"]
    verbs: ["get", "list", "watch"]
  - apiGroups: ["policy"]
    resources: ["poddisruptionbudgets"]
    verbs: ["get", "list", "watch"]
  - apiGroups: ["autoscaling"]
    resources: ["horizontalpodautoscalers"]
    verbs: ["get", "list", "watch"]
  - apiGroups: ["storage.k8s.io"]
    resources: ["storageclasses"]
    verbs: ["get", "list", "watch"]
  - apiGroups: ["discovery.k8s.io"]
    resources: ["endpointslices"]
    verbs: ["get", "list", "watch"]
  - apiGroups: ["rbac.authorization.k8s.io"]
    resources: ["roles", "rolebindings", "clusterroles", "clusterrolebindings"]
    verbs: ["get", "list", "watch"]
  - apiGroups: ["apiextensions.k8s.io"]
    resources: ["customresourcedefinitions"]
    verbs: ["get", "list", "watch"]
  - apiGroups: ["*"]
    resources: ["*"]
    verbs: ["get", "list", "watch"]
  - apiGroups: ["metrics.k8s.io"]
    resources: ["nodes"]
    verbs: ["get", "list"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: kubebuddy-reader-binding
subjects:
  - kind: ServiceAccount
    name: kubebuddy-sa
    namespace: kube-system
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: kubebuddy-reader
```

Update `subjects` to match the user, group, or service account in your environment.

## Is `cluster-admin` Required?

No. Use `cluster-admin` only as a temporary fallback for troubleshooting permission issues.

## Validate Access

Use these checks before running a scan:

```bash
kubectl auth can-i list secrets --all-namespaces
kubectl auth can-i list clusterroles
kubectl auth can-i list customresourcedefinitions.apiextensions.k8s.io
kubectl auth can-i get nodes.metrics.k8s.io
```

If any required check returns `no`, some scan checks may be skipped or incomplete.
