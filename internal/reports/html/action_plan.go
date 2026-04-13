package html

import (
	"fmt"
	"html"
	"strings"
	"time"

	reportassets "github.com/KubeDeckio/KubeBuddy/internal/reports/assets"
	"github.com/KubeDeckio/KubeBuddy/internal/scan"
)

type ActionPlanRenderer struct{}

func (ActionPlanRenderer) Render(clusterName string, readiness *scan.AutomaticReadiness) (string, error) {
	if readiness == nil {
		return "", nil
	}
	if strings.TrimSpace(clusterName) == "" {
		clusterName = readiness.Summary.ClusterName
	}
	if strings.TrimSpace(clusterName) == "" {
		clusterName = "Unknown"
	}
	var body strings.Builder
	generatedAt := time.Now().UTC().Format("January 02, 2006 15:04:05 UTC")
	statusClass := readinessStatusClass(readiness.Summary.Status)
	body.WriteString(`<!DOCTYPE html><html lang='en'><head><meta charset='UTF-8'><meta name='viewport' content='width=device-width, initial-scale=1.0'><title>AKS Automatic Action Plan</title>`)
	body.WriteString(`<script>(() => { try { const saved = localStorage.getItem('kb_report_theme'); if (saved === 'radar') { document.documentElement.setAttribute('data-kb-theme', 'radar'); } else { document.documentElement.removeAttribute('data-kb-theme'); } } catch (error) { document.documentElement.removeAttribute('data-kb-theme'); }})();</script>`)
	body.WriteString(`<style>`)
	body.WriteString(reportassets.ReportStyles)
	body.WriteString(`body { margin: 0; padding: 0; } .action-plan-page { max-width: 1350px; margin: 0 auto; padding: 24px; } .action-plan-intro { margin-bottom: 24px; } .action-plan-links { margin-top: 16px; } .action-plan-links ul { margin-top: 12px; } .action-plan-links li + li { margin-top: 10px; } .migration-sequence { margin-top: 18px; } .migration-sequence li + li { margin-top: 10px; } table { width: 100%; border-collapse: collapse; } th, td { padding: 12px; text-align: left; vertical-align: top; } small { color: #64748b; display: block; margin-top: 8px; } ul { margin: 0; padding-left: 18px; } .action-plan-section { margin-top: 24px; } .action-plan-card { margin-top: 16px; padding: 18px 20px; border-radius: 12px; background: linear-gradient(180deg, rgba(255, 255, 255, 0.98), rgba(245, 247, 250, 0.98)); border: 1px solid rgba(55, 71, 79, 0.12); box-shadow: var(--shadow-sm); } .action-plan-card-header { display: flex; align-items: center; justify-content: space-between; gap: 12px; margin-bottom: 12px; } .action-plan-card-header h3 { margin: 0; } .action-plan-count { display: inline-flex; align-items: center; justify-content: center; padding: 6px 10px; border-radius: 999px; background: rgba(0, 113, 255, 0.1); color: var(--brand-blue); font-size: 13px; font-weight: 600; white-space: nowrap; } .action-plan-meta { margin: 0 0 10px; color: var(--subtle-on-dark); font-size: 13px; } .action-plan-card-body > h4:first-child { margin-top: 0; } pre { margin: 12px 0 0; padding: 14px 16px; border-radius: var(--border-radius); background: rgba(15, 23, 42, 0.92); color: #e2e8f0; overflow-x: auto; white-space: pre; } code { font-family: SFMono-Regular, Consolas, "Liberation Mono", Menlo, monospace; font-size: 13px; } pre code { display: block; margin: 0; padding: 0; background: transparent; color: inherit; border-radius: 0; box-shadow: none; white-space: pre; line-height: 1.6; } td h4 { margin: 14px 0 8px; } html[data-kb-theme="radar"] .action-plan-page { max-width: 1440px; } html[data-kb-theme="radar"] .action-plan-intro, html[data-kb-theme="radar"] .action-plan-section { background: transparent; } html[data-kb-theme="radar"] .action-plan-card { background: linear-gradient(180deg, rgba(39, 52, 73, 0.96), rgba(33, 46, 66, 0.96)); border: 1px solid #3f5677; box-shadow: 0 10px 22px rgba(8, 18, 34, 0.24); } html[data-kb-theme="radar"] .action-plan-count { background: rgba(0, 194, 255, 0.14); color: #9de6ff; border: 1px solid rgba(0, 194, 255, 0.35); } html[data-kb-theme="radar"] .action-plan-meta { color: #9ba9be; } html[data-kb-theme="radar"] pre { background: rgba(11, 22, 43, 0.96); border: 1px solid rgba(0, 186, 255, 0.2); }`)
	body.WriteString(`</style></head><body><div class="wrapper"><div class="main-content"><div class="header"><div class="header-top"><div><span>AKS Automatic Action Plan: ` + esc(clusterName) + `</span></div><div style="text-align: right; font-size: 13px; line-height: 1.4;"><div>Generated on: <strong>` + esc(generatedAt) + `</strong></div><div>This action plan is intended for migration to a <strong>new AKS Automatic cluster</strong>.</div></div></div></div><div class="action-plan-page">`)
	body.WriteString(`<div class="container action-plan-intro"><h1>AKS Automatic Action Plan</h1><p><strong>Cluster:</strong> ` + esc(clusterName) + `</p><div class="compatibility ` + statusClass + `"><strong>` + esc(readiness.Summary.StatusLabel) + `</strong> - ` + esc(readiness.Summary.Message) + `</div><div class="hero-metrics">`)
	body.WriteString(metricCard("critical", "Blockers", fmt.Sprintf("%d", readiness.Summary.BlockerCount)))
	body.WriteString(metricCard("warning", "Warnings", fmt.Sprintf("%d", readiness.Summary.WarningCount)))
	body.WriteString(`</div>`)
	body.WriteString(`<div class="action-plan-links"><h2>Suggested Migration Sequence</h2><ul class="migration-sequence">`)
	for _, step := range migrationSequence(readiness) {
		body.WriteString(`<li>` + step + `</li>`)
	}
	body.WriteString(`</ul></div>`)
	body.WriteString(`<div class="action-plan-links"><h2>Build a New AKS Automatic Cluster</h2><p>Use these Microsoft Learn references when you build the destination cluster for this migration. The official quickstart currently covers the Azure portal, Azure CLI, and Bicep flows. For Terraform, the official Learn reference is the managed cluster AzAPI schema that exposes <code>sku.name = Automatic</code>.</p><ul>`)
	for _, resource := range automaticClusterBuildResources() {
		body.WriteString(`<li><strong>` + esc(resource.Title) + `</strong> - ` + esc(resource.Description) + ` <a href='` + escAttr(resource.URL) + `' target='_blank'>Open Microsoft Learn</a></li>`)
	}
	body.WriteString(`</ul></div></div>`)
	body.WriteString(`<div class="container action-plan-section"><h2>Fix Before Migration</h2><p>These actions are driven by blocker findings and should be completed before deploying workloads to a new AKS Automatic cluster.</p><div class="action-plan-cards">`)
	body.WriteString(renderActionPlanCards(filterActionBucket(readiness.ActionPlan, "blocker"), "No blocker-driven migration actions were identified."))
	body.WriteString(`</div></div>`)
	body.WriteString(`<div class="container action-plan-section"><h2>Warnings to Review</h2><p>These actions come from warning findings. They do not block migration by themselves, but resolving them reduces drift, warnings, and post-cutover rework.</p><div class="action-plan-cards">`)
	body.WriteString(renderActionPlanCards(filterActionExcludingBucket(readiness.ActionPlan, "blocker"), "No warning-only migration actions were identified."))
	body.WriteString(`</div></div>`)
	if len(readiness.TargetClusterBuildNotes) > 0 {
		body.WriteString(`<div class="container action-plan-section"><h2>Target Cluster Build Notes</h2><p>These actions do not block source migration directly, but they should shape how the destination AKS Automatic cluster is created and configured.</p><div class="action-plan-cards">`)
		body.WriteString(renderActionPlanCards(readiness.TargetClusterBuildNotes, "No build-note actions were identified."))
		body.WriteString(`</div></div>`)
	}
	body.WriteString(`</div></div><footer class="footer"><p><strong>Report generated by KubeBuddy</strong></p><p><em>This action plan is a snapshot of the evaluated migration findings.</em></p></footer></div></body></html>`)
	return body.String(), nil
}

