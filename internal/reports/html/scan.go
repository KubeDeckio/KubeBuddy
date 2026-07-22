package html

import (
	"context"
	"encoding/json"
	"fmt"
	"html"
	"io"
	"net/http"
	"regexp"
	"sort"
	"strconv"
	"strings"
	"time"

	"github.com/KubeDeckio/KubeBuddy/internal/collector/kubernetes"
	"github.com/KubeDeckio/KubeBuddy/internal/kubeapi"
	"github.com/KubeDeckio/KubeBuddy/internal/model"
	"github.com/KubeDeckio/KubeBuddy/internal/scan"
)

type ScanRenderer struct{}

var (
	inlineBacktickPattern   = regexp.MustCompile("`([^`]+)`")
	inlineQuotedCodePattern = regexp.MustCompile(`'([^']+)'`)
)

type RenderOptions struct {
	ExcludeNamespaces        bool
	ExcludedNamespaces       []string
	IncludePrometheus        bool
	PrometheusURL            string
	PrometheusMode           string
	PrometheusBearerTokenEnv string
	Snapshot                 *kubernetes.ClusterData
}

func (ScanRenderer) Render(title string, result scan.Result, opts RenderOptions) (string, error) {
	doc := model.ReportDocument{
		Title:       "Kubernetes Cluster Report",
		GeneratedAt: time.Now().UTC(),
		BodyHTML:    buildBody(title, result, opts),
	}
	return (Renderer{}).Render(doc)
}

type reportPage struct {
	ID       string
	Name     string
	Checks   []scan.CheckResult
	Findings int
}

type reportSnapshot struct {
	Context            string
	KubernetesVersion  string
	Summary            *kubernetes.Summary
	APIHealthHTML      string
	Metrics            *kubernetes.ClusterMetrics
	NodeObjects        []map[string]any
	PodObjects         []map[string]any
	AllPodObjects      []map[string]any
	JobObjects         []map[string]any
	AllJobObjects      []map[string]any
	EventObjects       []map[string]any
	AllEventObjects    []map[string]any
	ExcludedNamespaces []string
}

func buildBody(title string, result scan.Result, opts RenderOptions) string {
	clusterName := reportClusterName(title, result)
	snapshot := collectSnapshot(opts)
	htmlChecks := compatHTMLChecks(result.Checks)
	pages, aksPage, gkePage := buildPages(scan.Result{Checks: htmlChecks, AutomaticReadiness: result.AutomaticReadiness})
	overviewChecks := overviewChecks(htmlChecks)
	totalChecks := len(overviewChecks)
	passedChecks := passedChecks(overviewChecks)
	clusterScore := score(htmlChecks)

	var body strings.Builder
	body.WriteString(`<div class="wrapper">`)
	body.WriteString(`<div class="main-content">`)
	body.WriteString(`<div class="header" id="top">`)
	body.WriteString(`<div class="header-inner">`)
	body.WriteString(`<div class="header-top">`)
	body.WriteString(`<div><span>Kubernetes Cluster Report: ` + esc(clusterName) + `</span><br><span style="font-size: 12px;">Powered by <img src="https://raw.githubusercontent.com/KubeDeckio/KubeBuddy/refs/heads/main/images/reportheader%20(2).png" alt="KubeBuddy Logo" style="height: 70px; vertical-align: middle;"></span></div>`)
	body.WriteString(`<div style="text-align: right; font-size: 13px; line-height: 1.4;">`)
	body.WriteString(`<div>Generated on: <strong>` + esc(time.Now().UTC().Format("January 02, 2006 15:04:05 UTC")) + `</strong></div>`)
	body.WriteString(`<div>Created by <a href="https://kubedeck.io" target="_blank" style="color: #ffffff; text-decoration: underline;">🌐 KubeDeck.io</a></div>`)
	body.WriteString(`<div>Documentation <a href="https://kubebuddy.io" target="_blank" style="color: #ffffff; text-decoration: underline;">📄 KubeBuddy.io</a></div>`)
	body.WriteString(`<div id="printContainer" style="margin-top: 4px;"><button id="savePdfBtn">📄 Save as PDF</button></div>`)
	body.WriteString(`</div></div>`)
	body.WriteString(`<ul class="tabs">`)
	body.WriteString(`<li class="tab active" data-tab="overview" data-tooltip="Overview">Overview</li>`)
	body.WriteString(`<li class="tab" data-tab="summary" data-tooltip="Summary">Summary</li>`)
	for _, page := range pages {
		label := tabLabel(page)
		body.WriteString(`<li class="tab" data-tab="` + escAttr(page.ID) + `" data-tooltip="` + escAttr(label) + `">` + esc(label) + `</li>`)
	}
	if len(aksPage.Checks) > 0 {
		body.WriteString(`<li class="tab" data-tab="aks" data-tooltip="AKS Best Practices">AKS Best Practices</li>`)
	}
	if len(gkePage.Checks) > 0 {
		body.WriteString(`<li class="tab" data-tab="gke" data-tooltip="GKE Best Practices">GKE Best Practices</li>`)
	}
	if len(result.DirectRiskPaths) > 0 || len(result.CombinedRiskPaths) > 0 {
		body.WriteString(`<li class="tab" data-tab="risk-paths" data-tooltip="Risk Paths">Risk Paths</li>`)
	}
	body.WriteString(`</ul></div></div>`)
	body.WriteString(`<div id="navDrawer" class="nav-drawer"><div class="nav-header"><h3>Menu</h3><button id="navClose" class="nav-close">×</button></div><ul class="nav-items"></ul></div>`)
	body.WriteString(`<div id="navScrim" class="nav-scrim"></div>`)
	body.WriteString(`<button id="menuFab" class="menu-btn"><i id="menuIcon" class="material-icons">menu</i></button>`)
	body.WriteString(`<div>`)

	body.WriteString(`<div class="tab-content active" id="overview"><div class="container">`)
	body.WriteString(`<h1 id="Health">Cluster Overview</h1>`)
	body.WriteString(`<p><strong>Cluster Name:</strong> ` + esc(clusterName) + `</p>`)
	body.WriteString(`<div class="cluster-health">`)
	body.WriteString(`<div class="health-score">`)
	body.WriteString(`<div class="score-container">`)
	body.WriteString(`<h2 class="cluster-health-score">Cluster Health Score</h2>`)
	body.WriteString(fmt.Sprintf(`<p>Score: <strong>%d / 100</strong></p>`, clusterScore))
	body.WriteString(fmt.Sprintf(`<div class="progress-bar" style="--cluster-score: %d;" role="progressbar" aria-label="Cluster Health Score: %d out of 100"><div class="progress %s" style="width: 0%%;"><span class="progress-text">%d%%</span></div></div>`, clusterScore, clusterScore, scoreClass(clusterScore), clusterScore))
	body.WriteString(`<p style="margin-top:10px; font-size:16px;">This score is calculated from key checks across nodes, workloads, security, and configuration best practices. A higher score means fewer issues and better adherence to Kubernetes standards.</p>`)
	body.WriteString(`</div></div>`)
	body.WriteString(`<div class="api-summary"><h2>API Server Health</h2>`)
	body.WriteString(snapshot.APIHealthHTML)
	body.WriteString(`</div>`)
	body.WriteString(renderPassRateBlock(passedChecks, totalChecks))
	body.WriteString(`</div>`)
	body.WriteString(`<h2>Top 5 Improvements</h2>`)
	body.WriteString(`<p class="quick-fix-intro">These are the five checks whose remediation will yield the most immediate benefit to your overall Cluster Health Score. Each card shows the cluster score points you’ll recover by fixing it.</p>`)
	body.WriteString(`<div class="quick-fixes-grid">`)
	for _, improvement := range topImprovements(overviewChecks, 5) {
		name := improvement.Check.Name
		if improvement.Check.ID == "SC002" {
			name = "StorageClass Prevents Volume Expansion AKS Azure In-Tree Storage Provisioners"
		}
		body.WriteString(`<div class="quick-fix-card" data-lostpct="` + escAttr(improvement.Category) + `"><header class="card-header"><span class="material-icons fix-icon">home_repair_service</span><a href="#` + escAttr(improvement.Check.ID) + `" class="fix-id">` + esc(improvement.Check.ID) + `</a><span class="fix-metrics">+ ` + esc(formatGainPoints(improvement.GainPoints)) + ` pts</span></header><p class="fix-name">` + esc(name) + `</p></div>`)
	}
	body.WriteString(`</div>`)
	body.WriteString(renderIssueSummary(overviewChecks))
	body.WriteString(renderRightsizingAtGlance(scan.Result{Checks: htmlChecks, AutomaticReadiness: result.AutomaticReadiness}, snapshot))
	if len(snapshot.ExcludedNamespaces) > 0 {
		body.WriteString(`<h2>Excluded Namespaces <span class="tooltip"><span class="info-icon">i</span><span class="tooltip-text">These namespaces are excluded from analysis and reporting.</span></span></h2><p>`)
		for i, ns := range snapshot.ExcludedNamespaces {
			if i > 0 {
				body.WriteString(` <span class='excluded-separator'>•</span> `)
			}
			body.WriteString(`<span class='excluded-ns'>` + esc(ns) + `</span>`)
		}
		body.WriteString(`</p>`)
	}
	body.WriteString(`</div></div>`)

	body.WriteString(renderSummaryTab(clusterName, snapshot))
	for _, page := range pages {
		body.WriteString(renderPage(page, snapshot, result.DirectRiskPaths, result.CombinedRiskPaths))
	}
	if len(aksPage.Checks) > 0 {
		body.WriteString(renderAKSPage(aksPage, result.AutomaticReadiness))
	}
	if len(gkePage.Checks) > 0 {
		body.WriteString(renderGKEPage(gkePage))
	}
	if len(result.DirectRiskPaths) > 0 || len(result.CombinedRiskPaths) > 0 {
		body.WriteString(renderDirectRiskPathsPage(result.DirectRiskPaths, result.CombinedRiskPaths, htmlChecks))
	}

	body.WriteString(`</div>`)
	body.WriteString(`</div>`)
	body.WriteString(`<footer class="footer"><p><strong>Report generated by KubeBuddy</strong> on ` + esc(time.Now().UTC().Format("2006-01-02 15:04 UTC")) + `</p><p><em>This report is a snapshot of the cluster state at the time of generation.</em></p></footer>`)
	body.WriteString(`</div><a href="#top" id="backToTop">Back to Top</a>`)
	return body.String()
}

func renderRiskPathGraph(graph *scan.RiskPathGraph) string {
	if graph == nil || len(graph.Nodes) == 0 {
		return ""
	}
	model := riskPathGraphModel(graph)
	var b strings.Builder
	b.WriteString(`<h3>Path Graph</h3>`)
	b.WriteString(`<div class="risk-path-graph">`)
	b.WriteString(`<div class="risk-path-graph-row">`)
	for i, node := range model.Path {
		if i > 0 {
			b.WriteString(`<div class="risk-path-edge"><span>` + esc(node.EdgeLabel) + `</span><span>&rarr;</span></div>`)
		}
		b.WriteString(`<div class="risk-path-graph-node" style="--risk-path-accent:` + node.Color + `;">`)
		b.WriteString(`<strong>` + esc(node.Label) + `</strong>`)
		b.WriteString(`<span>` + esc(node.SubLabel) + `</span>`)
		b.WriteString(`</div>`)
	}
	b.WriteString(`</div>`)
	b.WriteString(`<div class="risk-path-step-row">`)
	for _, step := range model.Steps {
		b.WriteString(`<span class="risk-path-step" style="--risk-path-accent:` + step.Color + `;">` + esc(step.Text) + `</span>`)
	}
	b.WriteString(`</div>`)
	if len(graph.Edges) > 0 {
		b.WriteString(`<div class="collapsible-container"><details class="risk-path-subsection"><summary>Graph edges</summary><div class="risk-path-muted">`)
		for _, edge := range graph.Edges {
			b.WriteString(`<div>` + esc(edge.From) + ` &rarr; ` + esc(edge.To) + `: ` + esc(edge.Label) + `</div>`)
		}
		b.WriteString(`</div></details></div>`)
	}
	b.WriteString(`</div>`)
	return b.String()
}

type capabilityAttackGraphStep struct {
	Text  string
	Color string
}

type capabilityAttackGraphPathNode struct {
	EdgeLabel string
	Label     string
	SubLabel  string
	Color     string
}

type riskPathGraphModelResult struct {
	Steps []capabilityAttackGraphStep
	Path  []capabilityAttackGraphPathNode
}

type capabilityGraphProfile struct {
	SourceLabel     string
	ControlLabel    string
	ControlSubLabel string
	TargetLabel     string
	TargetSubLabel  string
	FirstEdge       string
	SecondEdge      string
}

func riskPathGraphModel(graph *scan.RiskPathGraph) riskPathGraphModelResult {
	incoming := map[string]int{}
	outgoing := map[string]int{}
	for _, node := range graph.Nodes {
		incoming[node.ID] = 0
		outgoing[node.ID] = 0
	}
	for _, edge := range graph.Edges {
		incoming[edge.To]++
		outgoing[edge.From]++
	}
	var sources, targets []scan.RiskPathGraphNode
	for _, node := range graph.Nodes {
		if incoming[node.ID] == 0 {
			sources = append(sources, node)
		}
		if outgoing[node.ID] == 0 {
			targets = append(targets, node)
		}
	}
	target := graph.Nodes[len(graph.Nodes)-1]
	if len(targets) > 0 {
		target = targets[0]
	}
	profile := boundaryGraphProfile(target.ID)
	sourceCount := len(sources)
	if sourceCount == 0 {
		sourceCount = len(graph.Nodes)
	}
	sourceText := fmt.Sprintf("%d finding signals detected", sourceCount)
	if strings.EqualFold(target.Type, "combinedRiskPath") {
		sourceText = "Multiple direct risk paths chained"
	}
	sourceSubLabel := "cluster observations"
	var sourceLabels []string
	for _, source := range sources {
		label := source.CheckID
		if strings.TrimSpace(label) == "" {
			label = source.Label
		}
		if strings.TrimSpace(label) != "" {
			sourceLabels = append(sourceLabels, label)
		}
		if len(sourceLabels) == 3 {
			break
		}
	}
	if len(sourceLabels) > 0 {
		sourceSubLabel = strings.Join(sourceLabels, ", ")
	}
	return riskPathGraphModelResult{
		Steps: []capabilityAttackGraphStep{
			{Text: sourceText, Color: "var(--danger,#ef4444)"},
			{Text: profile.ControlLabel + " is missing or weak", Color: "var(--warning,#f59e0b)"},
			{Text: profile.TargetLabel + " is reachable", Color: "var(--brand-blue,#4299e1)"},
		},
		Path: []capabilityAttackGraphPathNode{
			{Label: profile.SourceLabel, SubLabel: sourceSubLabel, Color: "var(--brand-blue,#4299e1)"},
			{EdgeLabel: profile.FirstEdge, Label: profile.ControlLabel, SubLabel: profile.ControlSubLabel, Color: "var(--warning,#f59e0b)"},
			{EdgeLabel: profile.SecondEdge, Label: profile.TargetLabel, SubLabel: profile.TargetSubLabel, Color: "var(--danger,#ef4444)"},
		},
	}
}

