package scan

import (
	"sort"
	"strings"
)

const (
	riskPathStatusClear     = "clear"
	riskPathStatusTriggered = "triggered"
)

type DirectRiskPath struct {
	ID              string              `json:"id"`
	Name            string              `json:"name"`
	Boundary        string              `json:"boundary"`
	Status          string              `json:"status"`
	Confidence      string              `json:"confidence"`
	Exploitability  string              `json:"exploitability"`
	FixPriority     string              `json:"fixPriority"`
	Summary         string              `json:"summary"`
	SignalChecks    []string            `json:"signalChecks"`
	Evidence        []RiskPathEvidence  `json:"evidence,omitempty"`
	ValidationProof []ValidationCommand `json:"validationProof,omitempty"`
	AttackGraph     *RiskPathGraph      `json:"attackGraph,omitempty"`
}

type RiskPathEvidence struct {
	CheckID        string    `json:"checkId"`
	CheckName      string    `json:"checkName"`
	Severity       string    `json:"severity"`
	FindingCount   int       `json:"findingCount"`
	SampleFindings []Finding `json:"sampleFindings,omitempty"`
}

type ValidationCommand struct {
	Title    string `json:"title"`
	Command  string `json:"command"`
	Purpose  string `json:"purpose"`
	ReadOnly bool   `json:"readOnly"`
}

type RiskPathGraph struct {
	Nodes []RiskPathGraphNode `json:"nodes"`
	Edges []RiskPathGraphEdge `json:"edges"`
}

type RiskPathGraphNode struct {
	ID      string `json:"id"`
	Label   string `json:"label"`
	Type    string `json:"type"`
	CheckID string `json:"checkId,omitempty"`
}

type RiskPathGraphEdge struct {
	From  string `json:"from"`
	To    string `json:"to"`
	Label string `json:"label"`
}

type CombinedRiskPath struct {
	ID                       string         `json:"id"`
	Name                     string         `json:"name"`
	Status                   string         `json:"status"`
	Confidence               string         `json:"confidence"`
	FixPriority              string         `json:"fixPriority"`
	Summary                  string         `json:"summary"`
	Requires                 []string       `json:"requires"`
	TriggeredDirectRiskPaths []string       `json:"triggeredDirectRiskPaths,omitempty"`
	AttackGraph              *RiskPathGraph `json:"attackGraph,omitempty"`
}

type directRiskPathDefinition struct {
	ID                 string
	Name               string
	Boundary           string
	Signals            []string
	TriggerThreshold   int
	CriticalSingleHits map[string]struct{}
	SummaryClear       string
	SummaryTriggered   string
	ValidationProof    []ValidationCommand
}

type combinedRiskPathDefinition struct {
	ID               string
	Name             string
	Requires         []string
	SummaryClear     string
	SummaryTriggered string
}

func AnalyzeDirectRiskPaths(checks []CheckResult) ([]DirectRiskPath, []CombinedRiskPath) {
	byID := mapChecksByID(checks)
	directRiskPaths := make([]DirectRiskPath, 0, len(directRiskPathDefinitions()))
	for _, definition := range directRiskPathDefinitions() {
		directRiskPaths = append(directRiskPaths, buildDirectRiskPath(definition, byID))
	}
	combinedRiskPaths := buildCombinedRiskPaths(combinedRiskPathDefinitions(), directRiskPaths)
	return directRiskPaths, combinedRiskPaths
}

