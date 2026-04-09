package scan

import (
	"fmt"
	"sort"
	"strings"
)

type AutomaticReadiness struct {
	Summary                 AutomaticSummary      `json:"summary"`
	Blockers                []AutomaticFinding    `json:"blockers"`
	Warnings                []AutomaticFinding    `json:"warnings"`
	Alignment               AutomaticAlignment    `json:"alignment"`
	ActionPlan              []AutomaticActionItem `json:"actionPlan"`
	TargetClusterBuildNotes []AutomaticActionItem `json:"targetClusterBuildNotes,omitempty"`
}

type AutomaticSummary struct {
	ClusterName          string `json:"clusterName"`
	Status               string `json:"status"`
	StatusLabel          string `json:"statusLabel"`
	BlockerCount         int    `json:"blockerCount"`
	WarningCount         int    `json:"warningCount"`
	AlignmentFailedCount int    `json:"alignmentFailedCount"`
	AlignmentPassedCount int    `json:"alignmentPassedCount"`
	Skipped              bool   `json:"skipped"`
	Message              string `json:"message"`
	ActionPlanPath       string `json:"actionPlanPath,omitempty"`
}

type AutomaticFinding struct {
	ID             string   `json:"id"`
	Name           string   `json:"name"`
	Severity       string   `json:"severity"`
	Category       string   `json:"category"`
	Scope          string   `json:"scope"`
	Relevance      string   `json:"relevance"`
	Reason         string   `json:"reason"`
	Total          int      `json:"total"`
	FailMessage    string   `json:"failMessage"`
	Recommendation string   `json:"recommendation"`
	URL            string   `json:"url"`
	AdmissionNote  string   `json:"admissionNote,omitempty"`
	Samples        []string `json:"samples,omitempty"`
}

type AutomaticAlignment struct {
	Status string             `json:"status"`
	Total  int                `json:"total"`
	Passed int                `json:"passed"`
	Failed int                `json:"failed"`
	Items  []AutomaticFinding `json:"items"`
}

type AutomaticActionItem struct {
	Key                   string                      `json:"key"`
	Phase                 string                      `json:"phase"`
	Bucket                string                      `json:"bucket"`
	Title                 string                      `json:"title"`
	Steps                 []string                    `json:"steps"`
	Checks                []string                    `json:"checks"`
	TotalAffected         int                         `json:"totalAffected"`
	AffectedResourceCount int                         `json:"affectedResourceCount,omitempty"`
	Samples               []string                    `json:"samples,omitempty"`
	Recommendations       []string                    `json:"recommendations,omitempty"`
	AdmissionNotes        []string                    `json:"admissionNotes,omitempty"`
	URLs                  []string                    `json:"urls,omitempty"`
	AffectedResources     []AutomaticAffectedResource `json:"affectedResources,omitempty"`
}

type AutomaticAffectedResource struct {
	Namespace        string `json:"namespace,omitempty"`
	Workload         string `json:"workload,omitempty"`
	ObservedResource string `json:"observedResource,omitempty"`
	HelmSource       string `json:"helmSource,omitempty"`
	Display          string `json:"display,omitempty"`
}