func boundaryGraphProfile(id string) capabilityGraphProfile {
	switch strings.ToUpper(strings.TrimSpace(id)) {
	case "RISK001":
		return capabilityGraphProfile{SourceLabel: "Workload Signals", ControlLabel: "Container Isolation", ControlSubLabel: "privilege, host access, or escape path", TargetLabel: "Node Access Risk", TargetSubLabel: "WORKLOAD TO NODE", FirstEdge: "weakens", SecondEdge: "exposes"}
	case "RISK002":
		return capabilityGraphProfile{SourceLabel: "Network and RBAC Signals", ControlLabel: "Namespace Isolation", ControlSubLabel: "east-west or identity controls", TargetLabel: "Cross-Namespace Risk", TargetSubLabel: "TENANCY PATH", FirstEdge: "crosses", SecondEdge: "exposes"}
	case "RISK003":
		return capabilityGraphProfile{SourceLabel: "RBAC Signals", ControlLabel: "Authorization Controls", ControlSubLabel: "over-broad identity permissions", TargetLabel: "Privilege Escalation Risk", TargetSubLabel: "IDENTITY PATH", FirstEdge: "grants", SecondEdge: "escalates"}
	case "RISK004":
		return capabilityGraphProfile{SourceLabel: "ServiceAccount Signals", ControlLabel: "Weak ServiceAccount Trust", ControlSubLabel: "token automount, default identity, or sensitive binding", TargetLabel: "Workload Identity Risk", TargetSubLabel: "BOUNDARY TARGET", FirstEdge: "trusts", SecondEdge: "exposes"}
	case "RISK007":
		return capabilityGraphProfile{SourceLabel: "Secret Exposure Signals", ControlLabel: "Secret Handling Controls", ControlSubLabel: "secret material, config data, or read paths", TargetLabel: "Credential Exposure Risk", TargetSubLabel: "CREDENTIAL PATH", FirstEdge: "exposes", SecondEdge: "enables"}
	case "CHAIN001":
		return capabilityGraphProfile{SourceLabel: "Chained Risk Paths", ControlLabel: "Workload and RBAC Controls", ControlSubLabel: "combined node and identity exposure", TargetLabel: "Cluster Control Path", TargetSubLabel: "MULTI-STAGE PATH", FirstEdge: "chains", SecondEdge: "enables"}
	case "CHAIN002":
		return capabilityGraphProfile{SourceLabel: "Chained Risk Paths", ControlLabel: "Namespace and RBAC Controls", ControlSubLabel: "combined tenant and identity exposure", TargetLabel: "Cross-Namespace Privilege Path", TargetSubLabel: "MULTI-STAGE PATH", FirstEdge: "chains", SecondEdge: "enables"}
	case "CHAIN003":
		return capabilityGraphProfile{SourceLabel: "Workload Identity", ControlLabel: "ServiceAccount and RBAC Controls", ControlSubLabel: "service account trust plus identity escalation", TargetLabel: "Cluster Control Path", TargetSubLabel: "MULTI-STAGE PATH", FirstEdge: "chains", SecondEdge: "enables"}
	case "CHAIN005":
		return capabilityGraphProfile{SourceLabel: "Credential Exposure", ControlLabel: "Secret and RBAC Controls", ControlSubLabel: "secret exposure plus identity escalation", TargetLabel: "Cluster Control Path", TargetSubLabel: "MULTI-STAGE PATH", FirstEdge: "chains", SecondEdge: "enables"}
	default:
		return capabilityGraphProfile{SourceLabel: "Finding Signals", ControlLabel: "Risk Area", ControlSubLabel: "missing or ineffective guardrail", TargetLabel: "Risk Path", TargetSubLabel: "PATH TARGET", FirstEdge: "correlate", SecondEdge: "enables"}
	}
}

func renderRiskPathValidationProof(capability scan.DirectRiskPath) string {
	if len(capability.ValidationProof) == 0 {
		return `<p style="margin:0;color:var(--text-muted,#94a3b8);">No validation commands are defined for this risk area yet.</p>`
	}
	var commands []string
	for _, command := range capability.ValidationProof {
		commands = append(commands, command.Command)
	}
	var b strings.Builder
	b.WriteString(`<div class="risk-path-action-row"><button class="kb-copy-command risk-path-button" type="button" data-copy="` + escAttr(strings.Join(commands, "\n\n")) + `">Copy all</button></div>`)
	b.WriteString(`<div class="risk-path-proof-list">`)
	for _, command := range capability.ValidationProof {
		state := "changes cluster state"
		class := "warning"
		if command.ReadOnly {
			state = "read-only"
			class = "normal"
		}
		b.WriteString(`<div class="risk-path-proof-item">`)
		b.WriteString(`<div class="risk-path-proof-header"><strong>` + esc(command.Title) + `</strong><span class="risk-path-chip ` + escAttr(class) + `">` + esc(state) + `</span></div>`)
		b.WriteString(`<p>` + esc(command.Purpose) + `</p>`)
		b.WriteString(`<pre class="risk-path-command-code"><code>` + esc(command.Command) + `</code></pre>`)
		b.WriteString(`<div class="risk-path-action-row"><button class="kb-copy-command risk-path-button" type="button" data-copy="` + escAttr(command.Command) + `">Copy</button></div>`)
		b.WriteString(`</div>`)
	}
	b.WriteString(`</div>`)
	return b.String()
}

type boundaryFixItem struct {
	ID       string
	Name     string
	Severity string
	Count    int
}

func riskPathFixFirstItems(directRiskPaths []scan.DirectRiskPath, checksByID map[string]scan.CheckResult) []boundaryFixItem {
	seen := map[string]struct{}{}
	var items []boundaryFixItem
	for _, capability := range directRiskPaths {
		if !strings.EqualFold(capability.Status, "triggered") {
			continue
		}
		for _, evidence := range capability.Evidence {
			id := strings.TrimSpace(evidence.CheckID)
			if id == "" {
				continue
			}
			if _, ok := seen[id]; ok {
				continue
			}
			seen[id] = struct{}{}
			name := evidence.CheckName
			severity := evidence.Severity
			count := evidence.FindingCount
			if check, ok := checksByID[id]; ok {
				name = firstNonEmpty(check.Name, name)
				severity = firstNonEmpty(check.Severity, severity)
				if check.Total > 0 {
					count = check.Total
				}
			}
			items = append(items, boundaryFixItem{ID: id, Name: name, Severity: severity, Count: count})
		}
	}
	sort.SliceStable(items, func(i, j int) bool {
		left := severityRank(items[i].Severity)
		right := severityRank(items[j].Severity)
		if left != right {
			return left > right
		}
		return items[i].Count > items[j].Count
	})
	if len(items) > 5 {
		return items[:5]
	}
	return items
}

func severityRank(severity string) int {
	switch strings.ToLower(strings.TrimSpace(severity)) {
	case "critical", "error":
		return 5
	case "high":
		return 4
	case "medium", "warning":
		return 3
	case "low":
		return 2
	default:
		return 1
	}
}

func boundaryImpact(id string) string {
	switch strings.ToUpper(strings.TrimSpace(id)) {
	case "RISK001":
		return "Workload can reach node-level controls or host data."
	case "RISK002":
		return "Namespace controls may not contain workload access."
	case "RISK003":
		return "Identities may cross intended authorization controls."
	case "RISK004":
		return "Workload identities and ServiceAccount tokens may be trusted too broadly."
	case "RISK007":
		return "Secret exposure findings may combine with credential access or identity paths."
	case "CHAIN001":
		return "Workload and identity issues combine into cluster-control risk."
	case "CHAIN002":
		return "Namespace and identity issues combine into cross-namespace privilege risk."
	case "CHAIN003":
		return "ServiceAccount trust and RBAC overexposure can combine into cluster-control risk."
	case "CHAIN005":
		return "Secret exposure and RBAC overexposure can combine into cluster-control risk."
	default:
		return "Correlated findings weaken a named risk area."
	}
}

func boundaryBlastRadius(id string) string {
	switch strings.ToUpper(strings.TrimSpace(id)) {
	case "RISK001":
		return "Workload to node/container isolation"
	case "RISK002":
		return "Namespace tenancy and east-west isolation"
	case "RISK003":
		return "Identity authorization and privilege controls"
	case "RISK004":
		return "ServiceAccount identity and token trust"
	case "RISK007":
		return "Secret data, ConfigMaps, and credential access paths"
	case "CHAIN001":
		return "Workload to cluster control"
	case "CHAIN002":
		return "Cross-namespace privilege path"
	case "CHAIN003":
		return "ServiceAccount identity to cluster authorization path"
	case "CHAIN005":
		return "Credential exposure to cluster authorization path"
	default:
		return "Cluster risk area"
	}
}

func boundaryVerdictDirectRiskPath(capability scan.DirectRiskPath) string {
	if !strings.EqualFold(capability.Status, "triggered") {
		return capability.Name + " is clear because the required correlated signals were not found in this scan."
	}
	ids := make([]string, 0, len(capability.Evidence))
	for _, evidence := range capability.Evidence {
		if strings.TrimSpace(evidence.CheckID) != "" {
			ids = append(ids, evidence.CheckID)
		}
		if len(ids) == 4 {
			break
		}
	}
	suffix := ""
	if extra := len(capability.Evidence) - len(ids); extra > 0 {
		suffix = fmt.Sprintf(", and %d more", extra)
	}
	return fmt.Sprintf("%s is active because %s%s indicate %s risk.", capability.Name, strings.Join(ids, ", "), suffix, strings.ToLower(boundaryBlastRadius(capability.ID)))
}

func boundaryVerdictCombinedRiskPath(compound scan.CombinedRiskPath) string {
	if !strings.EqualFold(compound.Status, "triggered") {
		return compound.Name + " is clear because the required active risk areas were not found in this scan."
	}
	return fmt.Sprintf("%s is possible because %s are active in this scan.", compound.Name, strings.Join(compound.Requires, " and "))
}

func renderBoundaryVerdict(text, class string) string {
	return `<div class="risk-path-verdict ` + escAttr(class) + `">` + esc(text) + `</div>`
}

func renderSampleFinding(finding scan.Finding) string {
	location := finding.Resource
	if strings.TrimSpace(finding.Namespace) != "" {
		location += " in " + finding.Namespace
	}
	detail := firstNonEmpty(finding.Message, finding.Value)
	if strings.TrimSpace(detail) != "" {
		return location + ": " + detail
	}
	return location
}
func renderBoundaryImpactRow(id, fixPriority string) string {
	return `<div class="risk-path-info-grid">` +
		`<div><strong>Impact</strong><span>` + esc(boundaryImpact(id)) + `</span></div>` +
		`<div><strong>Blast radius</strong><span>` + esc(boundaryBlastRadius(id)) + `</span></div>` +
		`<div><strong>Fix priority</strong><span>` + esc(firstNonEmpty(fixPriority, "normal")) + `</span></div>` +
		`</div>`
}

func renderBoundaryFixFirstPanel(items []boundaryFixItem) string {
	if len(items) == 0 {
		return ""
	}
	var b strings.Builder
	b.WriteString(`<div class="table-container"><h2>Fix First</h2><p class="risk-path-muted">These checks contribute to active risk paths and should give the clearest reduction in correlated risk.</p><div class="risk-path-fix-grid">`)
	for _, item := range items {
		b.WriteString(`<a class="risk-path-check-link" href="#` + escAttr(item.ID) + `" data-check-id="` + escAttr(item.ID) + `"><div class="risk-path-row"><span class="risk-path-chip default">` + esc(item.ID) + `</span><span class="risk-path-chip ` + escAttr(issueSummaryBucket(item.Severity)) + `">` + esc(firstNonEmpty(item.Severity, "unknown")) + `</span></div><strong>` + esc(item.Name) + `</strong><span>` + strconv.Itoa(item.Count) + ` findings</span></a>`)
	}
	b.WriteString(`</div></div>`)
	return b.String()
}

func renderRiskPathEvidence(evidenceItems []scan.RiskPathEvidence) string {
	if len(evidenceItems) == 0 {
		return `<p style="margin:0;color:var(--text-muted,#94a3b8);">No evidence was captured for this risk path.</p>`
	}
	var b strings.Builder
	b.WriteString(`<div class="table-container risk-path-table-container"><table class="risk-path-table"><thead><tr><th>Check</th><th>Findings</th><th>Sample affected resources</th><th>Action</th></tr></thead><tbody>`)
	for _, evidence := range evidenceItems {
		b.WriteString(`<tr>`)
		b.WriteString(`<td><span class="risk-path-chip default">` + esc(evidence.CheckID) + `</span><strong class="risk-path-table-title">` + esc(evidence.CheckName) + `</strong></td>`)
		b.WriteString(`<td>` + strconv.Itoa(evidence.FindingCount) + `</td>`)
		b.WriteString(`<td>`)
		if len(evidence.SampleFindings) > 0 {
			b.WriteString(`<ul class="risk-path-sample-list">`)
			for _, finding := range evidence.SampleFindings {
				b.WriteString(`<li>` + esc(renderSampleFinding(finding)) + `</li>`)
			}
			b.WriteString(`</ul>`)
		} else {
			b.WriteString(`<span class="risk-path-muted">No samples captured</span>`)
		}
		b.WriteString(`</td>`)
		b.WriteString(`<td><a class="risk-path-check-link" href="#` + escAttr(evidence.CheckID) + `" data-check-id="` + escAttr(evidence.CheckID) + `">View check</a></td>`)
		b.WriteString(`</tr>`)
	}
	b.WriteString(`</tbody></table></div>`)
	return b.String()
}

func renderDirectRiskPathCard(capability scan.DirectRiskPath) string {
	statusClass := "normal"
	if strings.EqualFold(capability.Status, "triggered") {
		statusClass = "critical"
	}
	var b strings.Builder
	b.WriteString(`<div class="collapsible-container"><details class="risk-path-card">`)
	b.WriteString(`<summary><span class="risk-path-card-main"><span class="risk-path-title-row"><strong>` + esc(capability.Name) + `</strong><span class="risk-path-chip default">` + esc(capability.ID) + `</span><span class="risk-path-chip ` + statusClass + `">` + esc(capability.Status) + `</span></span><span class="risk-path-summary">` + esc(capability.Summary) + `</span></span><span class="risk-path-meta"><span class="risk-path-chip default">confidence ` + esc(capability.Confidence) + `</span><span class="risk-path-chip default">priority ` + esc(capability.FixPriority) + `</span></span></summary>`)
	b.WriteString(`<div class="risk-path-card-body">`)
	b.WriteString(renderBoundaryVerdict(boundaryVerdictDirectRiskPath(capability), statusClass))
	b.WriteString(renderBoundaryImpactRow(capability.ID, capability.FixPriority))
	b.WriteString(`<div class="collapsible-container"><details open class="risk-path-subsection"><summary>Validation proof</summary><div>`)
	b.WriteString(renderRiskPathValidationProof(capability))
	b.WriteString(`</div></details></div>`)
	if capability.AttackGraph != nil {
		b.WriteString(`<div class="collapsible-container"><details class="risk-path-subsection"><summary>Path graph</summary><div>`)
		b.WriteString(renderRiskPathGraph(capability.AttackGraph))
		b.WriteString(`</div></details></div>`)
	}
	b.WriteString(`<div class="collapsible-container"><details class="risk-path-subsection"><summary>Evidence (` + strconv.Itoa(len(capability.Evidence)) + `)</summary><div>`)
	b.WriteString(renderRiskPathEvidence(capability.Evidence))
	b.WriteString(`</div></details></div></div></details></div>`)
	return b.String()
}

func renderCombinedRiskPathCard(compound scan.CombinedRiskPath) string {
	statusClass := "normal"
	if strings.EqualFold(compound.Status, "triggered") {
		statusClass = "critical"
	}
	var b strings.Builder
	b.WriteString(`<div class="collapsible-container"><details class="risk-path-card">`)
	b.WriteString(`<summary><span class="risk-path-card-main"><span class="risk-path-title-row"><strong>` + esc(compound.Name) + `</strong><span class="risk-path-chip default">` + esc(compound.ID) + `</span><span class="risk-path-chip ` + statusClass + `">` + esc(compound.Status) + `</span></span><span class="risk-path-summary">` + esc(compound.Summary) + `</span></span><span class="risk-path-meta"><span class="risk-path-chip default">confidence ` + esc(compound.Confidence) + `</span><span class="risk-path-chip default">priority ` + esc(compound.FixPriority) + `</span></span></summary>`)
	b.WriteString(`<div class="risk-path-card-body">`)
	b.WriteString(renderBoundaryVerdict(boundaryVerdictCombinedRiskPath(compound), statusClass))
	b.WriteString(renderBoundaryImpactRow(compound.ID, compound.FixPriority))
	b.WriteString(`<div class="collapsible-container"><details open class="risk-path-subsection"><summary>Required direct paths</summary><p class="risk-path-muted">` + esc(strings.Join(compound.Requires, ", ")) + `</p></details></div>`)
	if compound.AttackGraph != nil {
		b.WriteString(`<div class="collapsible-container"><details class="risk-path-subsection"><summary>Path graph</summary><div>`)
		b.WriteString(renderRiskPathGraph(compound.AttackGraph))
		b.WriteString(`</div></details></div>`)
	}
	b.WriteString(`</div></details></div>`)
	return b.String()
}

