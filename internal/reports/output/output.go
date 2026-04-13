package output

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"os/exec"
	"sort"
	"strconv"
	"strings"
	"time"

	"github.com/KubeDeckio/KubeBuddy/internal/collector/kubernetes"
	reporthtml "github.com/KubeDeckio/KubeBuddy/internal/reports/html"
	"github.com/KubeDeckio/KubeBuddy/internal/scan"
)

type Mode string

const (
	ModeText Mode = "text"
	ModeJSON Mode = "json"
	ModeCSV  Mode = "csv"
	ModeHTML Mode = "html"
)

type Metadata struct {
	ClusterName              string
	KubernetesVersion        string
	GeneratedAt              string
	ExcludeNamespacesEnabled bool
	ExcludedNamespaces       []string
	PrometheusURL            string
	PrometheusMode           string
	PrometheusBearerTokenEnv string
	AKS                      *AKSMetadata
	Metrics                  any
	Snapshot                 *kubernetes.ClusterData
}

type AKSMetadata struct {
	SubscriptionID string `json:"subscriptionId,omitempty"`
	ResourceGroup  string `json:"resourceGroup,omitempty"`
	ClusterName    string `json:"clusterName,omitempty"`
}

type jsonEnvelope struct {
	Metadata              jsonMetadata               `json:"metadata"`
	Checks                map[string]jsonCheckResult `json:"checks"`
	AKSAutomaticReadiness *scan.AutomaticReadiness   `json:"aksAutomaticReadiness,omitempty"`
	Metrics               any                        `json:"metrics"`
}

type jsonMetadata struct {
	ClusterName              string                 `json:"clusterName"`
	KubernetesVersion        string                 `json:"kubernetesVersion,omitempty"`
	GeneratedAt              string                 `json:"generatedAt"`
	ExcludeNamespacesEnabled bool                   `json:"excludeNamespacesEnabled"`
	ExcludedNamespaces       []string               `json:"excludedNamespaces"`
	PrometheusURL            string                 `json:"prometheusUrl,omitempty"`
	AKS                      *AKSMetadata           `json:"aks,omitempty"`
	AKSAutomaticSummary      *scan.AutomaticSummary `json:"aksAutomaticSummary,omitempty"`
	Score                    float64                `json:"score"`
}

type jsonCheckResult struct {
	ID                         string  `json:"ID"`
	Name                       string  `json:"Name"`
	Category                   string  `json:"Category"`
	Section                    string  `json:"Section,omitempty"`
	Severity                   string  `json:"Severity"`
	Weight                     int     `json:"Weight,omitempty"`
	Description                string  `json:"Description,omitempty"`
	Recommendation             any     `json:"Recommendation,omitempty"`
	URL                        string  `json:"URL,omitempty"`
	ResourceKind               string  `json:"ResourceKind,omitempty"`
	AutomaticRelevance         any     `json:"AutomaticRelevance"`
	AutomaticScope             any     `json:"AutomaticScope"`
	AutomaticReason            any     `json:"AutomaticReason"`
	AutomaticAdmissionBehavior any     `json:"AutomaticAdmissionBehavior"`
	AutomaticMutationOutcome   any     `json:"AutomaticMutationOutcome"`
	Total                      int     `json:"Total"`
	Message                    string  `json:"Message,omitempty"`
	Items                      any     `json:"Items"`
	Status                     string  `json:"Status,omitempty"`
	ObservedValue              string  `json:"ObservedValue,omitempty"`
	FailMessage                *string `json:"FailMessage,omitempty"`
	SummaryMessage             string  `json:"SummaryMessage,omitempty"`
}

type jsonRecommendation struct {
	Text         string   `json:"text,omitempty"`
	HTML         string   `json:"html,omitempty"`
	SpeechBubble []string `json:"SpeechBubble,omitempty"`
}

func WriteScanResult(w io.Writer, result scan.Result, mode Mode) error {
	return WriteScanResultWithMetadata(w, result, mode, Metadata{})
}

func WriteScanResultWithMetadata(w io.Writer, result scan.Result, mode Mode, metadata Metadata) error {
	switch mode {
	case "", ModeText:
		return writeText(w, result, metadata)
	case ModeJSON:
		return writeJSON(w, result, metadata)
	case ModeCSV:
		return writeCSV(w, result, metadata)
	case ModeHTML:
		return writeHTMLWithMetadata(w, result, metadata)
	default:
		return fmt.Errorf("unsupported output mode %q", mode)
	}
}

func writeJSON(w io.Writer, result scan.Result, metadata Metadata) error {
	enc := json.NewEncoder(w)
	enc.SetIndent("", "  ")
	return enc.Encode(buildJSONEnvelope(result, metadata))
}

func buildJSONEnvelope(result scan.Result, metadata Metadata) jsonEnvelope {
	resolved := resolveMetadata(metadata, result)
	checks := make(map[string]jsonCheckResult, len(result.Checks))
	for _, check := range orderedReportChecks(result.Checks) {
		checks[check.ID] = buildLegacyCheckResult(check, resolved.Metrics)
	}

	envelope := jsonEnvelope{
		Metadata: jsonMetadata{
			ClusterName:              resolved.ClusterName,
			KubernetesVersion:        resolved.KubernetesVersion,
			GeneratedAt:              resolved.GeneratedAt,
			ExcludeNamespacesEnabled: resolved.ExcludeNamespacesEnabled,
			ExcludedNamespaces:       append([]string(nil), resolved.ExcludedNamespaces...),
			PrometheusURL:            resolved.PrometheusURL,
			AKS:                      resolved.AKS,
			Score:                    clusterHealthScore(result.Checks),
		},
		Checks:                checks,
		AKSAutomaticReadiness: result.AutomaticReadiness,
		Metrics:               resolved.Metrics,
	}
	if result.AutomaticReadiness != nil {
		summary := result.AutomaticReadiness.Summary
		envelope.Metadata.AKSAutomaticSummary = &summary
	}
	return envelope
}

