package reportassets

import (
	"os"
	"testing"
)

func TestEmbeddedReportStylesMatchSource(t *testing.T) {
	t.Helper()

	data, err := os.ReadFile("report-styles.css")
	if err != nil {
		t.Fatalf("read report styles source: %v", err)
	}

	if string(data) != ReportStyles {
		t.Fatalf("embedded report styles do not match source file")
	}
}

func TestEmbeddedReportScriptsMatchSource(t *testing.T) {
	t.Helper()

	data, err := os.ReadFile("report-scripts.js")
	if err != nil {
		t.Fatalf("read report scripts source: %v", err)
	}

	if string(data) != ReportScripts {
		t.Fatalf("embedded report scripts do not match source file")
	}
}
