package scan

import "testing"

func TestAnalyzeDirectRiskPathsRISK001Triggered(t *testing.T) {
	directRiskPaths, combinedRiskPaths := AnalyzeDirectRiskPaths([]CheckResult{
		{
			ID:       "SEC004",
			Name:     "Privileged Container",
			Severity: "high",
			Total:    1,
			Items:    []Finding{{Namespace: "default", Resource: "pod/web", Message: "privileged container"}},
		},
		{
			ID:       "SEC010",
			Name:     "Host Path Mount",
			Severity: "high",
			Total:    1,
			Items:    []Finding{{Namespace: "default", Resource: "pod/web", Message: "host path mount"}},
		},
	})

	capability := findDirectRiskPath(t, directRiskPaths, "RISK001")
	if capability.Status != riskPathStatusTriggered {
		t.Fatalf("expected RISK001 triggered, got %q", capability.Status)
	}
	if len(capability.Evidence) != 2 {
		t.Fatalf("expected two evidence items, got %d", len(capability.Evidence))
	}
	if capability.AttackGraph == nil || len(capability.AttackGraph.Nodes) == 0 || len(capability.AttackGraph.Edges) == 0 {
		t.Fatalf("expected RISK001 attack graph to be populated")
	}
	for _, proof := range capability.ValidationProof {
		if !proof.ReadOnly {
			t.Fatalf("expected validation proof commands to be read-only, got %#v", proof)
		}
	}

	compound := findCombinedRiskPath(t, combinedRiskPaths, "CHAIN001")
	if compound.Status != riskPathStatusClear {
		t.Fatalf("expected CHAIN001 clear without RISK003, got %q", compound.Status)
	}
}

func TestAnalyzeDirectRiskPathsRISK002Clear(t *testing.T) {
	directRiskPaths, _ := AnalyzeDirectRiskPaths([]CheckResult{
		{ID: "NET004", Name: "Network Policy Coverage", Severity: "medium", Total: 0},
	})

	capability := findDirectRiskPath(t, directRiskPaths, "RISK002")
	if capability.Status != riskPathStatusClear {
		t.Fatalf("expected RISK002 clear, got %q", capability.Status)
	}
	if len(capability.Evidence) != 0 {
		t.Fatalf("expected no RISK002 evidence, got %#v", capability.Evidence)
	}
	if capability.AttackGraph != nil {
		t.Fatalf("expected clear RISK002 to omit attack graph")
	}
}

func TestAnalyzeDirectRiskPathsRISK003TriggeredFromSingleCriticalRBACSignal(t *testing.T) {
	directRiskPaths, _ := AnalyzeDirectRiskPaths([]CheckResult{
		{
			ID:       "RBAC006",
			Name:     "Escalating RBAC Permission",
			Severity: "high",
			Total:    1,
			Items:    []Finding{{Namespace: "-", Resource: "clusterrole/admin", Message: "escalate permission"}},
		},
	})

	capability := findDirectRiskPath(t, directRiskPaths, "RISK003")
	if capability.Status != riskPathStatusTriggered {
		t.Fatalf("expected RISK003 triggered, got %q", capability.Status)
	}
	if capability.Confidence != "medium" {
		t.Fatalf("expected medium confidence for a single critical RBAC signal, got %q", capability.Confidence)
	}
}

func TestAnalyzeDirectRiskPathsCompoundTriggered(t *testing.T) {
	_, combinedRiskPaths := AnalyzeDirectRiskPaths([]CheckResult{
		{ID: "SEC004", Name: "Privileged Container", Severity: "high", Total: 1, Items: []Finding{{Resource: "pod/a"}}},
		{ID: "SEC010", Name: "Host Path Mount", Severity: "high", Total: 1, Items: []Finding{{Resource: "pod/a"}}},
		{ID: "RBAC006", Name: "Escalating RBAC Permission", Severity: "high", Total: 1, Items: []Finding{{Resource: "clusterrole/admin"}}},
	})

	compound := findCombinedRiskPath(t, combinedRiskPaths, "CHAIN001")
	if compound.Status != riskPathStatusTriggered {
		t.Fatalf("expected CHAIN001 triggered, got %q", compound.Status)
	}
	if len(compound.TriggeredDirectRiskPaths) != 2 {
		t.Fatalf("expected two triggered directRiskPaths, got %#v", compound.TriggeredDirectRiskPaths)
	}
	if compound.AttackGraph == nil || len(compound.AttackGraph.Edges) != 2 {
		t.Fatalf("expected compound attack graph with two edges, got %#v", compound.AttackGraph)
	}
}