func resolveMetadata(metadata Metadata, result scan.Result) Metadata {
	resolved := metadata
	if strings.TrimSpace(resolved.GeneratedAt) == "" {
		resolved.GeneratedAt = time.Now().UTC().Format("2006-01-02T15:04:05Z")
	}
	if strings.TrimSpace(resolved.ClusterName) == "" {
		resolved.ClusterName = strings.TrimSpace(kubectlText("config", "current-context"))
	}
	if strings.TrimSpace(resolved.KubernetesVersion) == "" {
		resolved.KubernetesVersion = strings.TrimSpace(kubernetesVersion())
	}
	if result.AutomaticReadiness != nil {
		if strings.TrimSpace(resolved.ClusterName) == "" {
			resolved.ClusterName = strings.TrimSpace(result.AutomaticReadiness.Summary.ClusterName)
		}
		if resolved.AKS == nil {
			resolved.AKS = &AKSMetadata{ClusterName: result.AutomaticReadiness.Summary.ClusterName}
		} else if strings.TrimSpace(resolved.AKS.ClusterName) == "" {
			resolved.AKS.ClusterName = result.AutomaticReadiness.Summary.ClusterName
		}
	}
	if resolved.ExcludedNamespaces == nil {
		if resolved.ExcludeNamespacesEnabled {
			resolved.ExcludedNamespaces = defaultExcludedNamespaces()
		} else {
			resolved.ExcludedNamespaces = []string{}
		}
	}
	return resolved
}

func buildLegacyCheckResult(check scan.CheckResult, metrics any) jsonCheckResult {
	total := check.Total
	if check.ID == "NODE002" && total == 0 {
		total = legacyNODE002IssueCount(metrics)
	}
	out := jsonCheckResult{
		ID:                         check.ID,
		Name:                       check.Name,
		Category:                   check.Category,
		Section:                    check.Section,
		Severity:                   legacySeverity(check),
		Weight:                     check.Weight,
		Description:                check.Description,
		Recommendation:             recommendationPayload(check),
		URL:                        check.URL,
		ResourceKind:               check.ResourceKind,
		AutomaticRelevance:         nilIfEmpty(check.AutomaticRelevance),
		AutomaticScope:             nilIfEmpty(check.AutomaticScope),
		AutomaticReason:            nilIfEmpty(check.AutomaticReason),
		AutomaticAdmissionBehavior: nilIfEmpty(check.AutomaticAdmissionBehavior),
		AutomaticMutationOutcome:   nilIfEmpty(check.AutomaticMutationOutcome),
		Total:                      total,
		Items:                      legacyItems(check, metrics),
	}
	if strings.HasPrefix(check.ID, "AKS") {
		out.ResourceKind = ""
	}
	if strings.HasPrefix(check.ID, "AKS") {
		if check.Total == 0 {
			out.Status = "✅ PASS"
			out.ObservedValue = strings.TrimSpace(firstNonEmpty(check.ObservedValue, passObservedValue(check)))
			out.FailMessage = stringPtr(check.FailMessageText)
			out.Recommendation = check.Name + " is enabled."
		} else {
			out.Status = "❌ FAIL"
			out.ObservedValue = strings.TrimSpace(firstNonEmpty(check.ObservedValue, firstObservedValue(check)))
			out.FailMessage = stringPtr(strings.TrimSpace(firstNonEmpty(check.FailMessageText, firstFailMessage(check))))
		}
	}
	if check.Total == 0 {
		out.Message = checkMessage(check)
	}
	if strings.HasPrefix(check.ID, "PROM") && len(check.Items) == 1 && check.Items[0].Resource == "" && check.Items[0].Namespace == "" {
		out.SummaryMessage = strings.TrimSpace(check.Items[0].Message)
	}
	if check.SummaryMessage != "" {
		out.SummaryMessage = check.SummaryMessage
	}
	return out
}

func recommendationPayload(check scan.CheckResult) any {
	if strings.TrimSpace(check.Recommendation) == "" && strings.TrimSpace(check.RecommendationHTML) == "" {
		return nil
	}
	if strings.HasPrefix(check.ID, "AKS") {
		return strings.TrimSpace(check.Recommendation)
	}
	return &jsonRecommendation{
		Text: strings.TrimSpace(check.Recommendation),
		HTML: strings.TrimSpace(check.RecommendationHTML),
	}
}

func legacyItems(check scan.CheckResult, metrics any) any {
	if check.LegacyItems != nil {
		return check.LegacyItems
	}
	switch check.ID {
	case "NODE001":
		return legacyNODE001Items(check)
	case "NODE002":
		return legacyNODE002Items(metrics)
	case "NODE003":
		return legacyNODE003Items(check)
	case "PROM003":
		return legacyPROM003Items(check)
	case "NS001":
		return legacyNS001Items(check)
	case "NS002":
		return legacySimpleNamespaceIssueItems(check)
	case "NS003":
		return legacySimpleNamespaceIssueItems(check)
	case "RBAC002":
		return legacyRBACItems(check)
	case "SEC007":
		return legacySEC007Items(check)
	}
	if len(check.Items) == 0 {
		if strings.HasPrefix(check.ID, "AKS") {
			return nil
		}
		return []map[string]any{}
	}
	items := make([]map[string]any, 0, len(check.Items))
	for _, item := range check.Items {
		entry := map[string]any{
			"Namespace": item.Namespace,
		}
		if item.Resource != "" {
			entry["Resource"] = item.Resource
		}
		if item.Value != "" {
			entry["Value"] = item.Value
		}
		if item.Message != "" {
			entry["Message"] = item.Message
		}
		items = append(items, entry)
	}
	if strings.HasPrefix(check.ID, "AKS") && len(items) == 1 {
		return map[string]any{
			"Resource": check.Name,
			"Issue":    strings.TrimSpace(firstNonEmpty(check.Recommendation, firstFailMessage(check))),
		}
	}
	if strings.HasPrefix(check.ID, "PROM") && len(items) == 1 && items[0]["Resource"] == nil {
		status := "Insufficient Prometheus history"
		if msg := firstFailMessage(check); msg != "" {
			status = msg
		}
		return map[string]any{
			"Status":  status,
			"Message": firstFailMessage(check),
		}
	}
	return items
}

