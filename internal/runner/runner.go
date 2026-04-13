package runner

import (
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"sort"
	"strings"
	"time"

	"github.com/KubeDeckio/KubeBuddy/internal/collector/kubernetes"
	"github.com/KubeDeckio/KubeBuddy/internal/compat"
	"github.com/KubeDeckio/KubeBuddy/internal/config"
	reporthtml "github.com/KubeDeckio/KubeBuddy/internal/reports/html"
	"github.com/KubeDeckio/KubeBuddy/internal/reports/output"
	"github.com/KubeDeckio/KubeBuddy/internal/scan"
)

const (
	colorReset   = "\x1b[0m"
	colorCyan    = "\x1b[36m"
	colorYellow  = "\x1b[33m"
	colorGreen   = "\x1b[32m"
	colorMagenta = "\x1b[35m"
	colorGray    = "\x1b[90m"
)

func Execute(opts compat.RunOptions) error {
	if !(opts.HTMLReport || opts.TxtReport || opts.JSONReport || opts.CSVReport) {
		return fmt.Errorf("you must enable at least one report format")
	}
	printPhase("Starting", "Preparing native KubeBuddy run")
	cfg := config.Load(opts.ConfigPath)
	cleanup, err := maybeFetchRadarConfig(&opts)
	if err != nil {
		return err
	}
	defer cleanup()
	if opts.ConfigPath != "" {
		cfg = config.Load(opts.ConfigPath)
	}
	effectiveExcluded := effectiveExcludedNamespaces(opts.ExcludeNamespaces, cfg.ExcludedNamespaces, opts.AdditionalExcludedNamespaces)

	result := scan.Result{}
	var snapshot *kubernetes.ClusterData
	clusterReachable := kubernetesReachable()
	if clusterReachable {
		printPhase("Collector", "Building native cluster snapshot")
		collected, err := kubernetes.CollectClusterData(kubernetes.ClusterDataOptions{
			ExcludeNamespaces:        opts.ExcludeNamespaces,
			ExcludedNamespaces:       effectiveExcluded,
			IncludePrometheus:        opts.IncludePrometheus,
			PrometheusURL:            opts.PrometheusURL,
			PrometheusMode:           opts.PrometheusMode,
			PrometheusBearerTokenEnv: opts.PrometheusBearerTokenEnv,
		})
		if err != nil {
			fmt.Printf("%s[Collector]%s Snapshot skipped: %v\n", colorGray, colorReset, err)
		} else {
			snapshot = &collected
			if collected.Metrics != nil {
				fmt.Printf("%s[Collector]%s Metrics snapshot ready for %d nodes\n", colorGreen, colorReset, len(collected.Metrics.Nodes))
			} else {
				fmt.Printf("%s[Collector]%s Snapshot ready\n", colorGreen, colorReset)
			}
		}
	}
	if !(opts.AKS || opts.UseAKSRestAPI) || clusterReachable {
		printPhase("Kubernetes", "Running Kubernetes checks")
		if opts.IncludePrometheus && opts.PrometheusURL != "" {
			fmt.Printf("[Prometheus] enabled via %s (%s)\n", opts.PrometheusURL, firstNonEmpty(opts.PrometheusMode, "default"))
		}
		start := time.Now()
		var err error
		result, err = scan.Run(scan.Options{
			ChecksDir:                "checks/kubernetes",
			ConfigPath:               opts.ConfigPath,
			ExcludeNamespaces:        opts.ExcludeNamespaces,
			ExcludedNamespaces:       opts.AdditionalExcludedNamespaces,
			IncludePrometheus:        opts.IncludePrometheus,
			PrometheusURL:            opts.PrometheusURL,
			PrometheusMode:           opts.PrometheusMode,
			PrometheusBearerTokenEnv: opts.PrometheusBearerTokenEnv,
			Progress:                 logCheckProgress("Kubernetes"),
		})
		if err != nil {
			if !(opts.AKS || opts.UseAKSRestAPI) {
				return err
			}
			fmt.Printf("%s[Kubernetes]%s skipped: %v\n", colorGray, colorReset, err)
			result = scan.Result{}
		} else {
			fmt.Printf("%s[Kubernetes]%s Completed %d checks with %d findings in %s\n", colorGreen, colorReset, len(result.Checks), findingsCount(result), time.Since(start).Round(time.Second))
		}
	} else {
		fmt.Printf("%s[Kubernetes]%s Skipped: cluster API unreachable, continuing with AKS-only flow\n", colorGray, colorReset)
	}
	if opts.AKS || opts.UseAKSRestAPI {
		printPhase("AKS", "Running AKS checks")
		start := time.Now()
		aksResult, err := scan.RunAKS(scan.AKSOptions{
			ChecksDir:      "checks/aks",
			ConfigPath:     opts.ConfigPath,
			SubscriptionID: opts.SubscriptionID,
			ResourceGroup:  opts.ResourceGroup,
			ClusterName:    opts.ClusterName,
			Progress:       logCheckProgress("AKS"),
		})
		if err != nil {
			return err
		}
		result.Checks = append(result.Checks, aksResult.Checks...)
		sort.Slice(result.Checks, func(i, j int) bool { return result.Checks[i].ID < result.Checks[j].ID })
		result.AutomaticReadiness = scan.BuildAutomaticReadiness(opts.ClusterName, result)
		fmt.Printf("%s[AKS]%s Completed %d checks with %d findings in %s\n", colorGreen, colorReset, len(aksResult.Checks), findingsCount(aksResult), time.Since(start).Round(time.Second))
		if result.AutomaticReadiness != nil {
			fmt.Printf("%s[AKS]%s Automatic readiness: %s (%d blockers, %d warnings)\n", colorMagenta, colorReset, result.AutomaticReadiness.Summary.StatusLabel, result.AutomaticReadiness.Summary.BlockerCount, result.AutomaticReadiness.Summary.WarningCount)
		}
	}
	if len(result.Checks) == 0 {
		return fmt.Errorf("no checks executed")
	}
	printPhase("AI", "Checking AI enrichment")
	if enrichWithAI(&result) == 0 {
		fmt.Printf("%s[AI]%s Skipped or no failing checks enriched\n", colorGray, colorReset)
	}

	outputPath := opts.OutputPath
	if outputPath == "" {
		outputPath = filepath.Join(".", "reports")
	}
	if err := os.MkdirAll(outputPath, 0o755); err != nil {
		return err
	}
	printPhase("Reports", "Writing report files")

	timestamp := time.Now().UTC().Format("20060102-150405")
	base := filepath.Join(outputPath, "kubebuddy-report-"+timestamp)
	jsonReportPath := ""
	actionPlanPath := ""
	metadata := output.Metadata{
		ClusterName:              opts.ClusterName,
		ExcludeNamespacesEnabled: opts.ExcludeNamespaces,
		ExcludedNamespaces:       append([]string(nil), effectiveExcluded...),
		PrometheusURL:            opts.PrometheusURL,
		PrometheusMode:           opts.PrometheusMode,
		PrometheusBearerTokenEnv: opts.PrometheusBearerTokenEnv,
	}
	if snapshot != nil {
		metadata.Snapshot = snapshot
		if snapshot.Metrics != nil {
			metadata.Metrics = snapshot.Metrics
		}
	}
	if opts.AKS || opts.UseAKSRestAPI {
		metadata.AKS = &output.AKSMetadata{
			SubscriptionID: opts.SubscriptionID,
			ResourceGroup:  opts.ResourceGroup,
			ClusterName:    opts.ClusterName,
		}
		if result.AutomaticReadiness != nil && len(result.AutomaticReadiness.ActionPlan) > 0 {
			actionPlanPath = base + "-aks-automatic-action-plan.html"
			result.AutomaticReadiness.Summary.ActionPlanPath = actionPlanPath
		}
	}

	if opts.HTMLReport {
		fmt.Printf("%s[Reports]%s Writing %s\n", colorCyan, colorReset, base+".html")
		if err := writeFile(base+".html", result, output.ModeHTML, metadata); err != nil {
			return err
		}
		if actionPlanPath != "" {
			fmt.Printf("%s[Reports]%s Writing %s\n", colorCyan, colorReset, actionPlanPath)
			if err := writeAutomaticActionPlanFile(actionPlanPath, opts.ClusterName, result); err != nil {
				return err
			}
		}
	}
	if opts.TxtReport {
		fmt.Printf("%s[Reports]%s Writing %s\n", colorCyan, colorReset, base+".txt")
		if err := writeFile(base+".txt", result, output.ModeText, metadata); err != nil {
			return err
		}
	}
	if opts.JSONReport {
		jsonReportPath = base + ".json"
		fmt.Printf("%s[Reports]%s Writing %s\n", colorCyan, colorReset, jsonReportPath)
		if err := writeFile(jsonReportPath, result, output.ModeJSON, metadata); err != nil {
			return err
		}
	}
	if opts.CSVReport {
		fmt.Printf("%s[Reports]%s Writing %s\n", colorCyan, colorReset, base+".csv")
		if err := writeFile(base+".csv", result, output.ModeCSV, metadata); err != nil {
			return err
		}
	}
	if jsonReportPath != "" {
		if err := maybeUploadRadarReport(opts, jsonReportPath, result); err != nil {
			return err
		}
	}

	fmt.Printf("%s[Reports]%s Reports written to %s\n", colorGreen, colorReset, outputPath)
	return nil
}