func renderCapabilityCopyScript() string {
	return `<script>(()=>{const activateTab=(id)=>{document.querySelectorAll('.tabs li').forEach((tab)=>tab.classList.toggle('active',tab.getAttribute('data-tab')===id));document.querySelectorAll('.tab-content').forEach((pane)=>pane.classList.toggle('active',pane.id===id));};document.querySelectorAll('#risk-paths .kb-copy-command').forEach((button)=>{button.addEventListener('click',async()=>{try{await navigator.clipboard.writeText(button.getAttribute('data-copy')||'');const prev=button.textContent||'Copy';button.textContent='Copied';setTimeout(()=>{button.textContent=prev;},1600);}catch{}});});document.querySelectorAll('.risk-path-tab-link').forEach((link)=>{link.addEventListener('click',(event)=>{event.preventDefault();activateTab('risk-paths');const target=document.getElementById('risk-paths');window.setTimeout(()=>{target?.scrollIntoView({behavior:'smooth',block:'start'});},0);history.replaceState(null,'','#risk-paths');});});const escSel=(value)=>String(value||'').replace(/["\\]/g,'\\$&');document.querySelectorAll('#risk-paths .risk-path-check-link').forEach((link)=>{link.addEventListener('click',(event)=>{const checkID=link.getAttribute('data-check-id')||link.getAttribute('href')?.slice(1);if(!checkID)return;const selector=escSel(checkID);const heading=document.querySelector('h2[id="'+selector+'"]');const details=document.querySelector('details[id="'+selector+'"]');const target=heading||details;if(!target)return;event.preventDefault();const tabPane=target.closest('.tab-content');if(tabPane){activateTab(tabPane.id);}if(details)details.open=true;window.setTimeout(()=>{target.scrollIntoView({behavior:'smooth',block:'start'});},0);history.replaceState(null,'','#'+checkID);});});})();</script>`
}

func riskPathsScopedCSS() string {
	return `<style>
#risk-paths{--risk-path-surface:var(--bg-container);--risk-path-panel:var(--bg-panel);--risk-path-border:var(--border-color);--risk-path-border-strong:color-mix(in srgb,var(--brand-blue) 34%,var(--border-color));--risk-path-header:var(--bg-panel);--risk-path-muted:color-mix(in srgb,var(--text-dark) 68%,transparent);--risk-path-code-bg:color-mix(in srgb,var(--bg-panel) 82%,#000 18%);--risk-path-shadow:none;}
#risk-paths .risk-path-muted{color:var(--risk-path-muted);margin:.35rem 0;}
#risk-paths .risk-path-summary-grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(220px,1fr));gap:.8rem;margin:1rem 0;}
#risk-paths .risk-path-summary-card{display:flex;align-items:center;justify-content:space-between;gap:1rem;min-height:88px;padding:1rem 1.2rem;border-radius:var(--border-radius);border:1px solid var(--risk-path-border);background:var(--risk-path-surface);box-shadow:var(--risk-path-shadow);}
#risk-paths .risk-path-summary-card span{display:block;color:var(--risk-path-muted);font-weight:700;}
#risk-paths .risk-path-summary-card small{display:block;margin-top:.2rem;color:var(--risk-path-muted);}
#risk-paths .risk-path-summary-card strong{display:block;font-size:2.15rem;line-height:1;color:var(--text-dark);}
#risk-paths .risk-paths-section{padding-top:1.1rem;}
#risk-paths .collapsible-container > details{border:1px solid var(--risk-path-border);border-radius:var(--border-radius);background:var(--risk-path-surface);box-shadow:var(--risk-path-shadow);overflow:hidden;}
#risk-paths .risk-path-card{margin:.85rem 0;}
#risk-paths .risk-path-card > summary{cursor:pointer;display:flex;gap:.7rem;align-items:flex-start;padding:var(--spacing-sm) 3rem var(--spacing-sm) var(--spacing-md);background:var(--risk-path-header);position:relative;color:var(--brand-blue);font-weight:500;transition:background var(--transition);}
#risk-paths .risk-path-card > summary:hover{background:rgba(0,113,255,.1);}
#risk-paths .risk-path-card-main{flex:1 1 auto;min-width:0;}
#risk-paths .risk-path-title-row{display:flex;gap:.45rem;align-items:center;flex-wrap:wrap;}
#risk-paths .risk-path-title-row strong{font-size:1rem;line-height:1.25;overflow-wrap:anywhere;}
#risk-paths .risk-path-summary{display:block;margin-top:.3rem;color:var(--risk-path-muted);line-height:1.45;}
#risk-paths .risk-path-meta{display:flex;gap:.35rem;flex-wrap:wrap;justify-content:flex-end;max-width:260px;}
#risk-paths .risk-path-card-body{padding:.25rem var(--spacing-md) var(--spacing-md);}
#risk-paths .risk-path-verdict{margin:.75rem 0;padding:.65rem .75rem;border-radius:var(--border-radius);border:1px solid var(--risk-path-border-strong);font-weight:700;line-height:1.45;}
#risk-paths .risk-path-verdict.critical{background:color-mix(in srgb,var(--error-color) 14%,var(--risk-path-surface));}
#risk-paths .risk-path-verdict.normal{background:color-mix(in srgb,var(--success-color) 14%,var(--risk-path-surface));}
#risk-paths .risk-path-info-grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(190px,1fr));gap:.55rem;margin:.75rem 0;}
#risk-paths .risk-path-info-grid > div,#risk-paths .risk-path-graph{padding:.65rem;border:1px solid var(--risk-path-border);border-radius:var(--border-radius);background:var(--risk-path-panel);}
#risk-paths .risk-path-info-grid strong,#risk-paths .risk-path-info-grid span{display:block;}
#risk-paths .risk-path-info-grid span{margin-top:.2rem;color:var(--risk-path-muted);}
#risk-paths .risk-path-subsection{padding:0;margin:.7rem 0 0;}
#risk-paths .risk-path-subsection > summary{cursor:pointer;font-weight:500;padding:var(--spacing-sm) 2.6rem var(--spacing-sm) var(--spacing-md);background:var(--risk-path-header);position:relative;color:var(--brand-blue);transition:background var(--transition);}
#risk-paths .risk-path-subsection > summary:hover{background:rgba(0,113,255,.1);}
#risk-paths .risk-path-subsection > div,#risk-paths .risk-path-subsection > p{padding:.7rem var(--spacing-md);margin:0;}
#risk-paths .risk-path-row{display:flex;gap:.5rem;align-items:center;flex-wrap:wrap;}
#risk-paths .risk-path-row strong{flex:1 1 180px;min-width:0;overflow-wrap:anywhere;}
#risk-paths .risk-path-action-row{display:flex;justify-content:flex-end;margin:0 0 .55rem;}
#risk-paths .risk-path-button{border:1px solid var(--risk-path-border-strong);background:color-mix(in srgb,var(--brand-blue) 10%,var(--risk-path-surface));color:var(--brand-blue);border-radius:6px;padding:.25rem .55rem;cursor:pointer;}
#risk-paths .risk-path-table-container{margin:.55rem 0 0;padding:0;background:transparent;border:0;box-shadow:none;}
#risk-paths .risk-path-table{margin:.35rem 0 0;}
#risk-paths .risk-path-table th{white-space:normal;}
#risk-paths .risk-path-table td{vertical-align:top;}
#risk-paths .risk-path-table-title{display:block;margin-top:.35rem;line-height:1.35;}
#risk-paths .risk-path-command-code{margin:0;white-space:pre-wrap;overflow:auto;width:100%;max-width:none;box-sizing:border-box;padding:.55rem;border-radius:6px;background:var(--risk-path-code-bg);color:inherit;}
#risk-paths .risk-path-command-code code{display:block;background:transparent;padding:0;color:inherit;}
#risk-paths .risk-path-proof-list{display:grid;gap:.75rem;}
#risk-paths .risk-path-proof-item{padding:.75rem;border:1px solid var(--risk-path-border);border-radius:var(--border-radius);background:var(--risk-path-panel);}
#risk-paths .risk-path-proof-item p{margin:.45rem 0;color:var(--risk-path-muted);}
#risk-paths .risk-path-proof-header{display:flex;align-items:center;justify-content:space-between;gap:.75rem;flex-wrap:wrap;}
#risk-paths .risk-path-graph{margin:.6rem 0 .8rem;}
#risk-paths .risk-path-graph-row{display:flex;align-items:center;justify-content:center;gap:.65rem;flex-wrap:wrap;}
#risk-paths .risk-path-graph-node{flex:0 1 220px;min-width:0;min-height:68px;text-align:center;padding:.7rem;border-radius:var(--border-radius);border:1px solid var(--risk-path-accent);box-shadow:inset 3px 0 0 var(--risk-path-accent);background:var(--risk-path-surface);}
#risk-paths .risk-path-graph-node strong,#risk-paths .risk-path-graph-node span{display:block;overflow-wrap:anywhere;}
#risk-paths .risk-path-graph-node span{margin-top:.25rem;font-size:.76rem;color:var(--risk-path-muted);}
#risk-paths .risk-path-edge{display:flex;flex-direction:column;align-items:center;justify-content:center;color:var(--risk-path-muted);font-weight:900;min-width:44px;}
#risk-paths .risk-path-edge span:first-child{font-size:.72rem;}
#risk-paths .risk-path-step-row{display:flex;gap:.45rem;flex-wrap:wrap;margin-top:.75rem;}
#risk-paths .risk-path-step{display:inline-flex;align-items:center;padding:.22rem .5rem;border-radius:999px;border:1px solid var(--risk-path-accent);color:var(--risk-path-accent);font-size:.78rem;font-weight:800;}
#risk-paths .risk-path-fix-grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(220px,1fr));gap:.65rem;}
#risk-paths .risk-path-fix-grid a{display:block;text-decoration:none;color:inherit;padding:.75rem;border-radius:var(--border-radius);border:1px solid var(--risk-path-border);background:var(--risk-path-surface);}
#risk-paths .risk-path-fix-grid a > strong,#risk-paths .risk-path-fix-grid a > span:last-child{display:block;margin-top:.35rem;}
#risk-paths .risk-path-fix-grid a > span:last-child{color:var(--risk-path-muted);}
#risk-paths .risk-path-table a{font-weight:700;}
#risk-paths .risk-path-sample-list{margin:0;padding-left:1.1rem;color:var(--risk-path-muted);}
#risk-paths .risk-path-sample-list li{margin:.15rem 0;overflow-wrap:anywhere;}
html[data-kb-theme="radar"] #risk-paths{--risk-path-surface:#273449;--risk-path-panel:transparent;--risk-path-border:#3b4b63;--risk-path-border-strong:#3f5677;--risk-path-header:#1c2a3f;--risk-path-muted:#94a3b8;--risk-path-code-bg:#182338;--risk-path-shadow:none;}
html[data-kb-theme="radar"] #risk-paths .collapsible-container > details{border:0;border-radius:12px;background:linear-gradient(180deg,rgba(33,47,69,.96),rgba(30,43,63,.96));overflow:hidden;margin-bottom:12px;}
html[data-kb-theme="radar"] #risk-paths .collapsible-container > details > summary{display:flex;align-items:center;justify-content:space-between;gap:10px;padding:11px 40px 11px 14px;border-bottom:1px solid transparent;border-radius:0;position:relative;font-weight:600;background:#1c2a3f;color:#00c2ff;}
html[data-kb-theme="radar"] #risk-paths .risk-path-card > summary{align-items:flex-start;}
html[data-kb-theme="radar"] #risk-paths .collapsible-container summary:hover{background:#2a3c58;}
html[data-kb-theme="radar"] #risk-paths .risk-path-card-body{padding:14px;}
html[data-kb-theme="radar"] #risk-paths .risk-path-info-grid > div,html[data-kb-theme="radar"] #risk-paths .risk-path-graph,html[data-kb-theme="radar"] #risk-paths .risk-path-proof-item{background:transparent;}
html[data-kb-theme="radar"] #risk-paths .risk-path-fix-grid .risk-path-row{height:32px;align-items:center;}
html[data-kb-theme="radar"] #risk-paths .risk-path-fix-grid .risk-path-chip{height:28px;min-height:28px;padding:0 10px;line-height:26px;}
html[data-kb-theme="radar"] #risk-paths .risk-path-summary-card{background:#273449;border-color:#3f5677;}
html[data-kb-theme="radar"] #risk-paths .risk-path-summary-card strong{color:#eaf3ff;}
html[data-kb-theme="radar"] #risk-paths .risk-path-table-container{padding-left:8px;padding-right:8px;}
html[data-kb-theme="radar"] #risk-paths .risk-path-command-code{scrollbar-width:thin;scrollbar-color:#00bfff #14263d;}
@media (max-width: 760px){#risk-paths .risk-path-card > summary{flex-direction:column;}#risk-paths .risk-path-meta{justify-content:flex-start;max-width:none;}}
</style>`
}

func renderDirectRiskPathsPage(directRiskPaths []scan.DirectRiskPath, combinedRiskPaths []scan.CombinedRiskPath, checks []scan.CheckResult) string {
	checksByID := map[string]scan.CheckResult{}
	for _, check := range checks {
		checksByID[check.ID] = check
	}
	var triggeredDirectRiskPaths, clearCapabilities []scan.DirectRiskPath
	for _, capability := range directRiskPaths {
		if strings.EqualFold(capability.Status, "triggered") {
			triggeredDirectRiskPaths = append(triggeredDirectRiskPaths, capability)
		} else {
			clearCapabilities = append(clearCapabilities, capability)
		}
	}
	var triggeredCombinedRiskPaths []scan.CombinedRiskPath
	for _, compound := range combinedRiskPaths {
		if strings.EqualFold(compound.Status, "triggered") {
			triggeredCombinedRiskPaths = append(triggeredCombinedRiskPaths, compound)
		}
	}
	var b strings.Builder
	b.WriteString(`<div class="tab-content" id="risk-paths"><div class="container">`)
	b.WriteString(riskPathsScopedCSS())
	b.WriteString(`<h1>Risk Paths</h1>`)
	b.WriteString(`<p>Correlated findings grouped into direct risk paths, validation proof, and combined chained paths.</p>`)
	b.WriteString(`<div class="risk-path-summary-grid">`)
	b.WriteString(`<div class="risk-path-summary-card"><div><span>Direct Risk Paths</span><small>Active direct routes</small></div><strong>` + strconv.Itoa(len(triggeredDirectRiskPaths)) + `</strong></div>`)
	b.WriteString(`<div class="risk-path-summary-card"><div><span>Combined Risk Paths</span><small>Higher-impact combinations</small></div><strong>` + strconv.Itoa(len(triggeredCombinedRiskPaths)) + `</strong></div>`)
	b.WriteString(`</div>`)
	b.WriteString(renderBoundaryFixFirstPanel(riskPathFixFirstItems(triggeredDirectRiskPaths, checksByID)))
	b.WriteString(`<div class="table-container risk-paths-section">`)
	b.WriteString(`<h2>Direct Risk Paths</h2><p class="risk-path-muted">Open a risk path to review validation commands, the path graph, and the source checks.</p>`)
	if len(triggeredDirectRiskPaths) == 0 {
		b.WriteString(`<p class="risk-path-muted">No active direct risk paths were detected.</p>`)
	}
	for _, capability := range triggeredDirectRiskPaths {
		b.WriteString(renderDirectRiskPathCard(capability))
	}
	if len(clearCapabilities) > 0 {
		b.WriteString(`<div class="collapsible-container"><details class="risk-path-subsection"><summary>Show clear risk paths (` + strconv.Itoa(len(clearCapabilities)) + `)</summary><div>`)
		for _, capability := range clearCapabilities {
			b.WriteString(renderDirectRiskPathCard(capability))
		}
		b.WriteString(`</div></details></div>`)
	}
	if len(triggeredCombinedRiskPaths) > 0 {
		b.WriteString(`<h2 style="margin-top:1.5rem;">Combined Risk Paths</h2><p class="risk-path-muted">Higher-impact routes where multiple direct risk paths appear together.</p>`)
		for _, compound := range triggeredCombinedRiskPaths {
			b.WriteString(renderCombinedRiskPathCard(compound))
		}
	}
	b.WriteString(`</div></div></div>`)
	b.WriteString(renderCapabilityCopyScript())
	return b.String()
}
func classForTriggeredCount(count int) string {
	if count > 0 {
		return "critical"
	}
	return "normal"
}

