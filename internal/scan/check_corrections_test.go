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
