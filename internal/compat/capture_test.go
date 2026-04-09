package compat

import (
	"os"
	"path/filepath"
	"testing"
)

func TestEnableReport(t *testing.T) {
	t.Helper()

	options := RunOptions{HTMLReport: true, JSONReport: true}
	enableReport(&options, ReportCSV)
	if options.HTMLReport || options.JSONReport || !options.CSVReport || options.TxtReport {
		t.Fatalf("unexpected report flags: %+v", options)
	}
}

func TestFindGeneratedReportIgnoresActionPlan(t *testing.T) {
	t.Helper()

	dir := t.TempDir()
	mainReport := filepath.Join(dir, "kubebuddy-report-20260409-120000.html")
	actionPlan := filepath.Join(dir, "kubebuddy-report-20260409-120000-aks-automatic-action-plan.html")

	for _, file := range []string{mainReport, actionPlan} {
		if err := os.WriteFile(file, []byte("ok"), 0o600); err != nil {
			t.Fatalf("write fixture %s: %v", file, err)
		}
	}

	got, err := findGeneratedReport(dir, ReportHTML)
	if err != nil {
		t.Fatalf("find report: %v", err)
	}
	if got != mainReport {
		t.Fatalf("expected %s, got %s", mainReport, got)
	}
}
