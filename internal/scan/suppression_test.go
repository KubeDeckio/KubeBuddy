package scan

import "testing"

func TestApplyFindingSuppressionsByCheckID(t *testing.T) {
	cache := map[string][]map[string]any{
		"services": {
			{
				"metadata": map[string]any{
					"name":      "api",
					"namespace": "default",
					"annotations": map[string]any{
						"kubebuddy.io/ignore-checks": "NET001, SEC001",
						"kubebuddy.io/ignore-reason": "migration window",
					},
				},
			},
		},
	}
	result := CheckResult{
		ID:    "NET001",
		Items: []Finding{{Namespace: "default", Resource: "service/api", Message: "No endpoints"}},
		Total: 1,
	}

	applyFindingSuppressions(&result, cache)

	if result.Total != 0 || len(result.Items) != 0 {
		t.Fatalf("expected finding to be suppressed, got total=%d items=%v", result.Total, result.Items)
	}
	if len(result.SuppressedFindings) != 1 {
		t.Fatalf("expected one suppressed finding, got %d", len(result.SuppressedFindings))
	}
	if result.SuppressedFindings[0].Reason != "migration window" {
		t.Fatalf("unexpected suppression reason: %q", result.SuppressedFindings[0].Reason)
	}
}

func TestApplyFindingSuppressionsWildcardAndExpiredUntil(t *testing.T) {
	cache := map[string][]map[string]any{
		"secrets": {
			{
				"metadata": map[string]any{
					"name":      "active",
					"namespace": "default",
					"annotations": map[string]any{
						"kubebuddy.io/ignore-checks": "*",
					},
				},
			},
			{
				"metadata": map[string]any{
					"name":      "expired",
					"namespace": "default",
					"annotations": map[string]any{
						"kubebuddy.io/ignore-checks": "*",
						"kubebuddy.io/ignore-until":  "2000-01-01",
					},
				},
			},
		},
	}
	result := CheckResult{
		ID: "SEC001",
		Items: []Finding{
			{Namespace: "default", Resource: "secret/active", Message: "Unused"},
			{Namespace: "default", Resource: "secret/expired", Message: "Unused"},
		},
		Total: 2,
	}

	applyFindingSuppressions(&result, cache)

	if result.Total != 1 || len(result.Items) != 1 || result.Items[0].Resource != "secret/expired" {
		t.Fatalf("expected only expired suppression to remain active, got total=%d items=%v", result.Total, result.Items)
	}
	if len(result.SuppressedFindings) != 1 || result.SuppressedFindings[0].Resource != "secret/active" {
		t.Fatalf("expected wildcard suppression for active secret, got %+v", result.SuppressedFindings)
	}
}
