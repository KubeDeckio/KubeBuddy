# Security Fix Priority — Aareon ADS AKS Dev Cluster

Based on the KubeBuddy scan report dated 2026-06-18. Ordered by **attack chain consequence**, not weighted score. A targeted attacker doesn't need 854 pods — they need one entry point.

---

## Recommended Fix Order (Attack Chain Priority)

The weighted risk scores favour volume — 854 pods × score gives a big number, but a targeted attacker doesn't need 854 pods. They need one entry point. The order below follows the most dangerous attack chains first.

### Fix Today — These Form a Complete External Attack Chain

| Priority | ID | Finding | Why Now | Action |
|----------|----|---------|---------|--------|
| 1 | AKSNET001 | No Authorized IP Ranges | One command. Closes the internet-facing entry point before anything else is touched. | `az aks update --api-server-authorized-ip-ranges <your-ranges>` |
| 2 | AKSSEC007 | Kubernetes Dashboard Active | Active + cluster-admin binding below = full cluster takeover from the browser. Disable first. | `az aks disable-addons --addons kube-dashboard` |
| 3 | RBAC002 | cluster-admin on dashboard-admin-sa and Flux | Completes the chain above. Also removes cluster-admin from `flux-operator` and `flux-applier` — Flux does not need it. | `kubectl delete clusterrolebinding dashboard-adminsa flux-admin-binding flux-applier-binding` |

> **These three items form a single chain: public API → dashboard → cluster-admin → own everything. Break any link and the chain fails.**

---

### Fix This Week — Close the Backdoors

| Priority | ID | Finding | Why |
|----------|----|---------|-----|
| 4 | AKSIAM007 | Local Accounts Enabled | Certificate-based admin backdoor that bypasses AAD, MFA, and audit logs. With a public API server still in transition, this is a credential leak waiting to happen. |
| 5 | AKSIAM005 | No Azure RBAC | Without Azure RBAC, access control is inconsistent and cannot be centrally audited. Required before disabling local accounts. |
| 6 | SEC014 + AKSBP001 | Untrusted Registries + No Image Policy | Flux has cluster-admin and is pulling from uncontrolled registries. That is a supply chain attack directly to full cluster control. Lock down registries before hardening individual pods. |
| 7 | WRK013 + JOB002 | vault-secrets-operator OOMKilled + vault-backup-job Failed | These are **already broken right now**. Secret sync may be silently failing. This is not a future risk — it may already be causing data loss. Increase the operator memory limit and investigate the backup job immediately. |

---

### Fix This Month — Workload Hardening at Scale

| Priority | ID | Finding | Why |
|----------|----|---------|-----|
| 8 | AKSSEC008 | Pod Security Admission Not Configured | Enable PSA at namespace level *first*. Fixing the 854 root pods without this means nothing prevents them coming back after the next deployment. |
| 9 | SEC003 + SEC011 | 854 Pods Running as Root / 407 Containers as UID 0 | Largest volume risk. Address after PSA is enforcing so fixes are durable. |
| 10 | SEC006 + SEC009 | Missing Secure Defaults / No Capabilities Drop | Natural follow-on from root fixes — complete the securityContext hardening pass. |
| 11 | RBAC001 | Orphaned Rancher ClusterRoleBindings | Low effort cleanup — remove bindings referencing `cattle-fleet-system`, `cattle-system`, `cattle-provisioning-capi-system`. Reduces RBAC noise and attack surface. |
| 12 | NET003 + NET007 | Broken Ingress / TargetPort Mismatches | Reliability fixes — services are not routing correctly in several namespaces. |

