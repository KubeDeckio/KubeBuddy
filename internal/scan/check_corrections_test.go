package scan

import (
	"encoding/json"
	"path/filepath"
	"strings"
	"testing"

	"github.com/KubeDeckio/KubeBuddy/internal/checks"
)

func correctionDocument(t *testing.T, raw string) map[string]any {
	t.Helper()
	var document map[string]any
	if err := json.Unmarshal([]byte(raw), &document); err != nil {
		t.Fatal(err)
	}
	return document
}

func TestCorrectedAKSCatalogue(t *testing.T) {
	catalogue, err := checks.LoadCatalog(filepath.Join("..", "..", "checks", "aks"))
	if err != nil {
		t.Fatal(err)
	}
	definitions := map[string]checks.Check{}
	for _, check := range catalogue.Checks {
		definitions[check.ID] = check
	}
	for _, tt := range []struct {
		name, id, document string
		failed             bool
	}{
		{"absent dashboard", "AKSSEC007", `{"properties":{}}`, false},
		{"disabled dashboard", "AKSSEC007", `{"properties":{"addonProfiles":{"kubeDashboard":{"enabled":false}}}}`, false},
		{"enabled dashboard", "AKSSEC007", `{"properties":{"addonProfiles":{"kubeDashboard":{"enabled":true}}}}`, true},
		{"three system nodes", "AKSBP011", `{"properties":{"agentPoolProfiles":[{"mode":"System","count":3},{"mode":"User","count":2}]}}`, false},
		{"two system nodes", "AKSBP011", `{"properties":{"agentPoolProfiles":[{"mode":"System","count":2}]}}`, false},
		{"two one-node pools", "AKSBP011", `{"properties":{"agentPoolProfiles":[{"mode":"System","count":1},{"mode":"System","count":1}]}}`, true},
		{"undersized second pool", "AKSBP011", `{"properties":{"agentPoolProfiles":[{"mode":"System","count":3},{"mode":"System","count":1}]}}`, true},
		{"autoscaler minimum is not current count", "AKSBP011", `{"properties":{"agentPoolProfiles":[{"mode":"System","count":1,"minCount":3}]}}`, true},
		{"no system pools", "AKSBP011", `{"properties":{"agentPoolProfiles":[{"mode":"User","count":5}]}}`, true},
		{"tainted system", "AKSBP007", `{"properties":{"agentPoolProfiles":[{"mode":"System","nodeTaints":["CriticalAddonsOnly=true:NoSchedule"]}]}}`, false},
		{"tainted user not system", "AKSBP007", `{"properties":{"agentPoolProfiles":[{"mode":"System"},{"mode":"User","nodeTaints":["CriticalAddonsOnly=true:NoSchedule"]}]}}`, true},
		{"every system pool needs taint", "AKSBP007", `{"properties":{"agentPoolProfiles":[{"mode":"System","nodeTaints":["CriticalAddonsOnly=true:NoSchedule"]},{"mode":"System"}]}}`, true},
		{"settings do not enable autoscaling", "AKSRES001", `{"properties":{"autoScalerProfile":{},"agentPoolProfiles":[{"enableAutoScaling":false}]}}`, true},
		{"pool autoscaling", "AKSRES001", `{"properties":{"agentPoolProfiles":[{"enableAutoScaling":true}]}}`, false},
		{"manual with no autoscaling", "AKSRES005", `{"properties":{"autoScalerProfile":{},"nodeProvisioningProfile":{"mode":"Manual"}}}`, true},
		{"node auto provisioning", "AKSRES005", `{"properties":{"nodeProvisioningProfile":{"mode":"Auto"}}}`, false},
		{"autoscaling alternative", "AKSRES005", `{"properties":{"agentPoolProfiles":[{"enableAutoScaling":true}]}}`, false},
		{"premium SLA", "AKSDR002", `{"sku":{"tier":"Premium"}}`, false},
		{"free no SLA", "AKSDR002", `{"sku":{"tier":"Free"}}`, true},
		{"system managed identity", "AKSIAM004", `{"identity":{"type":"SystemAssigned"}}`, false},
		{"no identity", "AKSIAM004", `{"identity":{"type":"None"}}`, true},
		{"PSA default availability", "AKSSEC008", `{"properties":{"kubernetesVersion":"1.35"}}`, false},
		{"PSA old version", "AKSSEC008", `{"properties":{"kubernetesVersion":"1.22.9"}}`, true},
		{"missing upgrade channel", "AKSBP008", `{"properties":{}}`, true},
		{"missing network policy", "AKSNET002", `{"properties":{}}`, true},
		{"running patch differs", "AKSBP012", `{"properties":{"kubernetesVersion":"1.35","currentKubernetesVersion":"1.35.8","agentPoolProfiles":[{"currentOrchestratorVersion":"1.35.7"}]}}`, true},
		{"requested minor fallback", "AKSBP012", `{"properties":{"currentKubernetesVersion":"1.35.8","agentPoolProfiles":[{"orchestratorVersion":"1.35"}]}}`, false},
		{"v10 VM generation", "AKSBP014", `{"properties":{"agentPoolProfiles":[{"vmSize":"Standard_D4s_v10","count":3}]}}`, false},
	} {
		t.Run(tt.name, func(t *testing.T) {
			check, ok := definitions[tt.id]
			if !ok {
				t.Fatal("missing catalogue check")
			}
			document := correctionDocument(t, tt.document)
			evaluation := checks.Evaluation{}
			if check.Value != nil {
				evaluation, err = checks.EvaluateItem(check, document)
				if err != nil {
					t.Fatal(err)
				}
			}
			got, err := evaluateAKSCheck(check, document, evaluation)
			if err != nil || got.Failed != tt.failed {
				t.Fatalf("got %+v, error %v; want failed=%t", got, err, tt.failed)
			}
		})
	}
}

