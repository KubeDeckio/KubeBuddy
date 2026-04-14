package html

import (
	"strings"
	"testing"

	"github.com/KubeDeckio/KubeBuddy/internal/collector/kubernetes"
	"github.com/KubeDeckio/KubeBuddy/internal/scan"
)

func TestScanRenderer(t *testing.T) {
	t.Helper()

	out, err := (ScanRenderer{}).Render("KubeBuddy Native Report", scan.Result{
		Checks: []scan.CheckResult{
			{
				ID:       "POD008",
				Name:     "Automount",
				Category: "Security",
				Severity: "Warning",
				Total:    1,
				Items: []scan.Finding{
					{Namespace: "default", Resource: "pod/a", Value: "null", Message: "issue"},
				},
			},
			{
				ID:       "NODE001",
				Name:     "Node Readiness and Conditions",
				Category: "Nodes",
				Section:  "Nodes",
				Severity: "High",
				Total:    0,
			},
			{
				ID:       "PROM006",
				Name:     "Node Sizing Insights (Prometheus)",
				Category: "Workloads",
				Severity: "Info",
				Total:    1,
				Items: []scan.Finding{
					{Namespace: "(cluster)", Resource: "node/a", Message: "Underutilized"},
				},
			},
			{
				ID:       "PROM007",
				Name:     "Pod Sizing Insights (Prometheus)",
				Category: "Workloads",
				Severity: "Info",
				Total:    1,
				Items: []scan.Finding{
					{Namespace: "default", Resource: "pod/a", Value: "app", Message: "cpu_req=100 cpu_rec=200 mem_req=128 mem_rec=256 mem_limit=0 mem_limit_rec=320"},
				},
			},
			{
				ID:                 "AKSSEC001",
				Name:               "Private Cluster",
				Category:           "Security",
				Section:            "AKS",
				Severity:           "High",
				Total:              1,
				RecommendationHTML: `<div class="recommendation-content"><ul><li>Use <code>az aks update --enable-private-cluster</code>.</li></ul></div>`,
				Items: []scan.Finding{
					{Resource: "aks-test", Value: "false", Message: "Private cluster is disabled."},
				},
			},
		},
		AutomaticReadiness: &scan.AutomaticReadiness{
			Summary: scan.AutomaticSummary{
				ClusterName:    "aks-test",
				Status:         "ready_with_changes",
				StatusLabel:    "Ready With Changes",
				ActionPlanPath: "kubebuddy-report-aks-automatic-action-plan.html",
				Message:        "Migration is possible, but changes are recommended.",
			},
			ActionPlan: []scan.AutomaticActionItem{
				{
					Key:             "resource_requests",
					Title:           "Define container resource requests",
					Bucket:          "warning",
					Phase:           "fix_before_migration",
					Steps:           []string{"Add CPU and memory requests."},
					Recommendations: []string{"Define requests before migration."},
					URLs:            []string{"https://example.com/doc"},
				},
			},
		},
	}, RenderOptions{
		Snapshot: &kubernetes.ClusterData{
			Summary: kubernetes.Summary{
				Context:      "aks-test",
				Nodes:        3,
				Namespaces:   7,
				Pods:         67,
				Deployments:  2,
				StatefulSets: 0,
				DaemonSets:   1,
				Services:     3,
				Ingresses:    0,
			},
			KubernetesVersion: "v1.33.6",
			Nodes: []map[string]any{
				{
					"metadata": map[string]any{"name": "node-a"},
					"status": map[string]any{
						"conditions":  []any{map[string]any{"type": "Ready", "status": "True"}},
						"allocatable": map[string]any{"cpu": "3860m", "memory": "14846000Ki"},
						"capacity":    map[string]any{"pods": "50"},
					},
				},
			},
			AllPods: []map[string]any{
				{"metadata": map[string]any{"name": "pod-a", "namespace": "default"}, "spec": map[string]any{"nodeName": "node-a"}, "status": map[string]any{"phase": "Running"}},
			},
			Metrics: &kubernetes.ClusterMetrics{
				Cluster: kubernetes.MetricsCluster{
					AvgCPUPercent: 10.1,
					AvgMemPercent: 20.2,
				},
				Nodes: []kubernetes.NodeMetrics{
					{NodeName: "node-a", CPUAvg: 10.1, MemAvg: 20.2, DiskAvg: 30.3},
				},
			},
		},
	})
	if err != nil {
		t.Fatalf("render scan html: %v", err)
	}
	if !strings.Contains(out, "Kubernetes Cluster Report") {
		t.Fatalf("expected title in output")
	}
	if !strings.Contains(out, "<table>") {
		t.Fatalf("expected findings table in output")
	}
	if !strings.Contains(out, "Rightsizing at a Glance") {
		t.Fatalf("expected rightsizing block in output")
	}
	if !strings.Contains(out, "Open detailed AKS Automatic action plan") {
		t.Fatalf("expected automatic action plan link in output")
	}
	if !strings.Contains(out, `data-tab="aks"`) || !strings.Contains(out, "AKS Automatic Migration Readiness") {
		t.Fatalf("expected automatic readiness in AKS tab output")
	}
	if !strings.Contains(out, "card-expand-warning") {
		t.Fatalf("expected issue summary cards in output")
	}
	if !strings.Contains(out, "health-output") {
		t.Fatalf("expected expanded api health output in report")
	}
	if !strings.Contains(out, "Powered by") || !strings.Contains(out, "KubeBuddy Logo") {
		t.Fatalf("expected powershell-style header branding in output")
	}
	if !strings.Contains(out, "Node Conditions & Resources") {
		t.Fatalf("expected legacy node page heading in output")
	}
	if !strings.Contains(out, "Cluster Summary") {
		t.Fatalf("expected snapshot-backed summary section in output")
	}
	if !strings.Contains(out, "<code>az aks update --enable-private-cluster</code>") {
		t.Fatalf("expected AKS recommendation html in output")
	}
}