func BuildAutomaticReadiness(clusterName string, result Result) *AutomaticReadiness {
	var relevant []CheckResult
	for _, check := range result.Checks {
		if check.AutomaticRelevance == "blocker" || check.AutomaticRelevance == "warning" || check.AutomaticRelevance == "alignment" {
			relevant = append(relevant, check)
		}
	}
	if len(relevant) == 0 {
		return nil
	}

	var blockers, warnings, alignmentChecks []CheckResult
	for _, check := range relevant {
		switch check.AutomaticRelevance {
		case "blocker":
			if check.Total > 0 {
				blockers = append(blockers, check)
			}
		case "warning":
			if check.Total > 0 {
				warnings = append(warnings, check)
			}
		case "alignment":
			alignmentChecks = append(alignmentChecks, check)
		}
	}
	failedAlignment := 0
	passedAlignment := 0
	for _, check := range alignmentChecks {
		if check.Total > 0 {
			failedAlignment++
		} else {
			passedAlignment++
		}
	}

	status := "ready"
	statusLabel := "Ready"
	message := "Source cluster is ready for AKS Automatic migration based on current findings."
	if len(blockers) > 0 {
		status = "not_ready"
		statusLabel = "Not Ready"
		message = "Fix blocker findings before migrating workloads to a new AKS Automatic cluster."
	} else if len(warnings) > 0 {
		status = "ready_with_changes"
		statusLabel = "Ready With Changes"
		message = "Migration is possible, but warning findings should be cleaned up before or during the move."
	}

	alignmentItems := make([]AutomaticFinding, 0, len(alignmentChecks))
	for _, check := range alignmentChecks {
		alignmentItems = append(alignmentItems, toAutomaticFinding(check))
	}

	readiness := &AutomaticReadiness{
		Summary: AutomaticSummary{
			ClusterName:          clusterName,
			Status:               status,
			StatusLabel:          statusLabel,
			BlockerCount:         len(blockers),
			WarningCount:         len(warnings),
			AlignmentFailedCount: failedAlignment,
			AlignmentPassedCount: passedAlignment,
			Message:              message,
		},
		Blockers: convertAutomaticFindings(blockers),
		Warnings: convertAutomaticFindings(warnings),
		Alignment: AutomaticAlignment{
			Status: alignmentStatus(len(alignmentChecks), failedAlignment, passedAlignment),
			Total:  len(alignmentChecks),
			Passed: passedAlignment,
			Failed: failedAlignment,
			Items:  alignmentItems,
		},
		ActionPlan:              buildAutomaticActions(append(blockers, warnings...)),
		TargetClusterBuildNotes: buildAutomaticBuildNotes(alignmentChecks),
	}
	return readiness
}

func convertAutomaticFindings(checks []CheckResult) []AutomaticFinding {
	out := make([]AutomaticFinding, 0, len(checks))
	for _, check := range checks {
		out = append(out, toAutomaticFinding(check))
	}
	return out
}

func toAutomaticFinding(check CheckResult) AutomaticFinding {
	return AutomaticFinding{
		ID:             check.ID,
		Name:           check.Name,
		Severity:       check.Severity,
		Category:       check.Category,
		Scope:          check.AutomaticScope,
		Relevance:      check.AutomaticRelevance,
		Reason:         check.AutomaticReason,
		Total:          check.Total,
		FailMessage:    firstNonEmpty(check.firstMessage(), check.Description),
		Recommendation: check.Recommendation,
		URL:            check.URL,
		AdmissionNote:  automaticAdmissionNote(check.AutomaticAdmissionBehavior, check.AutomaticMutationOutcome),
		Samples:        findingSamples(check.Items),
	}
}

func (c CheckResult) firstMessage() string {
	if len(c.Items) == 0 {
		return ""
	}
	return strings.TrimSpace(c.Items[0].Message)
}

func findingSamples(items []Finding) []string {
	seen := map[string]struct{}{}
	var out []string
	for _, item := range items {
		sample := strings.TrimSpace(item.Resource)
		if sample == "" {
			sample = strings.TrimSpace(item.Message)
		}
		if sample == "" {
			continue
		}
		if _, ok := seen[sample]; ok {
			continue
		}
		seen[sample] = struct{}{}
		out = append(out, sample)
		if len(out) == 5 {
			break
		}
	}
	return out
}

func alignmentStatus(total, failed, passed int) string {
	if total == 0 {
		return "unknown"
	}
	if failed == 0 {
		return "already_aligned"
	}
	if passed == 0 {
		return "not_aligned"
	}
	return "partially_aligned"
}