func TestPSAAvailabilityRequiresVersion(t *testing.T) {
	_, err := evaluateAKSCheck(checks.Check{ID: "AKSSEC008"}, map[string]any{}, checks.Evaluation{})
	if err == nil {
		t.Fatal("missing version must not silently pass")
	}
}

func TestBuiltInNamespaceAndServiceAccountsAreNotOrphans(t *testing.T) {
	for _, name := range []string{"default", "kube-system", "kube-public", "kube-node-lease"} {
		findings, err := runNS001(checks.Check{}, correctionDocument(t, `{"metadata":{"name":"`+name+`"}}`), nil)
		if err != nil || len(findings) != 0 {
			t.Fatalf("built-in namespace %s: %v, %v", name, findings, err)
		}
	}
	findings, err := runRBAC003(checks.Check{}, correctionDocument(t, `{"metadata":{"name":"default","namespace":"app"}}`), nil)
	if err != nil || len(findings) != 0 {
		t.Fatalf("built-in service account: %v, %v", findings, err)
	}
}

func TestApplicationNamespaceAndServiceAccountStillReported(t *testing.T) {
	cache := map[string][]map[string]any{}
	for _, kind := range []string{"pods", "secrets", "persistentvolumeclaims", "services", "configmaps", "deployments", "statefulsets", "daemonsets", "rolebindings", "clusterrolebindings"} {
		cache[kind] = []map[string]any{}
	}
	ns := correctionDocument(t, `{"metadata":{"name":"unused-app"}}`)
	findings, err := runNS001(checks.Check{}, ns, cache)
	if err != nil || len(findings) != 1 {
		t.Fatalf("unused application namespace: %v, %v", findings, err)
	}
	sa := correctionDocument(t, `{"metadata":{"name":"unused-app","namespace":"app"}}`)
	findings, err = runRBAC003(checks.Check{}, sa, cache)
	if err != nil || len(findings) != 1 {
		t.Fatalf("unused application service account: %v, %v", findings, err)
	}
}

func TestOrphanRolesAccountForAggregationAndManagedResources(t *testing.T) {
	cache := map[string][]map[string]any{
		"roles": {}, "rolebindings": {},
		"clusterrolebindings": {
			correctionDocument(t, `{"metadata":{"name":"bootstrap","labels":{"kubernetes.io/bootstrapping":"rbac-defaults"}}}`),
			correctionDocument(t, `{"metadata":{"name":"unused-binding"}}`),
			correctionDocument(t, `{"metadata":{"name":"aggregate-binding"},"roleRef":{"name":"aggregate"},"subjects":[{"kind":"Group","name":"readers"}]}`),
		},
		"clusterroles": {
			correctionDocument(t, `{"metadata":{"name":"aggregate"},"aggregationRule":{"clusterRoleSelectors":[{"matchLabels":{"aggregate":"yes"}}]},"rules":[{"verbs":["get"]}]}`),
			correctionDocument(t, `{"metadata":{"name":"extension","labels":{"aggregate":"yes"}},"rules":[{"verbs":["get"]}]}`),
			correctionDocument(t, `{"metadata":{"name":"aks-service"},"rules":[{"verbs":["get"]}]}`),
			correctionDocument(t, `{"metadata":{"name":"bootstrap","labels":{"kubernetes.io/bootstrapping":"rbac-defaults"}},"rules":[{"verbs":["get"]}]}`),
			correctionDocument(t, `{"metadata":{"name":"unused-role"},"rules":[{"verbs":["get"]}]}`),
		},
	}
	findings, err := orphanedRoles(cache)
	if err != nil || len(findings) != 2 {
		t.Fatalf("got %v, %v; want unused role and binding", findings, err)
	}
	for _, finding := range findings {
		if finding.Resource != "clusterrole/unused-role" && finding.Resource != "clusterrolebinding/unused-binding" {
			t.Fatalf("unexpected finding: %+v", finding)
		}
	}
}

