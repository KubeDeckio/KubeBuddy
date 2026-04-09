package kubernetes

import (
	"encoding/json"
	"fmt"
	"sort"
	"strings"
	"time"

	prom "github.com/KubeDeckio/KubeBuddy/internal/collector/prometheus"
)

type ClusterDataOptions struct {
	ExcludeNamespaces        bool
	ExcludedNamespaces       []string
	IncludePrometheus        bool
	PrometheusURL            string
	PrometheusMode           string
	PrometheusBearerTokenEnv string
}

type ClusterData struct {
	Context               string
	KubernetesVersion     string
	Summary               Summary
	TopNodes              []string
	Nodes                 []map[string]any
	Pods                  []map[string]any
	AllPods               []map[string]any
	Namespaces            []map[string]any
	Events                []map[string]any
	AllEvents             []map[string]any
	Deployments           []map[string]any
	DaemonSets            []map[string]any
	StatefulSets          []map[string]any
	Jobs                  []map[string]any
	AllJobs               []map[string]any
	CronJobs              []map[string]any
	Services              []map[string]any
	Ingresses             []map[string]any
	ConfigMaps            []map[string]any
	Secrets               []map[string]any
	PersistentVolumes     []map[string]any
	PersistentClaims      []map[string]any
	NetworkPolicies       []map[string]any
	Roles                 []map[string]any
	RoleBindings          []map[string]any
	ClusterRoles          []map[string]any
	ClusterRoleBindings   []map[string]any
	ServiceAccounts       []map[string]any
	CustomResourcesByKind map[string][]map[string]any
	Metrics               *ClusterMetrics
}

type ClusterMetrics struct {
	Cluster MetricsCluster `json:"cluster"`
	Nodes   []NodeMetrics  `json:"nodes"`
}

type MetricsCluster struct {
	AvgCPUPercent float64       `json:"avgCpuPercent"`
	AvgMemPercent float64       `json:"avgMemPercent"`
	CPUTimeSeries []MetricPoint `json:"cpuTimeSeries"`
	MemTimeSeries []MetricPoint `json:"memTimeSeries"`
}

type NodeMetrics struct {
	NodeName   string        `json:"nodeName"`
	CPUAvg     float64       `json:"cpuAvg"`
	MemAvg     float64       `json:"memAvg"`
	DiskAvg    float64       `json:"diskAvg"`
	CPUSeries  []MetricPoint `json:"cpuSeries"`
	MemSeries  []MetricPoint `json:"memSeries"`
	DiskSeries []MetricPoint `json:"diskSeries"`
}

type MetricPoint struct {
	Timestamp string  `json:"timestamp"`
	Value     float64 `json:"value"`
}

func CollectClusterData(opts ClusterDataOptions) (ClusterData, error) {
	out := ClusterData{
		CustomResourcesByKind: map[string][]map[string]any{},
	}
	context, _ := kubectlOutput("config", "current-context")
	out.Context = strings.TrimSpace(context)
	out.KubernetesVersion = strings.TrimSpace(clusterKubernetesVersion())

	cache := map[string][]map[string]any{}
	loads := []struct {
		key string
		dst *[]map[string]any
	}{
		{"nodes", &out.Nodes},
		{"pods", &out.Pods},
		{"namespaces", &out.Namespaces},
		{"events", &out.Events},
		{"deployments", &out.Deployments},
		{"daemonsets", &out.DaemonSets},
		{"statefulsets", &out.StatefulSets},
		{"jobs", &out.Jobs},
		{"cronjobs", &out.CronJobs},
		{"services", &out.Services},
		{"ingresses", &out.Ingresses},
		{"configmaps", &out.ConfigMaps},
		{"secrets", &out.Secrets},
		{"persistentvolumes", &out.PersistentVolumes},
		{"persistentvolumeclaims", &out.PersistentClaims},
		{"networkpolicies", &out.NetworkPolicies},
		{"roles", &out.Roles},
		{"rolebindings", &out.RoleBindings},
		{"clusterroles", &out.ClusterRoles},
		{"clusterrolebindings", &out.ClusterRoleBindings},
		{"serviceaccounts", &out.ServiceAccounts},
	}
	for _, load := range loads {
		items, err := getItems(cache, load.key)
		if err != nil {
			if load.key == "ingresses" || load.key == "cronjobs" {
				continue
			}
			return ClusterData{}, fmt.Errorf("collect %s: %w", load.key, err)
		}
		*load.dst = append([]map[string]any(nil), items...)
	}
	out.AllPods = append([]map[string]any(nil), out.Pods...)
	out.AllEvents = append([]map[string]any(nil), out.Events...)
	out.AllJobs = append([]map[string]any(nil), out.Jobs...)

	topNodesOutput, topNodesErr := kubectlOutput("top", "nodes", "--no-headers")
	out.TopNodes = parseTopNodesOutput(topNodesOutput, topNodesErr)
	out.CustomResourcesByKind = collectCRDs()

	if opts.ExcludeNamespaces {
		excluded := excludedNamespaceSet(opts.ExcludedNamespaces)
		filterNamespacedCollections(&out, excluded)
	}

	out.Summary = summarizeClusterData(out)
	if opts.IncludePrometheus && strings.TrimSpace(opts.PrometheusURL) != "" {
		metrics, err := collectPrometheusMetrics(out.Nodes, opts)
		if err == nil {
			out.Metrics = metrics
		}
	}
	return out, nil
}