func TestActionPlanRenderer(t *testing.T) {
	out, err := (ActionPlanRenderer{}).Render("aks-test", &scan.AutomaticReadiness{
		Summary: scan.AutomaticSummary{
			ClusterName:    "aks-test",
			Status:         "ready_with_changes",
			StatusLabel:    "Ready With Changes",
			Message:        "Migration is possible, but changes are recommended.",
			BlockerCount:   0,
			WarningCount:   1,
			ActionPlanPath: "aks-plan.html",
		},
		ActionPlan: []scan.AutomaticActionItem{
			{
				Key:           "resource_requests",
				Title:         "Define container resource requests",
				Bucket:        "warning",
				Phase:         "fix_before_migration",
				Steps:         []string{"Add CPU and memory requests."},
				Checks:        []string{"WRK005"},
				TotalAffected: 3,
				Recommendations: []string{
					"Define requests before migration.",
				},
				URLs: []string{"https://example.com/doc"},
				AffectedResources: []scan.AutomaticAffectedResource{
					{Namespace: "default", Workload: "deployment/app", ObservedResource: "deployment/app"},
				},
			},
		},
		TargetClusterBuildNotes: []scan.AutomaticActionItem{
			{
				Key:           "aks_networking",
				Title:         "Align target cluster networking with AKS Automatic defaults",
				Bucket:        "alignment",
				Phase:         "target_cluster_build",
				Steps:         []string{"Plan Azure CNI Overlay with Cilium."},
				Checks:        []string{"AKSNET001"},
				TotalAffected: 1,
			},
		},
	})
	if err != nil {
		t.Fatalf("render action plan html: %v", err)
	}
	if !strings.Contains(out, "AKS Automatic Action Plan") {
		t.Fatalf("expected action plan title in output")
	}
	if !strings.Contains(out, "Target Cluster Build Notes") {
		t.Fatalf("expected target cluster build notes section in output")
	}
}