func firstNonEmpty(values ...string) string {
	for _, value := range values {
		value = strings.TrimSpace(value)
		if value != "" {
			return value
		}
	}
	return ""
}

func stringPtr(value string) *string {
	return &value
}

func legacyPROM003Items(check scan.CheckResult) any {
	items := make([]map[string]any, 0, len(check.Items))
	for _, item := range check.Items {
		name := strings.TrimPrefix(item.Resource, "pod/")
		items = append(items, map[string]any{
			"MetricLabels": "pod: " + name,
			"Average":      formatLegacyAverage(item.Value),
			"Message":      item.Message,
		})
	}
	return items
}

func legacyNODE001Items(check scan.CheckResult) any {
	names := clusterNodeNames()
	items := make([]map[string]any, 0, len(names))
	for _, name := range names {
		status := "✅ Healthy"
		issues := "None"
		for _, finding := range check.Items {
			if strings.TrimPrefix(finding.Resource, "node/") == name {
				if strings.TrimSpace(finding.Message) != "" {
					status = finding.Message
				}
				if strings.TrimSpace(finding.Value) != "" {
					issues = finding.Value
				}
				break
			}
		}
		items = append(items, map[string]any{
			"Node":   name,
			"Status": status,
			"Issues": issues,
		})
	}
	return items
}

func legacyNODE002Items(metrics any) any {
	items := make([]map[string]any, 0)
	for _, metric := range extractNodeMetrics(metrics) {
		cpuAvg := nodeMetricFloat(metric["cpuAvg"])
		memAvg := nodeMetricFloat(metric["memAvg"])
		diskAvg := nodeMetricFloat(metric["diskAvg"])
		cpuTotal := nodeMetricInt(metric["cpuTotal"])
		memTotal := nodeMetricInt(metric["memTotal"])
		cpuUsed := int(float64(cpuTotal) * cpuAvg / 100)
		memUsed := int(float64(memTotal) * memAvg / 100)
		items = append(items, map[string]any{
			"Node":           metric["nodeName"],
			"CPU Status":     legacyPressureStatus(cpuAvg, 50, 75),
			"CPU %":          fmt.Sprintf("%.2f%%", cpuAvg),
			"CPU Used":       fmt.Sprintf("%d mC", cpuUsed),
			"CPU Total":      fmt.Sprintf("%d mC", cpuTotal),
			"Mem Status":     legacyPressureStatus(memAvg, 50, 75),
			"Mem %":          fmt.Sprintf("%.2f%%", memAvg),
			"Mem Used":       fmt.Sprintf("%d Mi", memUsed),
			"Mem Total":      fmt.Sprintf("%d Mi", memTotal),
			"Disk %":         fmt.Sprintf("%.2f%%", diskAvg),
			"Disk Status":    legacyPressureStatus(diskAvg, 60, 80),
			"UsedPrometheus": true,
		})
	}
	return items
}

func legacyNODE002IssueCount(metrics any) int {
	count := 0
	for _, metric := range extractNodeMetrics(metrics) {
		cpuAvg := nodeMetricFloat(metric["cpuAvg"])
		memAvg := nodeMetricFloat(metric["memAvg"])
		diskAvg := nodeMetricFloat(metric["diskAvg"])
		if cpuAvg > 50 {
			count++
		}
		if memAvg > 50 {
			count++
		}
		if diskAvg > 60 {
			count++
		}
	}
	return count
}

func legacyPressureStatus(value, warn, crit float64) string {
	switch {
	case value > crit:
		return "🔴 Critical"
	case value > warn:
		return "🟡 Warning"
	default:
		return "✅ Normal"
	}
}

func legacyNODE003Items(check scan.CheckResult) any {
	items := make([]map[string]any, 0, len(check.Items))
	for _, item := range check.Items {
		items = append(items, map[string]any{
			"Node":       strings.TrimPrefix(item.Resource, "node/"),
			"Percentage": item.Value,
			"Threshold":  "80%",
			"Status":     item.Message,
		})
	}
	return items
}

func legacyNS001Items(check scan.CheckResult) any {
	items := make([]map[string]any, 0, len(check.Items))
	for _, item := range check.Items {
		items = append(items, map[string]any{
			"Namespace": item.Namespace,
			"Status":    item.Value,
			"Issue":     item.Message,
		})
	}
	return items
}

func legacySimpleNamespaceIssueItems(check scan.CheckResult) any {
	items := make([]map[string]any, 0, len(check.Items))
	for _, item := range check.Items {
		items = append(items, map[string]any{
			"Namespace": item.Namespace,
			"Issue":     item.Message,
		})
	}
	return items
}

func legacyRBACItems(check scan.CheckResult) any {
	items := make([]map[string]any, 0, len(check.Items))
	for _, item := range check.Items {
		resource := item.Resource
		if strings.HasPrefix(resource, "clusterrolebinding/") {
			resource = "ClusterRoleBinding/" + strings.TrimPrefix(resource, "clusterrolebinding/")
		}
		items = append(items, map[string]any{
			"Namespace": strings.ReplaceAll(item.Namespace, "🌍 Cluster-Wide", "🌍 Cluster-Wide"),
			"Resource":  resource,
			"Value":     item.Value,
			"Message":   item.Message,
		})
	}
	return items
}