type buildResource struct {
	Title       string
	Description string
	URL         string
}

func automaticClusterBuildResources() []buildResource {
	return []buildResource{
		{Title: "Azure portal", Description: "Official AKS Automatic quickstart with the portal flow for creating a new cluster.", URL: "https://learn.microsoft.com/en-us/azure/aks/automatic/quick-automatic-managed-network"},
		{Title: "Azure CLI", Description: "Official AKS Automatic quickstart using az aks create --sku automatic.", URL: "https://learn.microsoft.com/en-us/azure/aks/automatic/quick-automatic-managed-network"},
		{Title: "Bicep", Description: "Official AKS Automatic quickstart section with a Bicep example for a managed cluster using sku.name = Automatic.", URL: "https://learn.microsoft.com/en-us/azure/aks/automatic/quick-automatic-managed-network"},
		{Title: "Terraform (AzAPI reference)", Description: "Official managedClusters template reference showing sku.name values, including Automatic, for Terraform AzAPI-based deployments.", URL: "https://learn.microsoft.com/en-us/azure/templates/microsoft.containerservice/2025-05-02-preview/managedclusters"},
	}
}

func migrationSequence(readiness *scan.AutomaticReadiness) []string {
	hasGateway := false
	for _, action := range readiness.ActionPlan {
		if action.Key == "gateway_api" {
			hasGateway = true
			break
		}
	}
	steps := []string{
		"<strong>Step 1:</strong> Fix all blocker findings in source manifests, Helm values, and workload definitions before creating the destination cluster.",
		"<strong>Step 2:</strong> Review warning findings and clean up the items that could cause operational drift, security warnings, or migration rework after cutover.",
		"<strong>Step 4:</strong> Create the new AKS Automatic cluster using one of the supported Microsoft Learn deployment paths below.",
		"<strong>Step 5:</strong> Deploy workloads into the new cluster, validate health and traffic behavior, then perform cutover and decommission the old environment when ready.",
	}
	step3 := "<strong>Step 3:</strong> Prepare the target application routing model and confirm north-south traffic dependencies before building the new cluster."
	if hasGateway {
		step3 = "<strong>Step 3:</strong> Migrate north-south traffic from legacy Ingress assumptions to Gateway API resources and validate the target routing model before production cutover."
	}
	return []string{steps[0], steps[1], step3, steps[2], steps[3]}
}

