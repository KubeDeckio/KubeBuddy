package checks

import (
	"os"
	"path/filepath"
	"testing"
)

func TestLoadFileSupportsCurrentKubernetesChecks(t *testing.T) {
	t.Helper()

	path := filepath.Clean(filepath.Join("..", "..", "checks", "kubernetes", "network-storage.yaml"))
	ruleSet, err := LoadFile(path)
	if err != nil {
		t.Fatalf("load check file: %v", err)
	}

	if len(ruleSet.Checks) == 0 {
		t.Fatalf("expected checks from %s", path)
	}

	for _, check := range ruleSet.Checks {
		if !check.IsDeclarative() {
			t.Fatalf("expected only declarative checks in %s, found %s", path, check.ID)
		}
	}
}

func TestLoadDirSummarizesCurrentCheckCatalog(t *testing.T) {
	t.Helper()

	dir := filepath.Clean(filepath.Join("..", "..", "checks", "kubernetes"))
	ruleSet, err := LoadDir(dir)
	if err != nil {
		t.Fatalf("load check dir: %v", err)
	}

	inv := Summarize(ruleSet)
	if inv.Total == 0 {
		t.Fatalf("expected check inventory")
	}
	if inv.LegacyScripted != 0 {
		t.Fatalf("expected no scripted checks in current catalog")
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

func TestLoadFileSynthesizesRecommendationVariants(t *testing.T) {
	t.Helper()

	dir := t.TempDir()
	path := filepath.Join(dir, "checks.yaml")
	content := []byte(`checks:
  - id: TEST001
    name: Test Check
    category: Test
    section: Test
    severity: Warning
    fail_message: broken
    recommendation: "Run 'kubectl rollout restart deployment/app'; then verify probes."
    native_handler: test_handler
`)
	if err := os.WriteFile(path, content, 0o600); err != nil {
		t.Fatalf("write temp check file: %v", err)
	}

	ruleSet, err := LoadFile(path)
	if err != nil {
		t.Fatalf("load temp check file: %v", err)
	}
	if len(ruleSet.Checks) != 1 {
		t.Fatalf("expected 1 check, got %d", len(ruleSet.Checks))
	}
	check := ruleSet.Checks[0]
	if check.RecommendationHTML == "" {
		t.Fatalf("expected synthesized recommendation_html")
	}
	if len(check.SpeechBubble) == 0 {
		t.Fatalf("expected synthesized speech bubble")
	}
}