func renderPassRateBlock(passedChecks, totalChecks int) string {
	var b strings.Builder
	b.WriteString(`<div class="health-status"><div class="health-status"><h2>Passed / Failed Checks</h2><div class="status-container"><span class="status-text"><span class="count-up" data-count="`)
	b.WriteString(strconv.Itoa(passedChecks))
	b.WriteString(`">0</span>/<span class="count-up" data-count="`)
	b.WriteString(strconv.Itoa(totalChecks))
	b.WriteString(`">0</span> Passed</span><span class="status-chip"></span></div><p style="margin-top:10px; font-size:16px;">This shows the number of health checks that passed out of the total checks performed across the cluster. A higher pass rate indicates better overall cluster health.</p></div></div>`)
	return b.String()
}

func renderIssueSummary(checks []scan.CheckResult) string {
	groups := []struct {
		label string
		class string
		id    string
		items []scan.CheckResult
	}{
		{label: "Critical", class: "critical", id: "critical"},
		{label: "Warning", class: "warning", id: "warning"},
		{label: "Info", class: "info", id: "info"},
	}
	for _, check := range checks {
		if check.Total == 0 {
			continue
		}
		switch issueSummaryBucket(check.Severity) {
		case "critical":
			groups[0].items = append(groups[0].items, check)
		case "warning":
			groups[1].items = append(groups[1].items, check)
		default:
			groups[2].items = append(groups[2].items, check)
		}
	}
	var b strings.Builder
	b.WriteString(`<h2>Issue Summary</h2><p>This section shows how many checks have failed at each severity level over the last run. Click on a card below to expand and review those checks.</p><div class="hero-metrics">`)
	for _, group := range groups {
		if len(group.items) == 0 {
			continue
		}
		displayCount := len(group.items)
		b.WriteString(`<div class="metric-card ` + group.class + `" id="card-expand-` + group.id + `"><div class="card-content" onclick="toggleExpand('expand-` + group.id + `')"><span class="category">` + esc(group.label) + `</span><p>` + esc(fmt.Sprintf("%d checks failed", displayCount)) + `</p><span class="expand-icon material-icons">expand_more</span></div><div id="expand-` + group.id + `" class="expand-content scrollable-content"><div class="wide-content">`)
		for _, check := range group.items {
			b.WriteString(`<div class='check-item'><a href='#` + escAttr(check.ID) + `' class='check-id'>` + esc(check.ID) + `</a><span class='check-name'>` + esc(check.Name) + ` <em>(` + esc(firstNonEmpty(check.Section, check.Category)) + `)</em></span></div>`)
		}
		b.WriteString(`</div></div></div>`)
	}
	b.WriteString(`</div>`)
	return b.String()
}

func issueSummaryBucket(severity string) string {
	switch strings.ToLower(strings.TrimSpace(severity)) {
	case "critical", "high":
		return "critical"
	case "warning", "medium":
		return "warning"
	default:
		return "info"
	}
}

func renderSummaryTab(clusterName string, snapshot reportSnapshot) string {
	summary := kubernetes.Summary{}
	if snapshot.Summary != nil {
		summary = *snapshot.Summary
	}
	version := firstNonEmpty(snapshot.KubernetesVersion, "Unknown")
	stats := computeSummaryStats(snapshot)
	totalPods := summary.Pods
	if len(snapshot.AllPodObjects) > 0 {
		totalPods = len(snapshot.AllPodObjects)
	} else if len(snapshot.PodObjects) > 0 {
		totalPods = len(snapshot.PodObjects)
	}
	var b strings.Builder
	b.WriteString(`<div class="tab-content" id="summary"><div class="container">`)
	b.WriteString(`<h1 id="summaryHeading">Cluster Summary</h1>`)
	b.WriteString(`<p><strong>Cluster Name:</strong> ` + esc(clusterName) + `</p>`)
	b.WriteString(`<p><strong>Kubernetes Version:</strong> ` + esc(version) + `</p>`)
	b.WriteString(renderCompatibility(version))
	b.WriteString(`<h2>Cluster Metrics Summary <span class="tooltip"><span class="info-icon">i</span><span class="tooltip-text">Summary of metrics including node and pod counts, warnings, and issues.</span></span></h2>`)
	b.WriteString(`<table>`)
	b.WriteString(`<tr><td>🚀 Nodes: ` + esc(fmt.Sprintf("%d", summary.Nodes)) + `</td><td>🟩 Healthy: ` + esc(fmt.Sprintf("%d", stats.HealthyNodes)) + `</td><td>🟥 Issues: ` + esc(fmt.Sprintf("%d", stats.IssueNodes)) + `</td></tr>`)
	b.WriteString(`<tr><td>📦 Pods: ` + esc(fmt.Sprintf("%d", totalPods)) + `</td><td>🟩 Running: ` + esc(fmt.Sprintf("%d", stats.RunningPods)) + `</td><td>🟥 Failed: ` + esc(fmt.Sprintf("%d", stats.FailedPods)) + `</td></tr>`)
	b.WriteString(`<tr><td>🔄 Restarts: ` + esc(fmt.Sprintf("%d", stats.TotalRestarts)) + `</td><td>🟨 Warnings: ` + esc(fmt.Sprintf("%d", stats.WarningRestarts)) + `</td><td>🟥 Critical: ` + esc(fmt.Sprintf("%d", stats.CriticalRestarts)) + `</td></tr>`)
	b.WriteString(`<tr><td>⏳ Pending Pods: ` + esc(fmt.Sprintf("%d", stats.PendingPods)) + `</td><td>🟡 Waiting: ` + esc(fmt.Sprintf("%d", stats.PendingPods)) + `</td></tr>`)
	b.WriteString(`<tr><td>⚠️ Stuck Pods: ` + esc(fmt.Sprintf("%d", stats.StuckPods)) + `</td><td>❌ Stuck: ` + esc(fmt.Sprintf("%d", stats.StuckPods)) + `</td></tr>`)
	b.WriteString(`<tr><td>📉 Job Failures: ` + esc(fmt.Sprintf("%d", stats.FailedJobs)) + `</td><td>🔴 Failed: ` + esc(fmt.Sprintf("%d", stats.FailedJobs)) + `</td></tr>`)
	b.WriteString(`</table>`)
	b.WriteString(`<h2>Pod Distribution <span class="tooltip"><span class="info-icon">i</span><span class="tooltip-text">Average, min, and max pods per node and total node count.</span></span></h2>`)
	b.WriteString(`<table><tr><td>Avg: <strong>` + esc(fmt.Sprintf("%.1f", stats.AvgPods)) + `</strong></td><td>Max: <strong>` + esc(fmt.Sprintf("%d", stats.MaxPods)) + `</strong></td><td>Min: <strong>` + esc(fmt.Sprintf("%d", stats.MinPods)) + `</strong></td><td>Total Nodes: <strong>` + esc(fmt.Sprintf("%d", summary.Nodes)) + `</strong></td></tr></table>`)
	if snapshot.Metrics != nil {
		b.WriteString(`<h2>Cluster Health Metrics (Last 24h)
  <span class='tooltip'>
    <span class='info-icon'>i</span>
    <span class='tooltip-text'>24-hour Prometheus averages and charts for cluster CPU and memory usage.</span>
  </span></h2>`)
		b.WriteString(`<div class='hero-metrics'>`)
		b.WriteString(metricCard("normal", "Avg CPU", fmt.Sprintf("%.2f%%", snapshot.Metrics.Cluster.AvgCPUPercent)))
		b.WriteString(metricCard("normal", "Avg Memory", fmt.Sprintf("%.2f%%", snapshot.Metrics.Cluster.AvgMemPercent)))
		b.WriteString(`</div>`)
		if len(snapshot.Metrics.Cluster.CPUTimeSeries) > 0 {
			b.WriteString(`<div class='chart-wrapper'><div class='chart-item'><h3>Cluster CPU Usage (%)</h3><p>Historical CPU metrics from Prometheus, averaged over the last 24 hours.</p><canvas id='clusterCpuChart' data-values='` + escAttr(toJSON(snapshot.Metrics.Cluster.CPUTimeSeries)) + `'></canvas></div></div>`)
		}
		if len(snapshot.Metrics.Cluster.MemTimeSeries) > 0 {
			b.WriteString(`<div class='chart-wrapper'><div class='chart-item'><h3>Cluster Memory Usage (%)</h3><p>Historical memory metrics from Prometheus, averaged over the last 24 hours.</p><canvas id='clusterMemChart' data-values='` + escAttr(toJSON(snapshot.Metrics.Cluster.MemTimeSeries)) + `'></canvas></div></div>`)
		}
	}
	b.WriteString(`<h2>Cluster Events</h2><div class="hero-metrics">`)
	b.WriteString(metricCard(metricClass(float64(stats.ErrorEvents), 10, 20), "Errors", fmt.Sprintf("%d", stats.ErrorEvents)))
	b.WriteString(metricCard(metricClass(float64(stats.WarningEvents), 50, 100), "Warnings", fmt.Sprintf("%d", stats.WarningEvents)))
	b.WriteString(`</div>`)
	b.WriteString(`</div></div>`)
	return b.String()
}

func renderPage(page reportPage, snapshot reportSnapshot, directRiskPaths []scan.DirectRiskPath, combinedRiskPaths []scan.CombinedRiskPath) string {
	if page.ID == "nodes" {
		return renderNodesPage(page, snapshot, directRiskPaths, combinedRiskPaths)
	}
	var b strings.Builder
	b.WriteString(`<div class="tab-content" id="` + escAttr(page.ID) + `"><div class="container">`)
	b.WriteString(`<h1>` + esc(page.Name) + `</h1>`)
	b.WriteString(`<div class="table-container">`)
	for _, check := range page.Checks {
		b.WriteString(renderStandardSection(check, directRiskPaths, combinedRiskPaths))
	}
	b.WriteString(`</div></div></div>`)
	return b.String()
}

func renderNodesPage(page reportPage, snapshot reportSnapshot, directRiskPaths []scan.DirectRiskPath, combinedRiskPaths []scan.CombinedRiskPath) string {
	var b strings.Builder
	b.WriteString(`<div class="tab-content" id="nodes"><div class="container">`)
	b.WriteString(`<h1>Node Conditions & Resources</h1>`)
	b.WriteString(`<div class="table-container">`)
	for _, id := range []string{"NODE001", "NODE002", "NODE003", "PROM005", "PROM006", "PROM008"} {
		check, ok := findCheck(page.Checks, id)
		if !ok {
			continue
		}
		b.WriteString(renderNodeSection(check, snapshot, directRiskPaths, combinedRiskPaths))
	}
	for _, check := range page.Checks {
		if check.ID == "NODE001" || check.ID == "NODE002" || check.ID == "NODE003" || check.ID == "PROM005" || check.ID == "PROM006" || check.ID == "PROM008" {
			continue
		}
		b.WriteString(renderCheckDetails(check, directRiskPaths, combinedRiskPaths))
	}
	b.WriteString(renderNodeCards(snapshot))
	b.WriteString(`</div></div></div>`)
	return b.String()
}

func renderNodeSection(check scan.CheckResult, snapshot reportSnapshot, directRiskPaths []scan.DirectRiskPath, combinedRiskPaths []scan.CombinedRiskPath) string {
	var b strings.Builder
	b.WriteString(`<div class='table-container'><h2 id='` + escAttr(check.ID) + `'>` + esc(check.ID) + ` - ` + esc(compatNodeHeading(check)) + ` ` + headingTooltip(check) + `</h2>`)
	b.WriteString(`<p>` + compatNodeStatusLine(check) + `</p>`)
	if check.ID == "PROM006" && strings.Contains(strings.ToLower(check.SummaryMessage), "insufficient") {
		b.WriteString(`<div class="skipped-notice">⚠️ Node-exporter is not deployed. Deploy node-exporter with a GMP <code>ClusterPodMonitoring</code> to enable node sizing insights. See: <a href="https://cloud.google.com/stackdriver/docs/managed-prometheus/setup-unmanaged" target="_blank">GMP node-exporter setup</a>.</div>`)
	}
	if check.ID == "NODE003" || check.ID == "PROM006" || check.ID == "PROM008" {
		b.WriteString(renderRecommendationDetails(check))
		b.WriteString(renderCapabilityImpactForCheck(check.ID, directRiskPaths, combinedRiskPaths))
	}
	if compatNodeTableNeeded(check, snapshot) {
		b.WriteString(`<div class="collapsible-container"><details id='` + escAttr(check.ID) + `' style='margin:10px 0;'><summary style='font-size:16px; cursor:pointer; color:var(--brand-blue); font-weight:bold;'>Show Findings</summary><div style='padding-top: 15px;'>`)
		b.WriteString(renderNodeTable(check, snapshot))
		b.WriteString(`</div></details></div>`)
	}
	b.WriteString(`</div>`)
	return b.String()
}

func renderCapabilityImpactForCheck(checkID string, directRiskPaths []scan.DirectRiskPath, combinedRiskPaths []scan.CombinedRiskPath) string {
	impacted := directRiskPathsForCheck(checkID, directRiskPaths)
	if len(impacted) == 0 {
		return ""
	}
	compoundImpacts := combinedRiskPathsForDirectRiskPaths(impacted, combinedRiskPaths)
	var b strings.Builder
	b.WriteString(`<div class="check-risk-path-panel"><strong>Risk paths</strong><div class="check-risk-path-list">`)
	for _, capability := range impacted {
		class := "normal"
		if strings.EqualFold(capability.Status, "triggered") {
			class = "critical"
		}
		b.WriteString(`<a class="risk-path-chip risk-path-tab-link ` + escAttr(class) + `" href="#risk-paths">` + esc(capability.ID) + ` ` + esc(capability.Status) + `</a>`)
	}
	for _, compound := range compoundImpacts {
		class := "default"
		if strings.EqualFold(compound.Status, "triggered") {
			class = "critical"
		}
		b.WriteString(`<a class="risk-path-chip risk-path-tab-link ` + escAttr(class) + `" href="#risk-paths">` + esc(compound.ID) + ` ` + esc(compound.Status) + `</a>`)
	}
	b.WriteString(`</div><p>Full validation proof, evidence, and path graphs are in the Risk Paths tab.</p></div>`)
	return b.String()
}

func directRiskPathsForCheck(checkID string, directRiskPaths []scan.DirectRiskPath) []scan.DirectRiskPath {
	var out []scan.DirectRiskPath
	for _, capability := range directRiskPaths {
		for _, signal := range capability.SignalChecks {
			if strings.EqualFold(signal, checkID) {
				out = append(out, capability)
				break
			}
		}
	}
	return out
}

func combinedRiskPathsForDirectRiskPaths(directRiskPaths []scan.DirectRiskPath, combinedRiskPaths []scan.CombinedRiskPath) []scan.CombinedRiskPath {
	ids := map[string]struct{}{}
	for _, capability := range directRiskPaths {
		ids[capability.ID] = struct{}{}
	}
	var out []scan.CombinedRiskPath
	for _, compound := range combinedRiskPaths {
		for _, required := range compound.Requires {
			if _, ok := ids[required]; ok {
				out = append(out, compound)
				break
			}
		}
	}
	return out
}
func renderRecommendationDetails(check scan.CheckResult) string {
	if strings.TrimSpace(check.Recommendation) == "" && strings.TrimSpace(check.RecommendationHTML) == "" && strings.TrimSpace(check.URL) == "" {
		return ""
	}
	var b strings.Builder
	b.WriteString(`<div class="collapsible-container"><details id='` + escAttr(check.ID) + `_recommendations' style='margin:10px 0;'><summary style='font-size:16px; cursor:pointer; color:var(--brand-blue); font-weight:bold;'>Show Recommendations</summary><div style='padding-top: 15px;'><div class="recommendation-card"><div class="recommendation-banner"><span class="material-icons">tips_and_updates</span>Recommended Actions</div>`)
	if strings.TrimSpace(check.RecommendationHTML) != "" {
		b.WriteString(check.RecommendationHTML)
	} else if strings.TrimSpace(check.Recommendation) != "" {
		b.WriteString(`<div class="recommendation-content"><ul><li>` + esc(check.Recommendation) + `</li></ul></div>`)
	}
	if strings.TrimSpace(check.URL) != "" {
		b.WriteString(`<div class="recommendation-content"><ul><li><strong>Docs:</strong> <a href='` + escAttr(check.URL) + `' target='_blank'>` + esc(compatDocLabel(check.ID)) + `</a></li></ul></div>`)
	}
	b.WriteString(`</div><div style='height: 15px;'></div></div></details></div>`)
	return b.String()
}

