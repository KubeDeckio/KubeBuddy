package config

import (
	"os"
	"path/filepath"
	"testing"
)

func TestLoadDefaultsWhenConfigMissing(t *testing.T) {
	t.Helper()

	cfg := Load(filepath.Join(t.TempDir(), "missing.yaml"))
	if got := cfg.Thresholds["cpu_warning"]; got != 50 {
		t.Fatalf("expected default cpu_warning 50, got %v", got)
	}
	if len(cfg.ExcludedNamespaces) == 0 {
		t.Fatalf("expected default excluded namespaces")
	}
	if len(cfg.TrustedRegistries) != 1 || cfg.TrustedRegistries[0] != "mcr.microsoft.com/" {
		t.Fatalf("unexpected trusted registries: %#v", cfg.TrustedRegistries)
	}
	if cfg.Radar.APIBaseURL != "https://radar.kubebuddy.io/api/kb-radar/v1" {
		t.Fatalf("unexpected radar defaults: %#v", cfg.Radar)
	}
}

func TestLoadMergesFullConfigSurface(t *testing.T) {
	t.Helper()

	dir := t.TempDir()
	path := filepath.Join(dir, "kubebuddy-config.yaml")
	content := `
thresholds:
  cpu_warning: 61
  pod_sizing_profile: aggressive
excluded_namespaces:
  - kube-system
  - custom-ns
excluded_checks:
  - sec014
  - AKSSEC001
trusted_registries:
  - mcr.microsoft.com/
  - ghcr.io/approved/
radar:
  enabled: true
  api_base_url: https://radar.example.test/api/kb-radar/v1
  environment: staging
  api_user_env: CUSTOM_RADAR_USER
  api_password_env: CUSTOM_RADAR_PASSWORD
  upload_timeout_seconds: 45
  upload_retries: 4
`
	if err := os.WriteFile(path, []byte(content), 0o644); err != nil {
		t.Fatalf("write config: %v", err)
	}

	cfg := Load(path)
	if got := cfg.Thresholds["cpu_warning"]; got != 61 {
		t.Fatalf("expected cpu_warning override, got %v", got)
	}
	if got := cfg.Thresholds["pod_sizing_target_cpu_utilization"]; got != 75 {
		t.Fatalf("expected aggressive profile cpu target, got %v", got)
	}
	if got := cfg.Thresholds["pod_sizing_mem_request_floor_mib"]; got != 64 {
		t.Fatalf("expected aggressive profile mem floor, got %v", got)
	}
	if len(cfg.ExcludedNamespaces) != 2 || cfg.ExcludedNamespaces[1] != "custom-ns" {
		t.Fatalf("unexpected excluded namespaces: %#v", cfg.ExcludedNamespaces)
	}
	if len(cfg.ExcludedChecks) != 2 || cfg.ExcludedChecks[0] != "SEC014" || cfg.ExcludedChecks[1] != "AKSSEC001" {
		t.Fatalf("unexpected excluded checks: %#v", cfg.ExcludedChecks)
	}
	if len(cfg.TrustedRegistries) != 2 || cfg.TrustedRegistries[1] != "ghcr.io/approved/" {
		t.Fatalf("unexpected trusted registries: %#v", cfg.TrustedRegistries)
	}
	if !cfg.Radar.Enabled || cfg.Radar.Environment != "staging" || cfg.Radar.APIUserEnv != "CUSTOM_RADAR_USER" || cfg.Radar.UploadRetries != 4 {
		t.Fatalf("unexpected radar config: %#v", cfg.Radar)
	}
}