func summarizeClusterData(data ClusterData) Summary {
	return Summary{
		Context:      data.Context,
		Nodes:        len(data.Nodes),
		Namespaces:   len(data.Namespaces),
		Pods:         len(data.Pods),
		Deployments:  len(data.Deployments),
		StatefulSets: len(data.StatefulSets),
		DaemonSets:   len(data.DaemonSets),
		Services:     len(data.Services),
		Ingresses:    len(data.Ingresses),
	}
}

func collectCRDs() map[string][]map[string]any {
	output, err := kubectlOutput("get", "crds", "-o", "json")
	if err != nil {
		return map[string][]map[string]any{}
	}
	var payload struct {
		Items []map[string]any `json:"items"`
	}
	if err := json.Unmarshal([]byte(output), &payload); err != nil {
		return map[string][]map[string]any{}
	}
	out := map[string][]map[string]any{}
	for _, crd := range payload.Items {
		kind := stringifyLookup(crd, "spec.names.kind")
		plural := stringifyLookup(crd, "spec.names.plural")
		group := stringifyLookup(crd, "spec.group")
		version := ""
		for _, raw := range asSlice(mustResolve(crd, "spec.versions")) {
			item, ok := raw.(map[string]any)
			if !ok {
				continue
			}
			if asBool(item["served"]) && asBool(item["storage"]) {
				version = stringifyLookup(item, "name")
				break
			}
		}
		if version == "" {
			version = stringifyLookup(crd, "spec.versions.0.name")
		}
		if kind == "" || plural == "" || group == "" || version == "" {
			continue
		}
		output, err := kubectlOutput("get", plural, "-A", "-o", "json", "--api-version="+group+"/"+version)
		if err != nil {
			continue
		}
		var list struct {
			Items []map[string]any `json:"items"`
		}
		if err := json.Unmarshal([]byte(output), &list); err != nil {
			continue
		}
		out[kind] = list.Items
	}
	return out
}

func getItems(cache map[string][]map[string]any, resourceKind string) ([]map[string]any, error) {
	key := normalizedKind(resourceKind)
	if items, ok := cache[key]; ok {
		return items, nil
	}
	args := []string{"get", key}
	if !isClusterScoped(key) {
		args = append(args, "-A")
	}
	args = append(args, "-o", "json")
	output, err := kubectlOutput(args...)
	if err != nil {
		return nil, err
	}
	var response struct {
		Items []map[string]any `json:"items"`
	}
	if err := json.Unmarshal([]byte(output), &response); err != nil {
		return nil, err
	}
	cache[key] = response.Items
	return response.Items, nil
}

func collectPrometheusMetrics(nodes []map[string]any, opts ClusterDataOptions) (*ClusterMetrics, error) {
	client, err := prom.New(prom.Options{
		URL:               opts.PrometheusURL,
		Mode:              opts.PrometheusMode,
		BearerTokenEnv:    opts.PrometheusBearerTokenEnv,
		TimeoutSeconds:    60,
		RetryCount:        2,
		RetryDelaySeconds: 2,
	})
	if err != nil {
		return nil, err
	}
	end := time.Now().UTC()
	start := end.Add(-24 * time.Hour)
	queries := map[string]string{
		"NodeCpuUsagePercent":    `(1 - avg by(instance)(rate(node_cpu_seconds_total{mode="idle"}[5m]))) * 100`,
		"NodeMemoryUsagePercent": `(1 - (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes)) * 100`,
		"NodeDiskUsagePercent":   `100 * (1 - (sum by(instance)(node_filesystem_avail_bytes{fstype!~"tmpfs|aufs|squashfs", device!~"^$"}) / sum by(instance)(node_filesystem_size_bytes{fstype!~"tmpfs|aufs|squashfs", device!~"^$"})))`,
	}
	results := map[string][]prom.Result{}
	for key, query := range queries {
		series, err := client.QueryRange(query, start.Format(time.RFC3339), end.Format(time.RFC3339), "15m", 2, 2)
		if err != nil {
			return nil, err
		}
		results[key] = series
	}

	cluster := MetricsCluster{
		AvgCPUPercent: averageAcrossSeries(results["NodeCpuUsagePercent"]),
		AvgMemPercent: averageAcrossSeries(results["NodeMemoryUsagePercent"]),
		CPUTimeSeries: averageTimeSeries(results["NodeCpuUsagePercent"]),
		MemTimeSeries: averageTimeSeries(results["NodeMemoryUsagePercent"]),
	}
	nodeMetrics := make([]NodeMetrics, 0, len(nodes))
	for _, node := range nodes {
		name := stringifyLookup(node, "metadata.name")
		aliases := nodeAliasesForMetrics(node)
		cpuSeries := metricSeriesForNode(results["NodeCpuUsagePercent"], aliases)
		memSeries := metricSeriesForNode(results["NodeMemoryUsagePercent"], aliases)
		diskSeries := metricSeriesForNode(results["NodeDiskUsagePercent"], aliases)
		nodeMetrics = append(nodeMetrics, NodeMetrics{
			NodeName:   name,
			CPUAvg:     averageMetricPoints(cpuSeries),
			MemAvg:     averageMetricPoints(memSeries),
			DiskAvg:    averageMetricPoints(diskSeries),
			CPUSeries:  cpuSeries,
			MemSeries:  memSeries,
			DiskSeries: diskSeries,
		})
	}
	sort.Slice(nodeMetrics, func(i, j int) bool { return nodeMetrics[i].NodeName < nodeMetrics[j].NodeName })
	return &ClusterMetrics{Cluster: cluster, Nodes: nodeMetrics}, nil
}

