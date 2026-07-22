package output

import (
	"bytes"
	"encoding/json"
	"strings"
	"testing"

	"github.com/KubeDeckio/KubeBuddy/internal/collector/kubernetes"
	"github.com/KubeDeckio/KubeBuddy/internal/scan"
)

func TestWriteScanResultJSON(t *testing.T) {
	t.Helper()

	var buf bytes.Buffer
	err := WriteScanResultWithMetadata(&buf, scan.Result{
		Checks: []scan.CheckResult{{ID: "X001", Name: "Check", Total: 1, Weight: 2}},
	}, ModeJSON, Metadata{
		ClusterName:              "docker-desktop",
		KubernetesVersion:        "v1.30.0",
		GeneratedAt:              "2026-04-09T12:00:00Z",
		PrometheusSnapshotStatus: "unavailable",
		PrometheusSnapshotReason: "Prometheus checks were enabled, but no usable node metric series were collected for the snapshot.",
	})
	if err != nil {
		t.Fatalf("write json output: %v", err)
	}
	var payload map[string]any
	if err := json.Unmarshal(buf.Bytes(), &payload); err != nil {
		t.Fatalf("unmarshal json output: %v", err)
	}
	if _, ok := payload["metadata"]; !ok {
		t.Fatalf("expected metadata section, got %s", buf.String())
	}
	metadata, ok := payload["metadata"].(map[string]any)
	if !ok {
		t.Fatalf("expected metadata object, got %s", buf.String())
	}
	if got := metadata["prometheusSnapshotStatus"]; got != "unavailable" {
		t.Fatalf("expected prometheusSnapshotStatus=unavailable, got %#v", got)
	}
	if got := metadata["prometheusSnapshotReason"]; got == nil || got == "" {
		t.Fatalf("expected prometheusSnapshotReason to be present, got %#v", got)
	}
	checks, ok := payload["checks"].(map[string]any)
	if !ok || checks["X001"] == nil {
		t.Fatalf("expected keyed checks map, got %s", buf.String())
	}
}

func TestWriteScanResultText(t *testing.T) {
	t.Helper()

	var buf bytes.Buffer
	err := WriteScanResultWithMetadata(&buf, scan.Result{
		Checks: []scan.CheckResult{
			{ID: "X001", Name: "Check", Section: "Security", Category: "Cat", Severity: "Warning", Recommendation: "Do the thing", URL: "https://example.com", Total: 1, Items: []scan.Finding{{Namespace: "default", Resource: "pod/a", Message: "issue"}}},
		},
	}, ModeText, Metadata{
		ClusterName:       "docker-desktop",
		KubernetesVersion: "v1.30.0",
		GeneratedAt:       "2026-04-13T12:00:00Z",
	})
	if err != nil {
		t.Fatalf("write text output: %v", err)
	}
	if !strings.Contains(buf.String(), "--- Kubernetes Cluster Report ---") {
		t.Fatalf("expected report banner, got %s", buf.String())
	}
	if !strings.Contains(buf.String(), "=== Issue Summary ===") {
		t.Fatalf("expected issue summary block, got %s", buf.String())
	}
	if !strings.Contains(buf.String(), "=== Check Results ===") {
		t.Fatalf("expected check results block, got %s", buf.String())
	}
	if !strings.Contains(buf.String(), "X001 - Check") {
		t.Fatalf("expected powershell-style check header, got %s", buf.String())
	}
	if !strings.Contains(buf.String(), "Category: Cat") {
		t.Fatalf("expected category line, got %s", buf.String())
	}
	if !strings.Contains(buf.String(), "Total Issues: 1") {
		t.Fatalf("expected issue count line, got %s", buf.String())
	}
}

func TestWriteScanResultCSV(t *testing.T) {
	t.Helper()

	var buf bytes.Buffer
	err := WriteScanResultWithMetadata(&buf, scan.Result{
		Checks: []scan.CheckResult{
			{ID: "X001", Name: "Check", Category: "Cat", Severity: "High", Recommendation: "Do the thing", URL: "https://example.com", Total: 1, Items: []scan.Finding{{Namespace: "default", Resource: "pod/a", Value: "true", Message: "issue"}}},
		},
	}, ModeCSV, Metadata{})
	if err != nil {
		t.Fatalf("write csv output: %v", err)
	}
	if !bytes.HasPrefix(buf.Bytes(), []byte{0xEF, 0xBB, 0xBF}) {
		t.Fatalf("expected utf-8 bom, got %v", buf.Bytes()[:3])
	}
	if !strings.Contains(buf.String(), `"ID","Name","Category","Severity","Status","Message","Recommendation","URL"`) {
		t.Fatalf("expected csv header, got %s", buf.String())
	}
	if !strings.Contains(buf.String(), "Namespace: default | Resource: pod/a | Message: issue | Value: true") {
		t.Fatalf("expected powershell-style flattened message, got %s", buf.String())
	}
}