func directRiskPathDefinitions() []directRiskPathDefinition {
	return []directRiskPathDefinition{
		{
			ID:                 "RISK001",
			Name:               "Container Isolation Risk",
			Boundary:           "Workload to node/container isolation",
			Signals:            []string{"POD011", "POD013", "SEC002", "SEC004", "SEC010", "SEC012", "SEC017", "SEC021", "SEC023", "SEC029"},
			TriggerThreshold:   2,
			CriticalSingleHits: idSet([]string{"SEC004", "SEC010", "SEC012", "SEC029"}),
			SummaryClear:       "No correlated container isolation risk signals were detected.",
			SummaryTriggered:   "Correlated workload security findings indicate a possible path from workload settings toward host or node control.",
			ValidationProof: []ValidationCommand{
				{Title: "List pods with node placement", Command: "kubectl get pods --all-namespaces -o wide", Purpose: "Confirms which flagged workloads are scheduled and where they run.", ReadOnly: true},
				{Title: "Inspect host namespace usage", Command: "kubectl get pods --all-namespaces -o jsonpath=\"{range .items[*]}{.metadata.namespace}/{.metadata.name}{'\\t'}{.spec.hostNetwork}{'\\t'}{.spec.hostPID}{'\\t'}{.spec.hostIPC}{'\\n'}{end}\"", Purpose: "Shows host namespace settings that weaken container isolation.", ReadOnly: true},
			},
		},
		{
			ID:                 "RISK002",
			Name:               "Namespace Isolation Risk",
			Boundary:           "Namespace tenancy and east-west isolation",
			Signals:            []string{"NET004", "NET021", "RBAC002", "RBAC007", "RBAC008", "RBAC010"},
			TriggerThreshold:   2,
			CriticalSingleHits: idSet([]string{"RBAC002", "RBAC007", "RBAC010"}),
			SummaryClear:       "No correlated namespace isolation risk signals were detected.",
			SummaryTriggered:   "Network and RBAC findings indicate namespace boundaries may not contain workload access.",
			ValidationProof: []ValidationCommand{
				{Title: "List namespace network policies", Command: "kubectl get networkpolicy --all-namespaces", Purpose: "Confirms whether namespaces have network policy coverage.", ReadOnly: true},
				{Title: "List role bindings", Command: "kubectl get rolebinding --all-namespaces -o wide", Purpose: "Shows namespace-local bindings that may grant access across namespace boundaries.", ReadOnly: true},
			},
		},
		{
			ID:                 "RISK003",
			Name:               "RBAC Privilege Risk",
			Boundary:           "Identity authorization and privilege boundaries",
			Signals:            []string{"RBAC002", "RBAC005", "RBAC006", "RBAC007", "RBAC009", "RBAC010"},
			TriggerThreshold:   1,
			CriticalSingleHits: idSet([]string{"RBAC002", "RBAC006", "RBAC007", "RBAC009", "RBAC010"}),
			SummaryClear:       "No RBAC privilege risk signals were detected.",
			SummaryTriggered:   "RBAC findings indicate identities may have privileges that cross intended authorization boundaries.",
			ValidationProof: []ValidationCommand{
				{Title: "Review effective permissions", Command: "kubectl auth can-i --list --all-namespaces", Purpose: "Shows the current user's effective permissions for comparison with flagged RBAC paths.", ReadOnly: true},
				{Title: "List RBAC objects", Command: "kubectl get role,clusterrole,rolebinding,clusterrolebinding --all-namespaces", Purpose: "Collects RBAC objects needed to validate the reported privilege path.", ReadOnly: true},
			},
		},
		{
			ID:                 "RISK004",
			Name:               "ServiceAccount Trust Risk",
			Boundary:           "ServiceAccount identity and token trust",
			Signals:            []string{"POD008", "SEC015", "SEC018", "RBAC009", "RBAC010"},
			TriggerThreshold:   2,
			CriticalSingleHits: idSet([]string{"RBAC009", "RBAC010"}),
			SummaryClear:       "No correlated ServiceAccount trust risk signals were detected.",
			SummaryTriggered:   "ServiceAccount, workload token, and RBAC findings indicate workload identity trust may be overexposed.",
			ValidationProof: []ValidationCommand{
				{Title: "List ServiceAccounts", Command: "kubectl get serviceaccount --all-namespaces -o wide", Purpose: "Shows ServiceAccounts that may be bound to workloads or permissive RBAC.", ReadOnly: true},
				{Title: "Inspect ServiceAccount token automounting", Command: `kubectl get pods --all-namespaces -o jsonpath="{range .items[*]}{.metadata.namespace}/{.metadata.name}{'\t'}{.spec.serviceAccountName}{'\t'}{.spec.automountServiceAccountToken}{'\n'}{end}"`, Purpose: "Confirms workload ServiceAccount usage and token automount settings without reading token values.", ReadOnly: true},
			},
		},
		{
			ID:                 "RISK007",
			Name:               "Secret Exposure Risk",
			Boundary:           "Secret data and credential exposure",
			Signals:            []string{"SEC008", "SEC022", "SEC031", "SEC032", "SEC033", "RBAC006", "RBAC010"},
			TriggerThreshold:   2,
			CriticalSingleHits: idSet([]string{"SEC031", "RBAC006"}),
			SummaryClear:       "No correlated secret exposure risk signals were detected.",
			SummaryTriggered:   "Secret, ConfigMap, and RBAC findings indicate credential exposure may combine with access paths.",
			ValidationProof: []ValidationCommand{
				{Title: "List Secrets without values", Command: "kubectl get secrets --all-namespaces", Purpose: "Confirms Secret names, namespaces, and types without printing Secret data.", ReadOnly: true},
				{Title: "Check who can read Secrets", Command: "kubectl auth can-i get secrets --all-namespaces", Purpose: "Confirms whether the current identity can read Secrets without exposing Secret values.", ReadOnly: true},
			},
		},
	}
}