func legacySEC007Items(check scan.CheckResult) any {
	if len(check.Items) == 0 {
		return nil
	}
	item := check.Items[0]
	return map[string]any{
		"Namespace": item.Namespace,
		"Warn":      "N/A",
		"Audit":     "N/A",
		"Issue":     item.Message,
	}
}

func clusterNodeNames() []string {
	output := kubectlText("get", "nodes", "-o", "json")
	if strings.TrimSpace(output) == "" {
		return nil
	}
	var payload struct {
		Items []map[string]any `json:"items"`
	}
	if err := json.Unmarshal([]byte(output), &payload); err != nil {
		return nil
	}
	names := make([]string, 0, len(payload.Items))
	for _, item := range payload.Items {
		if name := strings.TrimSpace(fmt.Sprint(mustLookup(item, "metadata", "name"))); name != "" {
			names = append(names, name)
		}
	}
	return names
}

func extractNodeMetrics(metrics any) []map[string]any {
	if metrics == nil {
		return nil
	}
	raw, err := json.Marshal(metrics)
	if err != nil {
		return nil
	}
	var payload map[string]any
	if err := json.Unmarshal(raw, &payload); err != nil {
		return nil
	}
	nodes, _ := payload["nodes"].([]any)
	out := make([]map[string]any, 0, len(nodes))
	for _, item := range nodes {
		if metric, ok := item.(map[string]any); ok {
			out = append(out, metric)
		}
	}
	return out
}

func nodeMetricFloat(value any) float64 {
	switch raw := value.(type) {
	case float64:
		return raw
	case float32:
		return float64(raw)
	case int:
		return float64(raw)
	case int64:
		return float64(raw)
	case json.Number:
		parsed, _ := raw.Float64()
		return parsed
	default:
		var parsed float64
		fmt.Sscan(fmt.Sprint(value), &parsed)
		return parsed
	}
}

func nodeMetricInt(value any) int {
	switch raw := value.(type) {
	case int:
		return raw
	case int64:
		return int(raw)
	case float64:
		return int(raw)
	case json.Number:
		parsed, _ := raw.Int64()
		return int(parsed)
	default:
		var parsed int
		fmt.Sscan(fmt.Sprint(value), &parsed)
		return parsed
	}
}

func mustLookup(item map[string]any, keys ...string) any {
	current := any(item)
	for _, key := range keys {
		obj, ok := current.(map[string]any)
		if !ok {
			return nil
		}
		current = obj[key]
	}
	return current
}

func formatLegacyAverage(raw string) string {
	raw = strings.TrimSpace(raw)
	if raw == "" {
		return raw
	}
	var value float64
	if _, err := fmt.Sscan(raw, &value); err != nil {
		return raw
	}
	return formatWithCommas(round4(value))
}

func round4(value float64) float64 {
	return float64(int(value*10000+0.5)) / 10000
}

func formatWithCommas(value float64) string {
	base := fmt.Sprintf("%.4f", value)
	parts := strings.SplitN(base, ".", 2)
	intPart := parts[0]
	frac := ""
	if len(parts) == 2 {
		frac = "." + parts[1]
	}
	sign := ""
	if strings.HasPrefix(intPart, "-") {
		sign = "-"
		intPart = strings.TrimPrefix(intPart, "-")
	}
	for i := len(intPart) - 3; i > 0; i -= 3 {
		intPart = intPart[:i] + "," + intPart[i:]
	}
	return sign + intPart + frac
}

func legacySeverity(check scan.CheckResult) string {
	if strings.HasPrefix(check.ID, "AKS") {
		return check.Severity
	}
	switch strings.ToLower(strings.TrimSpace(check.Severity)) {
	case "high", "critical":
		return "critical"
	case "medium", "warning":
		return "warning"
	case "low", "info":
		return "info"
	default:
		return strings.ToLower(strings.TrimSpace(check.Severity))
	}
}

func firstObservedValue(check scan.CheckResult) string {
	if len(check.Items) == 0 {
		return ""
	}
	if strings.HasPrefix(check.ID, "AKS") {
		return check.Items[0].Value
	}
	return check.Items[0].Value
}

func passObservedValue(check scan.CheckResult) string {
	switch {
	case strings.HasPrefix(check.ID, "AKS"):
		return "true"
	default:
		return ""
	}
}

func firstFailMessage(check scan.CheckResult) string {
	if len(check.Items) == 0 {
		return ""
	}
	return strings.TrimSpace(check.Items[0].Message)
}

func nilIfEmpty(value string) any {
	value = strings.TrimSpace(value)
	if value == "" {
		return nil
	}
	return value
}

