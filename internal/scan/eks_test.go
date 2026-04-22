package scan

import (
	"os"
	"path/filepath"
	"testing"
)

func TestRunEKS(t *testing.T) {
	t.Helper()

	result, err := RunEKS(EKSOptions{
		ChecksDir: filepath.Clean(filepath.Join("..", "..", "checks", "eks")),
		InputFile: filepath.Clean(filepath.Join("..", "..", "checks", "eks", "testdata", "failing-cluster.json")),
	})
	if err != nil {
		t.Fatalf("run eks scan: %v", err)
	}

	if len(result.Checks) == 0 {
		t.Fatalf("expected eks checks to execute")
	}

	// The failing fixture should produce at least one finding for EKSSEC001
	found := false
	for _, check := range result.Checks {
		if check.ID == "EKSSEC001" && check.Total == 1 {
			found = true
		}
	}
	if !found {
		t.Fatalf("expected EKSSEC001 finding from failing cluster fixture")
	}
}

func TestRunEKSPassingCluster(t *testing.T) {
	t.Helper()

	result, err := RunEKS(EKSOptions{
		ChecksDir: filepath.Clean(filepath.Join("..", "..", "checks", "eks")),
		InputFile: filepath.Clean(filepath.Join("..", "..", "checks", "eks", "testdata", "passing-cluster.json")),
	})
	if err != nil {
		t.Fatalf("run eks scan on passing cluster: %v", err)
	}

	if len(result.Checks) == 0 {
		t.Fatalf("expected eks checks to execute on passing cluster")
	}

	// The passing fixture should have zero total findings
	totalFindings := 0
	for _, check := range result.Checks {
		totalFindings += check.Total
	}
	if totalFindings != 0 {
		for _, check := range result.Checks {
			if check.Total > 0 {
				t.Errorf("expected %s (%s) to pass on passing cluster, got %d findings", check.ID, check.Name, check.Total)
			}
		}
		t.Fatalf("expected zero findings on passing cluster, got %d", totalFindings)
	}
}

func TestRunEKSRespectsExcludedChecksFromConfig(t *testing.T) {
	t.Helper()

	dir := t.TempDir()
	configPath := filepath.Join(dir, "kubebuddy-config.yaml")
	if err := os.WriteFile(configPath, []byte("excluded_checks:\n  - EKSSEC001\n"), 0o644); err != nil {
		t.Fatalf("write config: %v", err)
	}

	result, err := RunEKS(EKSOptions{
		ChecksDir:  filepath.Clean(filepath.Join("..", "..", "checks", "eks")),
		ConfigPath: configPath,
		InputFile:  filepath.Clean(filepath.Join("..", "..", "checks", "eks", "testdata", "failing-cluster.json")),
	})
	if err != nil {
		t.Fatalf("run eks scan: %v", err)
	}

	for _, check := range result.Checks {
		if check.ID == "EKSSEC001" {
			t.Fatalf("expected EKSSEC001 to be excluded")
		}
	}
}

func TestRunEKSAllChecksExecute(t *testing.T) {
	t.Helper()

	result, err := RunEKS(EKSOptions{
		ChecksDir: filepath.Clean(filepath.Join("..", "..", "checks", "eks")),
		InputFile: filepath.Clean(filepath.Join("..", "..", "checks", "eks", "testdata", "failing-cluster.json")),
	})
	if err != nil {
		t.Fatalf("run eks scan: %v", err)
	}

	// Verify we have checks from all 4 categories
	categories := map[string]bool{}
	for _, check := range result.Checks {
		categories[check.Category] = true
	}

	expected := []string{"Best Practices", "Security", "Monitoring", "Networking"}
	for _, cat := range expected {
		if !categories[cat] {
			t.Errorf("expected checks in category %q but found none", cat)
		}
	}
}

func TestRunEKSCheckIDsAreUnique(t *testing.T) {
	t.Helper()

	result, err := RunEKS(EKSOptions{
		ChecksDir: filepath.Clean(filepath.Join("..", "..", "checks", "eks")),
		InputFile: filepath.Clean(filepath.Join("..", "..", "checks", "eks", "testdata", "failing-cluster.json")),
	})
	if err != nil {
		t.Fatalf("run eks scan: %v", err)
	}

	seen := map[string]bool{}
	for _, check := range result.Checks {
		if seen[check.ID] {
			t.Fatalf("duplicate check ID: %s", check.ID)
		}
		seen[check.ID] = true
	}
}

