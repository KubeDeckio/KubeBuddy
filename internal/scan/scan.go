package scan

import (
	"context"
	"encoding/json"
	"fmt"
	"sort"
	"strings"
	"time"

	"github.com/KubeDeckio/KubeBuddy/internal/checks"
	"github.com/KubeDeckio/KubeBuddy/internal/config"
	"github.com/KubeDeckio/KubeBuddy/internal/kubeapi"
)

type Options struct {
	ChecksDir                string
	ConfigPath               string
	AKSMode                  bool
	ExcludeNamespaces        bool
	ExcludedNamespaces       []string
	ExcludedChecks           []string
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
	CheckType                  string
	Weight                     int
	Description                string
	Recommendation             string
	RecommendationHTML         string
	SpeechBubble               []string
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
	CompatItems                any
	Total                      int
	Items                      []Finding
	SuppressedFindings         []SuppressedFinding
}

type Finding struct {
	Namespace string
	Resource  string
	Value     string
	Message   string
}

type SuppressedFinding struct {
	Finding
	Reason string
	Until  string
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
	cfg := config.Load(opts.ConfigPath)

	ruleSet, err := checks.LoadCatalog(opts.ChecksDir)
	if err != nil {
		return Result{}, err
	}
	ruleSet.Checks = filterExcludedChecks(ruleSet.Checks, effectiveExcludedChecks(cfg.ExcludedChecks, opts.ExcludedChecks))
	ruleSet.Checks = filterProviderSpecificChecks(ruleSet.Checks, opts)

	cache := map[string][]map[string]any{}
	client, err := kubeapi.New()
	if err != nil {
		return Result{}, err
	}
	ctx := context.Background()
	setRuntimeContext(runtimeContext{
		Thresholds: cfg.Thresholds,
		Prometheus: prometheusOptions{
			Enabled:        opts.IncludePrometheus && strings.TrimSpace(opts.PrometheusURL) != "",
			URL:            opts.PrometheusURL,
			Mode:           opts.PrometheusMode,
			BearerTokenEnv: opts.PrometheusBearerTokenEnv,
		},
		Excluded:          excludedNamespaceSet(opts.ExcludeNamespaces, cfg.ExcludedNamespaces, opts.ExcludedNamespaces),
		TrustedRegistries: append([]string(nil), cfg.TrustedRegistries...),
		AKSMode:           opts.AKSMode,
		KubeClient:        client,
		KubeContext:       ctx,
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
				result := skippedCheckResult(check, err)
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
			items, err = getItems(ctx, client, cache, check.ResourceKind)
			if err != nil {
				result := skippedCheckResult(check, err)
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
		}

		result := baseCheckResult(check)

		if findings, ok, err := executeNativeHandler(check, items, cache); err != nil {
			result = skippedCheckResult(check, err)
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
		} else if ok {
			result.Items = findings
			result.Total = len(result.Items)
			switch check.ID {
			case "EVENT001":
				result.CompatItems = buildCompatEVENT001Items(items)
				result.Total = len(result.CompatItems.([]map[string]any))
			case "EVENT002":
				result.CompatItems = buildCompatEVENT002Items(items)
				result.Total = len(result.CompatItems.([]map[string]any))
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
					result.CompatItems = map[string]any{
						"Status":         "Insufficient Prometheus history",
						"Required Days":  7,
						"Available Days": json.RawMessage(coverageDays),
						"Message":        fmt.Sprintf("%s sizing recommendations are withheld until at least 7 days of Prometheus history is available.", kind),
					}
				}
			}
			applyFindingSuppressions(&result, cache)
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
				result = skippedCheckResult(check, err)
				out.Checks = append(out.Checks, result)
				emitProgress(opts.Progress, ProgressEvent{
					Stage:     "result",
					CheckID:   result.ID,
					CheckName: result.Name,
					Index:     current,
					Total:     declarativeTotal,
					Findings:  result.Total,
				})
				goto nextCheck
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
		applyFindingSuppressions(&result, cache)
		out.Checks = append(out.Checks, result)
		emitProgress(opts.Progress, ProgressEvent{
			Stage:     "result",
			CheckID:   result.ID,
			CheckName: result.Name,
			Index:     current,
			Total:     declarativeTotal,
			Findings:  result.Total,
		})
	nextCheck:
	}

	sort.Slice(out.Checks, func(i, j int) bool { return out.Checks[i].ID < out.Checks[j].ID })
	return out, nil
}

func baseCheckResult(check checks.Check) CheckResult {
	return CheckResult{
		ID:                         check.ID,
		Name:                       check.Name,
		Category:                   check.Category,
		Section:                    check.Section,
		Severity:                   string(check.Severity),
		CheckType:                  check.CheckType,
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
}

func skippedCheckResult(check checks.Check, err error) CheckResult {
	result := baseCheckResult(check)
	result.SummaryMessage = fmt.Sprintf("Unable to check due to: %v", err)
	return result
}

const (
	ignoreChecksAnnotation = "kubebuddy.io/ignore-checks"
	ignoreReasonAnnotation = "kubebuddy.io/ignore-reason"
	ignoreUntilAnnotation  = "kubebuddy.io/ignore-until"
)

func applyFindingSuppressions(result *CheckResult, cache map[string][]map[string]any) {
	if result == nil || len(result.Items) == 0 {
		return
	}

	active := make([]Finding, 0, len(result.Items))
	suppressed := make([]SuppressedFinding, 0)
	for _, finding := range result.Items {
		resource := resourceForFinding(finding, cache)
		if resource == nil {
			active = append(active, finding)
			continue
		}
		if reason, until, ok := suppressionForCheck(resource, result.ID); ok {
			suppressed = append(suppressed, SuppressedFinding{
				Finding: finding,
				Reason:  reason,
				Until:   until,
			})
			continue
		}
		active = append(active, finding)
	}

	if len(suppressed) == 0 {
		return
	}
	result.Items = active
	result.SuppressedFindings = append(result.SuppressedFindings, suppressed...)
	result.Total = len(result.Items)
	result.CompatItems = nil
}

func suppressionForCheck(resource map[string]any, checkID string) (string, string, bool) {
	annotations, _ := mustResolve(resource, "metadata.annotations").(map[string]any)
	rawChecks := strings.TrimSpace(fmt.Sprint(annotations[ignoreChecksAnnotation]))
	if rawChecks == "" || rawChecks == "<nil>" {
		return "", "", false
	}
	if !suppressionIncludesCheck(rawChecks, checkID) {
		return "", "", false
	}

	until := strings.TrimSpace(fmt.Sprint(annotations[ignoreUntilAnnotation]))
	if until == "<nil>" {
		until = ""
	}
	if until != "" && suppressionExpired(until) {
		return "", "", false
	}

	reason := strings.TrimSpace(fmt.Sprint(annotations[ignoreReasonAnnotation]))
	if reason == "<nil>" {
		reason = ""
	}
	return reason, until, true
}

func suppressionIncludesCheck(raw string, checkID string) bool {
	checkID = strings.ToUpper(strings.TrimSpace(checkID))
	for _, token := range strings.FieldsFunc(raw, func(r rune) bool {
		return r == ',' || r == ';' || r == ' ' || r == '\n' || r == '\t'
	}) {
		token = strings.ToUpper(strings.TrimSpace(token))
		if token == "*" || token == checkID {
			return true
		}
	}
	return false
}

func suppressionExpired(raw string) bool {
	for _, layout := range []string{time.RFC3339, "2006-01-02"} {
		if parsed, err := time.Parse(layout, raw); err == nil {
			return time.Now().After(parsed)
		}
	}
	return false
}

func resourceForFinding(finding Finding, cache map[string][]map[string]any) map[string]any {
	parts := strings.SplitN(strings.TrimSpace(finding.Resource), "/", 2)
	if len(parts) != 2 || strings.TrimSpace(parts[0]) == "" || strings.TrimSpace(parts[1]) == "" {
		return nil
	}
	kind := normalizedKind(parts[0])
	name := parts[1]
	for _, item := range cache[kind] {
		if stringifyLookup(item, "metadata.name") != name {
			continue
		}
		itemNamespace := namespaceOf(item)
		findingNamespace := strings.TrimSpace(finding.Namespace)
		if findingNamespace == "" || findingNamespace == "(cluster)" || itemNamespace == findingNamespace {
			return item
		}
	}
	return nil
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
	case "PROM006", "PROM007", "RBAC001", "RBAC002", "RBAC004", "RBAC005", "RBAC006", "RBAC007", "RBAC008", "RBAC009", "RBAC010", "SEC028", "SEC030", "NET021", "WRK017", "WRK018", "WRK019", "WRK021", "NODE002", "SC003", "WRK005", "WRK006", "WRK007", "WRK012", "WRK014", "WRK015", "WRK016", "NET004", "NET013", "NET018", "NET020":
		return true
	default:
		return false
	}
}

func getItems(ctx context.Context, client *kubeapi.Client, cache map[string][]map[string]any, resourceKind string) ([]map[string]any, error) {
	key := normalizedKind(resourceKind)
	if items, ok := cache[key]; ok {
		return items, nil
	}
	items, err := client.List(ctx, key, !isClusterScoped(key))
	if err != nil {
		if strings.Contains(strings.ToLower(err.Error()), "not found") {
			cache[key] = nil
			return nil, nil
		}
		return nil, err
	}
	filtered := filterExcludedItems(items)
	cache[key] = filtered
	return filtered, nil
}

func normalizedKind(kind string) string {
	switch strings.ToLower(strings.TrimSpace(kind)) {
	case "clusterrole":
		return "clusterroles"
	case "clusterrolebinding":
		return "clusterrolebindings"
	case "configmap":
		return "configmaps"
	case "cronjob":
		return "cronjobs"
	case "daemonset":
		return "daemonsets"
	case "deployment":
		return "deployments"
	case "endpoint", "endpoints":
		return "endpoints"
	case "endpointslice":
		return "endpointslices"
	case "event":
		return "events"
	case "horizontalpodautoscaler":
		return "horizontalpodautoscalers"
	case "job":
		return "jobs"
	case "limitrange":
		return "limitranges"
	case "networkpolicy":
		return "networkpolicies"
	case "persistentvolume":
		return "persistentvolumes"
	case "persistentvolumeclaim":
		return "persistentvolumeclaims"
	case "poddisruptionbudget":
		return "poddisruptionbudgets"
	case "replicaset":
		return "replicasets"
	case "role":
		return "roles"
	case "rolebinding":
		return "rolebindings"
	case "secret":
		return "secrets"
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
	case "statefulset":
		return "statefulsets"
	case "mutatingwebhookconfiguration":
		return "mutatingwebhookconfigurations"
	case "validatingwebhookconfiguration":
		return "validatingwebhookconfigurations"
	default:
		return strings.ToLower(strings.TrimSpace(kind))
	}
}

func isClusterScoped(kind string) bool {
	switch kind {
	case "nodes", "namespaces", "persistentvolumes", "storageclasses",
		"mutatingwebhookconfigurations", "validatingwebhookconfigurations",
		"validatingadmissionpolicies", "validatingadmissionpolicybindings",
		"validatingadmissionpolicy", "validatingadmissionpolicybinding":
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

func excludedNamespaceSet(enabled bool, configured []string, extra []string) map[string]struct{} {
	if !enabled && !hasNonEmptyNamespace(extra) {
		return nil
	}
	names := append(append([]string{}, configured...), extra...)
	out := map[string]struct{}{}
	for _, ns := range names {
		ns = strings.ToLower(strings.TrimSpace(ns))
		if ns != "" {
			out[ns] = struct{}{}
		}
	}
	return out
}

func hasNonEmptyNamespace(values []string) bool {
	for _, value := range values {
		if strings.TrimSpace(value) != "" {
			return true
		}
	}
	return false
}

func filterExcludedChecks(checksList []checks.Check, excluded []string) []checks.Check {
	if len(excluded) == 0 {
		return checksList
	}
	excludedSet := map[string]struct{}{}
	for _, id := range excluded {
		trimmed := strings.ToUpper(strings.TrimSpace(id))
		if trimmed != "" {
			excludedSet[trimmed] = struct{}{}
		}
	}
	filtered := make([]checks.Check, 0, len(checksList))
	for _, check := range checksList {
		if _, ok := excludedSet[strings.ToUpper(strings.TrimSpace(check.ID))]; ok {
			continue
		}
		filtered = append(filtered, check)
	}
	return filtered
}

func effectiveExcludedChecks(configured []string, runtime []string) []string {
	set := map[string]struct{}{}
	for _, id := range append(append([]string{}, configured...), runtime...) {
		trimmed := strings.ToUpper(strings.TrimSpace(id))
		if trimmed != "" {
			set[trimmed] = struct{}{}
		}
	}
	out := make([]string, 0, len(set))
	for id := range set {
		out = append(out, id)
	}
	sort.Strings(out)
	return out
}

func filterProviderSpecificChecks(checksList []checks.Check, opts Options) []checks.Check {
	filtered := make([]checks.Check, 0, len(checksList))
	prometheusEnabled := opts.IncludePrometheus && strings.TrimSpace(opts.PrometheusURL) != ""
	for _, check := range checksList {
		if check.ID == "SC002" && !opts.AKSMode {
			continue
		}
		if strings.HasPrefix(strings.ToUpper(strings.TrimSpace(check.ID)), "PROM") && !prometheusEnabled {
			continue
		}
		filtered = append(filtered, check)
	}
	return filtered
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