func kubernetesVersion() string {
	output := kubectlText("version", "-o", "json")
	if strings.TrimSpace(output) == "" {
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

func kubectlText(args ...string) string {
	cmd := exec.Command("kubectl", args...)
	output, err := cmd.Output()
	if err != nil {
		return ""
	}
	return string(output)
}

func clusterHealthScore(checks []scan.CheckResult) float64 {
	var maxWeight float64
	var earned float64
	for _, check := range checks {
		if check.Weight <= 0 {
			continue
		}
		maxWeight += float64(check.Weight)
		earned += float64(check.Weight) / float64(check.Total+1)
	}
	if maxWeight == 0 {
		return 0
	}
	return float64(int(((earned/maxWeight)*100)+0.5))
}

func round2(value float64) float64 {
	return float64(int(value*100+0.5)) / 100
}

func checkMessage(check scan.CheckResult) string {
	if check.Total == 0 {
		if strings.TrimSpace(check.Name) == "" {
			return "No issues detected."
		}
		return "No issues detected for " + check.Name + "."
	}
	if len(check.Items) > 0 && strings.TrimSpace(check.Items[0].Message) != "" {
		return strings.TrimSpace(check.Items[0].Message)
	}
	return strings.TrimSpace(check.Description)
}

func defaultExcludedNamespaces() []string {
	return []string{
		"kube-system", "kube-public", "kube-node-lease",
		"local-path-storage", "kube-flannel",
		"tigera-operator", "calico-system", "coredns", "aks-istio-system", "gatekeeper-system",
	}
}

func writeText(w io.Writer, result scan.Result, metadata Metadata) error {
	resolved := resolveMetadata(metadata, result)
	writeLine := func(format string, args ...any) error {
		_, err := fmt.Fprintf(w, format+"\n", args...)
		return err
	}

	if err := writeLine("--- Kubernetes Cluster Report ---"); err != nil {
		return err
	}
	if err := writeLine("Timestamp: %s", textTimestamp(resolved.GeneratedAt)); err != nil {
		return err
	}
	if err := writeLine("---------------------------------"); err != nil {
		return err
	}
	if err := writeLine(""); err != nil {
		return err
	}
	if err := writeLine("[🌐 Cluster Summary]"); err != nil {
		return err
	}
	if err := writeLine(""); err != nil {
		return err
	}
	if err := writeClusterSummaryText(w, resolved); err != nil {
		return err
	}

	for _, check := range orderedReportChecks(result.Checks) {
		legacy := buildLegacyCheckResult(check, resolved.Metrics)
		if err := writeLine(""); err != nil {
			return err
		}
		if err := writeLine("[%s - %s]", legacy.ID, legacy.Name); err != nil {
			return err
		}
		if strings.TrimSpace(legacy.Section) != "" {
			if err := writeLine("Section: %s", legacy.Section); err != nil {
				return err
			}
		}
		if strings.TrimSpace(legacy.Category) != "" {
			if err := writeLine("Category: %s", legacy.Category); err != nil {
				return err
			}
		}
		if strings.TrimSpace(legacy.Severity) != "" {
			if err := writeLine("Severity: %s", legacy.Severity); err != nil {
				return err
			}
		}
		if recommendation := legacyRecommendationText(legacy.Recommendation); recommendation != "" {
			if err := writeLine("Recommendation: %s", recommendation); err != nil {
				return err
			}
		}
		if strings.TrimSpace(legacy.URL) != "" {
			if err := writeLine("URL: %s", legacy.URL); err != nil {
				return err
			}
		}
		if legacy.Total == 0 {
			if err := writeLine("✅ No issues detected for %s.", legacy.Name); err != nil {
				return err
			}
			continue
		}
		if err := writeLine("⚠️ Total Issues: %d", legacy.Total); err != nil {
			return err
		}
		for _, line := range legacyTextLines(legacy) {
			if err := writeLine("- %s", line); err != nil {
				return err
			}
		}
	}

	if result.AutomaticReadiness != nil {
		if err := writeLine(""); err != nil {
			return err
		}
		if err := writeLine("[AKS Automatic Migration Readiness]"); err != nil {
			return err
		}
		if err := writeLine("Status: %s", result.AutomaticReadiness.Summary.StatusLabel); err != nil {
			return err
		}
		if err := writeLine("Message: %s", textSanitize(result.AutomaticReadiness.Summary.Message)); err != nil {
			return err
		}
		if err := writeLine("Blockers: %d", result.AutomaticReadiness.Summary.BlockerCount); err != nil {
			return err
		}
		if err := writeLine("Warnings: %d", result.AutomaticReadiness.Summary.WarningCount); err != nil {
			return err
		}
	}

	if err := writeLine(""); err != nil {
		return err
	}
	return writeLine("🩺 Cluster Health Score: %.0f / 100", clusterHealthScore(result.Checks))
}

func writeCSV(w io.Writer, result scan.Result, metadata Metadata) error {
	resolved := resolveMetadata(metadata, result)
	if _, err := w.Write([]byte{0xEF, 0xBB, 0xBF}); err != nil {
		return err
	}
	if _, err := io.WriteString(w, csvLine([]string{"ID", "Name", "Category", "Severity", "Status", "Message", "Recommendation", "URL"})); err != nil {
		return err
	}
	for _, check := range orderedReportChecks(result.Checks) {
		legacy := buildLegacyCheckResult(check, resolved.Metrics)
		status := "PASS"
		if legacy.Total > 0 {
			status = "FAIL"
		}
		recommendation := legacyRecommendationText(legacy.Recommendation)
		url := strings.TrimSpace(legacy.URL)
		if legacy.Total == 0 {
			if _, err := io.WriteString(w, csvLine([]string{legacy.ID, legacy.Name, legacy.Category, legacy.Severity, status, textSanitize(firstNonEmpty(legacy.Message, checkMessage(check))), recommendation, url})); err != nil {
				return err
			}
			continue
		}
		for _, line := range legacyCSVLines(legacy) {
			if _, err := io.WriteString(w, csvLine([]string{legacy.ID, legacy.Name, legacy.Category, legacy.Severity, status, line, recommendation, url})); err != nil {
				return err
			}
		}
	}
	if result.AutomaticReadiness != nil {
		summary := result.AutomaticReadiness.Summary
		rows := [][]string{
			{"AKSAUTO", "AKS Automatic Migration Readiness", "AKS Automatic", "Info", summary.StatusLabel, textSanitize(summary.Message), "", ""},
			{"AKSAUTO", "AKS Automatic Migration Readiness", "AKS Automatic", "Info", "Blockers", strconv.Itoa(summary.BlockerCount), "", ""},
			{"AKSAUTO", "AKS Automatic Migration Readiness", "AKS Automatic", "Info", "Warnings", strconv.Itoa(summary.WarningCount), "", ""},
			{"AKSAUTO", "AKS Automatic Migration Readiness", "AKS Automatic", "Info", "Alignment Failed", strconv.Itoa(summary.AlignmentFailedCount), "", ""},
			{"AKSAUTO", "AKS Automatic Migration Readiness", "AKS Automatic", "Info", "Alignment Passed", strconv.Itoa(summary.AlignmentPassedCount), "", ""},
		}
		for _, row := range rows {
			if _, err := io.WriteString(w, csvLine(row)); err != nil {
				return err
			}
		}
	}
	return nil
}

func writeClusterSummaryText(w io.Writer, metadata Metadata) error {
	clusterName := firstNonEmpty(metadata.ClusterName)
	kubernetesVersion := firstNonEmpty(metadata.KubernetesVersion)
	if metadata.Snapshot != nil {
		clusterName = firstNonEmpty(clusterName, metadata.Snapshot.Summary.Context, metadata.Snapshot.Context)
		kubernetesVersion = firstNonEmpty(kubernetesVersion, metadata.Snapshot.KubernetesVersion)
	}
	if metadata.Snapshot != nil {
		summary := metadata.Snapshot.Summary
		version := firstNonEmpty(metadata.Snapshot.KubernetesVersion, metadata.KubernetesVersion)
		lines := []string{
			fmt.Sprintf("Cluster Name: %s", firstNonEmpty(clusterName, summary.Context)),
			fmt.Sprintf("Kubernetes Version: %s", version),
		}
		for _, line := range lines {
			if _, err := fmt.Fprintln(w, line); err != nil {
				return err
			}
		}
		if info := normalizeReportBlock(kubectlText("cluster-info")); info != "" {
			if _, err := fmt.Fprintln(w, info); err != nil {
				return err
			}
		}
		if compatibility := kubernetesCompatibilityLine(version); compatibility != "" {
			if _, err := fmt.Fprintf(w, "Compatibility Check: %s\n", compatibility); err != nil {
				return err
			}
		}
		if apiHealth := apiServerHealthText(); apiHealth != "" {
			if _, err := fmt.Fprintf(w, "\nAPI Server Health: %s\n", apiHealth); err != nil {
				return err
			}
		}
		if metricsSummary := clusterMetricsSummaryText(metadata.Snapshot); metricsSummary != "" {
			if _, err := fmt.Fprintf(w, "\nMetrics: %s\n", metricsSummary); err != nil {
				return err
			}
		}
		errorCount, warningCount := eventCounts(metadata.Snapshot)
		if _, err := fmt.Fprintf(w, "\n❌ Errors: %d   ⚠️ Warnings: %d\n", errorCount, warningCount); err != nil {
			return err
		}
		return nil
	}
	if strings.TrimSpace(clusterName) != "" {
		if _, err := fmt.Fprintf(w, "Cluster Name: %s\n", clusterName); err != nil {
			return err
		}
	}
	if strings.TrimSpace(kubernetesVersion) != "" {
		if _, err := fmt.Fprintf(w, "Kubernetes Version: %s\n", kubernetesVersion); err != nil {
			return err
		}
	}
	if info := normalizeReportBlock(kubectlText("cluster-info")); info != "" {
		if _, err := fmt.Fprintln(w, info); err != nil {
			return err
		}
	}
	if compatibility := kubernetesCompatibilityLine(kubernetesVersion); compatibility != "" {
		if _, err := fmt.Fprintf(w, "Compatibility Check: %s\n", compatibility); err != nil {
			return err
		}
	}
	if apiHealth := apiServerHealthText(); apiHealth != "" {
		if _, err := fmt.Fprintf(w, "\nAPI Server Health: %s\n", apiHealth); err != nil {
			return err
		}
	}
	return nil
}

func textTimestamp(raw string) string {
	if strings.TrimSpace(raw) == "" {
		return time.Now().Format("01/02/2006 15:04:05")
	}
	if parsed, err := time.Parse(time.RFC3339, raw); err == nil {
		return parsed.Local().Format("01/02/2006 15:04:05")
	}
	return raw
}

func textItemLines(check scan.CheckResult) []string {
	if check.LegacyItems != nil {
		return flattenLegacyItems(check.LegacyItems)
	}
	lines := make([]string, 0, len(check.Items))
	for _, item := range check.Items {
		parts := make([]string, 0, 4)
		if strings.TrimSpace(item.Namespace) != "" {
			parts = append(parts, "Namespace: "+textSanitize(item.Namespace))
		}
		if strings.TrimSpace(item.Resource) != "" {
			parts = append(parts, "Resource: "+textSanitize(item.Resource))
		}
		if strings.TrimSpace(item.Value) != "" {
			parts = append(parts, "Value: "+textSanitize(item.Value))
		}
		if strings.TrimSpace(item.Message) != "" {
			parts = append(parts, "Message: "+textSanitize(item.Message))
		}
		lines = append(lines, strings.Join(parts, " | "))
	}
	return lines
}

func csvMessages(check scan.CheckResult) []string {
	if check.Total == 0 {
		return []string{textSanitize(checkMessage(check))}
	}
	if check.LegacyItems != nil {
		return flattenLegacyItems(check.LegacyItems)
	}
	messages := make([]string, 0, len(check.Items))
	for _, item := range check.Items {
		parts := make([]string, 0, 3)
		if strings.TrimSpace(item.Namespace) != "" {
			parts = append(parts, textSanitize(item.Namespace))
		}
		if strings.TrimSpace(item.Resource) != "" {
			parts = append(parts, textSanitize(item.Resource))
		}
		if strings.TrimSpace(item.Message) != "" {
			parts = append(parts, textSanitize(item.Message))
		}
		if len(parts) == 0 && strings.TrimSpace(item.Value) != "" {
			parts = append(parts, textSanitize(item.Value))
		}
		messages = append(messages, strings.Join(parts, " | "))
	}
	if len(messages) == 0 {
		return []string{textSanitize(checkMessage(check))}
	}
	return messages
}

func legacyRecommendationText(value any) string {
	switch v := value.(type) {
	case nil:
		return ""
	case string:
		return textSanitize(v)
	case *jsonRecommendation:
		return textSanitize(v.Text)
	case jsonRecommendation:
		return textSanitize(v.Text)
	default:
		return textSanitize(fmt.Sprint(value))
	}
}

func legacyTextLines(check jsonCheckResult) []string {
	return flattenLegacyItems(check.Items)
}

func legacyCSVLines(check jsonCheckResult) []string {
	switch check.ID {
	case "EVENT001":
		lines := make([]string, 0)
		for _, item := range flattenLegacyMaps(check.Items) {
			message := textSanitize(fmt.Sprint(item["Message"]))
			if message != "" && message != "<nil>" {
				lines = append(lines, message)
			}
		}
		if len(lines) > 0 {
			return lines
		}
	case "EVENT002":
		lines := make([]string, 0)
		for _, item := range flattenLegacyMaps(check.Items) {
			namespace := textSanitize(fmt.Sprint(item["Namespace"]))
			message := textSanitize(fmt.Sprint(item["Message"]))
			line := strings.TrimSpace(strings.Join(nonEmptyStrings(namespace, message), " | "))
			if line != "" {
				lines = append(lines, line)
			}
		}
		if len(lines) > 0 {
			return lines
		}
	}
	return flattenLegacyItems(check.Items)
}

func flattenLegacyMaps(value any) []map[string]any {
	switch items := value.(type) {
	case []map[string]any:
		return items
	case map[string]any:
		return []map[string]any{items}
	default:
		return nil
	}
}

func kubernetesCompatibilityLine(current string) string {
	current = strings.TrimSpace(current)
	if current == "" {
		return ""
	}
	latest := latestStableKubernetesVersion()
	if latest == "" {
		return ""
	}
	if current < latest {
		return fmt.Sprintf("⚠️  Cluster is running an outdated version: %s (Latest: %s)", current, latest)
	}
	return fmt.Sprintf("✅ Cluster is up to date (%s)", current)
}

func latestStableKubernetesVersion() string {
	client := &http.Client{Timeout: 5 * time.Second}
	resp, err := client.Get("https://dl.k8s.io/release/stable.txt")
	if err != nil {
		return ""
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return ""
	}
	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return ""
	}
	return strings.TrimSpace(string(body))
}

func apiServerHealthText() string {
	metrics := kubectlText("get", "--raw", "/metrics")
	livez := kubectlText("get", "--raw", "/livez?verbose")
	readyz := kubectlText("get", "--raw", "/readyz?verbose")
	lines := []string{}
	if p99, ok := apiServerP99(metrics); ok {
		lines = append(lines, fmt.Sprintf("API Server Health:\n  p99 GET latency: %s ms", trimFloat(p99)))
	} else {
		lines = append(lines, "API Server Health:\n  Metrics endpoint unavailable")
	}
	lines = append(lines, "", "Liveness:")
	if livez != "" {
		lines = append(lines, normalizeReportBlock(livez))
	}
	lines = append(lines, "", "Readiness:")
	if readyz != "" {
		lines = append(lines, normalizeReportBlock(readyz))
	}
	return strings.TrimSpace(strings.Join(lines, "\n"))
}

func apiServerP99(metrics string) (float64, bool) {
	metrics = strings.TrimSpace(metrics)
	if metrics == "" {
		return 0, false
	}
	var buckets []struct {
		Le    float64
		Count float64
	}
	var total float64
	for _, line := range strings.Split(metrics, "\n") {
		line = strings.TrimSpace(line)
		if !strings.Contains(line, `apiserver_request_duration_seconds_bucket`) || !strings.Contains(line, `verb="GET"`) {
			continue
		}
		le, count, ok := parseBucketLine(line)
		if ok {
			buckets = append(buckets, struct {
				Le    float64
				Count float64
			}{Le: le, Count: count})
		}
	}
	for _, line := range strings.Split(metrics, "\n") {
		line = strings.TrimSpace(line)
		if !strings.Contains(line, `apiserver_request_duration_seconds_count`) || !strings.Contains(line, `verb="GET"`) {
			continue
		}
		fields := strings.Fields(line)
		if len(fields) == 0 {
			continue
		}
		value, err := strconv.ParseFloat(fields[len(fields)-1], 64)
		if err == nil {
			total = value
			break
		}
	}
	if len(buckets) == 0 || total <= 0 {
		return 0, false
	}
	sort.Slice(buckets, func(i, j int) bool { return buckets[i].Le < buckets[j].Le })
	target := total * 0.99
	for _, bucket := range buckets {
		if bucket.Count >= target {
			return round2(bucket.Le * 1000), true
		}
	}
	return 0, false
}

func parseBucketLine(line string) (float64, float64, bool) {
	leIdx := strings.Index(line, `le="`)
	if leIdx < 0 {
		return 0, 0, false
	}
	rest := line[leIdx+4:]
	endIdx := strings.Index(rest, `"`)
	if endIdx < 0 {
		return 0, 0, false
	}
	leValue := rest[:endIdx]
	if leValue == "+Inf" {
		return 0, 0, false
	}
	le, err := strconv.ParseFloat(leValue, 64)
	if err != nil {
		return 0, 0, false
	}
	fields := strings.Fields(line)
	if len(fields) == 0 {
		return 0, 0, false
	}
	count, err := strconv.ParseFloat(fields[len(fields)-1], 64)
	if err != nil {
		return 0, 0, false
	}
	return le, count, true
}

func clusterMetricsSummaryText(snapshot *kubernetes.ClusterData) string {
	if snapshot == nil || snapshot.Metrics == nil {
		return ""
	}
	return fmt.Sprintf("Avg CPU Usage: %.2f%% | Avg Memory Usage: %.2f%%", snapshot.Metrics.Cluster.AvgCPUPercent, snapshot.Metrics.Cluster.AvgMemPercent)
}

func eventCounts(snapshot *kubernetes.ClusterData) (int, int) {
	if snapshot == nil {
		return 0, 0
	}
	errorCount := 0
	warningCount := 0
	for _, event := range snapshot.AllEvents {
		eventType := strings.TrimSpace(fmt.Sprint(resolveValue(event, "type")))
		reason := strings.TrimSpace(fmt.Sprint(resolveValue(event, "reason")))
		if eventType == "Warning" {
			warningCount++
		}
		if strings.Contains(reason, "Failed") || strings.Contains(reason, "Error") {
			errorCount++
		}
	}
	return errorCount, warningCount
}

func resolveValue(item map[string]any, path string) any {
	current := any(item)
	for _, part := range strings.Split(path, ".") {
		object, ok := current.(map[string]any)
		if !ok {
			return nil
		}
		current, ok = object[part]
		if !ok {
			return nil
		}
	}
	return current
}

func nonEmptyStrings(values ...string) []string {
	out := make([]string, 0, len(values))
	for _, value := range values {
		value = strings.TrimSpace(value)
		if value != "" && value != "<nil>" {
			out = append(out, value)
		}
	}
	return out
}

func normalizeReportBlock(value string) string {
	rawLines := strings.Split(strings.ReplaceAll(value, "\r\n", "\n"), "\n")
	lines := make([]string, 0, len(rawLines))
	for _, line := range rawLines {
		line = strings.TrimRight(line, " \t\r")
		if strings.TrimSpace(line) == "" {
			if len(lines) == 0 || lines[len(lines)-1] == "" {
				continue
			}
			lines = append(lines, "")
			continue
		}
		lines = append(lines, line)
	}
	return strings.TrimSpace(strings.Join(lines, "\n"))
}

func trimFloat(value float64) string {
	return strconv.FormatFloat(value, 'f', -1, 64)
}

func flattenLegacyItems(value any) []string {
	switch items := value.(type) {
	case []map[string]any:
		out := make([]string, 0, len(items))
		for _, item := range items {
			out = append(out, joinLegacyMap(item))
		}
		return out
	case map[string]any:
		return []string{joinLegacyMap(items)}
	default:
		return []string{textSanitize(fmt.Sprint(value))}
	}
}

func joinLegacyMap(item map[string]any) string {
	preferred := []string{
		"Namespace", "Resource", "Pod", "Container", "ServiceAccount", "Node", "Object",
		"Reason", "Message", "Issue", "Status", "Value",
	}
	seen := map[string]struct{}{}
	keys := make([]string, 0, len(item))
	for _, key := range preferred {
		if _, ok := item[key]; ok {
			keys = append(keys, key)
			seen[key] = struct{}{}
		}
	}
	for key := range item {
		if _, ok := seen[key]; ok {
			continue
		}
		keys = append(keys, key)
	}
	sort.Strings(keys[len(seen):])
	parts := make([]string, 0, len(keys))
	for _, key := range keys {
		value := item[key]
		rendered := textSanitize(fmt.Sprint(value))
		if rendered == "" || rendered == "<nil>" {
			continue
		}
		parts = append(parts, fmt.Sprintf("%s: %s", key, rendered))
	}
	return strings.Join(parts, " | ")
}

func textSanitize(value string) string {
	value = strings.ReplaceAll(value, "\r", " ")
	value = strings.ReplaceAll(value, "\n", " ")
	value = strings.Join(strings.Fields(value), " ")
	return strings.TrimSpace(value)
}

func orderedReportChecks(checks []scan.CheckResult) []scan.CheckResult {
	ordered := append([]scan.CheckResult(nil), checks...)
	sort.SliceStable(ordered, func(i, j int) bool {
		leftAKS := strings.HasPrefix(ordered[i].ID, "AKS")
		rightAKS := strings.HasPrefix(ordered[j].ID, "AKS")
		if leftAKS != rightAKS {
			return !leftAKS
		}
		return ordered[i].ID < ordered[j].ID
	})
	return ordered
}

func maxInt(values ...int) int {
	max := 0
	for _, value := range values {
		if value > max {
			max = value
		}
	}
	return max
}

func csvLine(fields []string) string {
	quoted := make([]string, 0, len(fields))
	for _, field := range fields {
		field = strings.ReplaceAll(field, `"`, `""`)
		quoted = append(quoted, `"`+field+`"`)
	}
	return strings.Join(quoted, ",") + "\n"
}

func writeHTML(w io.Writer, result scan.Result) error {
	return writeHTMLWithMetadata(w, result, Metadata{})
}

func writeHTMLWithMetadata(w io.Writer, result scan.Result, metadata Metadata) error {
	excluded := append([]string(nil), metadata.ExcludedNamespaces...)
	if metadata.ExcludeNamespacesEnabled && len(excluded) == 0 {
		excluded = defaultExcludedNamespaces()
	}
	html, err := (reporthtml.ScanRenderer{}).Render("KubeBuddy Native Report", result, reporthtml.RenderOptions{
		ExcludeNamespaces:        metadata.ExcludeNamespacesEnabled,
		ExcludedNamespaces:       excluded,
		IncludePrometheus:        strings.TrimSpace(metadata.PrometheusURL) != "",
		PrometheusURL:            metadata.PrometheusURL,
		PrometheusMode:           metadata.PrometheusMode,
		PrometheusBearerTokenEnv: metadata.PrometheusBearerTokenEnv,
		Snapshot:                 metadata.Snapshot,
	})
	if err != nil {
		return err
	}
	_, err = io.Copy(w, bytes.NewBufferString(html))
	return err
}