func renderNodeTable(check scan.CheckResult, snapshot reportSnapshot) string {
	var b strings.Builder
	switch check.ID {
	case "NODE001":
		b.WriteString(`<table><tr><th>Node</th><th>Status</th><th>Issues</th></tr>`)
		for _, node := range snapshot.NodeObjects {
			name := lookupString(node, "metadata.name")
			status := "✅ Healthy"
			issues := "None"
			if !nodeReady(node) {
				status = "❌ Not Ready"
				issues = nodeIssueSummary(node)
			}
			b.WriteString(`<tr><td>` + esc(name) + `</td><td>` + esc(status) + `</td><td>` + esc(issues) + `</td></tr>`)
		}
	case "NODE002":
		b.WriteString(`<table><tr><th>Node</th><th>CPU Status</th><th>CPU %</th><th>CPU Used</th><th>CPU Total</th><th>Mem Status</th><th>Mem %</th><th>Mem Used</th><th>Mem Total</th><th>Disk %</th><th>Disk Status</th></tr>`)
		for _, row := range buildNodePressureRows(snapshot) {
			b.WriteString(`<tr><td>` + esc(row.Node) + `</td><td>` + esc(row.CPUStatus) + `</td><td>` + esc(row.CPUPct) + `</td><td>` + esc(row.CPUUsed) + `</td><td>` + esc(row.CPUTotal) + `</td><td>` + esc(row.MemStatus) + `</td><td>` + esc(row.MemPct) + `</td><td>` + esc(row.MemUsed) + `</td><td>` + esc(row.MemTotal) + `</td><td>` + esc(row.DiskPct) + `</td><td>` + esc(row.DiskStatus) + `</td></tr>`)
		}
	case "NODE003":
		b.WriteString(`<table><tr><th>Node</th><th>PodCount</th><th>Capacity</th><th>Percentage</th><th>Threshold</th><th>Status</th></tr>`)
		for _, item := range check.Items {
			resource := strings.TrimPrefix(item.Resource, "node/")
			count, capacity := nodePodCount(snapshot, resource)
			b.WriteString(`<tr><td>` + esc(resource) + `</td><td>` + esc(fmt.Sprintf("%d", count)) + `</td><td>` + esc(fmt.Sprintf("%d", capacity)) + `</td><td>` + esc(strings.TrimSpace(item.Value)) + `</td><td>80%</td><td>` + esc(item.Message) + `</td></tr>`)
		}
	case "PROM006":
		if compat, ok := check.CompatItems.(map[string]any); ok {
			b.WriteString(`<table><tr><th>Status</th><th>Required Days</th><th>Available Days</th><th>Message</th></tr>`)
			b.WriteString(`<tr><td>` + esc(fmt.Sprint(compat["Status"])) + `</td><td>` + esc(fmt.Sprint(compat["Required Days"])) + `</td><td>` + esc(formatCompatAvailableDays(compat["Available Days"])) + `</td><td>` + esc(fmt.Sprint(compat["Message"])) + `</td></tr>`)
			break
		}
		fallthrough
	default:
		b.WriteString(`<table><tr><th>Namespace</th><th>Resource</th><th>Value</th><th>Message</th></tr>`)
		for _, item := range check.Items {
			b.WriteString(`<tr><td>` + esc(item.Namespace) + `</td><td>` + esc(item.Resource) + `</td><td>` + esc(item.Value) + `</td><td>` + esc(item.Message) + `</td></tr>`)
		}
	}
	b.WriteString(`</table>`)
	return b.String()
}

func compatNodeTableNeeded(check scan.CheckResult, snapshot reportSnapshot) bool {
	switch check.ID {
	case "NODE001":
		return len(snapshot.NodeObjects) > 0
	case "NODE002":
		return len(buildNodePressureRows(snapshot)) > 0
	default:
		return len(check.Items) > 0
	}
}

func compatNodeHeading(check scan.CheckResult) string {
	switch check.ID {
	case "NODE002":
		return check.Name + " (Last 24h)"
	default:
		return check.Name
	}
}

func compatNodeStatusLine(check scan.CheckResult) string {
	switch check.ID {
	case "NODE003":
		if check.Total > 0 {
			return `⚠️ Total Nodes with Issues: ` + esc(fmt.Sprintf("%d", check.Total))
		}
	case "PROM006":
		if strings.Contains(strings.ToLower(check.SummaryMessage), "insufficient") {
			return `⚠️ Node-exporter metrics unavailable — node sizing requires node-exporter to be deployed.`
		}
		if check.Total == 0 {
			return `✅ All Nodes are healthy.`
		}
		return `⚠️ Total Nodes with Issues: ` + esc(fmt.Sprintf("%d", check.Total))
	}
	if check.Total == 0 {
		return `✅ All Nodes are healthy.`
	}
	return `⚠️ Total Nodes with Issues: ` + esc(fmt.Sprintf("%d", check.Total))
}

func headingTooltip(check scan.CheckResult) string {
	text := ""
	switch check.ID {
	case "NODE001":
		text = "Detects nodes that are not in Ready state or reporting other warning conditions."
	case "NODE002":
		text = "Detects nodes under high CPU, memory, or disk pressure.<br><br>Data source: Prometheus (24h average)"
	case "NODE003":
		text = "Alerts when any node is running too many pods according to configured thresholds."
	case "PROM005":
		text = "Checks if CPU requests on nodes exceed allocatable capacity over the last 24 hours."
	case "PROM006":
		text = "Uses Prometheus p95 CPU and memory usage over a fixed 7-day window to highlight underutilized or saturated nodes and suggest sizing actions."
	case "PROM008":
		text = "Checks whether a node-exporter DaemonSet is deployed. Node-exporter is required for node-level CPU, memory, and disk metrics in Prometheus."
	}
	if text == "" {
		return ""
	}
	return `<span class='tooltip'><span class='info-icon'>i</span><span class='tooltip-text'>` + text + `</span></span>`
}

func compatDocLabel(id string) string {
	switch id {
	case "NODE003":
		return "Kubernetes Nodes"
	case "PROM006":
		return "Kubernetes Node Autoscaling"
	default:
		return "Reference"
	}
}

func compatAKSCategoryID(name string) string {
	value := strings.TrimSpace(name)
	if value == "" {
		return "Unknown"
	}
	value = strings.ReplaceAll(value, "&", "_")
	value = strings.ReplaceAll(value, " ", "_")
	return value
}

type nodePressureRow struct {
	Node       string
	CPUStatus  string
	CPUPct     string
	CPUUsed    string
	CPUTotal   string
	MemStatus  string
	MemPct     string
	MemUsed    string
	MemTotal   string
	DiskPct    string
	DiskStatus string
}

func buildNodePressureRows(snapshot reportSnapshot) []nodePressureRow {
	if snapshot.Metrics == nil {
		return nil
	}
	nodeLookup := map[string]map[string]any{}
	for _, node := range snapshot.NodeObjects {
		nodeLookup[lookupString(node, "metadata.name")] = node
	}
	rows := make([]nodePressureRow, 0, len(snapshot.Metrics.Nodes))
	for _, metrics := range snapshot.Metrics.Nodes {
		node := nodeLookup[metrics.NodeName]
		if len(node) == 0 || !nodeReady(node) {
			continue
		}
		cpuAlloc := allocatableMilliCPU(node)
		memAlloc := allocatableMiB(node)
		cpuUsed := int(float64(cpuAlloc) * metrics.CPUAvg / 100)
		memUsed := int(float64(memAlloc) * metrics.MemAvg / 100)
		rows = append(rows, nodePressureRow{
			Node:       metrics.NodeName,
			CPUStatus:  compatPressureStatus(metrics.CPUAvg, 50, 75),
			CPUPct:     fmt.Sprintf("%.2f%%", metrics.CPUAvg),
			CPUUsed:    fmt.Sprintf("%d mC", cpuUsed),
			CPUTotal:   fmt.Sprintf("%d mC", cpuAlloc),
			MemStatus:  compatPressureStatus(metrics.MemAvg, 50, 75),
			MemPct:     fmt.Sprintf("%.1f%%", metrics.MemAvg),
			MemUsed:    fmt.Sprintf("%d Mi", memUsed),
			MemTotal:   fmt.Sprintf("%d Mi", memAlloc),
			DiskPct:    fmt.Sprintf("%.2f%%", metrics.DiskAvg),
			DiskStatus: compatPressureStatus(metrics.DiskAvg, 60, 80),
		})
	}
	return rows
}

func allocatableMilliCPU(node map[string]any) int {
	raw := strings.TrimSpace(lookupString(node, "status.allocatable.cpu"))
	if raw == "" {
		return 0
	}
	if strings.HasSuffix(raw, "m") {
		value, _ := strconv.Atoi(strings.TrimSuffix(raw, "m"))
		return value
	}
	value, _ := strconv.Atoi(raw)
	return value * 1000
}

func allocatableMiB(node map[string]any) int {
	raw := strings.TrimSpace(lookupString(node, "status.allocatable.memory"))
	raw = strings.TrimSuffix(raw, "Ki")
	if raw == "" {
		return 0
	}
	value, _ := strconv.Atoi(raw)
	return int(float64(value) / 1024)
}

func compatPressureStatus(value float64, warning, critical float64) string {
	switch {
	case value > critical:
		return "🔴 Critical"
	case value > warning:
		return "🟡 Warning"
	default:
		return "✅ Normal"
	}
}

func nodeIssueSummary(node map[string]any) string {
	var issues []string
	for _, raw := range anySlice(lookupAny(node, "status.conditions")) {
		item, ok := raw.(map[string]any)
		if !ok {
			continue
		}
		if lookupString(item, "type") != "Ready" && lookupString(item, "status") != "False" {
			issues = append(issues, lookupString(item, "type")+": "+lookupString(item, "message"))
		}
	}
	if len(issues) == 0 {
		return "Unknown Issue"
	}
	return strings.Join(issues, " | ")
}

func metricDisplay(avg float64, series []kubernetes.MetricPoint) string {
	if len(series) == 0 {
		return "N/A"
	}
	return fmt.Sprintf("%.2f%%", avg)
}

func metricClassWithData(avg float64, series []kubernetes.MetricPoint, warning, critical float64) string {
	if len(series) == 0 {
		return "default"
	}
	return metricClass(avg, warning, critical)
}

func nodePodCount(snapshot reportSnapshot, name string) (int, int) {
	pods := snapshot.AllPodObjects
	if len(pods) == 0 {
		pods = snapshot.PodObjects
	}
	count := 0
	for _, pod := range pods {
		if lookupString(pod, "spec.nodeName") == name {
			count++
		}
	}
	nodeLookup := map[string]any{}
	for _, node := range snapshot.NodeObjects {
		if lookupString(node, "metadata.name") == name {
			nodeLookup = node
			break
		}
	}
	return count, int(anyInt64(lookupAny(nodeLookup, "status.capacity.pods")))
}

func renderNodeCards(snapshot reportSnapshot) string {
	if snapshot.Metrics == nil || len(snapshot.Metrics.Nodes) == 0 {
		return ""
	}
	lookup := map[string]map[string]any{}
	for _, node := range snapshot.NodeObjects {
		lookup[lookupString(node, "metadata.name")] = node
	}
	var b strings.Builder
	b.WriteString(`<div class="material-input with-icon"><i class="material-icons">search</i><div style="position: relative; width: 100%;"><input type="text" id="nodeFilterInput" placeholder=" " /><label for="nodeFilterInput">Search Nodes</label></div></div><div id="filteredNodeCardsWrapper"><div id="filteredNodeCards">`)
	for _, metrics := range snapshot.Metrics.Nodes {
		node := lookup[metrics.NodeName]
		nodeID := "node_" + slug(metrics.NodeName)
		osImage := lookupString(node, "status.nodeInfo.osImage")
		kernel := lookupString(node, "status.nodeInfo.kernelVersion")
		kubelet := lookupString(node, "status.nodeInfo.kubeletVersion")
		runtime := lookupString(node, "status.nodeInfo.containerRuntimeVersion")
		cpuClass := metricClassWithData(metrics.CPUAvg, metrics.CPUSeries, 50, 75)
		memClass := metricClassWithData(metrics.MemAvg, metrics.MemSeries, 50, 75)
		diskClass := metricClassWithData(metrics.DiskAvg, metrics.DiskSeries, 75, 90)
		content := `<div class='recommendation-card node-card'><div style='padding: 15px;'><p><strong>OS:</strong> ` + esc(osImage) + `<br><strong>Kernel:</strong> ` + esc(kernel) + `<br><strong>Kubelet:</strong> ` + esc(kubelet) + `<br><strong>Runtime:</strong> ` + esc(runtime) + `</p><div class='hero-metrics'>` +
			metricCard(cpuClass, "CPU", metricDisplay(metrics.CPUAvg, metrics.CPUSeries)) +
			metricCard(memClass, "Memory", metricDisplay(metrics.MemAvg, metrics.MemSeries)) +
			metricCard(diskClass, "Disk", metricDisplay(metrics.DiskAvg, metrics.DiskSeries)) +
			`</div><div class='chart-wrapper row-3'><div class='chart-item'><h3>CPU Usage (%)</h3><canvas class='node-chart' data-values='` + escAttr(toJSON(metrics.CPUSeries)) + `'></canvas></div><div class='chart-item'><h3>Memory Usage (%)</h3><canvas class='node-chart' data-values='` + escAttr(toJSON(metrics.MemSeries)) + `'></canvas></div><div class='chart-item'><h3>Disk Usage (%)</h3><canvas class='node-chart' data-values='` + escAttr(toJSON(metrics.DiskSeries)) + `'></canvas></div></div></div></div>`
		summary := `<summary class="node-summary collapsible-arrow"><span class="summary-inner"><span class="node-name">Node: ` + esc(metrics.NodeName) + `</span><span class="summary-metrics"><span class="metric-badge ` + cpuClass + `">CPU: ` + esc(metricDisplay(metrics.CPUAvg, metrics.CPUSeries)) + `</span><span class="metric-badge ` + memClass + `">Mem: ` + esc(metricDisplay(metrics.MemAvg, metrics.MemSeries)) + `</span><span class="metric-badge ` + diskClass + `">Disk: ` + esc(metricDisplay(metrics.DiskAvg, metrics.DiskSeries)) + `</span></span></span></summary>`
		b.WriteString(`<div class="collapsible-container"><details id="` + escAttr(nodeID) + `">` + summary + `<div style='padding-top: 15px;'>` + content + `</div></details></div>`)
	}
	b.WriteString(`</div><div id="nodeCardPagination" class="table-pagination"></div></div>`)
	return b.String()
}