func renderActionPlanCards(items []scan.AutomaticActionItem, empty string) string {
	if len(items) == 0 {
		return `<p>` + esc(empty) + `</p>`
	}
	var body strings.Builder
	for _, item := range items {
		body.WriteString(`<section class="action-plan-card"><div class="action-plan-card-header"><h3>` + esc(item.Title) + `</h3><span class="action-plan-count">` + esc(fmt.Sprintf("%d resources", max(item.AffectedResourceCount, item.TotalAffected))) + `</span></div><div class="action-plan-card-body">`)
		if len(item.Recommendations) > 0 {
			body.WriteString(`<h4>Recommendation</h4><ul>`)
			for _, recommendation := range item.Recommendations {
				body.WriteString(`<li>` + esc(recommendation) + `</li>`)
			}
			body.WriteString(`</ul>`)
		}
		body.WriteString(`<h4>Steps</h4><ul>`)
		for _, step := range item.Steps {
			body.WriteString(`<li>` + esc(step) + `</li>`)
		}
		body.WriteString(`</ul>`)
		if len(item.AffectedResources) > 0 {
			resourceSummary := fmt.Sprintf("Showing %d affected resources.", len(item.AffectedResources))
			if item.AffectedResourceCount > 0 && item.AffectedResourceCount < item.TotalAffected {
				resourceSummary = fmt.Sprintf("%d total findings were grouped into %d unique source resources to update.", item.TotalAffected, item.AffectedResourceCount)
			}
			body.WriteString(`<h4>Affected resources</h4><p class="action-plan-meta">` + esc(resourceSummary) + `</p><div class="table-container action-resource-table"><table><thead><tr><th>Namespace</th><th>Workload</th><th>Observed Resource</th><th>Helm Source</th></tr></thead><tbody>`)
			for _, resource := range item.AffectedResources {
				helmSource := resource.HelmSource
				if strings.TrimSpace(helmSource) == "" {
					helmSource = "-"
				}
				body.WriteString(`<tr><td>` + esc(resource.Namespace) + `</td><td>` + esc(resource.Workload) + `</td><td>` + esc(resource.ObservedResource) + `</td><td>` + esc(helmSource) + `</td></tr>`)
			}
			body.WriteString(`</tbody></table></div>`)
		}
		example := automaticManifestExample(item.Key)
		if example != "" {
			body.WriteString(`<h4>Manifest example</h4><pre><code>` + html.EscapeString(example) + `</code></pre>`)
		}
		if len(item.AdmissionNotes) > 0 {
			body.WriteString(`<h4>AKS Automatic behavior</h4><ul>`)
			for _, note := range item.AdmissionNotes {
				body.WriteString(`<li>` + esc(note) + `</li>`)
			}
			body.WriteString(`</ul>`)
		}
		if len(item.URLs) > 0 {
			body.WriteString(`<h4>Docs</h4><ul>`)
			for _, url := range item.URLs {
				body.WriteString(`<li><a href='` + escAttr(url) + `' target='_blank'>` + esc(url) + `</a></li>`)
			}
			body.WriteString(`</ul>`)
		}
		body.WriteString(`</div></section>`)
	}
	return body.String()
}