func TestRootUserChecksOnlyRealContainersAndEffectiveSecurityContext(t *testing.T) {
	for _, tt := range []struct {
		spec  string
		count int
	}{
		{`{"containers":[{"name":"web"}]}`, 1},
		{`{"securityContext":{"runAsNonRoot":true},"containers":[{"name":"web"}]}`, 0},
		{`{"securityContext":{"runAsUser":0},"containers":[{"name":"web","securityContext":{"runAsUser":1000}}]}`, 0},
		{`{"securityContext":{"runAsUser":1000},"containers":[{"name":"web","securityContext":{"runAsUser":0}}]}`, 1},
		{`{"securityContext":{"runAsNonRoot":true},"containers":[{"name":"web","securityContext":{"runAsNonRoot":false}}]}`, 1},
		{`{"containers":[{"name":"web","securityContext":{"runAsUser":1000}}],"initContainers":[{"name":"init","securityContext":{"runAsUser":0}}]}`, 1},
		{`{"containers":[],"ephemeralContainers":[{"name":"debug","securityContext":{"runAsUser":0}}]}`, 1},
	} {
		pod := correctionDocument(t, `{"metadata":{"name":"test","namespace":"app"},"spec":`+tt.spec+`}`)
		findings, err := runSEC003(checks.Check{}, pod, nil)
		if err != nil || len(findings) != tt.count {
			t.Fatalf("spec %s: got %v, %v; want %d", tt.spec, findings, err, tt.count)
		}
		for _, finding := range findings {
			if strings.Contains(finding.Message, "Container  ") {
				t.Fatal("missing container generated a finding")
			}
		}
	}
}

func TestPodAuditChecksIncludeInitContainers(t *testing.T) {
	pod := correctionDocument(t, `{"metadata":{"name":"app","namespace":"test"},"spec":{"containers":[{"name":"web","resources":{"limits":{"memory":"128Mi"}},"securityContext":{"runAsNonRoot":true,"readOnlyRootFilesystem":true,"allowPrivilegeEscalation":false,"capabilities":{"drop":["ALL"]}}}],"initContainers":[{"name":"init","securityContext":{"capabilities":{"add":["NET_ADMIN"]}}}]}}`)
	for _, tt := range []struct {
		name    string
		handler nativeHandler
	}{
		{"secure defaults", runSEC006},
		{"capabilities drop", runSEC009},
		{"added capabilities", runSEC012},
		{"resource limits", runPOD014},
	} {
		t.Run(tt.name, func(t *testing.T) {
			findings, err := tt.handler(checks.Check{}, pod, nil)
			if err != nil || len(findings) != 1 || !strings.Contains(findings[0].Message+" "+findings[0].Value, "init") {
				t.Fatalf("expected one finding for init container, got %v, %v", findings, err)
			}
		})
	}
}

func TestPodResourceLimitsCheckHandlesEmptyAndConfiguredLimits(t *testing.T) {
	pod := correctionDocument(t, `{"metadata":{"name":"app","namespace":"test"},"spec":{"containers":[{"name":"missing"},{"name":"empty","resources":{"limits":{}}},{"name":"limited","resources":{"limits":{"memory":"128Mi"}}}],"ephemeralContainers":[{"name":"debug"}]}}`)
	findings, err := runPOD014(checks.Check{}, pod, nil)
	if err != nil || len(findings) != 2 || findings[0].Value != "missing" || findings[1].Value != "empty" {
		t.Fatalf("expected only missing and empty limits, got %v, %v", findings, err)
	}
}

func TestWildcardRolesIncludeUnboundAndExcludeManaged(t *testing.T) {
	cache := map[string][]map[string]any{
		"roles": {
			correctionDocument(t, `{"metadata":{"name":"custom","namespace":"app"},"rules":[{"apiGroups":[""],"verbs":["*"],"resources":["*"]}]}`),
			correctionDocument(t, `{"metadata":{"name":"separate","namespace":"app"},"rules":[{"verbs":["*"],"resources":["pods"]},{"verbs":["get"],"resources":["*"]}]}`),
		},
		"clusterroles": {
			correctionDocument(t, `{"metadata":{"name":"unbound"},"rules":[{"apiGroups":["apps"],"verbs":["*"],"resources":["*"]}]}`),
			correctionDocument(t, `{"metadata":{"name":"cluster-admin"},"rules":[{"verbs":["*"],"resources":["*"]}]}`),
			correctionDocument(t, `{"metadata":{"name":"bootstrap","labels":{"kubernetes.io/bootstrapping":"rbac-defaults"}},"rules":[{"verbs":["*"],"resources":["*"]}]}`),
		},
	}
	findings, err := runRBAC012(checks.Check{}, nil, cache)
	if err != nil || len(findings) != 2 || findings[0].Resource != "role/custom" || findings[1].Resource != "clusterrole/unbound" {
		t.Fatalf("expected custom and unbound wildcard roles, got %v, %v", findings, err)
	}
}