func clusterKubernetesVersion() string {
	output, err := kubectlOutput("version", "-o", "json")
	if err != nil {
		return ""
	}
	var payload struct {
		ServerVersion struct {
			GitVersion string `json:"gitVersion"`
		} `json:"serverVersion"`
	}
	if err := json.Unmarshal([]byte(output), &payload); err != nil {
		return ""
	}
	return strings.TrimSpace(payload.ServerVersion.GitVersion)
}

func averageAcrossSeries(series []prom.Result) float64 {
	var total float64
	var count int
	for _, entry := range series {
		for _, point := range entry.Values {
			if len(point) < 2 {
				continue
			}
			total += asFloat64(point[1])
			count++
		}
	}
	if count == 0 {
		return 0
	}
	return round2(total / float64(count))
}

func averageTimeSeries(series []prom.Result) []MetricPoint {
	grouped := map[string][]float64{}
	for _, entry := range series {
		for _, point := range entry.Values {
			if len(point) < 2 {
				continue
			}
			ts := fmt.Sprintf("%.0f", asFloat64(point[0])*1000)
			grouped[ts] = append(grouped[ts], asFloat64(point[1]))
		}
	}
	var keys []string
	for key := range grouped {
		keys = append(keys, key)
	}
	sort.Strings(keys)
	out := make([]MetricPoint, 0, len(keys))
	for _, key := range keys {
		out = append(out, MetricPoint{Timestamp: key, Value: round2(avgFloats(grouped[key]))})
	}
	return out
}

func metricSeriesForNode(series []prom.Result, aliases []string) []MetricPoint {
	for _, alias := range aliases {
		for _, entry := range series {
			instance := strings.ToLower(strings.TrimSpace(entry.Metric["instance"]))
			host := strings.Split(instance, ":")[0]
			if alias == host || alias == strings.Split(host, ".")[0] || strings.Contains(host, alias) {
				return toMetricPoints(entry.Values)
			}
		}
	}
	return nil
}

func toMetricPoints(values [][]any) []MetricPoint {
	out := make([]MetricPoint, 0, len(values))
	for _, value := range values {
		if len(value) < 2 {
			continue
		}
		out = append(out, MetricPoint{
			Timestamp: fmt.Sprintf("%.0f", asFloat64(value[0])*1000),
			Value:     round2(asFloat64(value[1])),
		})
	}
	return out
}

func averageMetricPoints(points []MetricPoint) float64 {
	if len(points) == 0 {
		return 0
	}
	values := make([]float64, 0, len(points))
	for _, point := range points {
		values = append(values, point.Value)
	}
	return round2(avgFloats(values))
}

func avgFloats(values []float64) float64 {
	if len(values) == 0 {
		return 0
	}
	var total float64
	for _, value := range values {
		total += value
	}
	return total / float64(len(values))
}

func asFloat64(value any) float64 {
	switch v := value.(type) {
	case float64:
		return v
	case string:
		var out float64
		fmt.Sscan(v, &out)
		return out
	default:
		var out float64
		fmt.Sscan(fmt.Sprint(v), &out)
		return out
	}
}

func round2(value float64) float64 {
	return float64(int(value*100+0.5)) / 100
}

func parseTopNodesOutput(output string, err error) []string {
	if err != nil {
		return nil
	}
	lines := strings.Split(strings.TrimSpace(output), "\n")
	out := make([]string, 0, len(lines))
	for _, line := range lines {
		line = strings.TrimSpace(line)
		if line != "" {
			out = append(out, line)
		}
	}
	return out
}