func effectiveExcludedNamespaces(enabled bool, configured []string, extra []string) []string {
	if !enabled {
		return nil
	}
	set := scanExcludedNamespaceSet(configured, extra)
	out := make([]string, 0, len(set))
	for ns := range set {
		out = append(out, ns)
	}
	sort.Strings(out)
	return out
}

func scanExcludedNamespaceSet(configured []string, extra []string) map[string]struct{} {
	out := map[string]struct{}{}
	for _, ns := range append(append([]string{}, configured...), extra...) {
		trimmed := strings.ToLower(strings.TrimSpace(ns))
		if trimmed != "" {
			out[trimmed] = struct{}{}
		}
	}
	return out
}

func printPhase(name string, message string) {
	fmt.Printf("%s[%s]%s %s\n", colorCyan, name, colorReset, message)
}

func kubernetesReachable() bool {
	cmd := exec.Command("kubectl", "version", "--request-timeout=8s")
	if err := cmd.Run(); err != nil {
		return false
	}
	return true
}

func findingsCount(result scan.Result) int {
	total := 0
	for _, check := range result.Checks {
		total += check.Total
	}
	return total
}

func logCheckProgress(scope string) func(scan.ProgressEvent) {
	return func(event scan.ProgressEvent) {
		switch event.Stage {
		case "start":
			fmt.Printf("%s[%s]%s [%03d/%03d] Checking %s - %s\n", colorCyan, scope, colorReset, event.Index, event.Total, event.CheckID, event.CheckName)
		case "result":
			if event.Findings > 0 {
				fmt.Printf("%s[%s]%s [%03d/%03d] Checked %s - %s %s(%d findings)%s\n", colorGreen, scope, colorReset, event.Index, event.Total, event.CheckID, event.CheckName, colorYellow, event.Findings, colorReset)
				return
			}
			fmt.Printf("%s[%s]%s [%03d/%03d] Checked %s - %s\n", colorGreen, scope, colorReset, event.Index, event.Total, event.CheckID, event.CheckName)
		}
	}
}

func writeFile(path string, result scan.Result, mode output.Mode, metadata output.Metadata) error {
	f, err := os.Create(path)
	if err != nil {
		return err
	}
	defer f.Close()
	return output.WriteScanResultWithMetadata(f, result, mode, metadata)
}

func writeAutomaticActionPlanFile(path string, clusterName string, result scan.Result) error {
	if result.AutomaticReadiness == nil {
		return nil
	}
	htmlDoc, err := (reporthtml.ActionPlanRenderer{}).Render(clusterName, result.AutomaticReadiness)
	if err != nil {
		return err
	}
	return os.WriteFile(path, []byte(htmlDoc), 0o644)
}
