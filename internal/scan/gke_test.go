package scan

import (
	"os"
	"path/filepath"
	"testing"
)

func TestRunGKE(t *testing.T) {
	t.Helper()

	result, err := RunGKE(GKEOptions{
		ChecksDir: filepath.Clean(filepath.Join("..", "..", "checks", "gke")),
		InputFile: filepath.Clean(filepath.Join("..", "..", "checks", "gke", "testdata", "failing-cluster.json")),
	})
	if err != nil {
		t.Fatalf("run gke scan: %v", err)
	}

	if len(result.Checks) == 0 {
		t.Fatalf("expected gke checks to execute")
	}

	found := false
	for _, check := range result.Checks {
		if check.ID == "GKESEC001" && check.Total == 1 {
			found = true
		}
	}
	if !found {
		t.Fatalf("expected GKESEC001 finding from failing cluster fixture")
	}
}

func TestRunGKERespectsExcludedChecksFromConfig(t *testing.T) {
	t.Helper()

	dir := t.TempDir()
	configPath := filepath.Join(dir, "kubebuddy-config.yaml")
	if err := os.WriteFile(configPath, []byte("excluded_checks:\n  - GKESEC001\n"), 0o644); err != nil {
		t.Fatalf("write config: %v", err)
	}

	result, err := RunGKE(GKEOptions{
		ChecksDir:  filepath.Clean(filepath.Join("..", "..", "checks", "gke")),
		ConfigPath: configPath,
		InputFile:  filepath.Clean(filepath.Join("..", "..", "checks", "gke", "testdata", "failing-cluster.json")),
	})
	if err != nil {
		t.Fatalf("run gke scan: %v", err)
	}

	for _, check := range result.Checks {
		if check.ID == "GKESEC001" {
			t.Fatalf("expected GKESEC001 to be excluded")
		}
	}
}