func filterActionBucket(items []scan.AutomaticActionItem, bucket string) []scan.AutomaticActionItem {
	var out []scan.AutomaticActionItem
	for _, item := range items {
		if item.Bucket == bucket {
			out = append(out, item)
		}
	}
	return out
}

func filterActionExcludingBucket(items []scan.AutomaticActionItem, bucket string) []scan.AutomaticActionItem {
	var out []scan.AutomaticActionItem
	for _, item := range items {
		if item.Bucket != bucket {
			out = append(out, item)
		}
	}
	return out
}

func readinessStatusClass(status string) string {
	switch status {
	case "ready":
		return "healthy"
	case "ready_with_changes":
		return "warning"
	default:
		return "critical"
	}
}

func automaticManifestExample(reason string) string {
	switch reason {
	case "image_tag":
		return "apiVersion: apps/v1\nkind: Deployment\nmetadata:\n  name: app\nspec:\n  template:\n    spec:\n      containers:\n        - name: app\n          image: contoso/app:1.2.3\n"
	case "resource_requests":
		return "resources:\n  requests:\n    cpu: 200m\n    memory: 256Mi\n  limits:\n    memory: 256Mi\n"
	case "health_probes":
		return "readinessProbe:\n  httpGet:\n    path: /healthz\n    port: 8080\nlivenessProbe:\n  httpGet:\n    path: /healthz\n    port: 8080\n"
	case "pod_spread":
		return "topologySpreadConstraints:\n  - maxSkew: 1\n    topologyKey: kubernetes.io/hostname\n    whenUnsatisfiable: DoNotSchedule\n    labelSelector:\n      matchLabels:\n        app: my-app\n"
	case "host_ports":
		return "ports:\n  - containerPort: 8080\n---\napiVersion: v1\nkind: Service\nmetadata:\n  name: app\nspec:\n  selector:\n    app: my-app\n  ports:\n    - port: 80\n      targetPort: 8080\n"
	case "seccomp":
		return "securityContext:\n  seccompProfile:\n    type: RuntimeDefault\n"
	case "proc_mount":
		return "securityContext:\n  procMount: Default\n"
	case "apparmor":
		return "metadata:\n  annotations:\n    container.apparmor.security.beta.kubernetes.io/app: runtime/default\n"
	case "capabilities":
		return "securityContext:\n  capabilities:\n    drop:\n      - ALL\n"
	case "service_selector":
		return "apiVersion: v1\nkind: Service\nmetadata:\n  name: app\nspec:\n  selector:\n    app: my-app\n    component: web\n"
	case "gateway_api":
		return "apiVersion: gateway.networking.k8s.io/v1\nkind: Gateway\nmetadata:\n  name: app-gateway\nspec:\n  gatewayClassName: approuting-istio\n  listeners:\n    - name: http\n      protocol: HTTP\n      port: 80\n      hostname: app.example.com\n---\napiVersion: gateway.networking.k8s.io/v1\nkind: HTTPRoute\nmetadata:\n  name: app-route\nspec:\n  parentRefs:\n    - name: app-gateway\n  hostnames:\n    - app.example.com\n  rules:\n    - matches:\n        - path:\n            type: PathPrefix\n            value: /\n      backendRefs:\n        - name: app\n          port: 80\n"
	case "host_namespace":
		return "spec:\n  hostNetwork: false\n  hostPID: false\n  hostIPC: false\n"
	case "host_path":
		return "volumes:\n  - name: app-data\n    persistentVolumeClaim:\n      claimName: app-data\n"
	case "storage_csi":
		return "apiVersion: storage.k8s.io/v1\nkind: StorageClass\nmetadata:\n  name: managed-csi\nprovisioner: disk.csi.azure.com\n"
	default:
		return ""
	}
}

func max(a, b int) int {
	if a > b {
		return a
	}
	return b
}
