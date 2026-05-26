package containerenv

import (
	"os"
	"testing"
)

func TestLoadValidatesReportFormats(t *testing.T) {
	t.Helper()

	origJR := os.Getenv("JSON_REPORT")
	origKC := os.Getenv("KUBECONFIG")
	defer func() {
		_ = os.Setenv("JSON_REPORT", origJR)
		_ = os.Setenv("KUBECONFIG", origKC)
	}()

	_ = os.Setenv("JSON_REPORT", "")
	_ = os.Setenv("KUBECONFIG", "/tmp/config")
	_, err := Load()
	if err == nil {
		t.Fatalf("expected missing report format error")
	}
}

func TestLoadReadsJSONReport(t *testing.T) {
	t.Helper()

	origJR := os.Getenv("JSON_REPORT")
	origKC := os.Getenv("KUBECONFIG")
	defer func() {
		_ = os.Setenv("JSON_REPORT", origJR)
		_ = os.Setenv("KUBECONFIG", origKC)
	}()

	_ = os.Setenv("JSON_REPORT", "true")
	_ = os.Setenv("KUBECONFIG", "/tmp/config")
	opts, err := Load()
	if err != nil {
		t.Fatalf("load env opts: %v", err)
	}
	if !opts.JSONReport {
		t.Fatalf("expected JSONReport true")
	}
}

func TestLoadReadsExcludedChecks(t *testing.T) {
	t.Helper()

	origJR := os.Getenv("JSON_REPORT")
	origKC := os.Getenv("KUBECONFIG")
	origEC := os.Getenv("EXCLUDED_CHECKS")
	defer func() {
		_ = os.Setenv("JSON_REPORT", origJR)
		_ = os.Setenv("KUBECONFIG", origKC)
		_ = os.Setenv("EXCLUDED_CHECKS", origEC)
	}()

	_ = os.Setenv("JSON_REPORT", "true")
	_ = os.Setenv("KUBECONFIG", "/tmp/config")
	_ = os.Setenv("EXCLUDED_CHECKS", "SEC014, WRK011")
	opts, err := Load()
	if err != nil {
		t.Fatalf("load env opts: %v", err)
	}
	if len(opts.ExcludedChecks) != 2 || opts.ExcludedChecks[0] != "SEC014" || opts.ExcludedChecks[1] != "WRK011" {
		t.Fatalf("unexpected excluded checks: %#v", opts.ExcludedChecks)
	}
}
