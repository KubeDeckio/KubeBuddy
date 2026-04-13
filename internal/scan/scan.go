package scan

import (
	"bytes"
	"encoding/json"
	"fmt"
	"os/exec"
	"sort"
	"strings"

	"github.com/KubeDeckio/KubeBuddy/internal/checks"
	"github.com/KubeDeckio/KubeBuddy/internal/config"
)

type Options struct {
	ChecksDir                string
	ConfigPath               string
	ExcludeNamespaces        bool
	ExcludedNamespaces       []string
	IncludePrometheus        bool
	PrometheusURL            string
	PrometheusMode           string
	PrometheusBearerTokenEnv string
	Progress                 func(ProgressEvent)
}

type Result struct {
	Checks             []CheckResult
	AutomaticReadiness *AutomaticReadiness `json:",omitempty"`
}

type CheckResult struct {
	ID                         string
	Name                       string
	Category                   string
	Section                    string
	Severity                   string
	Weight                     int
	Description                string
	Recommendation             string
	RecommendationHTML         string
	RecommendationSource       string
	URL                        string
	ResourceKind               string
	AutomaticRelevance         string
	AutomaticScope             string
	AutomaticReason            string
	AutomaticAdmissionBehavior string
	AutomaticMutationOutcome   string
	ObservedValue              string
	FailMessageText            string
	SummaryMessage             string
	LegacyItems                any
	Total                      int
	Items                      []Finding
}

type Finding struct {
	Namespace string
	Resource  string
	Value     string
	Message   string
}

type ProgressEvent struct {
	Stage     string
	CheckID   string
	CheckName string
	Index     int
	Total     int
	Findings  int
}

type listResponse struct {
	Items []map[string]any `json:"items"`
}

func Run(opts Options) (Result, error) {
	if strings.TrimSpace(opts.ChecksDir) == "" {
		opts.ChecksDir = "checks/kubernetes"
	}

	ruleSet, err := checks.LoadCatalog(opts.ChecksDir)
	if err != nil {
		return Result{}, err
	}

	cache := map[string][]map[string]any{}
	setRuntimeContext(runtimeContext{
		Thresholds: config.Thresholds(opts.ConfigPath),
		Prometheus: prometheusOptions{
			Enabled:        opts.IncludePrometheus && strings.TrimSpace(opts.PrometheusURL) != "",
			URL:            opts.PrometheusURL,
			Mode:           opts.PrometheusMode,
			BearerTokenEnv: opts.PrometheusBearerTokenEnv,
		},
		Excluded: excludedNamespaceSet(opts.ExcludeNamespaces, opts.ExcludedNamespaces),
	})
	defer clearRuntimeContext()
	var out Result
	declarativeTotal := countDeclarativeChecks(ruleSet.Checks)
	current := 0
	for _, check := range ruleSet.Checks {
		if !check.IsDeclarative() {
			continue
		}
		current++
		emitProgress(opts.Progress, ProgressEvent{
			Stage:     "start",
			CheckID:   check.ID,
			CheckName: check.Name,
			Index:     current,
			Total:     declarativeTotal,
		})

		if check.Prometheus != nil {
			result, err := runPrometheusCheck(check)
			if err != nil {
				return Result{}, fmt.Errorf("%s: %w", check.ID, err)
			}
			out.Checks = append(out.Checks, result)
			emitProgress(opts.Progress, ProgressEvent{
				Stage:     "result",
				CheckID:   result.ID,
				CheckName: result.Name,
				Index:     current,
				Total:     declarativeTotal,
				Findings:  result.Total,
			})
			continue
		}

		items := []map[string]any{{}}
		if !usesSyntheticInput(check) {
			var err error
			items, err = getItems(cache, check.ResourceKind)
			if err != nil {
				return Result{}, fmt.Errorf("%s: %w", check.ID, err)
			}
		}

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
			URL:                        check.URL,
			ResourceKind:               check.ResourceKind,
			AutomaticRelevance:         check.AutomaticRelevance,
			AutomaticScope:             check.AutomaticScope,
			AutomaticReason:            check.AutomaticReason,
			AutomaticAdmissionBehavior: check.AutomaticAdmissionBehavior,
			AutomaticMutationOutcome:   check.AutomaticMutationOutcome,
		}

		if findings, ok, err := executeNativeHandler(check, items, cache); err != nil {
			return Result{}, fmt.Errorf("%s: %w", check.ID, err)
		} else if ok {
			result.Items = findings
			result.Total = len(result.Items)
			switch check.ID {
			case "EVENT001":
				result.LegacyItems = buildLegacyEVENT001Items(items)
				result.Total = len(result.LegacyItems.([]map[string]any))
			case "EVENT002":
				result.LegacyItems = buildLegacyEVENT002Items(items)
				result.Total = len(result.LegacyItems.([]map[string]any))
			}
			if check.ID == "PROM006" || check.ID == "PROM007" {
				if len(result.Items) == 1 && strings.HasPrefix(result.Items[0].Resource, "prometheus/") && strings.Contains(strings.ToLower(result.Items[0].Message), "insufficient prometheus history") {
					result.Total = 0
					kind := "Node"
					if check.ID == "PROM007" {
						kind = "Pod"
					}
					coverageDays := strings.TrimSpace(result.Items[0].Value)
					if coverageDays == "" {
						coverageDays = "0.0"
					}
					displayDays := strings.TrimRight(strings.TrimRight(coverageDays, "0"), ".")
					if displayDays == "" {
						displayDays = "0"
					}
					result.SummaryMessage = fmt.Sprintf("Insufficient Prometheus history for sizing. Required: 7 days, available: %s days.", displayDays)
					result.LegacyItems = map[string]any{
						"Status":         "Insufficient Prometheus history",
						"Required Days":  7,
						"Available Days": json.RawMessage(coverageDays),
						"Message":        fmt.Sprintf("%s sizing recommendations are withheld until at least 7 days of Prometheus history is available.", kind),
					}
				}
			}
			out.Checks = append(out.Checks, result)
			emitProgress(opts.Progress, ProgressEvent{
				Stage:     "result",
				CheckID:   result.ID,
				CheckName: result.Name,
				Index:     current,
				Total:     declarativeTotal,
				Findings:  result.Total,
			})
			continue
		}

		for _, item := range items {
			eval, err := checks.EvaluateItem(check, item)
			if err != nil {
				return Result{}, fmt.Errorf("%s: %w", check.ID, err)
			}
			if !eval.Failed {
				continue
			}

			result.Items = append(result.Items, Finding{
				Namespace: namespaceOf(item),
				Resource:  resourceRef(check.ResourceKind, item),
				Value:     flattenValue(eval.Value),
				Message:   check.FailMessage,
			})
		}

		result.Total = len(result.Items)
		out.Checks = append(out.Checks, result)
		emitProgress(opts.Progress, ProgressEvent{
			Stage:     "result",
			CheckID:   result.ID,
			CheckName: result.Name,
			Index:     current,
			Total:     declarativeTotal,
			Findings:  result.Total,
		})
	}

	sort.Slice(out.Checks, func(i, j int) bool { return out.Checks[i].ID < out.Checks[j].ID })
	return out, nil
}