func TestWriteScanResultCSVIncludesRiskPaths(t *testing.T) {
	t.Helper()

	var buf bytes.Buffer
	err := WriteScanResultWithMetadata(&buf, scan.Result{
		Checks: []scan.CheckResult{{ID: "SEC004", Name: "Privileged Container", Total: 1, Weight: 2}},
		DirectRiskPaths: []scan.DirectRiskPath{{
			ID:           "RISK001",
			Name:         "Container Isolation Risk",
			Status:       "triggered",
			FixPriority:  "urgent",
			Summary:      "Container isolation findings are active.",
			SignalChecks: []string{"SEC004"},
			Evidence:     []scan.RiskPathEvidence{{CheckID: "SEC004", FindingCount: 2}},
		}},
		CombinedRiskPaths: []scan.CombinedRiskPath{{
			ID:                       "CHAIN001",
			Name:                     "Workload to Cluster Control Path",
			Status:                   "triggered",
			FixPriority:              "urgent",
			Summary:                  "Direct risks combine into a higher-impact path.",
			Requires:                 []string{"RISK001", "RISK003"},
			TriggeredDirectRiskPaths: []string{"RISK001", "RISK003"},
		}},
	}, ModeCSV, Metadata{})
	if err != nil {
		t.Fatalf("write csv output: %v", err)
	}
	out := buf.String()
	for _, want := range []string{
		`"RISK001","Container Isolation Risk","Risk Paths","Direct","TRIGGERED"`,
		`"CHAIN001","Workload to Cluster Control Path","Risk Paths","Combined","TRIGGERED"`,
		`Findings: 2 | Active: SEC004`,
		`Requires: RISK001, RISK003`,
	} {
		if !strings.Contains(out, want) {
			t.Fatalf("expected %q in csv output, got %s", want, out)
		}
	}
}

