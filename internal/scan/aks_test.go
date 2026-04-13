package scan

import (
	"os"
	"path/filepath"
	"testing"
)

func TestRunAKS(t *testing.T) {
	t.Helper()

	result, err := RunAKS(AKSOptions{
		ChecksDir: filepath.Clean(filepath.Join("..", "..", "checks", "aks")),
		InputFile: filepath.Clean(filepath.Join("..", "..", "internal", "scan", "testdata", "aks-sample.json")),
	})
	if err != nil {
		t.Fatalf("run aks scan: %v", err)
	}

	if len(result.Checks) == 0 {
		t.Fatalf("expected aks checks to execute")
	}

	found := false
	for _, check := range result.Checks {
		if check.ID == "AKSSEC001" && check.Total == 1 {
			found = true
		}
	}
	if !found {
		t.Fatalf("expected AKSSEC001 finding from sample input")
	}
}

func TestRunAKSRespectsExcludedChecksFromConfig(t *testing.T) {
	t.Helper()

	dir := t.TempDir()
	configPath := filepath.Join(dir, "kubebuddy-config.yaml")
	if err := os.WriteFile(configPath, []byte("excluded_checks:\n  - AKSSEC001\n"), 0o644); err != nil {
		t.Fatalf("write config: %v", err)
	}

	result, err := RunAKS(AKSOptions{
		ChecksDir:  filepath.Clean(filepath.Join("..", "..", "checks", "aks")),
		ConfigPath: configPath,
		InputFile:  filepath.Clean(filepath.Join("..", "..", "internal", "scan", "testdata", "aks-sample.json")),
	})
	if err != nil {
		t.Fatalf("run aks scan: %v", err)
	}

	for _, check := range result.Checks {
		if check.ID == "AKSSEC001" {
			t.Fatalf("expected AKSSEC001 to be excluded")
		}
	}
}
