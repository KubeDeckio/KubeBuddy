package scan

import "testing"

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
		Excluded: excludedNamespaceSet(true, []string{"custom-ns"}),
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
