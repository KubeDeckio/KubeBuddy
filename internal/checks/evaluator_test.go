package checks

import "testing"

func TestEvaluateItemSupportsSimpleEquality(t *testing.T) {
	t.Helper()

	check := Check{
		ID:       "PVC004",
		Operator: OperatorEquals,
		Value:    &Expression{Path: "status.phase"},
		Expected: "Pending",
	}
	item := map[string]any{
		"status": map[string]any{"phase": "Pending"},
	}

	got, err := EvaluateItem(check, item)
	if err != nil {
		t.Fatalf("evaluate item: %v", err)
	}
	if got.Failed {
		t.Fatalf("expected matching equals check not to produce a finding")
	}
}

func TestEvaluateItemSupportsLegacyNotEqualsList(t *testing.T) {
	t.Helper()

	check := Check{
		ID:       "POD008",
		Operator: OperatorNotEquals,
		Value:    &Expression{Path: "spec.automountServiceAccountToken"},
		Expected: "true,null",
	}

	itemTrue := map[string]any{
		"spec": map[string]any{"automountServiceAccountToken": true},
	}
	got, err := EvaluateItem(check, itemTrue)
	if err != nil {
		t.Fatalf("evaluate true item: %v", err)
	}
	if !got.Failed {
		t.Fatalf("expected true to be treated as a failing legacy value")
	}

	itemFalse := map[string]any{
		"spec": map[string]any{"automountServiceAccountToken": false},
	}
	got, err = EvaluateItem(check, itemFalse)
	if err != nil {
		t.Fatalf("evaluate false item: %v", err)
	}
	if got.Failed {
		t.Fatalf("expected false not to be treated as a failing legacy value")
	}
}

func TestEvaluateItemSupportsStringContainsChecks(t *testing.T) {
	t.Helper()

	check := Check{
		ID:       "SC001",
		Operator: OperatorNotContains,
		Value:    &Expression{Path: "provisioner"},
		Expected: "kubernetes.io/",
	}
	item := map[string]any{"provisioner": "kubernetes.io/aws-ebs"}

	got, err := EvaluateItem(check, item)
	if err != nil {
		t.Fatalf("evaluate contains item: %v", err)
	}
	if !got.Failed {
		t.Fatalf("expected legacy not_contains item to fail when substring is present")
	}
}

func TestEvaluateItemSupportsCoalesceAndBooleanPredicates(t *testing.T) {
	t.Helper()

	check := Check{
		ID:       "AKSSEC007",
		Operator: OperatorNotEquals,
		Value: &Expression{
			Coalesce: []*Expression{
				{Path: "properties.addonProfiles.kubeDashboard.enabled"},
				{Value: false},
			},
		},
		Expected: false,
	}
	item := map[string]any{
		"properties": map[string]any{},
	}

	got, err := EvaluateItem(check, item)
	if err != nil {
		t.Fatalf("evaluate coalesce item: %v", err)
	}
	if !got.Failed {
		t.Fatalf("expected current legacy not_equals semantics to produce a finding")
	}
}

func TestEvaluateItemSupportsCountWhere(t *testing.T) {
	t.Helper()

	check := Check{
		ID:       "AKSBP013",
		Operator: OperatorEquals,
		Value: &Expression{
			CountWhere: &CountWhereExpr{
				Path: "properties.agentPoolProfiles",
				Where: Predicate{
					Path:     "vmSize",
					Operator: OperatorMatches,
					Expected: "^Standard_B",
				},
			},
		},
		Expected: 0,
	}
	item := map[string]any{
		"properties": map[string]any{
			"agentPoolProfiles": []any{
				map[string]any{"vmSize": "Standard_B4ms"},
				map[string]any{"vmSize": "Standard_D2s_v5"},
			},
		},
	}

	got, err := EvaluateItem(check, item)
	if err != nil {
		t.Fatalf("evaluate count_where item: %v", err)
	}
	if got.Value != 1 {
		t.Fatalf("expected count_where value 1, got %#v", got.Value)
	}
	if !got.Failed {
		t.Fatalf("expected equals 0 to fail when one matching item exists")
	}
}

func TestResolvePathFlattensNestedSlices(t *testing.T) {
	t.Helper()

	item := map[string]any{
		"status": map[string]any{
			"containerStatuses": []any{
				map[string]any{
					"state": map[string]any{
						"waiting": map[string]any{
							"reason": "CrashLoopBackOff",
						},
					},
				},
				map[string]any{
					"state": map[string]any{
						"waiting": map[string]any{
							"reason": "ImagePullBackOff",
						},
					},
				},
			},
		},
	}

	got, err := ResolvePath(item, "status.containerStatuses[].state.waiting.reason")
	if err != nil {
		t.Fatalf("resolve path: %v", err)
	}

	values := normalizeSlice(got)
	if len(values) != 2 {
		t.Fatalf("expected 2 values, got %d", len(values))
	}
	if values[0] != "CrashLoopBackOff" || values[1] != "ImagePullBackOff" {
		t.Fatalf("unexpected values: %#v", values)
	}
}

func TestEvaluateItemSupportsContainsAgainstSliceValues(t *testing.T) {
	t.Helper()

	check := Check{
		ID:       "POD005",
		Operator: OperatorNotContains,
		Value: &Expression{
			Path: "status.containerStatuses[].state.waiting.reason",
		},
		Expected: "CrashLoopBackOff",
	}

	item := map[string]any{
		"status": map[string]any{
			"containerStatuses": []any{
				map[string]any{
					"state": map[string]any{
						"waiting": map[string]any{
							"reason": "CrashLoopBackOff",
						},
					},
				},
			},
		},
	}

	got, err := EvaluateItem(check, item)
	if err != nil {
		t.Fatalf("evaluate contains slice item: %v", err)
	}
	if !got.Failed {
		t.Fatalf("expected not_contains to fail when any nested value matches")
	}
}
