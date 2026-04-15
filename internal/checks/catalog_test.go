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
