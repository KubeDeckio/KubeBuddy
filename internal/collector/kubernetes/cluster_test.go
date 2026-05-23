package kubernetes

import (
	"fmt"
	"testing"

	prom "github.com/KubeDeckio/KubeBuddy/internal/collector/prometheus"
)

func TestCollectPrometheusMetricsWithQueryKeepsPartialResults(t *testing.T) {
	nodes := []map[string]any{
		{
			"metadata": map[string]any{
				"name": "gke-node-1",
			},
			"status": map[string]any{
				"allocatable": map[string]any{
					"cpu":    "4",
					"memory": "8388608Ki",
				},
			},
		},
	}

	queries := map[string][]prom.Result{
		`sum by(node)(rate(container_cpu_usage_seconds_total{container!="",pod!=""}[5m])) / on(node) machine_cpu_cores * 100`: {
			{
				Metric: map[string]string{"node": "gke-node-1"},
				Values: [][]any{{float64(1710000000), "25"}, {float64(1710000900), "35"}},
			},
		},
		`sum by(node)(container_memory_working_set_bytes{container!="",pod!=""}) / on(node) machine_memory_bytes * 100`: {
			{
				Metric: map[string]string{"node": "gke-node-1"},
				Values: [][]any{{float64(1710000000), "40"}, {float64(1710000900), "50"}},
			},
		},
	}

	queryRange := func(query, start, end, step string, retries int, retryDelaySeconds int) ([]prom.Result, error) {
		switch query {
		case `(1 - avg by(instance)(rate(node_cpu_seconds_total{mode="idle"}[5m]))) * 100`,
			`(1 - avg by(instance)(rate(kubernetes_io:anthos_node_cpu_seconds_total{mode="idle"}[5m]))) * 100`,
			`(1 - (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes)) * 100`,
			`(1 - (kubernetes_io:anthos_node_memory_MemAvailable_bytes / kubernetes_io:anthos_node_memory_MemTotal_bytes)) * 100`,
			`100 * (1 - (sum by(instance) (node_filesystem_avail_bytes{fstype!~"tmpfs|aufs|squashfs", device!~"^$"}) / sum by(instance) (node_filesystem_size_bytes{fstype!~"tmpfs|aufs|squashfs", device!~"^$"})))`,
			`100 * (1 - (sum by(instance) (kubernetes_io:anthos_node_filesystem_avail_bytes{fstype!~"tmpfs|aufs|squashfs", device!~"^$"}) / sum by(instance) (kubernetes_io:anthos_node_filesystem_size_bytes{fstype!~"tmpfs|aufs|squashfs", device!~"^$"})))`:
			return nil, fmt.Errorf("metric unavailable")
		}
		return queries[query], nil
	}

	metrics, err := collectPrometheusMetricsWithQuery(nodes, queryRange)
	if err != nil {
		t.Fatalf("collectPrometheusMetricsWithQuery returned error: %v", err)
	}
	if metrics == nil {
		t.Fatal("expected metrics, got nil")
	}
	if got := metrics.Cluster.AvgCPUPercent; got != 30 {
		t.Fatalf("expected avg CPU 30, got %v", got)
	}
	if got := metrics.Cluster.AvgMemPercent; got != 45 {
		t.Fatalf("expected avg memory 45, got %v", got)
	}
	if len(metrics.Nodes) != 1 {
		t.Fatalf("expected 1 node metrics entry, got %d", len(metrics.Nodes))
	}
	if got := metrics.Nodes[0].CPUAvg; got != 30 {
		t.Fatalf("expected node CPU 30, got %v", got)
	}
	if got := metrics.Nodes[0].MemAvg; got != 45 {
		t.Fatalf("expected node memory 45, got %v", got)
	}
	if got := metrics.Nodes[0].DiskAvg; got != 0 {
		t.Fatalf("expected node disk 0 when disk metrics are unavailable, got %v", got)
	}
	if len(metrics.Nodes[0].DiskSeries) != 0 {
		t.Fatalf("expected no disk series when disk metrics are unavailable, got %d points", len(metrics.Nodes[0].DiskSeries))
	}
}

func TestExcludedNamespaceSetUsesProvidedEffectiveList(t *testing.T) {
	t.Helper()

	excluded := excludedNamespaceSet([]string{"custom-ns"})
	if _, ok := excluded["custom-ns"]; !ok {
		t.Fatalf("expected custom namespace to be excluded: %#v", excluded)
	}
	if _, ok := excluded["kube-system"]; ok {
		t.Fatalf("collector should not re-add default namespaces after config resolution: %#v", excluded)
	}
}