func countDeclarativeChecks(checksList []checks.Check) int {
	total := 0
	for _, check := range checksList {
		if check.IsDeclarative() {
			total++
		}
	}
	return total
}

func emitProgress(progress func(ProgressEvent), event ProgressEvent) {
	if progress != nil {
		progress(event)
	}
}

func usesSyntheticInput(check checks.Check) bool {
	if strings.TrimSpace(check.NativeHandler) == "" {
		return false
	}
	if strings.Contains(check.ResourceKind, ",") {
		return true
	}
	switch check.NativeHandler {
	case "PROM006", "PROM007", "RBAC001", "RBAC002", "RBAC004", "NODE002", "SC003", "WRK005", "WRK006", "WRK007", "WRK012", "WRK014", "WRK015", "NET004", "NET013", "NET018":
		return true
	default:
		return false
	}
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

	var response listResponse
	if err := json.Unmarshal([]byte(output), &response); err != nil {
		return nil, err
	}

	cache[key] = response.Items
	filtered := filterExcludedItems(response.Items)
	cache[key] = filtered
	return filtered, nil
}

func kubectlOutput(args ...string) (string, error) {
	cmd := exec.Command("kubectl", args...)
	var stdout bytes.Buffer
	var stderr bytes.Buffer
	cmd.Stdout = &stdout
	cmd.Stderr = &stderr
	if err := cmd.Run(); err != nil {
		if stderr.Len() > 0 {
			return "", fmt.Errorf("%w: %s", err, strings.TrimSpace(stderr.String()))
		}
		return "", err
	}
	return stdout.String(), nil
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
	case "nodes", "namespaces", "persistentvolumes", "storageclasses":
		return true
	default:
		return false
	}
}

func namespaceOf(item map[string]any) string {
	if metadata, ok := item["metadata"].(map[string]any); ok {
		if ns, ok := metadata["namespace"].(string); ok && ns != "" {
			return ns
		}
	}
	return "(cluster)"
}

func excludedNamespaceSet(enabled bool, extra []string) map[string]struct{} {
	if !enabled {
		return nil
	}
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

func filterExcludedItems(items []map[string]any) []map[string]any {
	if len(currentRuntime.Excluded) == 0 {
		return items
	}
	filtered := make([]map[string]any, 0, len(items))
	for _, item := range items {
		ns := strings.ToLower(strings.TrimSpace(namespaceOrName(item)))
		if ns != "" && ns != "(cluster)" {
			if _, ok := currentRuntime.Excluded[ns]; ok {
				continue
			}
		}
		filtered = append(filtered, item)
	}
	return filtered
}

func namespaceOrName(item map[string]any) string {
	if metadata, ok := item["metadata"].(map[string]any); ok {
		if ns, ok := metadata["namespace"].(string); ok && ns != "" {
			return ns
		}
		if name, ok := metadata["name"].(string); ok && name != "" && stringifyLookup(item, "kind") == "Namespace" {
			return name
		}
	}
	if stringifyLookup(item, "kind") == "Namespace" {
		return stringifyLookup(item, "metadata.name")
	}
	return "(cluster)"
}

func resourceRef(kind string, item map[string]any) string {
	name := "(unknown)"
	if metadata, ok := item["metadata"].(map[string]any); ok {
		if v, ok := metadata["name"].(string); ok && v != "" {
			name = v
		}
	}
	return fmt.Sprintf("%s/%s", strings.ToLower(strings.TrimSpace(kind)), name)
}

func flattenValue(value any) string {
	switch v := value.(type) {
	case nil:
		return "null"
	case []any:
		parts := make([]string, 0, len(v))
		for _, item := range v {
			parts = append(parts, fmt.Sprint(item))
		}
		return strings.Join(parts, ", ")
	default:
		return fmt.Sprint(v)
	}
}
