package scan

import (
	"fmt"
	"math"
	"sort"
	"strings"
	"time"

	"github.com/KubeDeckio/KubeBuddy/internal/checks"
	prom "github.com/KubeDeckio/KubeBuddy/internal/collector/prometheus"
)

func runPrometheusCheck(check checks.Check) (CheckResult, error) {
	result := CheckResult{
		ID:                         check.ID,
		Name:                       check.Name,
		Category:                   check.Category,
		Section:                    check.Section,
		Severity:                   string(check.Severity),
		Weight:                     check.Weight,
		Description:                check.Description,
		Recommendation:             check.Recommendation,
		RecommendationHTML:         check.RecommendationHTML,
		SpeechBubble:               append([]string(nil), check.SpeechBubble...),
		URL:                        check.URL,
		ResourceKind:               check.ResourceKind,
		AutomaticRelevance:         check.AutomaticRelevance,
		AutomaticScope:             check.AutomaticScope,
		AutomaticReason:            check.AutomaticReason,
		AutomaticAdmissionBehavior: check.AutomaticAdmissionBehavior,
		AutomaticMutationOutcome:   check.AutomaticMutationOutcome,
	}
	if !currentRuntime.Prometheus.Enabled {
		return result, nil
	}
	client, err := newPrometheusClient()
	if err != nil {
		return result, err
	}
	end := currentRuntime.Now
	if end.IsZero() {
		end = time.Now().UTC()
	}
	start := end.Add(-parsePromDuration(check.Prometheus.Range.Duration))
	series, err := client.QueryRange(
		check.Prometheus.Query,
		start.Format(time.RFC3339),
		end.Format(time.RFC3339),
		check.Prometheus.Range.Step,
		int(numberThreshold("prometheus_query_retries", 2)),
		int(numberThreshold("prometheus_retry_delay_seconds", 2)),
	)
	if err != nil {
		return result, err
	}
	expected := check.Expected
	if key, ok := expected.(string); ok {
		if value, found := currentRuntime.Thresholds[key]; found {
			expected = value
		}
	}
	for _, s := range series {
		avg := averageSeries(s.Values)
		failed, err := comparePrometheusValue(string(check.Operator), avg, expected)
		if err != nil || !failed {
			continue
		}
		result.Items = append(result.Items, Finding{
			Namespace: metricNamespace(s.Metric),
			Resource:  metricResource(s.Metric),
			Value:     fmt.Sprintf("%.4f", avg),
			Message:   check.FailMessage,
		})
	}
	result.Total = len(result.Items)
	sort.Slice(result.Items, func(i, j int) bool {
		return result.Items[i].Resource < result.Items[j].Resource
	})
	return result, nil
}

func newPrometheusClient() (*prom.Client, error) {
	if !currentRuntime.Prometheus.Enabled {
		return nil, fmt.Errorf("prometheus is not enabled")
	}
	return prom.New(prom.Options{
		URL:               currentRuntime.Prometheus.URL,
		Mode:              currentRuntime.Prometheus.Mode,
		BearerTokenEnv:    currentRuntime.Prometheus.BearerTokenEnv,
		TimeoutSeconds:    int(numberThreshold("prometheus_timeout_seconds", 60)),
		RetryCount:        int(numberThreshold("prometheus_query_retries", 2)),
		RetryDelaySeconds: int(numberThreshold("prometheus_retry_delay_seconds", 2)),
	})
}

func averageSeries(values [][]any) float64 {
	if len(values) == 0 {
		return 0
	}
	var sum float64
	var count float64
	for _, row := range values {
		if len(row) < 2 {
			continue
		}
		sum += asFloat(row[1])
		count++
	}
	if count == 0 {
		return 0
	}
	return sum / count
}

