package scan

import (
	"context"
	"encoding/json"
	"fmt"
	"os"
	"sort"
	"strconv"
	"strings"

	"github.com/KubeDeckio/KubeBuddy/internal/checks"
	"github.com/KubeDeckio/KubeBuddy/internal/config"

	awsconfig "github.com/aws/aws-sdk-go-v2/config"
	"github.com/aws/aws-sdk-go-v2/service/eks"
)

// EKSOptions holds the parameters needed to run an EKS best-practice scan.
type EKSOptions struct {
	ChecksDir   string
	ConfigPath  string
	InputFile   string
	Region      string
	ClusterName string
	Progress    func(ProgressEvent)
}

// RunEKS executes EKS-specific best-practice checks against a cluster document.
// The document can be loaded from a local JSON file (--input) or collected
// live from the AWS EKS API using the default credential chain.
func RunEKS(opts EKSOptions) (Result, error) {
	if strings.TrimSpace(opts.ChecksDir) == "" {
		opts.ChecksDir = "checks/eks"
	}
	cfg := config.Load(opts.ConfigPath)

	ruleSet, err := checks.LoadDir(opts.ChecksDir)
	if err != nil {
		return Result{}, err
	}
	ruleSet.Checks = filterExcludedChecks(ruleSet.Checks, cfg.ExcludedChecks)

	document, err := loadEKSDocument(opts)
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
		eksEval, err := evaluateEKSCheck(check, document, eval)
		if err != nil {
			return Result{}, fmt.Errorf("%s: %w", check.ID, err)
		}
		result.ObservedValue = eksEval.ObservedValue
		result.FailMessageText = eksEval.FailMessage
		if eksEval.Failed {
			result.Items = append(result.Items, Finding{
				Namespace: "(cluster)",
				Resource:  check.Name,
				Value:     eksEval.ObservedValue,
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

type eksEvaluation struct {
	Failed        bool
	ObservedValue string
	FailMessage   string
}

func evaluateEKSCheck(check checks.Check, document map[string]any, eval checks.Evaluation) (eksEvaluation, error) {
	switch check.ID {
	case "EKSBP001":
		// IRSA: check identity.oidc.issuer is set
		issuer := strings.TrimSpace(stringifyLookup(document, "identity.oidc.issuer"))
		ok := issuer != ""
		return eksBoolEval(!ok, ok), nil

	case "EKSBP002":
		// Platform version exists
		pv := strings.TrimSpace(stringifyLookup(document, "platformVersion"))
		ok := pv != ""
		return eksBoolEval(!ok, ok), nil

	case "EKSBP003":
		// Kubernetes version exists
		ver := strings.TrimSpace(stringifyLookup(document, "version"))
		ok := ver != ""
		return eksBoolEval(!ok, ok), nil

	case "EKSBP004":
		// Managed node groups exist
		groups := eksNodeGroups(document)
		ok := len(groups) > 0
		return eksBoolEval(!ok, ok), nil

	case "EKSBP005":
		// EKS-managed add-ons exist
		addons := eksAddons(document)
		ok := len(addons) > 0
		return eksBoolEval(!ok, ok), nil

	case "EKSBP006":
		// EKS Auto Mode enabled
		ok := boolFromAny(mustResolve(document, "computeConfig.enabled"))
		return eksBoolEval(!ok, ok), nil

	case "EKSBP007":
		// Access config not using legacy CONFIG_MAP
		mode := strings.TrimSpace(stringifyLookup(document, "accessConfig.authenticationMode"))
		ok := !strings.EqualFold(mode, "CONFIG_MAP") && mode != ""
		return eksBoolEval(!ok, ok), nil

	case "EKSBP008":
		// Tags applied
		tags := mustResolve(document, "tags")
		ok := false
		if m, isMap := tags.(map[string]any); isMap && len(m) > 0 {
			ok = true
		}
		return eksBoolEval(!ok, ok), nil

	case "EKSSEC001":
		// Private endpoint access enabled
		ok := boolFromAny(mustResolve(document, "resourcesVpcConfig.endpointPrivateAccess"))
		return eksBoolEval(!ok, ok), nil

	case "EKSSEC002":
		// Public endpoint access disabled
		publicAccess := boolFromAny(mustResolve(document, "resourcesVpcConfig.endpointPublicAccess"))
		ok := !publicAccess
		return eksBoolEval(!ok, ok), nil

	case "EKSSEC003":
		// Public access CIDRs restricted (not 0.0.0.0/0)
		cidrs := asSlice(mustResolve(document, "resourcesVpcConfig.publicAccessCidrs"))
		ok := true
		if len(cidrs) == 0 {
			ok = false
		}
		for _, cidr := range cidrs {
			if strings.TrimSpace(fmt.Sprint(cidr)) == "0.0.0.0/0" {
				ok = false
				break
			}
		}
		return eksBoolEval(!ok, ok), nil

	case "EKSSEC004":
		// Envelope encryption configured
		enc := mustResolve(document, "encryptionConfig")
		ok := false
		if items := asSlice(enc); len(items) > 0 {
			ok = true
		}
		return eksBoolEval(!ok, ok), nil

	case "EKSSEC005":
		// Additional security groups attached
		sgs := asSlice(mustResolve(document, "resourcesVpcConfig.securityGroupIds"))
		ok := len(sgs) > 0
		return eksBoolEval(!ok, ok), nil

	case "EKSSEC006":
		// EKS Pod Identity Agent installed
		ok := boolFromAny(mustResolve(document, "_hasPodIdentityAgent"))
		if !ok {
			ok = eksHasAddon(document, "eks-pod-identity-agent")
		}
		return eksBoolEval(!ok, ok), nil

	case "EKSSEC007":
		// Cluster role ARN exists
		role := strings.TrimSpace(stringifyLookup(document, "roleArn"))
		ok := role != ""
		return eksBoolEval(!ok, ok), nil

	case "EKSMON001":
		// Control plane logging exists
		ok := eksLoggingEnabled(document)
		return eksBoolEval(!ok, ok), nil

	case "EKSMON002":
		// All 5 log types enabled
		ok := eksAllLogTypesEnabled(document)
		return eksBoolEval(!ok, ok), nil

	case "EKSMON003":
		// CloudWatch observability add-on
		ok := boolFromAny(mustResolve(document, "_hasCloudWatchObservability"))
		if !ok {
			ok = eksHasAddon(document, "amazon-cloudwatch-observability")
		}
		return eksBoolEval(!ok, ok), nil

	case "EKSNET001":
		// VPC CNI managed add-on
		ok := boolFromAny(mustResolve(document, "_hasVpcCniAddon"))
		if !ok {
			ok = eksHasAddon(document, "vpc-cni")
		}
		return eksBoolEval(!ok, ok), nil

	case "EKSNET002":
		// CoreDNS managed add-on
		ok := boolFromAny(mustResolve(document, "_hasCoreDnsAddon"))
		if !ok {
			ok = eksHasAddon(document, "coredns")
		}
		return eksBoolEval(!ok, ok), nil

	case "EKSNET003":
		// kube-proxy managed add-on
		ok := boolFromAny(mustResolve(document, "_hasKubeProxyAddon"))
		if !ok {
			ok = eksHasAddon(document, "kube-proxy")
		}
		return eksBoolEval(!ok, ok), nil
	}

	// Fallback: use the declarative evaluation from the YAML spec
	return eksEvaluation{
		Failed:        eval.Failed,
		ObservedValue: flattenValue(eval.Value),
		FailMessage:   "",
	}, nil
}

func eksBoolEval(failed bool, actual bool) eksEvaluation {
	return eksEvaluation{
		Failed:        failed,
		ObservedValue: strconv.FormatBool(actual),
		FailMessage:   "",
	}
}

// eksNodeGroups extracts the node group list from an EKS cluster document.
func eksNodeGroups(document map[string]any) []map[string]any {
	var groups []map[string]any
	for _, item := range asSlice(mustResolve(document, "_nodeGroups")) {
		if group, ok := item.(map[string]any); ok {
			groups = append(groups, group)
		}
	}
	return groups
}

// eksAddons extracts the add-on list from an EKS cluster document.
func eksAddons(document map[string]any) []map[string]any {
	var addons []map[string]any
	for _, item := range asSlice(mustResolve(document, "_addons")) {
		if addon, ok := item.(map[string]any); ok {
			addons = append(addons, addon)
		}
	}
	return addons
}

// eksHasAddon checks whether a specific EKS add-on is present in the document.
func eksHasAddon(document map[string]any, name string) bool {
	for _, addon := range eksAddons(document) {
		if strings.EqualFold(stringifyLookup(addon, "addonName"), name) {
			return true
		}
	}
	return false
}

// eksLoggingEnabled returns true if at least one cluster logging entry is enabled.
func eksLoggingEnabled(document map[string]any) bool {
	for _, entry := range asSlice(mustResolve(document, "logging.clusterLogging")) {
		if m, ok := entry.(map[string]any); ok {
			if boolFromAny(m["enabled"]) {
				return true
			}
		}
	}
	return false
}

// eksAllLogTypesEnabled returns true if all five EKS control plane log types
// (api, audit, authenticator, controllerManager, scheduler) are enabled.
func eksAllLogTypesEnabled(document map[string]any) bool {
	required := map[string]bool{
		"api":               false,
		"audit":             false,
		"authenticator":     false,
		"controllermanager": false,
		"scheduler":         false,
	}
	for _, entry := range asSlice(mustResolve(document, "logging.clusterLogging")) {
		m, ok := entry.(map[string]any)
		if !ok || !boolFromAny(m["enabled"]) {
			continue
		}
		for _, t := range asSlice(m["types"]) {
			key := strings.ToLower(strings.TrimSpace(fmt.Sprint(t)))
			if _, exists := required[key]; exists {
				required[key] = true
			}
		}
	}
	for _, found := range required {
		if !found {
			return false
		}
	}
	return true
}

// loadEKSDocument loads an EKS cluster description from a local JSON file
// or from the live AWS EKS API using the default credential chain.
func loadEKSDocument(opts EKSOptions) (map[string]any, error) {
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
	if strings.TrimSpace(opts.ClusterName) != "" {
		return collectLiveEKSDocument(opts)
	}
	return nil, fmt.Errorf("provide --input with an EKS cluster JSON file, or --cluster-name (and optionally --region) for live collection")
}

// collectLiveEKSDocument fetches the cluster description from the AWS EKS API
// using the official AWS SDK v2 and the default credential chain.
func collectLiveEKSDocument(opts EKSOptions) (map[string]any, error) {
	ctx := context.Background()

	var cfgOpts []func(*awsconfig.LoadOptions) error
	if strings.TrimSpace(opts.Region) != "" {
		cfgOpts = append(cfgOpts, awsconfig.WithRegion(opts.Region))
	}
	cfg, err := awsconfig.LoadDefaultConfig(ctx, cfgOpts...)
	if err != nil {
		return nil, fmt.Errorf("loading AWS config: %w", err)
	}

	client := eks.NewFromConfig(cfg)
	cluster, err := client.DescribeCluster(ctx, &eks.DescribeClusterInput{
		Name: &opts.ClusterName,
	})
	if err != nil {
		return nil, fmt.Errorf("describing cluster %s: %w", opts.ClusterName, err)
	}

	// Marshal the SDK response to JSON, then unmarshal into map[string]any
	// to match the format used by the declarative evaluator.
	data, err := json.Marshal(cluster.Cluster)
	if err != nil {
		return nil, fmt.Errorf("marshalling cluster response: %w", err)
	}
	var document map[string]any
	if err := json.Unmarshal(data, &document); err != nil {
		return nil, fmt.Errorf("parsing cluster response: %w", err)
	}

	// Enrich the document with add-on and node group data from separate API calls.
	enrichEKSDocument(ctx, client, opts.ClusterName, document)

	return document, nil
}

// enrichEKSDocument fetches add-ons and managed node groups from the EKS API
// and merges them into the cluster document under synthetic keys.
func enrichEKSDocument(ctx context.Context, client *eks.Client, clusterName string, document map[string]any) {
	// Fetch add-ons
	addonsOut, err := client.ListAddons(ctx, &eks.ListAddonsInput{
		ClusterName: &clusterName,
	})
	if err == nil && len(addonsOut.Addons) > 0 {
		var addons []map[string]any
		for _, name := range addonsOut.Addons {
			addon := map[string]any{"addonName": name}
			if detail, err := client.DescribeAddon(ctx, &eks.DescribeAddonInput{
				ClusterName: &clusterName,
				AddonName:   &name,
			}); err == nil && detail.Addon != nil {
				if detail.Addon.AddonVersion != nil {
					addon["addonVersion"] = *detail.Addon.AddonVersion
				}
				addon["status"] = string(detail.Addon.Status)
			}
			addons = append(addons, addon)
		}
		document["_addons"] = addons

		// Set convenience flags
		for _, addon := range addons {
			switch strings.ToLower(stringifyLookup(addon, "addonName")) {
			case "vpc-cni":
				document["_hasVpcCniAddon"] = true
			case "coredns":
				document["_hasCoreDnsAddon"] = true
			case "kube-proxy":
				document["_hasKubeProxyAddon"] = true
			case "eks-pod-identity-agent":
				document["_hasPodIdentityAgent"] = true
			case "amazon-cloudwatch-observability":
				document["_hasCloudWatchObservability"] = true
			}
		}
	}

	// Fetch managed node groups
	ngOut, err := client.ListNodegroups(ctx, &eks.ListNodegroupsInput{
		ClusterName: &clusterName,
	})
	if err == nil && len(ngOut.Nodegroups) > 0 {
		var groups []map[string]any
		for _, name := range ngOut.Nodegroups {
			group := map[string]any{"nodegroupName": name}
			if detail, err := client.DescribeNodegroup(ctx, &eks.DescribeNodegroupInput{
				ClusterName:   &clusterName,
				NodegroupName: &name,
			}); err == nil && detail.Nodegroup != nil {
				group["instanceTypes"] = detail.Nodegroup.InstanceTypes
				if detail.Nodegroup.ScalingConfig != nil {
					group["scalingConfig"] = map[string]any{
						"minSize":     detail.Nodegroup.ScalingConfig.MinSize,
						"maxSize":     detail.Nodegroup.ScalingConfig.MaxSize,
						"desiredSize": detail.Nodegroup.ScalingConfig.DesiredSize,
					}
				}
				group["amiType"] = string(detail.Nodegroup.AmiType)
			}
			groups = append(groups, group)
		}
		document["_nodeGroups"] = groups
	}
}
