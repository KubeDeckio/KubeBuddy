package checks

import (
	"path/filepath"
	"testing"
)

func TestLoadFileSupportsCurrentKubernetesChecks(t *testing.T) {
	t.Helper()

	path := filepath.Clean(filepath.Join("..", "..", "Private", "yamlChecks", "stg-checks.yaml"))
	ruleSet, err := LoadFile(path)
	if err != nil {
		t.Fatalf("load check file: %v", err)
	}

	if len(ruleSet.Checks) == 0 {
		t.Fatalf("expected checks from %s", path)
	}

	foundDeclarative := false
	foundScripted := false
	for _, check := range ruleSet.Checks {
		if check.IsDeclarative() {
			foundDeclarative = true
		}
		if check.IsScripted() {
			foundScripted = true
		}
	}

	if !foundDeclarative {
		t.Fatalf("expected at least one declarative check in %s", path)
	}
	if !foundScripted {
		t.Fatalf("expected at least one scripted check in %s", path)
	}
}

func TestLoadDirSummarizesCurrentCheckCatalog(t *testing.T) {
	t.Helper()

	dir := filepath.Clean(filepath.Join("..", "..", "Private", "yamlChecks"))
	ruleSet, err := LoadDir(dir)
	if err != nil {
		t.Fatalf("load check dir: %v", err)
	}

	inv := Summarize(ruleSet)
	if inv.Total == 0 {
		t.Fatalf("expected check inventory")
	}
	if inv.LegacyScripted == 0 {
		t.Fatalf("expected scripted checks in current catalog")
	}
	if inv.Declarative == 0 {
		t.Fatalf("expected declarative checks in current catalog")
	}
	if inv.Prometheus == 0 {
		t.Fatalf("expected prometheus checks in current catalog")
	}
}

func TestLoadFileSupportsModernAKSYAMLChecks(t *testing.T) {
	t.Helper()

	path := filepath.Clean(filepath.Join("..", "..", "checks", "aks", "security.yaml"))
	ruleSet, err := LoadFile(path)
	if err != nil {
		t.Fatalf("load modern aks check file: %v", err)
	}

	if len(ruleSet.Checks) != 8 {
		t.Fatalf("expected 8 checks from %s, got %d", path, len(ruleSet.Checks))
	}

	if ruleSet.Checks[0].ID != "AKSSEC001" {
		t.Fatalf("unexpected first check id: %s", ruleSet.Checks[0].ID)
	}
}