func combinedRiskPathDefinitions() []combinedRiskPathDefinition {
	return []combinedRiskPathDefinition{
		{
			ID:               "CHAIN001",
			Name:             "Workload to Cluster Control Path",
			Requires:         []string{"RISK001", "RISK003"},
			SummaryClear:     "Container isolation and RBAC privilege risks were not both present.",
			SummaryTriggered: "Container isolation and RBAC privilege risks combine into a possible workload-to-cluster-control path.",
		},
		{
			ID:               "CHAIN002",
			Name:             "Cross-Namespace Privilege Path",
			Requires:         []string{"RISK002", "RISK003"},
			SummaryClear:     "Namespace isolation and RBAC privilege risks were not both present.",
			SummaryTriggered: "Namespace isolation and RBAC privilege risks combine into a possible cross-namespace privilege path.",
		},
		{
			ID:               "CHAIN003",
			Name:             "ServiceAccount to Cluster Control Path",
			Requires:         []string{"RISK004", "RISK003"},
			SummaryClear:     "ServiceAccount trust and RBAC privilege risks were not both present.",
			SummaryTriggered: "ServiceAccount trust and RBAC privilege risks combine into a possible workload-identity-to-cluster-control path.",
		},
		{
			ID:               "CHAIN005",
			Name:             "Secret Exposure to Cluster Control Path",
			Requires:         []string{"RISK003", "RISK007"},
			SummaryClear:     "Secret exposure and RBAC privilege risks were not both present.",
			SummaryTriggered: "Secret exposure and RBAC privilege risks combine into a possible credential-to-cluster-control path.",
		},
	}
}

func buildDirectRiskPath(definition directRiskPathDefinition, byID map[string]CheckResult) DirectRiskPath {
	evidence := collectRiskPathEvidence(definition.Signals, byID)
	status := riskPathStatusClear
	if len(evidence) >= definition.TriggerThreshold || hasCriticalSingleHit(evidence, definition.CriticalSingleHits) {
		status = riskPathStatusTriggered
	}
	summary := definition.SummaryClear
	if status == riskPathStatusTriggered {
		summary = definition.SummaryTriggered
	}
	capability := DirectRiskPath{
		ID:              definition.ID,
		Name:            definition.Name,
		Boundary:        definition.Boundary,
		Status:          status,
		Confidence:      riskPathConfidence(status, len(evidence)),
		Exploitability:  riskPathExploitability(status, evidence, definition.CriticalSingleHits),
		FixPriority:     riskPathFixPriority(status, evidence),
		Summary:         summary,
		SignalChecks:    append([]string(nil), definition.Signals...),
		Evidence:        evidence,
		ValidationProof: append([]ValidationCommand(nil), definition.ValidationProof...),
	}
	if status == riskPathStatusTriggered {
		capability.AttackGraph = buildRiskPathGraph(definition.ID, definition.Name, evidence)
	}
	return capability
}

func collectRiskPathEvidence(signals []string, byID map[string]CheckResult) []RiskPathEvidence {
	evidence := make([]RiskPathEvidence, 0, len(signals))
	for _, id := range signals {
		check, ok := byID[id]
		if !ok || check.Total <= 0 {
			continue
		}
		evidence = append(evidence, RiskPathEvidence{
			CheckID:        check.ID,
			CheckName:      check.Name,
			Severity:       check.Severity,
			FindingCount:   check.Total,
			SampleFindings: sampleFindings(check.Items, 3),
		})
	}
	sort.Slice(evidence, func(i, j int) bool { return evidence[i].CheckID < evidence[j].CheckID })
	return evidence
}

