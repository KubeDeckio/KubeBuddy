package scan

import (
	"os"
	"path/filepath"
	"testing"
)

func TestParseLegacyJSONReport(t *testing.T) {
	t.Helper()

	data, err := os.ReadFile(filepath.Join("..", "..", "docs", "examples", "json-report-sample.json"))
	if err != nil {
		t.Fatalf("read sample report: %v", err)
	}

	result, err := ParseLegacyJSONReport(data)
	if err != nil {
		t.Fatalf("parse report: %v", err)
	}

	if len(result.Checks) == 0 {
		t.Fatalf("expected checks to be imported")
	}

	var found bool
	for _, check := range result.Checks {
		if check.ID != "SEC008" {
			continue
		}
		found = true
		if check.Recommendation == "" {
			t.Fatalf("expected recommendation to be preserved")
		}
		if len(check.Items) == 0 {
			t.Fatalf("expected imported findings")
		}
		if check.Items[0].Namespace == "" || check.Items[0].Resource == "" || check.Items[0].Message == "" {
			t.Fatalf("expected finding fields to be populated: %+v", check.Items[0])
		}
		break
	}

	if !found {
		t.Fatalf("expected SEC008 to be present in imported report")
	}
}
