package scan

import (
	"bytes"
	"context"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"os"
	"path/filepath"
	"sort"
	"strconv"
	"strings"
	"time"

	"github.com/KubeDeckio/KubeBuddy/internal/azure"
	"github.com/KubeDeckio/KubeBuddy/internal/checks"
	"github.com/KubeDeckio/KubeBuddy/internal/config"
	"github.com/KubeDeckio/KubeBuddy/internal/kubeapi"
)

type AKSOptions struct {
	ChecksDir      string
	ConfigPath     string
	InputFile      string
	SubscriptionID string
	ResourceGroup  string
	ClusterName    string
	Progress       func(ProgressEvent)
}

func RunAKS(opts AKSOptions) (Result, error) {
	if strings.TrimSpace(opts.ChecksDir) == "" {
		opts.ChecksDir = "checks/aks"
	}
	cfg := config.Load(opts.ConfigPath)

	ruleSet, err := checks.LoadDir(opts.ChecksDir)
	if err != nil {
		return Result{}, err
	}
	ruleSet.Checks = filterExcludedChecks(ruleSet.Checks, cfg.ExcludedChecks)

	document, err := loadAKSDocument(opts)
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
			URL:                        check.URL,
			ResourceKind:               check.ResourceKind,
			AutomaticRelevance:         check.AutomaticRelevance,
			AutomaticScope:             check.AutomaticScope,
			AutomaticReason:            check.AutomaticReason,
			AutomaticAdmissionBehavior: check.AutomaticAdmissionBehavior,
			AutomaticMutationOutcome:   check.AutomaticMutationOutcome,
			FailMessageText:            "",
		}
		aksEval, err := evaluateAKSCheck(check, document, eval)
		if err != nil {
			return Result{}, fmt.Errorf("%s: %w", check.ID, err)
		}
		result.ObservedValue = aksEval.ObservedValue
		result.FailMessageText = aksEval.FailMessage
		if aksEval.Failed {
			result.Items = append(result.Items, Finding{
				Namespace: "(cluster)",
				Resource:  check.Name,
				Value:     aksEval.ObservedValue,
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

type aksEvaluation struct {
	Failed        bool
	ObservedValue string
	FailMessage   string
}

func evaluateAKSCheck(check checks.Check, document map[string]any, eval checks.Evaluation) (aksEvaluation, error) {
	switch check.ID {
	case "AKSBP001":
		ok := aksConstraintEnforced(document, "K8sAzureV2ContainerAllowedImages")
		return aksBoolEval(!ok, ok), nil
	case "AKSBP002":
		ok := aksConstraintEnforced(document, "K8sAzureV2NoPrivilege")
		return aksBoolEval(!ok, ok), nil
	case "AKSBP003":
		ok := len(aksAgentPools(document)) > 1
		return aksBoolEval(!ok, ok), nil
	case "AKSBP007":
		ok := false
		for _, pool := range aksAgentPools(document) {
			if !strings.EqualFold(stringifyLookup(pool, "mode"), "System") {
				continue
			}
			for _, taint := range asSlice(mustResolve(pool, "nodeTaints")) {
				if strings.EqualFold(fmt.Sprint(taint), "CriticalAddonsOnly=true:NoSchedule") {
					ok = true
					break
				}
			}
		}
		return aksBoolEval(!ok, ok), nil
	case "AKSBP008":
		channel := strings.TrimSpace(stringifyLookup(document, "properties.autoUpgradeProfile.upgradeChannel"))
		ok := !strings.EqualFold(channel, "none")
		return aksBoolEval(!ok, ok), nil
	case "AKSBP009":
		channel := strings.TrimSpace(stringifyLookup(document, "properties.autoUpgradeProfile.nodeOSUpgradeChannel"))
		ok := !strings.EqualFold(channel, "none")
		return aksBoolEval(!ok, ok), nil
	case "AKSBP010":
		group := strings.TrimSpace(stringifyLookup(document, "properties.nodeResourceGroup"))
		ok := !strings.HasPrefix(group, "MC_")
		return aksBoolEval(!ok, ok), nil
	case "AKSBP011":
		ok := aksSystemNodeCount(document) >= 2
		return aksBoolEval(!ok, ok), nil
	case "AKSBP012":
		ok := aksNodePoolsMatchControlPlane(document)
		return aksBoolEval(!ok, ok), nil
	case "AKSBP014":
		count := 0
		for _, pool := range aksAgentPools(document) {
			if !aksVMIsV5OrNewer(stringifyLookup(pool, "vmSize")) {
				nodes := int(asInt64(mustResolve(pool, "count")))
				if nodes <= 0 {
					nodes = 1
				}
				count += nodes
			}
		}
		return aksCountEval(count > 0, count), nil
	case "AKSDR002":
		ok := strings.EqualFold(stringifyLookup(document, "sku.tier"), "Standard")
		return aksBoolEval(!ok, ok), nil
	case "AKSNET001":
		ok := aksAuthorizedIPRangesConfigured(document)
		return aksBoolEval(!ok, ok), nil
	case "AKSNET002":
		ok := !strings.EqualFold(stringifyLookup(document, "properties.networkProfile.networkPolicy"), "none")
		return aksBoolEval(!ok, ok), nil
	case "AKSRES001":
		ok := mustResolve(document, "properties.autoScalerProfile") != nil
		return aksBoolEval(!ok, ok), nil
	case "AKSSEC007":
		enabled := aksAddonEnabled(document, "kubeDashboard")
		return aksBoolEval(enabled, enabled), nil
	case "AKSSEC008":
		ok := mustResolve(document, "properties.podSecurityAdmissionConfiguration") != nil
		return aksBoolEval(!ok, ok), nil
	}
	return aksEvaluation{
		Failed:        eval.Failed,
		ObservedValue: flattenValue(eval.Value),
		FailMessage:   "",
	}, nil
}

func aksBoolEval(failed bool, actual bool) aksEvaluation {
	return aksEvaluation{
		Failed:        failed,
		ObservedValue: strconv.FormatBool(actual),
		FailMessage:   "",
	}
}

func aksCountEval(failed bool, actual int) aksEvaluation {
	return aksEvaluation{
		Failed:        failed,
		ObservedValue: strconv.Itoa(actual),
		FailMessage:   "",
	}
}

func aksConstraintEnforced(document map[string]any, kind string) bool {
	for _, item := range asSlice(mustResolve(document, "properties.kubeData.Constraints.items")) {
		if stringifyLookup(item, "kind") != kind {
			continue
		}
		action := stringifyLookup(item, "spec.enforcementAction")
		if strings.EqualFold(action, "deny") {
			return true
		}
		for _, value := range asSlice(mustResolve(item, "spec.enforcementAction")) {
			if strings.EqualFold(fmt.Sprint(value), "deny") {
				return true
			}
		}
	}
	return false
}

func aksAgentPools(document map[string]any) []map[string]any {
	var pools []map[string]any
	for _, item := range asSlice(mustResolve(document, "properties.agentPoolProfiles")) {
		if pool, ok := item.(map[string]any); ok {
			pools = append(pools, pool)
		}
	}
	return pools
}

func aksSystemNodeCount(document map[string]any) int {
	total := 0
	for _, pool := range aksAgentPools(document) {
		if !strings.EqualFold(stringifyLookup(pool, "mode"), "System") {
			continue
		}
		if count := asInt64(mustResolve(pool, "count")); count > 0 {
			total += int(count)
			continue
		}
		if count := asInt64(mustResolve(pool, "minCount")); count > 0 {
			total += int(count)
		}
	}
	return total
}

func aksNodePoolsMatchControlPlane(document map[string]any) bool {
	control := strings.TrimSpace(stringifyLookup(document, "properties.currentKubernetesVersion"))
	if control == "" {
		control = strings.TrimSpace(stringifyLookup(document, "properties.kubernetesVersion"))
	}
	if control == "" {
		return false
	}
	for _, pool := range aksAgentPools(document) {
		if strings.TrimSpace(stringifyLookup(pool, "currentOrchestratorVersion")) != control {
			return false
		}
	}
	return true
}

func aksAuthorizedIPRangesConfigured(document map[string]any) bool {
	if boolFromAny(mustResolve(document, "properties.apiServerAccessProfile.enablePrivateCluster")) {
		return true
	}
	ranges := asSlice(mustResolve(document, "properties.apiServerAccessProfile.authorizedIpRanges"))
	return len(ranges) > 0
}

func aksAddonEnabled(document map[string]any, name string) bool {
	return boolFromAny(mustResolve(document, "properties.addonProfiles."+name+".enabled"))
}

func aksVMIsV5OrNewer(vmSize string) bool {
	vmSize = strings.TrimSpace(vmSize)
	if vmSize == "" {
		return false
	}
	for i := len(vmSize) - 1; i >= 0; i-- {
		if vmSize[i] != 'v' && vmSize[i] != 'V' {
			continue
		}
		major, err := strconv.Atoi(vmSize[i+1:])
		return err == nil && major >= 5
	}
	return false
}

func boolFromAny(value any) bool {
	switch v := value.(type) {
	case bool:
		return v
	case string:
		b, err := strconv.ParseBool(strings.TrimSpace(v))
		return err == nil && b
	default:
		return false
	}
}

func loadAKSDocument(opts AKSOptions) (map[string]any, error) {
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
	if strings.TrimSpace(opts.SubscriptionID) == "" || strings.TrimSpace(opts.ResourceGroup) == "" || strings.TrimSpace(opts.ClusterName) == "" {
		return nil, fmt.Errorf("missing input file or live AKS target (--subscription-id, --resource-group, --cluster-name)")
	}
	return collectLiveAKSDocument(opts)
}

func collectLiveAKSDocument(opts AKSOptions) (map[string]any, error) {
	document, err := collectLiveAKSDocumentWithToken(opts)
	if err != nil {
		return nil, err
	}
	constraints, _ := loadAKSConstraints(opts)
	ensureAKSConstraints(document, constraints)
	return document, nil
}

func collectLiveAKSDocumentWithToken(opts AKSOptions) (map[string]any, error) {
	token, err := azure.ARMToken()
	if err != nil {
		return nil, err
	}
	uri := fmt.Sprintf(
		"https://management.azure.com/subscriptions/%s/resourceGroups/%s/providers/Microsoft.ContainerService/managedClusters/%s?api-version=2025-01-01",
		opts.SubscriptionID,
		opts.ResourceGroup,
		opts.ClusterName,
	)
	req, err := http.NewRequest(http.MethodGet, uri, nil)
	if err != nil {
		return nil, err
	}
	req.Header.Set("Authorization", "Bearer "+token)
	req.Header.Set("Accept", "application/json")
	client := &http.Client{Timeout: 30 * time.Second}
	resp, err := client.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		body, _ := io.ReadAll(resp.Body)
		return nil, fmt.Errorf("ARM cluster GET returned %s: %s", resp.Status, strings.TrimSpace(string(body)))
	}
	var document map[string]any
	if err := json.NewDecoder(resp.Body).Decode(&document); err != nil {
		return nil, err
	}
	return document, nil
}

func loadAKSConstraints(opts AKSOptions) ([]map[string]any, error) {
	if client, err := kubeapi.New(); err == nil {
		constraints, err := client.GatekeeperConstraints(context.Background())
		if err == nil && len(constraints) > 0 {
			return constraints, nil
		}
	}
	tempDir, err := os.MkdirTemp("", "kubebuddy-aks-kubeconfig-*")
	if err != nil {
		return nil, err
	}
	defer os.RemoveAll(tempDir)
	kubeconfig := filepath.Join(tempDir, "config")
	if err := writeClusterUserKubeconfig(opts, kubeconfig); err != nil {
		return nil, err
	}
	token, err := azure.AKSToken()
	if err != nil {
		return nil, err
	}
	client, err := kubeapi.NewFromPathWithBearerToken(kubeconfig, token)
	if err != nil {
		return nil, err
	}
	return client.GatekeeperConstraints(context.Background())
}

func writeClusterUserKubeconfig(opts AKSOptions, path string) error {
	token, err := azure.ARMToken()
	if err != nil {
		return err
	}
	uri := fmt.Sprintf(
		"https://management.azure.com/subscriptions/%s/resourceGroups/%s/providers/Microsoft.ContainerService/managedClusters/%s/listClusterUserCredential?api-version=2025-01-01",
		opts.SubscriptionID,
		opts.ResourceGroup,
		opts.ClusterName,
	)
	req, err := http.NewRequest(http.MethodPost, uri, bytes.NewReader([]byte("{}")))
	if err != nil {
		return err
	}
	req.Header.Set("Authorization", "Bearer "+token)
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Accept", "application/json")
	client := &http.Client{Timeout: 30 * time.Second}
	resp, err := client.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		body, _ := io.ReadAll(resp.Body)
		return fmt.Errorf("listClusterUserCredential returned %s: %s", resp.Status, strings.TrimSpace(string(body)))
	}
	var payload struct {
		Kubeconfigs []struct {
			Name  string `json:"name"`
			Value string `json:"value"`
		} `json:"kubeconfigs"`
	}
	if err := json.NewDecoder(resp.Body).Decode(&payload); err != nil {
		return err
	}
	if len(payload.Kubeconfigs) == 0 || strings.TrimSpace(payload.Kubeconfigs[0].Value) == "" {
		return fmt.Errorf("listClusterUserCredential returned no kubeconfigs")
	}
	decoded, err := decodeBase64String(payload.Kubeconfigs[0].Value)
	if err != nil {
		return err
	}
	return os.WriteFile(path, decoded, 0o600)
}

func decodeBase64String(value string) ([]byte, error) {
	value = strings.TrimSpace(value)
	return base64.StdEncoding.DecodeString(value)
}

func ensureAKSConstraints(document map[string]any, constraints []map[string]any) {
	properties, ok := document["properties"].(map[string]any)
	if !ok {
		properties = map[string]any{}
		document["properties"] = properties
	}
	kubeData, ok := properties["kubeData"].(map[string]any)
	if !ok {
		kubeData = map[string]any{}
		properties["kubeData"] = kubeData
	}
	kubeData["Constraints"] = map[string]any{
		"items": constraints,
	}
}

func clusterName(document map[string]any) string {
	if name, ok := document["name"].(string); ok && name != "" {
		return name
	}
	return "unknown"
}