func findDirectRiskPath(t *testing.T, directRiskPaths []DirectRiskPath, id string) DirectRiskPath {
	t.Helper()
	for _, capability := range directRiskPaths {
		if capability.ID == id {
			return capability
		}
	}
	t.Fatalf("capability %s not found in %#v", id, directRiskPaths)
	return DirectRiskPath{}
}

func findCombinedRiskPath(t *testing.T, combinedRiskPaths []CombinedRiskPath, id string) CombinedRiskPath {
	t.Helper()
	for _, compound := range combinedRiskPaths {
		if compound.ID == id {
			return compound
		}
	}
	t.Fatalf("compound %s not found in %#v", id, combinedRiskPaths)
	return CombinedRiskPath{}
}

func TestAnalyzeDirectRiskPathsServiceAccountAndSecretChains(t *testing.T) {
	directRiskPaths, combinedRiskPaths := AnalyzeDirectRiskPaths([]CheckResult{
		{ID: "RBAC006", Name: "Dangerous RBAC Verbs and Subresources", Severity: "high", Total: 1, Items: []Finding{{Resource: "clusterrole/admin", Message: "escalate permission"}}},
		{ID: "RBAC010", Name: "Sensitive ServiceAccount Bound to Workload", Severity: "high", Total: 1, Items: []Finding{{Namespace: "default", Resource: "deployment/api", Message: "sensitive service account bound"}}},
		{ID: "SEC015", Name: "Default ServiceAccount Used", Severity: "medium", Total: 1, Items: []Finding{{Namespace: "default", Resource: "pod/api", Message: "default service account used"}}},
		{ID: "SEC031", Name: "Secret Material Pattern Detected", Severity: "high", Total: 1, Items: []Finding{{Namespace: "default", Resource: "secret/app-config", Message: "private key material detected"}}},
	})

	cap004 := findDirectRiskPath(t, directRiskPaths, "RISK004")
	if cap004.Status != riskPathStatusTriggered {
		t.Fatalf("expected RISK004 triggered, got %q", cap004.Status)
	}
	if cap004.AttackGraph == nil || len(cap004.ValidationProof) == 0 {
		t.Fatalf("expected RISK004 proof and graph, got %#v", cap004)
	}

	cap007 := findDirectRiskPath(t, directRiskPaths, "RISK007")
	if cap007.Status != riskPathStatusTriggered {
		t.Fatalf("expected RISK007 triggered, got %q", cap007.Status)
	}
	if len(cap007.Evidence) < 2 {
		t.Fatalf("expected RISK007 to include secret/RBAC evidence, got %#v", cap007.Evidence)
	}
	for _, proof := range cap007.ValidationProof {
		if !proof.ReadOnly {
			t.Fatalf("expected RISK007 validation proof to be read-only, got %#v", proof)
		}
	}

	compound003 := findCombinedRiskPath(t, combinedRiskPaths, "CHAIN003")
	if compound003.Status != riskPathStatusTriggered {
		t.Fatalf("expected CHAIN003 triggered, got %q", compound003.Status)
	}
	compound005 := findCombinedRiskPath(t, combinedRiskPaths, "CHAIN005")
	if compound005.Status != riskPathStatusTriggered {
		t.Fatalf("expected CHAIN005 triggered, got %q", compound005.Status)
	}
}