func TestNodePressureReportsUnavailableMetrics(t *testing.T) {
	previous := currentRuntime
	currentRuntime = runtimeContext{}
	t.Cleanup(func() { currentRuntime = previous })
	_, err := runNODE002(checks.Check{}, nil, map[string][]map[string]any{"nodes": {}})
	if err == nil || !strings.Contains(err.Error(), "node metrics unavailable") {
		t.Fatalf("expected explicit node metrics error, got %v", err)
	}
}

func TestNetworkPolicyCoverageIncludesEmptyNamespaces(t *testing.T) {
	previous := currentRuntime
	currentRuntime = runtimeContext{Excluded: map[string]struct{}{"excluded": {}}}
	t.Cleanup(func() { currentRuntime = previous })
	namespaces := []map[string]any{
		correctionDocument(t, `{"kind":"Namespace","metadata":{"name":"empty"}}`),
		correctionDocument(t, `{"kind":"Namespace","metadata":{"name":"active"}}`),
		correctionDocument(t, `{"kind":"Namespace","metadata":{"name":"covered"}}`),
		correctionDocument(t, `{"kind":"Namespace","metadata":{"name":"default"}}`),
		correctionDocument(t, `{"kind":"Namespace","metadata":{"name":"excluded"}}`),
		correctionDocument(t, `{"kind":"Namespace","metadata":{"name":"kube-system"}}`),
		correctionDocument(t, `{"kind":"Namespace","metadata":{"name":"kube-public"}}`),
		correctionDocument(t, `{"kind":"Namespace","metadata":{"name":"kube-node-lease"}}`),
	}
	cache := map[string][]map[string]any{
		"namespaces": filterExcludedItems(namespaces),
		"networkpolicies": {
			correctionDocument(t, `{"metadata":{"name":"deny","namespace":"covered"}}`),
		},
		"pods": {correctionDocument(t, `{"metadata":{"name":"pod","namespace":"active"}}`)},
	}
	findings, err := runNET004(checks.Check{}, nil, cache)
	if err != nil || len(findings) != 3 {
		t.Fatalf("expected empty, active and default namespaces, got %v, %v", findings, err)
	}
	for i, name := range []string{"empty", "active", "default"} {
		if findings[i].Resource != "namespace/"+name {
			t.Fatalf("unexpected finding: %+v", findings[i])
		}
	}
}

func TestNodeTaintExemptionRequiresActualSystemPoolLabel(t *testing.T) {
	for _, mode := range []string{"system", "user", ""} {
		node := correctionDocument(t, `{"metadata":{"name":"node","labels":{"kubernetes.azure.com/mode":"`+mode+`"}},"spec":{"taints":[{"key":"CriticalAddonsOnly","value":"true","effect":"NoSchedule"},{"key":"custom","value":"true","effect":"NoSchedule"}]}}`)
		cache := map[string][]map[string]any{"nodes": {node}, "pods": {}}
		findings, err := runNODE004(checks.Check{}, nil, cache)
		want := 2
		if mode == "system" {
			want = 1
		}
		if err != nil || len(findings) != want {
			t.Fatalf("mode %q: got %v, %v; want %d", mode, findings, err, want)
		}
	}
}

func TestServiceSelectorCanTargetAnotherDeployment(t *testing.T) {
	controller := correctionDocument(t, `{"metadata":{"name":"controller","namespace":"app"},"spec":{"selector":{"matchLabels":{"app":"suite","component":"controller"}},"template":{"metadata":{"labels":{"app":"suite","component":"controller"}}}}}`)
	webhook := correctionDocument(t, `{"metadata":{"name":"webhook","namespace":"app"},"spec":{"template":{"metadata":{"labels":{"app":"suite","component":"webhook"}}}}}`)
	service := correctionDocument(t, `{"metadata":{"name":"webhook","namespace":"app"},"spec":{"selector":{"app":"suite","component":"webhook"}}}`)
	cache := map[string][]map[string]any{"services": {service}, "deployments": {controller, webhook}, "pods": {}}
	findings, err := runWRK009(checks.Check{}, controller, cache)
	if err != nil || len(findings) != 0 {
		t.Fatalf("service targets webhook, not controller: %v, %v", findings, err)
	}
	cache["deployments"] = []map[string]any{controller}
	findings, err = runWRK009(checks.Check{}, controller, cache)
	if err != nil || len(findings) != 1 {
		t.Fatalf("genuine unmatched selector should remain: %v, %v", findings, err)
	}
}
