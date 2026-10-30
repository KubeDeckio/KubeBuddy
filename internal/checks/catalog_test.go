package checks

import "testing"

func TestLoadCatalogLoadsNativeKubernetesCatalog(t *testing.T) {
	t.Helper()

	ruleSet, err := LoadCatalog("../../checks/kubernetes")
	if err != nil {
		t.Fatalf("load catalog: %v", err)
	}

	found := map[string]Check{}
	for _, check := range ruleSet.Checks {
		found[check.ID] = check
	}

	for _, id := range []string{"POD003", "POD004", "POD005", "EVENT001", "EVENT002", "SEC002", "SEC004", "SEC006", "SEC009", "SEC010", "SEC012", "SEC013", "SEC015", "SEC018", "SEC019", "SEC020"} {
		check, ok := found[id]
		if !ok {
			t.Fatalf("expected %s to be present in native catalog", id)
		}
		if !check.IsDeclarative() {
			t.Fatalf("expected %s to be declarative in native catalog", id)
		}
	}
}

func TestExpansionAndAdmissionPolicyCataloguePredicates(t *testing.T) {
	catalogue, err := LoadCatalog("../../checks/kubernetes")
	if err != nil {
		t.Fatal(err)
	}
	definitions := map[string]Check{}
	for _, check := range catalogue.Checks {
		definitions[check.ID] = check
	}
	for _, tt := range []struct {
		id     string
		item   map[string]any
		failed bool
	}{
		{"SC004", map[string]any{"allowVolumeExpansion": true}, false},
		{"SC004", map[string]any{"allowVolumeExpansion": false}, true},
		{"SC004", map[string]any{}, true},
		{"SEC024", map[string]any{"spec": map[string]any{"failurePolicy": "Fail"}}, false},
		{"SEC024", map[string]any{"spec": map[string]any{"failurePolicy": "Ignore"}}, true},
		{"SEC024", map[string]any{"spec": map[string]any{}}, false},
	} {
		got, err := EvaluateItem(definitions[tt.id], tt.item)
		if err != nil || got.Failed != tt.failed {
			t.Fatalf("%s %v: got %+v, %v; want failed=%t", tt.id, tt.item, got, err, tt.failed)
		}
	}
}

func TestLoadCatalogFallsBackToBundledCatalog(t *testing.T) {
	t.Helper()
	t.Chdir(t.TempDir())

	ruleSet, err := LoadCatalog("checks/kubernetes")
	if err != nil {
		t.Fatalf("load bundled catalog: %v", err)
	}

	found := map[string]Check{}
	for _, check := range ruleSet.Checks {
		found[check.ID] = check
	}

	for _, id := range []string{"PVC004", "POD004", "SEC020"} {
		if _, ok := found[id]; !ok {
			t.Fatalf("expected %s to be present in bundled catalog", id)
		}
	}
}

func TestLoadCatalogWithSourceReportsSource(t *testing.T) {
	t.Helper()

	catalog, err := LoadCatalogWithSource("../../checks/kubernetes")
	if err != nil {
		t.Fatalf("load filesystem catalog: %v", err)
	}
	if catalog.Source != CatalogSourceFilesystem {
		t.Fatalf("expected filesystem source, got %q", catalog.Source)
	}

	t.Chdir(t.TempDir())
	catalog, err = LoadCatalogWithSource("checks/kubernetes")
	if err != nil {
		t.Fatalf("load embedded catalog: %v", err)
	}
	if catalog.Source != CatalogSourceEmbedded {
		t.Fatalf("expected embedded source, got %q", catalog.Source)
	}
}