func buildAutomaticActions(checks []CheckResult) []AutomaticActionItem {
	type key struct{ phase, reason string }
	grouped := map[key]*AutomaticActionItem{}
	for _, check := range checks {
		reason := firstNonEmpty(check.AutomaticReason, strings.ToLower(check.ID))
		phase := automaticPhase(check.AutomaticRelevance, check.AutomaticScope)
		k := key{phase: phase, reason: reason}
		if grouped[k] == nil {
			grouped[k] = &AutomaticActionItem{
				Key:             reason,
				Phase:           phase,
				Bucket:          check.AutomaticRelevance,
				Title:           automaticReasonTitle(reason),
				Steps:           automaticReasonSteps(reason),
				Recommendations: compactStrings([]string{check.Recommendation}),
				AdmissionNotes:  compactStrings([]string{automaticAdmissionNote(check.AutomaticAdmissionBehavior, check.AutomaticMutationOutcome)}),
				URLs:            compactStrings([]string{check.URL}),
			}
		}
		grouped[k].Checks = append(grouped[k].Checks, check.ID)
		grouped[k].TotalAffected += check.Total
		grouped[k].AffectedResources = append(grouped[k].AffectedResources, findingResources(check.Items)...)
		for _, sample := range findingSamples(check.Items) {
			if !contains(grouped[k].Samples, sample) {
				grouped[k].Samples = append(grouped[k].Samples, sample)
			}
		}
		grouped[k].Recommendations = appendUniqueStrings(grouped[k].Recommendations, check.Recommendation)
		grouped[k].AdmissionNotes = appendUniqueStrings(grouped[k].AdmissionNotes, automaticAdmissionNote(check.AutomaticAdmissionBehavior, check.AutomaticMutationOutcome))
		grouped[k].URLs = appendUniqueStrings(grouped[k].URLs, check.URL)
		if check.AutomaticRelevance == "blocker" {
			grouped[k].Bucket = "blocker"
		}
	}

	var out []AutomaticActionItem
	for _, item := range grouped {
		sort.Strings(item.Checks)
		item.AffectedResources = uniqueAffectedResources(item.AffectedResources)
		item.AffectedResourceCount = len(item.AffectedResources)
		if len(item.AffectedResources) > 10 {
			item.AffectedResources = item.AffectedResources[:10]
		}
		out = append(out, *item)
	}
	sort.Slice(out, func(i, j int) bool {
		if out[i].Phase != out[j].Phase {
			return out[i].Phase < out[j].Phase
		}
		if out[i].Bucket != out[j].Bucket {
			return out[i].Bucket < out[j].Bucket
		}
		return out[i].Title < out[j].Title
	})
	return out
}

func buildAutomaticBuildNotes(checks []CheckResult) []AutomaticActionItem {
	grouped := map[string]*AutomaticActionItem{}
	for _, check := range checks {
		if check.AutomaticRelevance != "alignment" || check.Total == 0 {
			continue
		}
		reason := firstNonEmpty(check.AutomaticReason, strings.ToLower(check.ID))
		if grouped[reason] == nil {
			grouped[reason] = &AutomaticActionItem{
				Key:             reason,
				Phase:           "target_cluster_build",
				Bucket:          "alignment",
				Title:           automaticReasonTitle(reason),
				Steps:           automaticReasonSteps(reason),
				Recommendations: compactStrings([]string{check.Recommendation}),
				AdmissionNotes:  compactStrings([]string{automaticAdmissionNote(check.AutomaticAdmissionBehavior, check.AutomaticMutationOutcome)}),
				URLs:            compactStrings([]string{check.URL}),
			}
		}
		item := grouped[reason]
		item.Checks = append(item.Checks, check.ID)
		item.TotalAffected += check.Total
		item.Samples = appendUniqueStrings(item.Samples, findingSamples(check.Items)...)
		item.Recommendations = appendUniqueStrings(item.Recommendations, check.Recommendation)
		item.AdmissionNotes = appendUniqueStrings(item.AdmissionNotes, automaticAdmissionNote(check.AutomaticAdmissionBehavior, check.AutomaticMutationOutcome))
		item.URLs = appendUniqueStrings(item.URLs, check.URL)
	}

	var out []AutomaticActionItem
	for _, item := range grouped {
		sort.Strings(item.Checks)
		out = append(out, *item)
	}
	sort.Slice(out, func(i, j int) bool { return out[i].Title < out[j].Title })
	return out
}

func automaticPhase(relevance, scope string) string {
	if scope == "cluster" || scope == "platform" || relevance == "alignment" {
		return "target_cluster_build"
	}
	return "fix_before_migration"
}

func automaticAdmissionNote(behavior, mutation string) string {
	switch behavior {
	case "mutates_on_enforce":
		if mutation != "" {
			return "AKS Automatic may mutate this on admission: " + mutation
		}
		return "AKS Automatic may mutate this on admission."
	case "denies_on_enforce":
		if mutation != "" {
			return "AKS Automatic may deny this resource in enforce mode. " + mutation
		}
		return "AKS Automatic may deny this resource in enforce mode."
	case "warns_only":
		return "AKS Automatic surfaces this as a warning and does not auto-mutate it."
	default:
		return ""
	}
}

