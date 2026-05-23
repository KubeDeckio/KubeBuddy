package scan

import (
	"testing"

	"github.com/KubeDeckio/KubeBuddy/internal/checks"
)

func TestNormalizedKind(t *testing.T) {
	t.Helper()

	if got := normalizedKind("PersistentVolumeClaim"); got != "persistentvolumeclaims" {
		t.Fatalf("unexpected normalized kind: %s", got)
	}
}

func TestClusterScopedKinds(t *testing.T) {
	t.Helper()

	if !isClusterScoped("nodes") {
		t.Fatalf("nodes should be cluster scoped")
	}
	if isClusterScoped("pods") {
		t.Fatalf("pods should be namespaced")
	}
}

func TestFilterExcludedItems(t *testing.T) {
	t.Helper()

	setRuntimeContext(runtimeContext{
		Excluded: excludedNamespaceSet(true, []string{"kube-system", "kube-public", "kube-node-lease"}, []string{"custom-ns"}),
	})
	defer clearRuntimeContext()

	items := []map[string]any{
		{"metadata": map[string]any{"namespace": "kube-system", "name": "a"}},
		{"metadata": map[string]any{"namespace": "custom-ns", "name": "b"}},
		{"metadata": map[string]any{"namespace": "default", "name": "c"}},
		{"metadata": map[string]any{"name": "cluster-role"}},
	}

	filtered := filterExcludedItems(items)
	if len(filtered) != 2 {
		t.Fatalf("expected 2 items after filtering, got %d", len(filtered))
	}
	if namespaceOf(filtered[0]) != "default" {
		t.Fatalf("expected default namespace item to remain")
	}
	if namespaceOf(filtered[1]) != "(cluster)" {
		t.Fatalf("expected cluster-scoped item to remain")
	}
}

func TestExcludedNamespaceSetAdditionalNamespacesEnableFiltering(t *testing.T) {
	t.Helper()

	excluded := excludedNamespaceSet(false, []string{"kube-system"}, []string{"custom-ns"})
	if _, ok := excluded["custom-ns"]; !ok {
		t.Fatalf("expected additional namespace to enable filtering: %#v", excluded)
	}
	if _, ok := excluded["kube-system"]; !ok {
		t.Fatalf("expected configured namespaces to be included with additional namespace: %#v", excluded)
	}
}

func TestFilterExcludedChecks(t *testing.T) {
	t.Helper()

	input := []checks.Check{
		{ID: "SEC014"},
		{ID: "NS001"},
		{ID: "AKSSEC001"},
	}
	filtered := filterExcludedChecks(input, []string{"sec014", "akssec001"})
	if len(filtered) != 1 {
		t.Fatalf("expected 1 check after filtering, got %d", len(filtered))
	}
	if filtered[0].ID != "NS001" {
		t.Fatalf("unexpected remaining check: %s", filtered[0].ID)
	}
}

func TestFilterProviderSpecificChecks(t *testing.T) {
	t.Helper()

	input := []checks.Check{
		{ID: "SC001"},
		{ID: "SC002"},
		{ID: "SC004"},
	}

	generic := filterProviderSpecificChecks(input, Options{})
	if len(generic) != 2 {
		t.Fatalf("expected 2 generic checks after filtering, got %d", len(generic))
	}
	for _, check := range generic {
		if check.ID == "SC002" {
			t.Fatalf("SC002 should be hidden for non-AKS runs")
		}
	}

	aks := filterProviderSpecificChecks(input, Options{AKSMode: true})
	if len(aks) != 3 {
		t.Fatalf("expected AKS runs to retain SC002, got %d checks", len(aks))
	}
}

func TestFilterProviderSpecificChecksHidesPrometheusChecksWhenDisabled(t *testing.T) {
	t.Helper()

	input := []checks.Check{
		{ID: "NS001"},
		{ID: "PROM001"},
		{ID: "PROM006"},
	}

	filtered := filterProviderSpecificChecks(input, Options{})
	if len(filtered) != 1 {
		t.Fatalf("expected only non-prometheus checks to remain, got %d", len(filtered))
	}
	if filtered[0].ID != "NS001" {
		t.Fatalf("unexpected remaining check: %s", filtered[0].ID)
	}

	enabled := filterProviderSpecificChecks(input, Options{IncludePrometheus: true, PrometheusURL: "https://prom.example"})
	if len(enabled) != 3 {
		t.Fatalf("expected prometheus-enabled runs to retain all checks, got %d", len(enabled))
	}
}
