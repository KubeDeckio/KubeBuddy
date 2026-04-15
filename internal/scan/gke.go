package scan

import (
	"context"
	"encoding/json"
	"fmt"
	"os"
	"sort"
	"strconv"
	"strings"

	container "cloud.google.com/go/container/apiv1"
	containerpb "cloud.google.com/go/container/apiv1/containerpb"
	"github.com/KubeDeckio/KubeBuddy/internal/checks"
	"github.com/KubeDeckio/KubeBuddy/internal/config"
)

// GKEOptions holds the parameters needed to run a GKE best-practice scan.
type GKEOptions struct {
	ChecksDir  string
	ConfigPath string
	InputFile  string
	ProjectID  string
	Location   string
	ClusterName string
	Progress   func(ProgressEvent)
}

// RunGKE executes GKE-specific best-practice checks against a cluster document.
// The document can be loaded from a local JSON file (--input-file) or collected
// from the GKE API in a future iteration.
func RunGKE(opts GKEOptions) (Result, error) {
	if strings.TrimSpace(opts.ChecksDir) == "" {
		opts.ChecksDir = "checks/gke"
	}
	cfg := config.Load(opts.ConfigPath)

	ruleSet, err := checks.LoadDir(opts.ChecksDir)
	if err != nil {
		return Result{}, err
	}
	ruleSet.Checks = filterExcludedChecks(ruleSet.Checks, cfg.ExcludedChecks)

	document, err := loadGKEDocument(opts)
	if err != nil {
		return Result{}, err
	}

	var out Result
	totalChecks := countDeclarativeChecks(ruleSet.Checks)
	current := 0
	for _, check := range ruleSet.Checks {
		if !check.IsDeclarative() || check.Prometheus != nil {
			continue
		}
		current++
		emitProgress(opts.Progress, ProgressEvent{
			Stage:     "start",
			CheckID:   check.ID,
			CheckName: check.Name,
			Index:     current,
			Total:     totalChecks,
		})

		eval := checks.Evaluation{}
		if check.Value != nil {
			eval, err = checks.EvaluateItem(check, document)
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
			SpeechBubble:               append([]string(nil), check.SpeechBubble...),
			URL:                        check.URL,
			ResourceKind:               check.ResourceKind,
			AutomaticRelevance:         check.AutomaticRelevance,
			AutomaticScope:             check.AutomaticScope,
			AutomaticReason:            check.AutomaticReason,
			AutomaticAdmissionBehavior: check.AutomaticAdmissionBehavior,
			AutomaticMutationOutcome:   check.AutomaticMutationOutcome,
			FailMessageText:            "",
		}
		gkeEval, err := evaluateGKECheck(check, document, eval)
		if err != nil {
			return Result{}, fmt.Errorf("%s: %w", check.ID, err)
		}
		result.ObservedValue = gkeEval.ObservedValue
		result.FailMessageText = gkeEval.FailMessage
		if gkeEval.Failed {
			result.Items = append(result.Items, Finding{
				Namespace: "(cluster)",
				Resource:  check.Name,
				Value:     gkeEval.ObservedValue,
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
			Total:     totalChecks,
			Findings:  result.Total,
		})
	}

	sort.Slice(out.Checks, func(i, j int) bool { return out.Checks[i].ID < out.Checks[j].ID })
	return out, nil
}

type gkeEvaluation struct {
	Failed        bool
	ObservedValue string
	FailMessage   string
}

func evaluateGKECheck(check checks.Check, document map[string]any, eval checks.Evaluation) (gkeEvaluation, error) {
	switch check.ID {
	case "GKEBP001":
		// Workload Identity: check workloadIdentityConfig.workloadPool is set
		pool := strings.TrimSpace(stringifyLookup(document, "workloadIdentityConfig.workloadPool"))
		ok := pool != ""
		return gkeBoolEval(!ok, ok), nil

	case "GKEBP002":
		// Shielded Nodes: check shieldedNodes.enabled
		ok := boolFromAny(mustResolve(document, "shieldedNodes.enabled"))
		return gkeBoolEval(!ok, ok), nil

	case "GKEBP003":
		// Node Auto-Upgrade: check all node pools
		ok := gkeAllNodePoolsBool(document, "management.autoUpgrade")
		return gkeBoolEval(!ok, ok), nil

	case "GKEBP004":
		// Node Auto-Repair: check all node pools
		ok := gkeAllNodePoolsBool(document, "management.autoRepair")
		return gkeBoolEval(!ok, ok), nil

	case "GKEBP005":
		// Cloud Logging enabled
		svc := strings.TrimSpace(stringifyLookup(document, "loggingService"))
		ok := !strings.EqualFold(svc, "none") && svc != ""
		return gkeBoolEval(!ok, ok), nil

	case "GKEBP006":
		// Cloud Monitoring enabled
		svc := strings.TrimSpace(stringifyLookup(document, "monitoringService"))
		ok := !strings.EqualFold(svc, "none") && svc != ""
		return gkeBoolEval(!ok, ok), nil

	case "GKEBP007":
		// VPC-Native (Alias IP)
		ok := boolFromAny(mustResolve(document, "ipAllocationPolicy.useIpAliases"))
		return gkeBoolEval(!ok, ok), nil

	case "GKEBP008":
		// Release Channel
		channel := strings.TrimSpace(stringifyLookup(document, "releaseChannel.channel"))
		ok := !strings.EqualFold(channel, "UNSPECIFIED") && channel != ""
		return gkeBoolEval(!ok, ok), nil

	case "GKEBP009":
		// Cluster Autoscaler on all node pools
		ok := gkeAllNodePoolsBool(document, "autoscaling.enabled")
		return gkeBoolEval(!ok, ok), nil

	case "GKEBP010":
		// Binary Authorization
		mode := strings.TrimSpace(stringifyLookup(document, "binaryAuthorization.evaluationMode"))
		ok := !strings.EqualFold(mode, "DISABLED") && mode != ""
		return gkeBoolEval(!ok, ok), nil

	case "GKESEC001":
		// Private Nodes
		ok := boolFromAny(mustResolve(document, "privateClusterConfig.enablePrivateNodes"))
		return gkeBoolEval(!ok, ok), nil

	case "GKESEC002":
		// Master Authorized Networks
		ok := boolFromAny(mustResolve(document, "masterAuthorizedNetworksConfig.enabled"))
		return gkeBoolEval(!ok, ok), nil

	case "GKESEC003":
		// Network Policy or Dataplane V2
		npEnabled := boolFromAny(mustResolve(document, "networkPolicy.enabled"))
		dpv2 := strings.EqualFold(stringifyLookup(document, "datapathProvider"), "ADVANCED_DATAPATH")
		ok := npEnabled || dpv2
		return gkeBoolEval(!ok, ok), nil

	case "GKESEC004":
		// Dataplane V2
		ok := strings.EqualFold(stringifyLookup(document, "datapathProvider"), "ADVANCED_DATAPATH")
		return gkeBoolEval(!ok, ok), nil

	case "GKESEC005":
		// Intranode Visibility
		ok := boolFromAny(mustResolve(document, "networkConfig.enableIntraNodeVisibility"))
		return gkeBoolEval(!ok, ok), nil

	case "GKESEC006":
		// Application-Layer Secrets Encryption
		state := strings.TrimSpace(stringifyLookup(document, "databaseEncryption.state"))
		ok := strings.EqualFold(state, "ENCRYPTED")
		return gkeBoolEval(!ok, ok), nil
	}

	// Fallback: use the declarative evaluation from the YAML spec
	return gkeEvaluation{
		Failed:        eval.Failed,
		ObservedValue: flattenValue(eval.Value),
		FailMessage:   "",
	}, nil
}

func gkeBoolEval(failed bool, actual bool) gkeEvaluation {
	return gkeEvaluation{
		Failed:        failed,
		ObservedValue: strconv.FormatBool(actual),
		FailMessage:   "",
	}
}

// gkeNodePools extracts the node pool list from a GKE cluster document.
func gkeNodePools(document map[string]any) []map[string]any {
	var pools []map[string]any
	for _, item := range asSlice(mustResolve(document, "nodePools")) {
		if pool, ok := item.(map[string]any); ok {
			pools = append(pools, pool)
		}
	}
	return pools
}

// gkeAllNodePoolsBool returns true only if every node pool has the given
// nested boolean field set to true.
func gkeAllNodePoolsBool(document map[string]any, path string) bool {
	pools := gkeNodePools(document)
	if len(pools) == 0 {
		return false
	}
	for _, pool := range pools {
		if !boolFromAny(mustResolve(pool, path)) {
			return false
		}
	}
	return true
}

// loadGKEDocument loads a GKE cluster description from a local JSON file
// or from the live GKE API using Application Default Credentials (ADC).
func loadGKEDocument(opts GKEOptions) (map[string]any, error) {
	if strings.TrimSpace(opts.InputFile) != "" {
		data, err := os.ReadFile(opts.InputFile)
		if err != nil {
			return nil, err
		}
		var document map[string]any
		if err := json.Unmarshal(data, &document); err != nil {
			return nil, err
		}
		return document, nil
	}
	if strings.TrimSpace(opts.ProjectID) != "" && strings.TrimSpace(opts.Location) != "" && strings.TrimSpace(opts.ClusterName) != "" {
		return collectLiveGKEDocument(opts)
	}
	return nil, fmt.Errorf("provide --input with a GKE cluster JSON file, or --project-id, --location, and --cluster-name for live collection")
}

// collectLiveGKEDocument fetches the cluster description from the GKE API
// using the official Go SDK and Application Default Credentials.
func collectLiveGKEDocument(opts GKEOptions) (map[string]any, error) {
	ctx := context.Background()
	client, err := container.NewClusterManagerClient(ctx)
	if err != nil {
		return nil, fmt.Errorf("creating GKE client: %w", err)
	}
	defer client.Close()

	name := fmt.Sprintf("projects/%s/locations/%s/clusters/%s", opts.ProjectID, opts.Location, opts.ClusterName)
	cluster, err := client.GetCluster(ctx, &containerpb.GetClusterRequest{Name: name})
	if err != nil {
		return nil, fmt.Errorf("fetching cluster %s: %w", name, err)
	}

	// Marshal the protobuf response to JSON, then unmarshal into map[string]any
	// to match the format used by gcloud --format json and the declarative evaluator.
	data, err := json.Marshal(cluster)
	if err != nil {
		return nil, fmt.Errorf("marshalling cluster response: %w", err)
	}
	var document map[string]any
	if err := json.Unmarshal(data, &document); err != nil {
		return nil, fmt.Errorf("parsing cluster response: %w", err)
	}
	return document, nil
}