func automaticReasonTitle(reason string) string {
	switch reason {
	case "aks_networking":
		return "Align target cluster networking with AKS Automatic defaults"
	case "aks_platform":
		return "Review AKS Automatic platform defaults"
	case "aks_security":
		return "Align target cluster security defaults"
	case "aks_autoscaling":
		return "Adopt AKS Automatic autoscaling defaults"
	case "resource_requests":
		return "Define container resource requests"
	case "health_probes":
		return "Add readiness and liveness probes"
	default:
		return "Review compatibility finding"
	}
}

func automaticReasonSteps(reason string) []string {
	switch reason {
	case "aks_networking":
		return []string{
			"Plan the target cluster with AKS Automatic-compatible networking defaults such as Azure CNI Overlay with Cilium.",
			"Review dependencies on the current network plugin and policy engine.",
			"Validate ingress, egress, and policy behavior in a migration environment before cutover.",
		}
	case "aks_platform":
		return []string{
			"Review the target cluster build against AKS Automatic defaults such as Azure Linux, Standard tier, and deployment safeguards.",
			"Create the destination cluster with those defaults from the start.",
			"Verify region, quota, and prerequisite support before creating the target cluster.",
		}
	case "aks_security":
		return []string{
			"Enable AKS security capabilities expected on the target cluster, such as OIDC issuer, workload identity, and image cleaner where applicable.",
			"Update workloads to use federated identity instead of stored credentials.",
			"Validate the security features are active before moving production workloads.",
		}
	case "aks_autoscaling":
		return []string{
			"Plan the target cluster around AKS Automatic scaling defaults such as node autoprovisioning, VPA, and KEDA where relevant.",
			"Review workload requests and autoscaler assumptions before migration.",
			"Run a controlled workload test on the target cluster to confirm expected scaling behavior.",
		}
	default:
		return []string{
			"Review the failing shared check and identify the manifest or platform setting causing it.",
			"Apply the recommended change in a non-production environment first.",
			"Rerun KubeBuddy to confirm the issue no longer appears.",
		}
	}
}

func contains(values []string, needle string) bool {
	for _, value := range values {
		if value == needle {
			return true
		}
	}
	return false
}

func appendUniqueStrings(values []string, additions ...string) []string {
	for _, value := range additions {
		value = strings.TrimSpace(value)
		if value == "" || contains(values, value) {
			continue
		}
		values = append(values, value)
	}
	return values
}

func compactStrings(values []string) []string {
	var out []string
	for _, value := range values {
		if strings.TrimSpace(value) == "" {
			continue
		}
		out = append(out, strings.TrimSpace(value))
	}
	return out
}

func findingResources(items []Finding) []AutomaticAffectedResource {
	var resources []AutomaticAffectedResource
	for _, item := range items {
		resource := strings.TrimSpace(item.Resource)
		if resource == "" {
			continue
		}
		resources = append(resources, AutomaticAffectedResource{
			Namespace:        strings.TrimSpace(item.Namespace),
			Workload:         topLevelWorkload(resource),
			ObservedResource: resource,
			Display:          resource,
		})
	}
	return resources
}

func topLevelWorkload(resource string) string {
	resource = strings.TrimSpace(resource)
	if resource == "" {
		return ""
	}
	parts := strings.Split(resource, "/")
	if len(parts) >= 2 {
		return parts[0] + "/" + parts[1]
	}
	return resource
}

func uniqueAffectedResources(items []AutomaticAffectedResource) []AutomaticAffectedResource {
	seen := map[string]struct{}{}
	var out []AutomaticAffectedResource
	for _, item := range items {
		key := strings.ToLower(item.Namespace + "|" + item.Workload + "|" + item.ObservedResource + "|" + item.HelmSource)
		if _, ok := seen[key]; ok {
			continue
		}
		seen[key] = struct{}{}
		out = append(out, item)
	}
	sort.Slice(out, func(i, j int) bool {
		if out[i].Namespace != out[j].Namespace {
			return out[i].Namespace < out[j].Namespace
		}
		if out[i].Workload != out[j].Workload {
			return out[i].Workload < out[j].Workload
		}
		return out[i].ObservedResource < out[j].ObservedResource
	})
	return out
}

