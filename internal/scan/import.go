package scan

import (
	"encoding/json"
	"fmt"
	"sort"
	"strings"
)

type legacyReport struct {
	Metadata map[string]any               `json:"metadata"`
	Checks   map[string]legacyCheckResult `json:"checks"`
}

type legacyCheckResult struct {
	ID             string      `json:"ID"`
	Name           string      `json:"Name"`
	Category       string      `json:"Category"`
	Section        string      `json:"Section"`
	Severity       string      `json:"Severity"`
	Description    string      `json:"Description"`
	Recommendation string      `json:"Recommendation"`
	URL            string      `json:"URL"`
	ResourceKind   string      `json:"ResourceKind"`
	Total          int         `json:"Total"`
	Message        string      `json:"Message"`
	Items          legacyItems `json:"Items"`
}

type legacyItems []map[string]any

func (items *legacyItems) UnmarshalJSON(data []byte) error {
	if string(data) == "null" || len(data) == 0 {
		*items = nil
		return nil
	}

	var list []map[string]any
	if err := json.Unmarshal(data, &list); err == nil {
		*items = list
		return nil
	}

	var single map[string]any
	if err := json.Unmarshal(data, &single); err == nil {
		*items = []map[string]any{single}
		return nil
	}

	return fmt.Errorf("unsupported legacy Items payload: %s", string(data))
}

func ParseLegacyJSONReport(data []byte) (Result, error) {
	var report legacyReport
	if err := json.Unmarshal(data, &report); err != nil {
		return Result{}, err
	}

	out := Result{
		Checks: make([]CheckResult, 0, len(report.Checks)),
	}
	for id, check := range report.Checks {
		currentID := strings.TrimSpace(check.ID)
		if currentID == "" {
			currentID = strings.TrimSpace(id)
		}

		result := CheckResult{
			ID:             currentID,
			Name:           check.Name,
			Category:       check.Category,
			Section:        check.Section,
			Severity:       check.Severity,
			Description:    check.Description,
			Recommendation: check.Recommendation,
			URL:            check.URL,
			ResourceKind:   check.ResourceKind,
			Total:          check.Total,
			Items:          make([]Finding, 0, len(check.Items)),
		}

		for _, item := range check.Items {
			result.Items = append(result.Items, flattenLegacyItem(item, check.Message))
		}

		if result.Total == 0 {
			result.Total = len(result.Items)
		}
		out.Checks = append(out.Checks, result)
	}

	sort.Slice(out.Checks, func(i, j int) bool {
		return out.Checks[i].ID < out.Checks[j].ID
	})
	return out, nil
}

func flattenLegacyItem(item map[string]any, defaultMessage string) Finding {
	finding := Finding{
		Namespace: stringValue(item["Namespace"], "(cluster)"),
		Resource:  extractLegacyResource(item),
		Value:     extractLegacyValue(item),
		Message:   extractLegacyMessage(item, defaultMessage),
	}

	return finding
}

func extractLegacyResource(item map[string]any) string {
	for _, key := range []string{
		"Resource", "Pod", "Deployment", "StatefulSet", "DaemonSet", "Service",
		"Ingress", "Node", "Role", "ClusterRole", "RoleBinding", "ClusterRoleBinding",
		"PVC", "PV", "StorageClass", "NamespaceName", "ServiceAccount", "Secret",
		"ConfigMap", "CronJob", "Job", "Container", "NetworkPolicy",
	} {
		if value := strings.TrimSpace(stringify(item[key])); value != "" {
			return value
		}
	}
	return "(unknown)"
}

func extractLegacyValue(item map[string]any) string {
	for _, key := range []string{
		"Value", "EnvVar", "Label", "Annotation", "Capability", "Volume", "Image",
		"Selector", "Constraint", "Metric", "Path", "Port", "Policy", "Rule",
		"Setting", "Mode", "Class", "Profile", "Account",
	} {
		if value := strings.TrimSpace(stringify(item[key])); value != "" {
			return value
		}
	}
	return ""
}

func extractLegacyMessage(item map[string]any, defaultMessage string) string {
	for _, key := range []string{"Issue", "Message", "Reason", "Summary"} {
		if value := strings.TrimSpace(stringify(item[key])); value != "" {
			return value
		}
	}
	return strings.TrimSpace(defaultMessage)
}

func stringValue(value any, fallback string) string {
	if text := strings.TrimSpace(stringify(value)); text != "" {
		return text
	}
	return fallback
}

func stringify(value any) string {
	switch v := value.(type) {
	case nil:
		return ""
	case string:
		return v
	case fmt.Stringer:
		return v.String()
	default:
		return fmt.Sprint(v)
	}
}