func asFloat(value any) float64 {
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

func parsePromDuration(value string) time.Duration {
	value = strings.TrimSpace(value)
	if value == "" {
		return 24 * time.Hour
	}
	var num int
	var unit string
	fmt.Sscanf(value, "%d%s", &num, &unit)
	switch unit {
	case "m":
		return time.Duration(num) * time.Minute
	case "d":
		return time.Duration(num) * 24 * time.Hour
	default:
		return time.Duration(num) * time.Hour
	}
}

func metricNamespace(labels map[string]string) string {
	if labels["namespace"] != "" {
		return labels["namespace"]
	}
	return "(prometheus)"
}

func metricResource(labels map[string]string) string {
	switch {
	case labels["pod"] != "":
		return "pod/" + labels["pod"]
	case labels["node"] != "":
		return "node/" + labels["node"]
	case labels["instance"] != "":
		return "instance/" + labels["instance"]
	default:
		parts := make([]string, 0, len(labels))
		for k, v := range labels {
			parts = append(parts, k+"="+v)
		}
		sort.Strings(parts)
		return strings.Join(parts, ",")
	}
}

func numberThreshold(key string, fallback float64) float64 {
	if value, ok := currentRuntime.Thresholds[key]; ok {
		switch v := value.(type) {
		case int:
			return float64(v)
		case float64:
			return v
		case string:
			var out float64
			fmt.Sscan(v, &out)
			return out
		}
	}
	return fallback
}

func maxCoverageDays(series []prom.Result) float64 {
	var maxDays float64
	for _, entry := range series {
		if len(entry.Values) < 2 {
			continue
		}
		first := asFloat(entry.Values[0][0])
		last := asFloat(entry.Values[len(entry.Values)-1][0])
		days := (last - first) / 86400
		if days > maxDays {
			maxDays = days
		}
	}
	return math.Round(maxDays*100) / 100
}

func nodeAliases(node map[string]any) []string {
	aliases := []string{
		strings.TrimSpace(stringifyLookup(node, "metadata.name")),
	}
	for _, addr := range asSlice(mustResolve(node, "status.addresses")) {
		addrMap, ok := addr.(map[string]any)
		if !ok {
			continue
		}
		value := strings.TrimSpace(stringifyLookup(addrMap, "address"))
		if value != "" {
			aliases = append(aliases, value)
		}
	}
	return uniqueAliases(aliases)
}

func uniqueAliases(values []string) []string {
	seen := map[string]struct{}{}
	out := make([]string, 0, len(values))
	for _, value := range values {
		value = strings.ToLower(strings.TrimSpace(value))
		if value == "" {
			continue
		}
		host := strings.Split(value, ":")[0]
		short := strings.Split(host, ".")[0]
		for _, candidate := range []string{value, host, short} {
			if candidate == "" {
				continue
			}
			if _, ok := seen[candidate]; ok {
				continue
			}
			seen[candidate] = struct{}{}
			out = append(out, candidate)
		}
	}
	return out
}

func findPromMetricValue(series []prom.Result, name string, aliases []string) *float64 {
	lookup := uniqueAliases(append([]string{name}, aliases...))
	for _, entry := range series {
		labels := []string{
			entry.Metric["instance"],
			entry.Metric["node"],
			entry.Metric["nodename"],
			entry.Metric["kubernetes_node"],
			entry.Metric["hostname"],
		}
		for _, label := range labels {
			label = strings.ToLower(strings.TrimSpace(label))
			if label == "" {
				continue
			}
			host := strings.Split(label, ":")[0]
			short := strings.Split(host, ".")[0]
			for _, alias := range lookup {
				if alias == host || alias == short || strings.Contains(host, alias) {
					if len(entry.Value) >= 2 {
						value := asFloat(entry.Value[1])
						return &value
					}
				}
			}
		}
	}
	return nil
}

func valueOrZero(value *float64) float64 {
	if value == nil {
		return 0
	}
	return *value
}

func metricMapByKey(series []prom.Result) map[string]float64 {
	out := map[string]float64{}
	for _, entry := range series {
		ns := strings.TrimSpace(entry.Metric["namespace"])
		pod := strings.TrimSpace(entry.Metric["pod"])
		container := strings.TrimSpace(entry.Metric["container"])
		if ns == "" || pod == "" || container == "" || container == "POD" {
			continue
		}
		if len(entry.Value) < 2 {
			continue
		}
		out[ns+"|"+pod+"|"+container] = asFloat(entry.Value[1])
	}
	return out
}

func cpuMillicores(value string) float64 {
	value = strings.TrimSpace(value)
	if value == "" {
		return 0
	}
	if strings.HasSuffix(value, "m") {
		return parseFloat(strings.TrimSuffix(value, "m"))
	}
	return parseFloat(value) * 1000
}

func memoryMi(value string) float64 {
	value = strings.TrimSpace(value)
	if value == "" {
		return 0
	}
	binaryUnits := map[string]float64{
		"Ki": 1.0 / 1024,
		"Mi": 1,
		"Gi": 1024,
		"Ti": 1024 * 1024,
	}
	decimalUnits := map[string]float64{
		"K": 1e3 / (1024 * 1024),
		"M": 1e6 / (1024 * 1024),
		"G": 1e9 / (1024 * 1024),
		"T": 1e12 / (1024 * 1024),
		"P": 1e15 / (1024 * 1024),
		"E": 1e18 / (1024 * 1024),
	}
	for suffix, scale := range binaryUnits {
		if strings.HasSuffix(value, suffix) {
			return parseFloat(strings.TrimSuffix(value, suffix)) * scale
		}
	}
	for suffix, scale := range decimalUnits {
		if strings.HasSuffix(value, suffix) {
			return parseFloat(strings.TrimSuffix(value, suffix)) * scale
		}
	}
	return parseFloat(value) / (1024 * 1024)
}

func maxFloat(values ...float64) float64 {
	if len(values) == 0 {
		return 0
	}
	max := values[0]
	for _, value := range values[1:] {
		if value > max {
			max = value
		}
	}
	return max
}

func ceilStep(value float64, step float64) float64 {
	if value <= 0 || step <= 0 {
		return 0
	}
	return math.Ceil(value/step) * step
}

func approxWithin(current float64, recommended float64, lower float64, upper float64) bool {
	if recommended <= 0 {
		return current <= 0
	}
	if current <= 0 {
		return false
	}
	return current >= recommended*lower && current <= recommended*upper
}

func parseFloat(value string) float64 {
	var out float64
	fmt.Sscan(strings.TrimSpace(value), &out)
	return out
}

func comparePrometheusValue(operator string, actual float64, expected any) (bool, error) {
	target := 0.0
	switch v := expected.(type) {
	case int:
		target = float64(v)
	case int64:
		target = float64(v)
	case float64:
		target = v
	case string:
		target = parseFloat(v)
	default:
		target = parseFloat(fmt.Sprint(v))
	}
	switch strings.ToLower(strings.TrimSpace(operator)) {
	case "greater_than":
		return actual > target, nil
	case "less_than":
		return actual < target, nil
	case "equals":
		return math.Round(actual*100000)/100000 == math.Round(target*100000)/100000, nil
	default:
		return false, fmt.Errorf("unsupported operator %q", operator)
	}
}