func firstNonEmpty(values ...string) string {
	for _, value := range values {
		if strings.TrimSpace(value) != "" {
			return strings.TrimSpace(value)
		}
	}
	return ""
}

func AutomaticReadinessHTML(readiness *AutomaticReadiness) string {
	if readiness == nil {
		return ""
	}
	statusClass := map[string]string{
		"ready":              "healthy",
		"ready_with_changes": "warning",
		"skipped":            "unknown",
		"not_ready":          "critical",
	}[readiness.Summary.Status]
	if statusClass == "" {
		statusClass = "unknown"
	}

	var b strings.Builder
	b.WriteString(`<div class="collapsible-container aks-automatic-readiness"><details id="aksAutomaticReadiness">`)
	b.WriteString(`<summary>AKS Automatic Migration Readiness <span class="status-pill ` + statusClass + `">` + htmlEscape(readiness.Summary.StatusLabel) + `</span></summary>`)
	b.WriteString(`<div class="table-container">`)
	b.WriteString(`<div class="compatibility ` + statusClass + `"><strong>` + htmlEscape(readiness.Summary.StatusLabel) + `</strong> - ` + htmlEscape(readiness.Summary.Message) + `</div>`)
	b.WriteString(`<div class="hero-metrics">`)
	b.WriteString(automaticMetricCard("critical", "Blockers", fmt.Sprintf("%d", readiness.Summary.BlockerCount)))
	b.WriteString(automaticMetricCard("warning", "Warnings", fmt.Sprintf("%d", readiness.Summary.WarningCount)))
	b.WriteString(automaticMetricCard("normal", "Aligned Checks", fmt.Sprintf("%d", readiness.Summary.AlignmentPassedCount)))
	b.WriteString(`</div>`)
	if strings.TrimSpace(readiness.Summary.ActionPlanPath) != "" {
		leaf := readiness.Summary.ActionPlanPath
		if idx := strings.LastIndexAny(leaf, `/\`); idx >= 0 && idx < len(leaf)-1 {
			leaf = leaf[idx+1:]
		}
		b.WriteString(`<p><a href='` + htmlEscape(leaf) + `' target='_blank'>Open detailed AKS Automatic action plan</a></p>`)
	}
	b.WriteString(`<h3>Fix Before Migration</h3>`)
	b.WriteString(renderAutomaticTable(readiness.Blockers))
	b.WriteString(`<h3>Warnings</h3>`)
	b.WriteString(renderAutomaticTable(readiness.Warnings))
	b.WriteString(`</div></details></div>`)
	return b.String()
}

func renderAutomaticTable(items []AutomaticFinding) string {
	var b strings.Builder
	b.WriteString(`<div class="table-container"><table><thead><tr><th>ID</th><th>Check</th><th>Affected</th><th>Recommendation</th><th>Examples</th></tr></thead><tbody>`)
	if len(items) == 0 {
		b.WriteString(`<tr><td colspan="5">None</td></tr>`)
	} else {
		for _, item := range items {
			b.WriteString(`<tr><td><a href="#` + htmlEscape(item.ID) + `">` + htmlEscape(item.ID) + `</a></td><td>` + htmlEscape(item.Name) + `</td><td>`)
			b.WriteString(fmt.Sprintf("%d", item.Total) + `</td><td>` + htmlEscape(item.Recommendation) + `</td><td>` + htmlEscape(strings.Join(item.Samples, ", ")) + `</td></tr>`)
		}
	}
	b.WriteString(`</tbody></table></div>`)
	return b.String()
}

func htmlEscape(value string) string {
	repl := strings.NewReplacer("&", "&amp;", "<", "&lt;", ">", "&gt;", `"`, "&quot;", "'", "&#39;")
	return repl.Replace(value)
}

func automaticMetricCard(class string, label string, value string) string {
	return `<div class="metric-card ` + class + `"><div class="card-content"><p>` + htmlEscape(label) + `: <strong>` + htmlEscape(value) + `</strong></p></div></div>`
}