func TestWriteScanResultHTML(t *testing.T) {
	t.Helper()

	var buf bytes.Buffer
	err := WriteScanResultWithMetadata(&buf, scan.Result{
		Checks: []scan.CheckResult{{ID: "X001", Name: "Check", Category: "Cat", Severity: "High", Total: 0}},
	}, ModeHTML, Metadata{
		ClusterName: "aks-test",
		Snapshot: &kubernetes.ClusterData{
			Summary: kubernetes.Summary{
				Context:    "aks-test",
				Nodes:      3,
				Pods:       67,
				Namespaces: 7,
			},
			KubernetesVersion: "v1.33.6",
			Nodes: []map[string]any{
				{"metadata": map[string]any{"name": "node-a"}, "status": map[string]any{"conditions": []any{map[string]any{"type": "Ready", "status": "True"}}}},
			},
			AllPods: []map[string]any{
				{"metadata": map[string]any{"name": "pod-a", "namespace": "default"}, "spec": map[string]any{"nodeName": "node-a"}, "status": map[string]any{"phase": "Running"}},
			},
		},
	})
	if err != nil {
		t.Fatalf("write html output: %v", err)
	}
	if !strings.Contains(buf.String(), "<html") {
		t.Fatalf("expected html output")
	}
	if !strings.Contains(buf.String(), "Cluster Summary") {
		t.Fatalf("expected snapshot-backed summary section, got %s", buf.String())
	}
	if !strings.Contains(buf.String(), "Kubernetes Cluster Report: aks-test") {
		t.Fatalf("expected html report header to use cluster name, got %s", buf.String())
	}
	if strings.Contains(buf.String(), "Cluster Name:</strong> KubeBuddy Native Report") {
		t.Fatalf("expected html report overview to avoid generic cluster name, got %s", buf.String())
	}
}
func TestWriteScanResultJSONIncludesDirectRiskPaths(t *testing.T) {
	t.Helper()

	var buf bytes.Buffer
	err := WriteScanResultWithMetadata(&buf, scan.Result{
		Checks: []scan.CheckResult{{ID: "SEC004", Name: "Privileged Container", Total: 1, Weight: 2}},
		DirectRiskPaths: []scan.DirectRiskPath{{
			ID:              "RISK001",
			Name:            "Container Isolation Risk",
			Status:          "triggered",
			ValidationProof: []scan.ValidationCommand{{Title: "List pods", Command: "kubectl get pods --all-namespaces", Purpose: "Confirm pods.", ReadOnly: true}},
			AttackGraph:     &scan.RiskPathGraph{Nodes: []scan.RiskPathGraphNode{{ID: "RISK001", Label: "Container Isolation Risk", Type: "directRiskPath"}}, Edges: []scan.RiskPathGraphEdge{{From: "check:SEC004", To: "RISK001", Label: "contributes"}}},
		}},
		CombinedRiskPaths: []scan.CombinedRiskPath{{
			ID:       "CHAIN001",
			Name:     "Workload to Cluster Control Path",
			Status:   "clear",
			Requires: []string{"RISK001", "RISK003"},
		}},
	}, ModeJSON, Metadata{
		ClusterName:       "docker-desktop",
		KubernetesVersion: "v1.30.0",
		GeneratedAt:       "2026-04-09T12:00:00Z",
	})
	if err != nil {
		t.Fatalf("write json output: %v", err)
	}

	var payload map[string]any
	if err := json.Unmarshal(buf.Bytes(), &payload); err != nil {
		t.Fatalf("unmarshal json output: %v", err)
	}
	directRiskPaths, ok := payload["directRiskPaths"].([]any)
	if !ok || len(directRiskPaths) != 1 {
		t.Fatalf("expected one capability break, got %s", buf.String())
	}
	firstCapability, ok := directRiskPaths[0].(map[string]any)
	if !ok || firstCapability["id"] != "RISK001" {
		t.Fatalf("expected RISK001 capability break, got %#v", directRiskPaths[0])
	}
	if proof, ok := firstCapability["validationProof"].([]any); !ok || len(proof) != 1 {
		t.Fatalf("expected validationProof in RISK001, got %#v", firstCapability["validationProof"])
	}
	if graph, ok := firstCapability["attackGraph"].(map[string]any); !ok || graph["nodes"] == nil || graph["edges"] == nil {
		t.Fatalf("expected attackGraph nodes and edges in RISK001, got %#v", firstCapability["attackGraph"])
	}
	combinedRiskPaths, ok := payload["combinedRiskPaths"].([]any)
	if !ok || len(combinedRiskPaths) != 1 {
		t.Fatalf("expected one compound break, got %s", buf.String())
	}
}

func TestWriteScanResultTextIncludesRiskPaths(t *testing.T) {
	t.Helper()

	var buf bytes.Buffer
	err := WriteScanResultWithMetadata(&buf, scan.Result{
		Checks: []scan.CheckResult{{ID: "SEC004", Name: "Privileged Container", Total: 1, Weight: 2}},
		DirectRiskPaths: []scan.DirectRiskPath{{
			ID:           "RISK001",
			Name:         "Container Isolation Risk",
			Status:       "triggered",
			Confidence:   "high",
			FixPriority:  "urgent",
			Summary:      "Container isolation findings are active.",
			SignalChecks: []string{"SEC004"},
			Evidence: []scan.RiskPathEvidence{{
				CheckID:      "SEC004",
				CheckName:    "Privileged Container",
				FindingCount: 2,
			}},
		}},
		CombinedRiskPaths: []scan.CombinedRiskPath{{
			ID:                       "CHAIN001",
			Name:                     "Workload to Cluster Control Path",
			Status:                   "triggered",
			Confidence:               "possible",
			FixPriority:              "urgent",
			Summary:                  "Direct risks combine into a higher-impact path.",
			Requires:                 []string{"RISK001", "RISK003"},
			TriggeredDirectRiskPaths: []string{"RISK001", "RISK003"},
		}},
	}, ModeText, Metadata{
		ClusterName:       "docker-desktop",
		KubernetesVersion: "v1.30.0",
		GeneratedAt:       "2026-04-13T12:00:00Z",
	})
	if err != nil {
		t.Fatalf("write text output: %v", err)
	}
	out := buf.String()
	for _, want := range []string{
		"=== Risk Paths ===",
		"Direct Risk Paths:",
		"RISK001 - Container Isolation Risk [triggered]",
		"Findings: 2 across 1 checks",
		"Combined Risk Paths:",
		"CHAIN001 - Workload to Cluster Control Path [triggered]",
		"Active Risks: RISK001, RISK003",
	} {
		if !strings.Contains(out, want) {
			t.Fatalf("expected %q in text output, got %s", want, out)
		}
	}
}