func renderAKSPage(page reportPage, readiness *scan.AutomaticReadiness) string {
	passed := 0
	for _, check := range page.Checks {
		if check.Total == 0 {
			passed++
		}
	}
	failed := len(page.Checks) - passed
	rating := aksRating(passed, failed)
	var b strings.Builder
	b.WriteString(`<div class="tab-content" id="aks"><div class="container">`)
	b.WriteString(`<h1>AKS Best Practices Results</h1>`)
	b.WriteString(`<div class="hero-metrics">`)
	b.WriteString(metricCard("normal", "✅ Passed", fmt.Sprintf("%d", passed)))
	b.WriteString(metricCard("critical", "❌ Failed", fmt.Sprintf("%d", failed)))
	b.WriteString(metricCard("default", "📊 Total Checks", fmt.Sprintf("%d", len(page.Checks))))
	b.WriteString(metricCard("default", "🎯 Score", fmt.Sprintf("%.2f%%", aksScore(passed, len(page.Checks)))))
	b.WriteString(metricCard(ratingClass(rating), "⭐ Rating", rating))
	b.WriteString(`</div><div class="table-container">`)
	b.WriteString(`<div class="aks-filter-bar" role="group" aria-label="AKS check filter">`)
	b.WriteString(`<button type="button" class="aks-filter-btn is-active" id="aksFilterFailed" data-filter-mode="failed" aria-pressed="true" onclick="setAKSFilter('failed')">Failed Checks Only</button>`)
	b.WriteString(`<button type="button" class="aks-filter-btn" id="aksFilterAll" data-filter-mode="all" aria-pressed="false" onclick="setAKSFilter('all')">All Checks</button>`)
	b.WriteString(`</div>`)
	categories := groupByCategory(page.Checks)
	for _, category := range categories {
		// Sort: failed checks first, then alphabetically by ID
		sort.Slice(category.Checks, func(i, j int) bool {
			iFailed := category.Checks[i].Total > 0
			jFailed := category.Checks[j].Total > 0
			if iFailed != jFailed {
				return iFailed
			}
			return category.Checks[i].ID < category.Checks[j].ID
		})
		failures := 0
		for _, check := range category.Checks {
			if check.Total > 0 {
				failures++
			}
		}
		b.WriteString(`<div class="collapsible-container"><details id='aksCategory_` + escAttr(compatAKSCategoryID(category.Name)) + `'><summary style='font-size:16px; cursor:pointer; color:var(--brand-blue); font-weight:bold;'>Show ` + category.Name + ` (` + esc(fmt.Sprintf("%d/%d failed", failures, len(category.Checks))) + `)</summary><div style='padding-top: 15px;'>`)
		b.WriteString(`<table><thead><tr><th>ID</th><th>Check</th><th>Severity</th><th>Category</th><th>Status</th><th>Observed Value</th><th>Fail Message</th><th>Recommendation</th><th>URL</th></tr></thead><tbody>`)
		for _, check := range category.Checks {
			status := "PASS"
			icon := "✅"
			value := ""
			failMessage := "No issues detected."
			rowClass := ` class="aks-pass-row"`
			if check.Total > 0 {
				status = "FAIL"
				icon = "❌"
				value = firstFindingValue(check)
				failMessage = firstFindingMessage(check)
				rowClass = ""
			}
			b.WriteString(`<tr` + rowClass + `><td>` + esc(check.ID) + `</td><td>` + esc(check.Name) + `</td><td>` + esc(check.Severity) + `</td><td>` + check.Category + `</td><td>` + icon + ` ` + status + `</td><td>` + formatAKSCellText(value) + `</td><td>` + formatAKSCellText(failMessage) + `</td><td>` + renderAKSRecommendationCell(check) + `</td><td>`)
			if strings.TrimSpace(check.URL) != "" {
				b.WriteString(`<a href='` + escAttr(check.URL) + `' target='_blank'>Learn More</a>`)
			}
			b.WriteString(`</td></tr>`)
		}
		b.WriteString(`</tbody></table></div></details></div>`)
	}
	if readiness != nil {
		b.WriteString(`<h2>AKS Automatic Migration Readiness</h2>`)
		b.WriteString(scan.AutomaticReadinessHTML(readiness))
	}
	b.WriteString(`</div></div></div>`)
	return b.String()
}

func renderGKEPage(page reportPage) string {
	passed := 0
	for _, check := range page.Checks {
		if check.Total == 0 {
			passed++
		}
	}
	failed := len(page.Checks) - passed
	rating := aksRating(passed, failed)
	var b strings.Builder
	b.WriteString(`<div class="tab-content" id="gke"><div class="container">`)
	b.WriteString(`<h1>GKE Best Practices Results</h1>`)
	b.WriteString(`<div class="hero-metrics">`)
	b.WriteString(metricCard("normal", "✅ Passed", fmt.Sprintf("%d", passed)))
	b.WriteString(metricCard("critical", "❌ Failed", fmt.Sprintf("%d", failed)))
	b.WriteString(metricCard("default", "📊 Total Checks", fmt.Sprintf("%d", len(page.Checks))))
	b.WriteString(metricCard("default", "🎯 Score", fmt.Sprintf("%.2f%%", aksScore(passed, len(page.Checks)))))
	b.WriteString(metricCard(ratingClass(rating), "⭐ Rating", rating))
	b.WriteString(`</div><div class="table-container">`)
	b.WriteString(`<div class="aks-filter-bar" role="group" aria-label="GKE check filter">`)
	b.WriteString(`<button type="button" class="aks-filter-btn is-active" id="gkeFilterFailed" data-filter-mode="failed" aria-pressed="true" onclick="setGKEFilter('failed')">Failed Checks Only</button>`)
	b.WriteString(`<button type="button" class="aks-filter-btn" id="gkeFilterAll" data-filter-mode="all" aria-pressed="false" onclick="setGKEFilter('all')">All Checks</button>`)
	b.WriteString(`</div>`)
	categories := groupByCategory(page.Checks)
	for _, category := range categories {
		sort.Slice(category.Checks, func(i, j int) bool {
			iFailed := category.Checks[i].Total > 0
			jFailed := category.Checks[j].Total > 0
			if iFailed != jFailed {
				return iFailed
			}
			return category.Checks[i].ID < category.Checks[j].ID
		})
		failures := 0
		for _, check := range category.Checks {
			if check.Total > 0 {
				failures++
			}
		}
		b.WriteString(`<div class="collapsible-container"><details id='gkeCategory_` + escAttr(compatAKSCategoryID(category.Name)) + `'><summary style='font-size:16px; cursor:pointer; color:var(--brand-blue); font-weight:bold;'>Show ` + category.Name + ` (` + esc(fmt.Sprintf("%d/%d failed", failures, len(category.Checks))) + `)</summary><div style='padding-top: 15px;'>`)
		b.WriteString(`<table><thead><tr><th>ID</th><th>Check</th><th>Severity</th><th>Category</th><th>Status</th><th>Observed Value</th><th>Fail Message</th><th>Recommendation</th><th>URL</th></tr></thead><tbody>`)
		for _, check := range category.Checks {
			status := "PASS"
			icon := "✅"
			value := ""
			failMessage := "No issues detected."
			rowClass := ` class="aks-pass-row"`
			if check.Total > 0 {
				status = "FAIL"
				icon = "❌"
				value = firstFindingValue(check)
				failMessage = firstFindingMessage(check)
				rowClass = ""
			}
			b.WriteString(`<tr` + rowClass + `><td>` + esc(check.ID) + `</td><td>` + esc(check.Name) + `</td><td>` + esc(check.Severity) + `</td><td>` + check.Category + `</td><td>` + icon + ` ` + status + `</td><td>` + formatAKSCellText(value) + `</td><td>` + formatAKSCellText(failMessage) + `</td><td>` + renderAKSRecommendationCell(check) + `</td><td>`)
			if strings.TrimSpace(check.URL) != "" {
				b.WriteString(`<a href='` + escAttr(check.URL) + `' target='_blank'>Learn More</a>`)
			}
			b.WriteString(`</td></tr>`)
		}
		b.WriteString(`</tbody></table></div></details></div>`)
	}
	b.WriteString(`</div></div></div>`)
	return b.String()
}

func renderRightsizingAtGlance(result scan.Result, snapshot reportSnapshot) string {
	nodeCheck, hasNodes := findCheck(result.Checks, "PROM006")
	podCheck, hasPods := findCheck(result.Checks, "PROM007")
	if !hasNodes && !hasPods {
		return ""
	}

	underutilizedNodes := 0
	saturatedNodes := 0
	rightSizedNodes := 0
	if hasNodes {
		for _, item := range nodeCheck.Items {
			switch strings.TrimSpace(strings.ToLower(item.Message)) {
			case "underutilized":
				underutilizedNodes++
			case "saturated":
				saturatedNodes++
			}
		}
		if totalNodes := len(snapshot.NodeObjects); totalNodes > 0 {
			rightSizedNodes = totalNodes - underutilizedNodes - saturatedNodes
			if rightSizedNodes < 0 {
				rightSizedNodes = 0
			}
		}
	}

	stats := rightsizingStats{}
	if hasPods {
		stats = computeRightsizingStats(podCheck.Items)
	}

	var b strings.Builder
	b.WriteString(`<div class="rightsizing-glance"><h2>Rightsizing at a Glance</h2><div class="rightsizing-grid">`)
	b.WriteString(`<div class="rightsizing-card"><h3>Node Insights</h3><div class="rightsizing-list">`)
	b.WriteString(rightsizingItem("🖥️ Underutilized Nodes", underutilizedNodes))
	b.WriteString(rightsizingItem("🔥 Saturated Nodes", saturatedNodes))
	b.WriteString(rightsizingItem("✅ Right-sized Nodes", rightSizedNodes))
	b.WriteString(`</div></div>`)
	b.WriteString(`<div class="rightsizing-card"><h3>Pod Actions</h3><div class="rightsizing-list">`)
	b.WriteString(rightsizingItem("⚙️ CPU Request Changes", stats.CPURequestChanges))
	b.WriteString(rightsizingItem("🧠 Memory Request Changes", stats.MemoryRequestChanges))
	b.WriteString(rightsizingItem("🛡️ Memory Limit Changes", stats.MemoryLimitChanges))
	b.WriteString(rightsizingItem("🚫 CPU Limit Removals", stats.CPULimitRemovals))
	b.WriteString(`</div></div>`)
	b.WriteString(`<div class="rightsizing-card"><h3>Impact Summary</h3><div class="rightsizing-list">`)
	b.WriteString(rightsizingItem("🚀 High Impact", stats.ImpactHigh))
	b.WriteString(rightsizingItem("📈 Medium Impact", stats.ImpactMedium))
	b.WriteString(rightsizingItem("🧩 Low Impact", stats.ImpactLow))
	b.WriteString(`</div><p class="rightsizing-links">🔗 Quick Links: <a href="#PROM006">PROM006</a> <span>•</span> <a href="#PROM007">PROM007</a></p></div></div></div>`)
	return b.String()
}

func renderAKSRecommendationCell(check scan.CheckResult) string {
	if strings.TrimSpace(check.Recommendation) == "" {
		if strings.TrimSpace(check.RecommendationHTML) != "" {
			return check.RecommendationHTML
		}
		return ""
	}
	items := splitRecommendationItems(check.Recommendation)
	if len(items) == 0 {
		return formatAKSCellText(check.Recommendation)
	}
	if len(items) == 1 {
		return `<div class="aks-recommendation-text">` + formatAKSCellText(items[0]) + `</div>`
	}
	var b strings.Builder
	b.WriteString(`<div class="aks-recommendation-lines">`)
	for _, item := range items {
		b.WriteString(`<div class="aks-recommendation-line">` + formatAKSCellText(item) + `</div>`)
	}
	b.WriteString(`</div>`)
	return b.String()
}

func renderCheckDetails(check scan.CheckResult, directRiskPaths []scan.DirectRiskPath, combinedRiskPaths []scan.CombinedRiskPath) string {
	return renderStandardSection(check, directRiskPaths, combinedRiskPaths)
}

func renderStandardSection(check scan.CheckResult, directRiskPaths []scan.DirectRiskPath, combinedRiskPaths []scan.CombinedRiskPath) string {
	var b strings.Builder
	b.WriteString(`<div class='table-container'>`)
	b.WriteString(`<h2 id='` + escAttr(check.ID) + `'>` + esc(check.ID) + ` - ` + esc(compatStandardHeading(check)) + ` ` + standardHeadingTooltip(check) + `</h2>`)
	b.WriteString(`<p>` + compatStandardStatusLine(check) + `</p>`)
	if check.Total == 0 && strings.TrimSpace(check.SummaryMessage) != "" {
		b.WriteString(renderSkippedNotice(check.SummaryMessage))
	}
	if strings.Contains(strings.ToLower(check.SummaryMessage), "insufficient prometheus history") {
		b.WriteString(`<p>📅 ` + esc(check.SummaryMessage) + `</p>`)
	}
	if strings.TrimSpace(check.Recommendation) != "" || strings.TrimSpace(check.RecommendationHTML) != "" || strings.TrimSpace(check.URL) != "" {
		b.WriteString(renderRecommendationDetails(check))
		b.WriteString(renderCapabilityImpactForCheck(check.ID, directRiskPaths, combinedRiskPaths))
	}
	if compatStandardHasFindings(check) {
		b.WriteString(`<div class="collapsible-container"><details id='` + escAttr(check.ID) + `' style='margin:10px 0;'><summary style='font-size:16px; cursor:pointer; color:var(--brand-blue); font-weight:bold;'>Show Findings</summary><div style='padding-top: 15px;'>`)
		b.WriteString(renderStandardFindingsTable(check))
		b.WriteString(`</div></details></div>`)
	}
	b.WriteString(`</div>`)
	return b.String()
}

func compatStandardHeading(check scan.CheckResult) string {
	switch check.ID {
	case "PROM004", "SC003":
		if strings.Contains(check.Name, "(Prometheus)") {
			return check.Name
		}
		return check.Name + " (Prometheus)"
	default:
		return check.Name
	}
}

func compatStandardHasFindings(check scan.CheckResult) bool {
	if check.Total > 0 {
		return true
	}
	switch check.ID {
	case "PROM007":
		return check.CompatItems != nil
	default:
		return false
	}
}

func standardHeadingTooltip(check scan.CheckResult) string {
	text := strings.TrimSpace(check.Description)
	if text == "" {
		return ""
	}
	return `<span class='tooltip'><span class='info-icon'>i</span><span class='tooltip-text'>` + esc(text) + `</span></span>`
}

func compatStandardStatusLine(check scan.CheckResult) string {
	label := statusSubject(check)
	if check.Total == 0 {
		if strings.TrimSpace(check.SummaryMessage) != "" {
			return `⚪ Check could not be completed`
		}
		return `✅ All ` + esc(label) + ` are healthy.`
	}
	return `⚠️ Total ` + esc(label) + ` with Issues: ` + esc(strconv.Itoa(check.Total))
}

func renderSkippedNotice(message string) string {
	trimmed := strings.TrimSpace(message)
	if trimmed == "" {
		return ""
	}
	return `<div style="margin:0.75rem 0 1rem;padding:0.9rem 1rem;border-radius:12px;border:1px solid rgba(255,196,92,0.35);background:linear-gradient(180deg, rgba(255,196,92,0.14), rgba(255,196,92,0.08));color:#ffe7ad;"><strong style="display:block;margin-bottom:0.35rem;color:#ffd36b;">Unable to complete this check</strong><span style="line-height:1.6;">` + esc(trimmed) + `</span></div>`
}

func statusSubject(check scan.CheckResult) string {
	switch check.ID {
	case "NS001":
		return "Namespaces"
	case "NS002":
		return "ResourceQuotas"
	case "NS003":
		return "LimitRanges"
	case "NS004":
		return "Pods"
	case "EVENT001", "EVENT002":
		return "Events"
	}
	switch strings.TrimSpace(check.ResourceKind) {
	case "configmaps":
		return "ConfigMaps"
	case "namespaces":
		return "Namespaces"
	case "pods":
		return "Pods"
	case "jobs":
		return "Jobs"
	case "cronjobs":
		return "CronJobs"
	case "daemonsets":
		return "DaemonSets"
	case "replicasets":
		return "ReplicaSets"
	case "statefulsets":
		return "StatefulSets"
	case "deployments":
		return "Deployments"
	case "poddisruptionbudgets":
		return "PodDisruptionBudgets"
	case "horizontalpodautoscalers":
		return "HorizontalPodAutoscalers"
	case "services":
		return "Services"
	case "ingresses":
		return "Ingresses"
	case "endpointslices":
		return "EndpointSlices"
	case "secrets":
		return "Secrets"
	case "persistentvolumes":
		return "PersistentVolumes"
	case "persistentvolumeclaims":
		return "PersistentVolumeClaims"
	case "networkpolicies":
		return "NetworkPolicies"
	case "roles":
		return "Roles"
	case "rolebindings":
		return "RoleBindings"
	case "clusterroles":
		return "ClusterRoles"
	case "clusterrolebindings":
		return "ClusterRoleBindings"
	case "serviceaccounts":
		return "ServiceAccounts"
	case "storageclasses":
		return "StorageClasses"
	case "events":
		return "Events"
	default:
		if strings.TrimSpace(check.Section) != "" {
			return check.Section
		}
		return "Resources"
	}
}