func excludedNamespaceSet(extra []string) map[string]struct{} {
	names := append([]string{
		"kube-system", "kube-public", "kube-node-lease",
		"local-path-storage", "kube-flannel",
		"tigera-operator", "calico-system", "coredns", "aks-istio-system", "gatekeeper-system",
	}, extra...)
	out := map[string]struct{}{}
	for _, ns := range names {
		ns = strings.ToLower(strings.TrimSpace(ns))
		if ns != "" {
			out[ns] = struct{}{}
		}
	}
	return out
}

func filterNamespacedCollections(data *ClusterData, excluded map[string]struct{}) {
	filter := func(items []map[string]any) []map[string]any {
		out := make([]map[string]any, 0, len(items))
		for _, item := range items {
			ns := strings.ToLower(strings.TrimSpace(stringifyLookup(item, "metadata.namespace")))
			if ns != "" {
				if _, ok := excluded[ns]; ok {
					continue
				}
			}
			out = append(out, item)
		}
		return out
	}
	data.Pods = filter(data.Pods)
	data.Events = filter(data.Events)
	data.Deployments = filter(data.Deployments)
	data.DaemonSets = filter(data.DaemonSets)
	data.StatefulSets = filter(data.StatefulSets)
	data.Jobs = filter(data.Jobs)
	data.CronJobs = filter(data.CronJobs)
	data.Services = filter(data.Services)
	data.Ingresses = filter(data.Ingresses)
	data.ConfigMaps = filter(data.ConfigMaps)
	data.Secrets = filter(data.Secrets)
	data.PersistentClaims = filter(data.PersistentClaims)
	data.NetworkPolicies = filter(data.NetworkPolicies)
	data.Roles = filter(data.Roles)
	data.RoleBindings = filter(data.RoleBindings)
	data.ServiceAccounts = filter(data.ServiceAccounts)
	for kind, items := range data.CustomResourcesByKind {
		data.CustomResourcesByKind[kind] = filter(items)
	}
}

func nodeAliasesForMetrics(node map[string]any) []string {
	aliases := []string{strings.ToLower(strings.TrimSpace(stringifyLookup(node, "metadata.name")))}
	for _, raw := range asSlice(mustResolve(node, "status.addresses")) {
		item, ok := raw.(map[string]any)
		if !ok {
			continue
		}
		address := strings.ToLower(strings.TrimSpace(stringifyLookup(item, "address")))
		if address == "" {
			continue
		}
		host := strings.Split(address, ":")[0]
		aliases = append(aliases, host, strings.Split(host, ".")[0])
	}
	return uniqueStrings(aliases)
}

func uniqueStrings(values []string) []string {
	seen := map[string]struct{}{}
	out := make([]string, 0, len(values))
	for _, value := range values {
		value = strings.TrimSpace(value)
		if value == "" {
			continue
		}
		if _, ok := seen[value]; ok {
			continue
		}
		seen[value] = struct{}{}
		out = append(out, value)
	}
	return out
}

func normalizedKind(kind string) string {
	switch strings.ToLower(strings.TrimSpace(kind)) {
	case "persistentvolume":
		return "persistentvolumes"
	case "persistentvolumeclaim":
		return "persistentvolumeclaims"
	case "storageclass":
		return "storageclasses"
	case "service":
		return "services"
	case "pod":
		return "pods"
	case "serviceaccount":
		return "serviceaccounts"
	case "node":
		return "nodes"
	case "namespace", "namespaces":
		return "namespaces"
	case "ingress":
		return "ingresses"
	default:
		return strings.ToLower(strings.TrimSpace(kind))
	}
}

func isClusterScoped(kind string) bool {
	switch kind {
	case "nodes", "namespaces", "persistentvolumes", "storageclasses", "clusterroles", "clusterrolebindings":
		return true
	default:
		return false
	}
}

func mustResolve(item map[string]any, path string) any {
	current := any(item)
	for _, part := range strings.Split(path, ".") {
		switch node := current.(type) {
		case map[string]any:
			current = node[part]
		default:
			return nil
		}
	}
	return current
}

func asSlice(value any) []any {
	switch v := value.(type) {
	case []any:
		return v
	case []map[string]any:
		out := make([]any, 0, len(v))
		for _, item := range v {
			out = append(out, item)
		}
		return out
	default:
		return nil
	}
}

func asBool(value any) bool {
	switch v := value.(type) {
	case bool:
		return v
	case string:
		return strings.EqualFold(v, "true")
	default:
		return false
	}
}

func stringifyLookup(item map[string]any, path string) string {
	value := mustResolve(item, path)
	switch v := value.(type) {
	case string:
		return v
	default:
		return fmt.Sprint(v)
	}
}