func TestRunEKSFailingClusterHasFindings(t *testing.T) {
	t.Helper()

	result, err := RunEKS(EKSOptions{
		ChecksDir: filepath.Clean(filepath.Join("..", "..", "checks", "eks")),
		InputFile: filepath.Clean(filepath.Join("..", "..", "checks", "eks", "testdata", "failing-cluster.json")),
	})
	if err != nil {
		t.Fatalf("run eks scan: %v", err)
	}

	// The failing cluster should fail specific critical checks
	expectedFailures := []string{
		"EKSBP001", // No IRSA
		"EKSBP007", // CONFIG_MAP auth
		"EKSSEC001", // No private endpoint
		"EKSSEC002", // Public endpoint enabled
		"EKSSEC003", // 0.0.0.0/0 CIDR
		"EKSSEC004", // No encryption
		"EKSSEC005", // No security groups
		"EKSMON001", // Logging disabled
		"EKSMON002", // Not all log types
	}

	failedIDs := map[string]bool{}
	for _, check := range result.Checks {
		if check.Total > 0 {
			failedIDs[check.ID] = true
		}
	}

	for _, id := range expectedFailures {
		if !failedIDs[id] {
			t.Errorf("expected %s to fail on failing cluster fixture", id)
		}
	}
}

func TestEKSLoggingEnabled(t *testing.T) {
	t.Helper()

	tests := []struct {
		name     string
		document map[string]any
		want     bool
	}{
		{
			name: "logging enabled",
			document: map[string]any{
				"logging": map[string]any{
					"clusterLogging": []any{
						map[string]any{
							"types":   []any{"api", "audit"},
							"enabled": true,
						},
					},
				},
			},
			want: true,
		},
		{
			name: "logging disabled",
			document: map[string]any{
				"logging": map[string]any{
					"clusterLogging": []any{
						map[string]any{
							"types":   []any{"api", "audit"},
							"enabled": false,
						},
					},
				},
			},
			want: false,
		},
		{
			name:     "no logging config",
			document: map[string]any{},
			want:     false,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := eksLoggingEnabled(tt.document)
			if got != tt.want {
				t.Errorf("eksLoggingEnabled() = %v, want %v", got, tt.want)
			}
		})
	}
}

func TestEKSAllLogTypesEnabled(t *testing.T) {
	t.Helper()

	tests := []struct {
		name     string
		document map[string]any
		want     bool
	}{
		{
			name: "all 5 types enabled",
			document: map[string]any{
				"logging": map[string]any{
					"clusterLogging": []any{
						map[string]any{
							"types":   []any{"api", "audit", "authenticator", "controllerManager", "scheduler"},
							"enabled": true,
						},
					},
				},
			},
			want: true,
		},
		{
			name: "partial types enabled",
			document: map[string]any{
				"logging": map[string]any{
					"clusterLogging": []any{
						map[string]any{
							"types":   []any{"api", "audit"},
							"enabled": true,
						},
					},
				},
			},
			want: false,
		},
		{
			name: "all types but disabled",
			document: map[string]any{
				"logging": map[string]any{
					"clusterLogging": []any{
						map[string]any{
							"types":   []any{"api", "audit", "authenticator", "controllerManager", "scheduler"},
							"enabled": false,
						},
					},
				},
			},
			want: false,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := eksAllLogTypesEnabled(tt.document)
			if got != tt.want {
				t.Errorf("eksAllLogTypesEnabled() = %v, want %v", got, tt.want)
			}
		})
	}
}

func TestEKSHasAddon(t *testing.T) {
	t.Helper()

	document := map[string]any{
		"_addons": []any{
			map[string]any{"addonName": "vpc-cni"},
			map[string]any{"addonName": "coredns"},
		},
	}

	if !eksHasAddon(document, "vpc-cni") {
		t.Error("expected vpc-cni addon to be found")
	}
	if !eksHasAddon(document, "coredns") {
		t.Error("expected coredns addon to be found")
	}
	if eksHasAddon(document, "kube-proxy") {
		t.Error("expected kube-proxy addon NOT to be found")
	}
}