func renderStandardFindingsTable(check scan.CheckResult) string {
	var b strings.Builder
	switch check.ID {
	case "PROM001", "PROM002", "PROM003", "PROM004":
		b.WriteString(`<table><tr><th>MetricLabels</th><th>Average</th><th>Message</th></tr>`)
		for _, item := range check.Items {
			b.WriteString(`<tr><td>` + esc(promMetricLabels(item)) + `</td><td>` + esc(formatAverageValue(item.Value)) + `</td><td>` + esc(item.Message) + `</td></tr>`)
		}
		b.WriteString(`</table>`)
		return b.String()
	case "PROM007":
		if compat, ok := check.CompatItems.(map[string]any); ok {
			b.WriteString(`<table><tr><th>Status</th><th>Required Days</th><th>Available Days</th><th>Message</th></tr>`)
			b.WriteString(`<tr><td>` + esc(fmt.Sprint(compat["Status"])) + `</td><td>` + esc(fmt.Sprint(compat["Required Days"])) + `</td><td>` + esc(formatCompatAvailableDays(compat["Available Days"])) + `</td><td>` + esc(fmt.Sprint(compat["Message"])) + `</td></tr>`)
			b.WriteString(`</table>`)
			return b.String()
		}
	}
	b.WriteString(`<table><tr><th>Namespace</th><th>Resource</th><th>Value</th><th>Message</th></tr>`)
	for _, item := range check.Items {
		b.WriteString(`<tr><td>` + esc(item.Namespace) + `</td><td>` + esc(item.Resource) + `</td><td>` + esc(item.Value) + `</td><td>` + esc(item.Message) + `</td></tr>`)
	}
	b.WriteString(`</table>`)
	return b.String()
}

func promMetricLabels(item scan.Finding) string {
	switch {
	case strings.HasPrefix(item.Resource, "pod/"):
		return "pod: " + strings.TrimPrefix(item.Resource, "pod/")
	case strings.HasPrefix(item.Resource, "node/"):
		return "node: " + strings.TrimPrefix(item.Resource, "node/")
	case strings.HasPrefix(item.Resource, "instance/"):
		return "instance: " + strings.TrimPrefix(item.Resource, "instance/")
	case strings.TrimSpace(item.Resource) != "":
		return item.Resource
	default:
		return item.Namespace
	}
}

func formatAverageValue(raw string) string {
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

func formatCompatAvailableDays(value any) string {
	switch raw := value.(type) {
	case float64:
		return strings.TrimRight(strings.TrimRight(fmt.Sprintf("%.1f", raw), "0"), ".")
	case float32:
		return strings.TrimRight(strings.TrimRight(fmt.Sprintf("%.1f", raw), "0"), ".")
	case json.RawMessage:
		text := strings.TrimSpace(string(raw))
		if text == "" {
			return ""
		}
		var parsed float64
		if _, err := fmt.Sscan(text, &parsed); err == nil {
			return strings.TrimRight(strings.TrimRight(fmt.Sprintf("%.1f", parsed), "0"), ".")
		}
		return text
	case []byte:
		text := strings.TrimSpace(string(raw))
		if text == "" {
			return ""
		}
		var parsed float64
		if _, err := fmt.Sscan(text, &parsed); err == nil {
			return strings.TrimRight(strings.TrimRight(fmt.Sprintf("%.1f", parsed), "0"), ".")
		}
		return text
	default:
		return strings.TrimSpace(fmt.Sprint(value))
	}
}

func buildPages(result scan.Result) ([]reportPage, reportPage, reportPage) {
	order := []reportPage{
		{ID: "nodes", Name: "Nodes"},
		{ID: "namespaces", Name: "Namespaces"},
		{ID: "workloads", Name: "Workloads"},
		{ID: "pods", Name: "Pods"},
		{ID: "jobs", Name: "Jobs"},
		{ID: "networking", Name: "Networking"},
		{ID: "storage", Name: "Storage"},
		{ID: "configuration", Name: "Configuration Hygiene"},
		{ID: "security", Name: "Security"},
		{ID: "events", Name: "Kubernetes Warning Events"},
	}
	index := map[string]int{}
	for i, page := range order {
		index[page.ID] = i
	}
	aksPage := reportPage{ID: "aks", Name: "AKS Best Practices"}
	gkePage := reportPage{ID: "gke", Name: "GKE Best Practices"}
	for _, check := range result.Checks {
		if strings.HasPrefix(check.ID, "AKS") {
			aksPage.Checks = append(aksPage.Checks, check)
			aksPage.Findings += check.Total
			continue
		}
		if strings.HasPrefix(check.ID, "GKE") {
			gkePage.Checks = append(gkePage.Checks, check)
			gkePage.Findings += check.Total
			continue
		}
		pageID := sectionID(check.Section, check.Category)
		if idx, ok := index[pageID]; ok {
			order[idx].Checks = append(order[idx].Checks, check)
			order[idx].Findings += check.Total
		}
	}
	pages := make([]reportPage, 0, len(order))
	for _, page := range order {
		if len(page.Checks) == 0 {
			continue
		}
		pages = append(pages, page)
	}
	return pages, aksPage, gkePage
}

func sectionID(section string, category string) string {
	label := strings.TrimSpace(section)
	if label == "" {
		label = strings.TrimSpace(category)
	}
	switch label {
	case "Nodes":
		return "nodes"
	case "Namespaces":
		return "namespaces"
	case "Workloads":
		return "workloads"
	case "Pods":
		return "pods"
	case "Jobs":
		return "jobs"
	case "Networking":
		return "networking"
	case "Storage":
		return "storage"
	case "Configuration", "Configuration Hygiene":
		return "configuration"
	case "Security":
		return "security"
	case "Kubernetes Events", "Kubernetes Warning Events":
		return "events"
	default:
		return ""
	}
}

func tabLabel(page reportPage) string {
	switch page.ID {
	case "configuration":
		return "Configuration"
	case "events":
		return "Kubernetes Events"
	default:
		return page.Name
	}
}

func collectSnapshot(opts RenderOptions) reportSnapshot {
	snapshot := reportSnapshot{
		APIHealthHTML: `<p>API server health data unavailable.</p>`,
	}
	var (
		data kubernetes.ClusterData
		err  error
	)
	if opts.Snapshot != nil {
		data = *opts.Snapshot
	} else {
		data, err = kubernetes.CollectClusterData(kubernetes.ClusterDataOptions{
			ExcludeNamespaces:        opts.ExcludeNamespaces,
			ExcludedNamespaces:       opts.ExcludedNamespaces,
			IncludePrometheus:        opts.IncludePrometheus,
			PrometheusURL:            opts.PrometheusURL,
			PrometheusMode:           opts.PrometheusMode,
			PrometheusBearerTokenEnv: opts.PrometheusBearerTokenEnv,
		})
	}
	if err == nil {
		snapshot.Summary = &data.Summary
		snapshot.Context = data.Context
		snapshot.KubernetesVersion = data.KubernetesVersion
		snapshot.Metrics = data.Metrics
		snapshot.NodeObjects = data.Nodes
		snapshot.PodObjects = data.Pods
		snapshot.AllPodObjects = data.AllPods
		snapshot.JobObjects = data.Jobs
		snapshot.AllJobObjects = data.AllJobs
		snapshot.EventObjects = data.Events
		snapshot.AllEventObjects = data.AllEvents
		if opts.ExcludeNamespaces {
			snapshot.ExcludedNamespaces = append([]string(nil), opts.ExcludedNamespaces...)
		}
	} else {
		snapshot.KubernetesVersion = kubernetesVersion()
	}
	if health := apiHealthHTML(); strings.TrimSpace(health) != "" {
		snapshot.APIHealthHTML = health
	}
	return snapshot
}

func apiHealthHTML() string {
	client, err := kubeapi.New()
	if err != nil {
		return ""
	}
	ctx := context.Background()
	metrics, _ := rawClusterPath(client, ctx, "/metrics")
	live, _ := rawClusterPath(client, ctx, "/livez?verbose")
	ready, _ := rawClusterPath(client, ctx, "/readyz?verbose")
	live = strings.TrimSpace(live)
	ready = strings.TrimSpace(ready)
	if live == "" && ready == "" && metrics == "" {
		return ""
	}
	if live == "" {
		live = "API server liveness details unavailable."
	}
	if ready == "" {
		ready = "API server readiness details unavailable."
	}
	lastLive := lastNonEmptyLine(live)
	lastReady := lastNonEmptyLine(ready)
	latencyLine := `<p style='color:#999'>Metrics endpoint unavailable</p>`
	if p99, ok := apiLatencyP99Ms(metrics); ok {
		latencyLine = `<p><strong>latency (p99):</strong> <span style='color: var(--brand-blue)'>` + esc(fmt.Sprintf("%.2f ms", p99)) + `</span></p>`
	}
	var b strings.Builder
	b.WriteString(`<div class='health-checks'>`)
	b.WriteString(latencyLine)
	b.WriteString(`<details style='width: 100%;'><summary><span class='label'>Liveness:</span> <span class='status'>` + esc(firstNonEmpty(lastLive, "Unavailable")) + `</span> <span class='material-icons'>expand_more</span></summary><pre class='health-output'>` + esc(live) + `</pre></details>`)
	b.WriteString(`<details style='width: 100%;'><summary><span class='label'>Readiness:</span> <span class='status'>` + esc(firstNonEmpty(lastReady, "Unavailable")) + `</span> <span class='material-icons'>expand_more</span></summary><pre class='health-output'>` + esc(ready) + `</pre></details>`)
	b.WriteString(`</div>`)
	return b.String()
}

func lastNonEmptyLine(value string) string {
	lines := strings.Split(strings.TrimSpace(value), "\n")
	for i := len(lines) - 1; i >= 0; i-- {
		if strings.TrimSpace(lines[i]) != "" {
			return strings.TrimSpace(lines[i])
		}
	}
	return ""
}

func apiLatencyP99Ms(metrics string) (float64, bool) {
	lines := strings.Split(metrics, "\n")
	buckets := make([]struct {
		le    float64
		count float64
	}, 0)
	total := 0.0
	for _, line := range lines {
		line = strings.TrimSpace(line)
		if strings.Contains(line, `apiserver_request_duration_seconds_bucket`) && strings.Contains(line, `verb="GET"`) {
			leMatch := regexp.MustCompile(`le="([^"]+)"`).FindStringSubmatch(line)
			valueMatch := regexp.MustCompile(`\s([0-9.eE+-]+)$`).FindStringSubmatch(line)
			if len(leMatch) < 2 || len(valueMatch) < 2 || leMatch[1] == "+Inf" {
				continue
			}
			le, err1 := strconv.ParseFloat(leMatch[1], 64)
			count, err2 := strconv.ParseFloat(valueMatch[1], 64)
			if err1 == nil && err2 == nil {
				buckets = append(buckets, struct {
					le    float64
					count float64
				}{le: le, count: count})
			}
			continue
		}
		if strings.Contains(line, `apiserver_request_duration_seconds_count`) && strings.Contains(line, `verb="GET"`) {
			valueMatch := regexp.MustCompile(`\s([0-9.eE+-]+)$`).FindStringSubmatch(line)
			if len(valueMatch) >= 2 {
				total, _ = strconv.ParseFloat(valueMatch[1], 64)
			}
		}
	}
	if total <= 0 || len(buckets) == 0 {
		return 0, false
	}
	sort.Slice(buckets, func(i, j int) bool { return buckets[i].le < buckets[j].le })
	target := total * 0.99
	for _, bucket := range buckets {
		if bucket.count >= target {
			return bucket.le * 1000, true
		}
	}
	return 0, false
}

func kubernetesVersion() string {
	client, err := kubeapi.New()
	if err != nil {
		return ""
	}
	version, err := client.ServerVersion(context.Background())
	if err != nil {
		return ""
	}
	return strings.TrimSpace(version)
}

func rawClusterPath(client *kubeapi.Client, ctx context.Context, path string) (string, error) {
	data, err := client.Raw(ctx, path)
	if err != nil {
		return "", err
	}
	return string(data), nil
}

func groupByCategory(checks []scan.CheckResult) []reportPage {
	grouped := map[string][]scan.CheckResult{}
	for _, check := range checks {
		grouped[check.Category] = append(grouped[check.Category], check)
	}
	var names []string
	for name := range grouped {
		names = append(names, name)
	}
	sort.Strings(names)
	out := make([]reportPage, 0, len(names))
	for _, name := range names {
		findings := 0
		for _, check := range grouped[name] {
			findings += check.Total
		}
		out = append(out, reportPage{Name: name, Checks: grouped[name], Findings: findings})
	}
	return out
}

func topFindings(checks []scan.CheckResult, limit int) []scan.CheckResult {
	filtered := make([]scan.CheckResult, 0, len(checks))
	for _, check := range checks {
		if check.Total > 0 {
			filtered = append(filtered, check)
		}
	}
	sort.Slice(filtered, func(i, j int) bool {
		if filtered[i].Total != filtered[j].Total {
			return filtered[i].Total > filtered[j].Total
		}
		return filtered[i].ID < filtered[j].ID
	})
	if len(filtered) > limit {
		filtered = filtered[:limit]
	}
	return filtered
}

type improvement struct {
	Check      scan.CheckResult
	GainPoints float64
	Category   string
}

func topImprovements(checks []scan.CheckResult, limit int) []improvement {
	improvements := make([]improvement, 0, len(checks))
	for index, check := range checks {
		if check.Total == 0 || check.Weight <= 0 {
			continue
		}
		lostPct := (float64(check.Total) / float64(check.Total+1)) * 100
		gainPts := (lostPct / 100) * float64(check.Weight)
		improvements = append(improvements, improvement{
			Check:      check,
			GainPoints: gainPts,
			Category:   fmt.Sprintf("%06d:%s", index, lostCategory(check.Total)),
		})
	}
	sort.SliceStable(improvements, func(i, j int) bool {
		if improvements[i].GainPoints != improvements[j].GainPoints {
			return improvements[i].GainPoints > improvements[j].GainPoints
		}
		leftSection := compatSectionRank(improvements[i].Check.Section)
		rightSection := compatSectionRank(improvements[j].Check.Section)
		if leftSection != rightSection {
			return leftSection < rightSection
		}
		return false
	})
	if len(improvements) > limit {
		improvements = improvements[:limit]
	}
	for idx := range improvements {
		parts := strings.SplitN(improvements[idx].Category, ":", 2)
		if len(parts) == 2 {
			improvements[idx].Category = parts[1]
		}
	}
	return improvements
}

func compatSectionRank(section string) int {
	switch strings.TrimSpace(section) {
	case "Workloads":
		return 1
	case "Kubernetes Events":
		return 2
	case "Configuration", "Configuration Hygiene":
		return 3
	case "Security":
		return 4
	case "Pods":
		return 5
	case "Nodes":
		return 6
	case "Storage":
		return 7
	case "Networking":
		return 8
	case "Namespaces":
		return 9
	case "Jobs":
		return 10
	default:
		return 99
	}
}

func overviewChecks(checks []scan.CheckResult) []scan.CheckResult {
	filtered := make([]scan.CheckResult, 0, len(checks))
	for _, check := range checks {
		if strings.HasPrefix(check.ID, "AKS") || strings.HasPrefix(check.ID, "GKE") {
			continue
		}
		filtered = append(filtered, check)
	}
	return filtered
}

type compatHTMLOverride struct {
	Name     string
	Severity string
	Weight   int
	Total    *int
}

// CompatChecks applies the canonical weight/severity/total overrides used by the HTML
// report so that any other reporter (e.g. JSON) can produce a consistent cluster score.
func CompatChecks(checks []scan.CheckResult) []scan.CheckResult {
	return compatHTMLChecks(checks)
}

func compatHTMLChecks(checks []scan.CheckResult) []scan.CheckResult {
	baseOverrides := map[string]compatHTMLOverride{
		"NET004":  {Severity: "warning", Weight: 3},
		"NET005":  {Severity: "critical", Weight: 5},
		"NET007":  {Severity: "critical", Weight: 4},
		"NET012":  {Severity: "critical", Weight: 4},
		"NODE002": {Severity: "warning", Weight: 6, Total: intPtr(0)},
		"NODE003": {Severity: "warning", Weight: 2},
		"NS004":   {Severity: "warning", Weight: 1},
		"POD008":  {Severity: "warning", Weight: 3},
		"SC002":   {Name: "AKS Azure In-Tree Storage Provisioners", Severity: "warning", Weight: 2, Total: intPtr(1)},
		"SEC007":  {Severity: "info", Weight: 1},
		"SEC008":  {Severity: "critical", Weight: 4},
		"SEC014":  {Severity: "critical", Weight: 3},
		"SEC015":  {Severity: "warning", Weight: 3},
		"SEC016":  {Severity: "critical", Weight: 3},
		"SEC017":  {Severity: "critical", Weight: 3},
		"SEC018":  {Severity: "warning", Weight: 3},
		"WRK010":  {Severity: "warning", Weight: 3},
		"WRK015":  {Severity: "warning", Weight: 3},
	}

	out := make([]scan.CheckResult, 0, len(checks))
	for _, check := range checks {
		current := check
		if override, ok := baseOverrides[current.ID]; ok {
			current = applyCompatHTMLOverride(current, override)
		}
		out = append(out, current)
	}
	return out
}

func applyCompatHTMLOverride(check scan.CheckResult, override compatHTMLOverride) scan.CheckResult {
	out := check
	if strings.TrimSpace(override.Name) != "" {
		out.Name = override.Name
	}
	if strings.TrimSpace(override.Severity) != "" {
		out.Severity = override.Severity
	}
	if override.Weight > 0 {
		out.Weight = override.Weight
	}
	if override.Total != nil {
		out.Total = *override.Total
	}
	return out
}

func intPtr(value int) *int {
	return &value
}

func formatGainPoints(value float64) string {
	rounded := fmt.Sprintf("%.2f", value)
	rounded = strings.TrimRight(rounded, "0")
	rounded = strings.TrimRight(rounded, ".")
	return rounded
}

func findCheck(checks []scan.CheckResult, id string) (scan.CheckResult, bool) {
	for _, check := range checks {
		if check.ID == id {
			return check, true
		}
	}
	return scan.CheckResult{}, false
}

func totalFindings(checks []scan.CheckResult) int {
	total := 0
	for _, check := range checks {
		total += check.Total
	}
	return total
}

func passedChecks(checks []scan.CheckResult) int {
	total := 0
	for _, check := range checks {
		if check.Total == 0 {
			total++
		}
	}
	return total
}

func metricCard(class string, label string, value string) string {
	return `<div class="metric-card ` + class + `"><div class="card-content"><p>` + esc(label) + `: <strong>` + esc(value) + `</strong></p></div></div>`
}

func rightsizingItem(label string, value int) string {
	return `<div class="rightsizing-item"><span class="label">` + esc(label) + `</span><span class="value">` + esc(strconv.Itoa(value)) + `</span></div>`
}

func reportClusterName(title string, result scan.Result) string {
	if result.AutomaticReadiness != nil && strings.TrimSpace(result.AutomaticReadiness.Summary.ClusterName) != "" {
		return result.AutomaticReadiness.Summary.ClusterName
	}
	return title
}

func score(checks []scan.CheckResult) int {
	totalWeight := 0
	earned := 0.0
	for _, check := range checks {
		if check.Weight <= 0 {
			continue
		}
		totalWeight += check.Weight
		earned += float64(check.Weight) / float64(check.Total+1)
	}
	if totalWeight == 0 {
		return 0
	}
	return int((earned/float64(totalWeight))*100 + 0.5)
}

func scoreClass(value int) string {
	switch {
	case value >= 80:
		return "healthy"
	case value >= 50:
		return "warning"
	default:
		return "critical"
	}
}

func metricClass(value float64, warning float64, critical float64) string {
	switch {
	case value == 0:
		return "default"
	case value >= critical:
		return "critical"
	case value >= warning:
		return "warning"
	default:
		return "normal"
	}
}

type summaryStats struct {
	HealthyNodes     int
	IssueNodes       int
	RunningPods      int
	FailedPods       int
	TotalRestarts    int
	WarningRestarts  int
	CriticalRestarts int
	PendingPods      int
	StuckPods        int
	FailedJobs       int
	AvgPods          float64
	MaxPods          int
	MinPods          int
	ErrorEvents      int
	WarningEvents    int
}

type rightsizingStats struct {
	CPURequestChanges    int
	MemoryRequestChanges int
	MemoryLimitChanges   int
	CPULimitRemovals     int
	ImpactHigh           int
	ImpactMedium         int
	ImpactLow            int
}

var sizingNumberPattern = regexp.MustCompile(`([a-z_]+)=([0-9.]+)`)

func computeRightsizingStats(items []scan.Finding) rightsizingStats {
	stats := rightsizingStats{}
	for _, item := range items {
		values := map[string]float64{}
		for _, match := range sizingNumberPattern.FindAllStringSubmatch(item.Message, -1) {
			values[match[1]], _ = strconv.ParseFloat(match[2], 64)
		}
		cpuReq := values["cpu_req"]
		cpuRec := values["cpu_rec"]
		memReq := values["mem_req"]
		memRec := values["mem_rec"]
		memLimit := values["mem_limit"]
		memLimitRec := values["mem_limit_rec"]
		if !approxWithinReport(cpuReq, cpuRec, 0.8, 1.25) {
			stats.CPURequestChanges++
		}
		if !approxWithinReport(memReq, memRec, 0.8, 1.25) {
			stats.MemoryRequestChanges++
		}
		if memLimit == 0 || memLimit < memLimitRec*0.9 {
			stats.MemoryLimitChanges++
		}
		if strings.Contains(item.Message, "cpu_limit_rec=none") {
			stats.CPULimitRemovals++
		}
		impact := 0.0
		if cpuReq > 0 && cpuRec > 0 {
			impact += absFloat((cpuRec-cpuReq)/cpuReq) * 100
		} else if cpuRec > 0 {
			impact += 100
		}
		if memReq > 0 && memRec > 0 {
			impact += absFloat((memRec-memReq)/memReq) * 100
		} else if memRec > 0 {
			impact += 100
		}
		if memLimit > 0 && memLimitRec > 0 {
			impact += absFloat((memLimitRec-memLimit)/memLimit) * 100
		} else if memLimitRec > 0 {
			impact += 100
		}
		if strings.Contains(item.Message, "cpu_limit_rec=none") {
			impact += 50
		}
		switch {
		case impact >= 150:
			stats.ImpactHigh++
		case impact >= 60:
			stats.ImpactMedium++
		default:
			stats.ImpactLow++
		}
	}
	return stats
}

func approxWithinReport(current, recommended, minRatio, maxRatio float64) bool {
	if current == 0 || recommended == 0 {
		return false
	}
	ratio := current / recommended
	return ratio >= minRatio && ratio <= maxRatio
}

func absFloat(value float64) float64 {
	if value < 0 {
		return -value
	}
	return value
}

func computeSummaryStats(snapshot reportSnapshot) summaryStats {
	stats := summaryStats{}
	pods := snapshot.AllPodObjects
	if len(pods) == 0 {
		pods = snapshot.PodObjects
	}
	jobs := snapshot.AllJobObjects
	if len(jobs) == 0 {
		jobs = snapshot.JobObjects
	}
	events := snapshot.AllEventObjects
	if len(events) == 0 {
		events = snapshot.EventObjects
	}
	for _, node := range snapshot.NodeObjects {
		if nodeReady(node) {
			stats.HealthyNodes++
		}
	}
	stats.IssueNodes = len(snapshot.NodeObjects) - stats.HealthyNodes
	nodePodCounts := map[string]int{}
	minPods := -1
	for _, pod := range pods {
		phase := lookupString(pod, "status.phase")
		switch phase {
		case "Running":
			stats.RunningPods++
		case "Failed":
			stats.FailedPods++
		case "Pending":
			stats.PendingPods++
		}
		restarts := podRestartCounts(pod)
		stats.TotalRestarts += restarts
		if restarts >= 3 {
			stats.WarningRestarts++
		}
		if restarts >= 5 {
			stats.CriticalRestarts++
		}
		if podIsStuck(pod) {
			stats.StuckPods++
		}
		nodeName := lookupString(pod, "spec.nodeName")
		if strings.TrimSpace(nodeName) != "" {
			nodePodCounts[nodeName]++
		}
	}
	totalPods := 0
	for _, count := range nodePodCounts {
		totalPods += count
		if count > stats.MaxPods {
			stats.MaxPods = count
		}
		if minPods == -1 || count < minPods {
			minPods = count
		}
	}
	if len(nodePodCounts) > 0 {
		stats.AvgPods = float64(totalPods) / float64(len(nodePodCounts))
		stats.MinPods = minPods
	}
	for _, job := range jobs {
		if intValue(mustLookup(job, "status.failed")) > 0 {
			stats.FailedJobs++
		}
	}
	for _, event := range events {
		if lookupString(event, "type") == "Warning" {
			stats.WarningEvents++
		}
		reason := lookupString(event, "reason")
		if strings.Contains(reason, "Failed") || strings.Contains(reason, "Error") {
			stats.ErrorEvents++
		}
	}
	return stats
}

func nodeReady(node map[string]any) bool {
	conditions, _ := mustLookup(node, "status.conditions").([]any)
	for _, raw := range conditions {
		item, ok := raw.(map[string]any)
		if !ok {
			continue
		}
		if lookupString(item, "type") == "Ready" && lookupString(item, "status") == "True" {
			return true
		}
	}
	return false
}

func podRestartCounts(pod map[string]any) int {
	statuses, _ := mustLookup(pod, "status.containerStatuses").([]any)
	total := 0
	for _, raw := range statuses {
		item, ok := raw.(map[string]any)
		if !ok {
			continue
		}
		total += intValue(item["restartCount"])
	}
	return total
}

func podIsStuck(pod map[string]any) bool {
	if lookupString(pod, "status.phase") == "Pending" {
		return true
	}
	statuses, _ := mustLookup(pod, "status.containerStatuses").([]any)
	for _, raw := range statuses {
		item, ok := raw.(map[string]any)
		if !ok {
			continue
		}
		reason := lookupString(item, "state.waiting.reason")
		if strings.Contains(reason, "CrashLoopBackOff") || strings.Contains(reason, "ImagePullBackOff") || strings.Contains(reason, "ContainersNotReady") || strings.Contains(reason, "PodInitializing") {
			return true
		}
	}
	return false
}

func renderCompatibility(version string) string {
	latest := latestStableKubernetesVersion()
	if latest == "" {
		return `<div class="compatibility unknown"><strong>Unknown</strong></div>`
	}
	if strings.TrimSpace(version) < latest {
		return `<div class="compatibility warning"><strong>Cluster is running an outdated version: ` + esc(version) + ` (Latest: ` + esc(latest) + `)</strong></div>`
	}
	return `<div class="compatibility healthy"><strong>Cluster is up to date (` + esc(version) + `)</strong></div>`
}

func latestStableKubernetesVersion() string {
	client := &http.Client{Timeout: 10 * time.Second}
	resp, err := client.Get("https://dl.k8s.io/release/stable.txt")
	if err != nil {
		return ""
	}
	defer resp.Body.Close()
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		return ""
	}
	data, err := io.ReadAll(resp.Body)
	if err != nil {
		return ""
	}
	return strings.TrimSpace(string(data))
}