func buildCombinedRiskPaths(definitions []combinedRiskPathDefinition, directRiskPaths []DirectRiskPath) []CombinedRiskPath {
	byID := map[string]DirectRiskPath{}
	for _, capability := range directRiskPaths {
		byID[capability.ID] = capability
	}
	combinedRiskPaths := make([]CombinedRiskPath, 0, len(definitions))
	for _, definition := range definitions {
		triggered := make([]string, 0, len(definition.Requires))
		for _, id := range definition.Requires {
			if byID[id].Status == riskPathStatusTriggered {
				triggered = append(triggered, id)
			}
		}
		status := riskPathStatusClear
		summary := definition.SummaryClear
		if len(triggered) == len(definition.Requires) {
			status = riskPathStatusTriggered
			summary = definition.SummaryTriggered
		}
		compound := CombinedRiskPath{
			ID:                       definition.ID,
			Name:                     definition.Name,
			Status:                   status,
			Confidence:               compoundConfidence(status, triggered),
			FixPriority:              compoundFixPriority(status),
			Summary:                  summary,
			Requires:                 append([]string(nil), definition.Requires...),
			TriggeredDirectRiskPaths: triggered,
		}
		if status == riskPathStatusTriggered {
			compound.AttackGraph = buildCombinedRiskPathGraph(definition.ID, definition.Name, definition.Requires)
		}
		combinedRiskPaths = append(combinedRiskPaths, compound)
	}
	return combinedRiskPaths
}

func mapChecksByID(checks []CheckResult) map[string]CheckResult {
	byID := make(map[string]CheckResult, len(checks))
	for _, check := range checks {
		byID[strings.ToUpper(strings.TrimSpace(check.ID))] = check
	}
	return byID
}

func sampleFindings(findings []Finding, limit int) []Finding {
	if len(findings) == 0 || limit <= 0 {
		return nil
	}
	if len(findings) < limit {
		limit = len(findings)
	}
	return append([]Finding(nil), findings[:limit]...)
}

func hasCriticalSingleHit(evidence []RiskPathEvidence, criticalIDs map[string]struct{}) bool {
	for _, item := range evidence {
		if _, ok := criticalIDs[item.CheckID]; ok {
			return true
		}
	}
	return false
}

func riskPathConfidence(status string, evidenceCount int) string {
	if status != riskPathStatusTriggered {
		return "none"
	}
	if evidenceCount >= 3 {
		return "high"
	}
	return "medium"
}

func riskPathExploitability(status string, evidence []RiskPathEvidence, criticalIDs map[string]struct{}) string {
	if status != riskPathStatusTriggered {
		return "none"
	}
	if hasCriticalSingleHit(evidence, criticalIDs) || len(evidence) >= 3 {
		return "high"
	}
	return "medium"
}

func riskPathFixPriority(status string, evidence []RiskPathEvidence) string {
	if status != riskPathStatusTriggered {
		return "normal"
	}
	if len(evidence) >= 3 {
		return "urgent"
	}
	return "high"
}

func compoundConfidence(status string, triggered []string) string {
	if status != riskPathStatusTriggered {
		return "none"
	}
	if len(triggered) >= 2 {
		return "high"
	}
	return "medium"
}

func compoundFixPriority(status string) string {
	if status == riskPathStatusTriggered {
		return "urgent"
	}
	return "normal"
}

func buildRiskPathGraph(id, name string, evidence []RiskPathEvidence) *RiskPathGraph {
	graph := &RiskPathGraph{
		Nodes: []RiskPathGraphNode{{ID: id, Label: name, Type: "directRiskPath"}},
		Edges: []RiskPathGraphEdge{},
	}
	for _, item := range evidence {
		nodeID := "check:" + item.CheckID
		graph.Nodes = append(graph.Nodes, RiskPathGraphNode{ID: nodeID, Label: item.CheckName, Type: "check", CheckID: item.CheckID})
		graph.Edges = append(graph.Edges, RiskPathGraphEdge{From: nodeID, To: id, Label: "contributes"})
	}
	return graph
}

func buildCombinedRiskPathGraph(id, name string, requires []string) *RiskPathGraph {
	graph := &RiskPathGraph{
		Nodes: []RiskPathGraphNode{{ID: id, Label: name, Type: "combinedRiskPath"}},
		Edges: []RiskPathGraphEdge{},
	}
	for _, required := range requires {
		graph.Nodes = append(graph.Nodes, RiskPathGraphNode{ID: required, Label: required, Type: "directRiskPath"})
		graph.Edges = append(graph.Edges, RiskPathGraphEdge{From: required, To: id, Label: "enables"})
	}
	return graph
}

func idSet(ids []string) map[string]struct{} {
	set := make(map[string]struct{}, len(ids))
	for _, id := range ids {
		set[id] = struct{}{}
	}
	return set
}
