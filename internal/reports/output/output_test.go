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
	if _, ok := payload["metadata"]; !ok {
		t.Fatalf("expected metadata section, got %s", buf.String())
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
	if !strings.Contains(buf.String(), "[X001 - Check]") {
		t.Fatalf("expected powershell-style check header, got %s", buf.String())
	}
	if !strings.Contains(buf.String(), "Section: Security") {
		t.Fatalf("expected section line, got %s", buf.String())
	}
	if !strings.Contains(buf.String(), "⚠️ Total Issues: 1") {
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

func TestWriteScanResultHTML(t *testing.T) {
	t.Helper()

	var buf bytes.Buffer
	err := WriteScanResultWithMetadata(&buf, scan.Result{
		Checks: []scan.CheckResult{{ID: "X001", Name: "Check", Category: "Cat", Severity: "High", Total: 0}},
	}, ModeHTML, Metadata{
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
}