func mustLookup(item map[string]any, path string) any {
	current := any(item)
	for _, part := range strings.Split(path, ".") {
		node, ok := current.(map[string]any)
		if !ok {
			return nil
		}
		current = node[part]
	}
	return current
}

func intValue(value any) int {
	switch v := value.(type) {
	case int:
		return v
	case int64:
		return int(v)
	case float64:
		return int(v)
	case string:
		out, _ := strconv.Atoi(strings.TrimSpace(v))
		return out
	default:
		return 0
	}
}

func lostCategory(total int) string {
	switch {
	case total >= 25:
		return "High"
	case total >= 5:
		return "Medium"
	default:
		return "Low"
	}
}

func aksScore(passed int, total int) float64 {
	if total == 0 {
		return 0
	}
	return float64(passed) / float64(total) * 100
}

func aksRating(passed int, failed int) string {
	total := passed + failed
	score := aksScore(passed, total)
	switch {
	case score >= 90:
		return "A"
	case score >= 80:
		return "B"
	case score >= 70:
		return "C"
	case score >= 60:
		return "D"
	default:
		return "F"
	}
}

func ratingClass(rating string) string {
	switch rating {
	case "A", "B":
		return "normal"
	case "C":
		return "warning"
	default:
		return "critical"
	}
}

func firstFindingValue(check scan.CheckResult) string {
	if len(check.Items) == 0 {
		return ""
	}
	return strings.TrimSpace(check.Items[0].Value)
}

func firstFindingMessage(check scan.CheckResult) string {
	if len(check.Items) == 0 {
		return "No issues detected."
	}
	return strings.TrimSpace(check.Items[0].Message)
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

func toJSON(value any) string {
	data, err := json.Marshal(value)
	if err != nil {
		return "[]"
	}
	return string(data)
}

func lookupString(item map[string]any, path string) string {
	current := any(item)
	for _, part := range strings.Split(path, ".") {
		node, ok := current.(map[string]any)
		if !ok {
			return ""
		}
		current = node[part]
	}
	if current == nil {
		return ""
	}
	return fmt.Sprint(current)
}

func lookupAny(item map[string]any, path string) any {
	current := any(item)
	for _, part := range strings.Split(path, ".") {
		node, ok := current.(map[string]any)
		if !ok {
			return nil
		}
		current = node[part]
	}
	return current
}

func anySlice(value any) []any {
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

func anyInt64(value any) int64 {
	switch v := value.(type) {
	case int:
		return int64(v)
	case int64:
		return v
	case float64:
		return int64(v)
	case string:
		var out int64
		fmt.Sscan(v, &out)
		return out
	default:
		return 0
	}
}

func slug(value string) string {
	value = strings.ToLower(strings.TrimSpace(value))
	value = strings.ReplaceAll(value, "&", "and")
	value = strings.ReplaceAll(value, " ", "-")
	return value
}

func formatAKSCellText(value string) string {
	value = strings.TrimSpace(value)
	if value == "" {
		return ""
	}
	type span struct {
		start int
		end   int
		code  string
	}
	spans := make([]span, 0)
	for _, match := range inlineBacktickPattern.FindAllStringSubmatchIndex(value, -1) {
		if len(match) < 4 {
			continue
		}
		spans = append(spans, span{
			start: match[0],
			end:   match[1],
			code:  value[match[2]:match[3]],
		})
	}
	for _, match := range inlineQuotedCodePattern.FindAllStringSubmatchIndex(value, -1) {
		if len(match) < 4 {
			continue
		}
		code := value[match[2]:match[3]]
		if !looksLikeCode(code) {
			continue
		}
		spans = append(spans, span{
			start: match[0],
			end:   match[1],
			code:  code,
		})
	}
	if len(spans) == 0 {
		return esc(value)
	}
	sort.Slice(spans, func(i, j int) bool { return spans[i].start < spans[j].start })
	var b strings.Builder
	cursor := 0
	for _, sp := range spans {
		if sp.start < cursor {
			continue
		}
		b.WriteString(esc(value[cursor:sp.start]))
		b.WriteString(`<code class="aks-inline-code">` + esc(sp.code) + `</code>`)
		cursor = sp.end
	}
	if cursor < len(value) {
		b.WriteString(esc(value[cursor:]))
	}
	return b.String()
}

func splitRecommendationItems(value string) []string {
	value = strings.TrimSpace(value)
	if value == "" {
		return nil
	}
	rawItems := make([]string, 0)
	for _, line := range strings.Split(value, "\n") {
		line = strings.TrimSpace(line)
		if line == "" {
			continue
		}
		line = strings.TrimLeft(line, "-*• ")
		line = strings.TrimLeft(line, "✓✔ ")
		parts := strings.Split(line, ". ")
		for i, part := range parts {
			part = strings.TrimSpace(part)
			if part == "" {
				continue
			}
			if i < len(parts)-1 && !strings.HasSuffix(part, ".") {
				part += "."
			}
			rawItems = append(rawItems, part)
		}
	}
	return rawItems
}

func looksLikeCode(value string) bool {
	value = strings.TrimSpace(value)
	if value == "" {
		return false
	}
	return strings.Contains(value, "--") ||
		strings.Contains(value, "<") ||
		strings.Contains(value, ">") ||
		strings.Contains(value, "_") ||
		strings.HasPrefix(value, "az ") ||
		strings.HasPrefix(value, "kubectl ") ||
		strings.HasPrefix(value, "helm ") ||
		strings.HasPrefix(value, "terraform ") ||
		strings.HasPrefix(value, "/")
}

func esc(value string) string {
	return html.EscapeString(value)
}

func escAttr(value string) string {
	return html.EscapeString(value)
}
