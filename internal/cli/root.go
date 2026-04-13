package cli

import (
	"fmt"
	"strings"

	"github.com/KubeDeckio/KubeBuddy/internal/checks"
	"github.com/KubeDeckio/KubeBuddy/internal/collector/kubernetes"
	"github.com/KubeDeckio/KubeBuddy/internal/compat"
	"github.com/KubeDeckio/KubeBuddy/internal/containerenv"
	"github.com/KubeDeckio/KubeBuddy/internal/probe"
	reportassets "github.com/KubeDeckio/KubeBuddy/internal/reports/assets"
	"github.com/KubeDeckio/KubeBuddy/internal/reports/output"
	"github.com/KubeDeckio/KubeBuddy/internal/runner"
	"github.com/KubeDeckio/KubeBuddy/internal/scan"
	"github.com/KubeDeckio/KubeBuddy/internal/version"
	"github.com/spf13/cobra"
)

type options struct {
	ui bool
}

func NewRootCommand() *cobra.Command {
	opts := &options{}

	cmd := &cobra.Command{
		Use:   "kubebuddy",
		Short: "KubeBuddy scans Kubernetes and AKS clusters without changing them",
		Long: strings.TrimSpace(`
KubeBuddy scans Kubernetes and AKS clusters from your terminal, generates
HTML/JSON/CSV/text output, and preserves the existing report theme and
behavior while the native runtime continues to replace the legacy module path.`),
		SilenceUsage:  true,
		SilenceErrors: true,
		PersistentPreRun: func(cmd *cobra.Command, args []string) {
			if opts.ui {
				return
			}
			switch cmd.Name() {
			case "version", "assets":
				return
			}
			printBanner(cmd)
		},
		RunE: func(cmd *cobra.Command, args []string) error {
			return cmd.Help()
		},
	}

	cmd.Version = version.Version
	cmd.SetVersionTemplate("kubebuddy {{.Version}}\n")
	cmd.Flags().BoolVar(&opts.ui, "ui", false, "Suppress the banner for UI integrations.")

	cmd.AddCommand(newVersionCommand())
	cmd.AddCommand(newAssetsCommand())
	cmd.AddCommand(newChecksCommand())
	cmd.AddCommand(newProbeCommand())
	cmd.AddCommand(newSummaryCommand())
	cmd.AddCommand(newScanCommand())
	cmd.AddCommand(newAKSScanCommand())
	cmd.AddCommand(newRunCommand())
	cmd.AddCommand(newRunEnvCommand())

	return cmd
}

func printBanner(cmd *cobra.Command) {
	const (
		cyan    = "\x1b[36m"
		magenta = "\x1b[35m"
		gray    = "\x1b[90m"
		reset   = "\x1b[0m"
	)
	banner := strings.Join([]string{
		"██╗  ██╗██╗   ██║██████╗ ███████╗██████╗ ██╗   ██╗██████╗ ██████╗ ██╗   ██╗",
		"██║ ██╔╝██║   ██║██╔══██╗██╔════╝██╔══██╗██║   ██║██╔══██╗██╔══██╗╚██╗ ██╔╝",
		"█████╔╝ ██║   ██║██████╔╝█████╗  ██████╔╝██║   ██║██║  ██║██║  ██║ ╚████╔╝ ",
		"██╔═██╗ ██║   ██║██╔══██╗██╔══╝  ██╔══██╗██║   ██║██║  ██║██║  ██║  ╚██╔╝  ",
		"██║  ██╗╚██████╔╝██████╔╝███████╗██████╔╝╚██████╔╝██████╔╝██████╔╝   ██║   ",
		"╚═╝  ╚═╝ ╚═════╝ ╚═════╝ ╚══════╝╚═════╝  ╚═════╝ ╚═════╝ ╚═════╝    ╚═╝   ",
	}, "\n")
	fmt.Fprintln(cmd.OutOrStdout())
	fmt.Fprint(cmd.OutOrStdout(), cyan+banner+reset)
	fmt.Fprintln(cmd.OutOrStdout(), " "+magenta+version.Version+reset)
	fmt.Fprintln(cmd.OutOrStdout(), gray+"-------------------------------------------------------------"+reset)
	fmt.Fprintln(cmd.OutOrStdout(), cyan+"Your Kubernetes Assistant"+reset)
	fmt.Fprintln(cmd.OutOrStdout(), gray+"-------------------------------------------------------------"+reset)
	fmt.Fprintln(cmd.OutOrStdout())
}

func newVersionCommand() *cobra.Command {
	return &cobra.Command{
		Use:   "version",
		Short: "Print the KubeBuddy version",
		Run: func(cmd *cobra.Command, args []string) {
			fmt.Fprintf(cmd.OutOrStdout(), "version: %s\ncommit: %s\ndate: %s\n", version.Version, version.Commit, version.Date)
		},
	}
}

func newAssetsCommand() *cobra.Command {
	return &cobra.Command{
		Use:   "assets",
		Short: "Inspect embedded report asset compatibility",
		Run: func(cmd *cobra.Command, args []string) {
			fmt.Fprintf(cmd.OutOrStdout(), "report-styles.css bytes: %d\n", len(reportassets.ReportStyles))
			fmt.Fprintf(cmd.OutOrStdout(), "report-scripts.js bytes: %d\n", len(reportassets.ReportScripts))
		},
	}
}

func newChecksCommand() *cobra.Command {
	var checksDir string
	cmd := &cobra.Command{
		Use:   "checks",
		Short: "Inspect the current check catalog",
		RunE: func(cmd *cobra.Command, args []string) error {
			if strings.TrimSpace(checksDir) == "" {
				checksDir = "checks/kubernetes"
			}
			ruleSet, err := checks.LoadCatalog(checksDir)
			if err != nil {
				return err
			}

			inv := checks.Summarize(ruleSet)
			fmt.Fprintf(cmd.OutOrStdout(), "total: %d\n", inv.Total)
			fmt.Fprintf(cmd.OutOrStdout(), "declarative: %d\n", inv.Declarative)
			fmt.Fprintf(cmd.OutOrStdout(), "prometheus: %d\n", inv.Prometheus)
			fmt.Fprintf(cmd.OutOrStdout(), "legacy_scripted: %d\n", inv.LegacyScripted)
			return nil
		},
	}
	cmd.Flags().StringVar(&checksDir, "checks-dir", "checks/kubernetes", "Directory containing check YAML files.")
	return cmd
}

func newProbeCommand() *cobra.Command {
	return &cobra.Command{
		Use:   "probe",
		Short: "Verify Kubernetes cluster connectivity from the native CLI",
		RunE: func(cmd *cobra.Command, args []string) error {
			result, err := probe.Run()
			if err != nil {
				return err
			}

			fmt.Fprintln(cmd.OutOrStdout(), probe.Format(result))
			return nil
		},
	}
}

func newSummaryCommand() *cobra.Command {
	return &cobra.Command{
		Use:   "summary",
		Short: "Collect a basic native cluster summary",
		RunE: func(cmd *cobra.Command, args []string) error {
			summary, err := kubernetes.CollectSummary()
			if err != nil {
				return err
			}

			fmt.Fprintf(cmd.OutOrStdout(), "context: %s\n", summary.Context)
			fmt.Fprintf(cmd.OutOrStdout(), "nodes: %d\n", summary.Nodes)
			fmt.Fprintf(cmd.OutOrStdout(), "namespaces: %d\n", summary.Namespaces)
			fmt.Fprintf(cmd.OutOrStdout(), "pods: %d\n", summary.Pods)
			fmt.Fprintf(cmd.OutOrStdout(), "deployments: %d\n", summary.Deployments)
			fmt.Fprintf(cmd.OutOrStdout(), "statefulsets: %d\n", summary.StatefulSets)
			fmt.Fprintf(cmd.OutOrStdout(), "daemonsets: %d\n", summary.DaemonSets)
			fmt.Fprintf(cmd.OutOrStdout(), "services: %d\n", summary.Services)
			fmt.Fprintf(cmd.OutOrStdout(), "ingresses: %d\n", summary.Ingresses)
			return nil
		},
	}
}

func newScanCommand() *cobra.Command {
	opts := scan.Options{}
	var outputMode string
	cmd := &cobra.Command{
		Use:   "scan",
		Short: "Run KubeBuddy checks against the current cluster",
		RunE: func(cmd *cobra.Command, args []string) error {
			result, err := scan.Run(opts)
			if err != nil {
				return err
			}
			return output.WriteScanResultWithMetadata(cmd.OutOrStdout(), result, output.Mode(outputMode), output.Metadata{
				PrometheusURL:            opts.PrometheusURL,
				PrometheusMode:           opts.PrometheusMode,
				PrometheusBearerTokenEnv: opts.PrometheusBearerTokenEnv,
			})
		},
	}
	cmd.Flags().StringVar(&opts.ChecksDir, "checks-dir", "checks/kubernetes", "Directory containing check YAML files.")
	cmd.Flags().StringVar(&opts.ConfigPath, "config-path", "", "KubeBuddy config file path.")
	cmd.Flags().BoolVar(&opts.ExcludeNamespaces, "exclude-namespaces", false, "Exclude configured namespaces.")
	cmd.Flags().StringSliceVar(&opts.ExcludedNamespaces, "additional-excluded-namespaces", nil, "Additional namespaces to exclude.")
	cmd.Flags().BoolVar(&opts.IncludePrometheus, "include-prometheus", false, "Include Prometheus data in the native scan.")
	cmd.Flags().StringVar(&opts.PrometheusURL, "prometheus-url", "", "Prometheus URL.")
	cmd.Flags().StringVar(&opts.PrometheusMode, "prometheus-mode", "", "Prometheus auth mode.")
	cmd.Flags().StringVar(&opts.PrometheusBearerTokenEnv, "prometheus-bearer-token-env", "", "Environment variable containing the bearer token.")
	cmd.Flags().StringVar(&outputMode, "output", "text", "Output format: text, json, csv, or html.")
	return cmd
}

func newAKSScanCommand() *cobra.Command {
	opts := scan.AKSOptions{}
	var outputMode string
	cmd := &cobra.Command{
		Use:   "scan-aks",
		Short: "Run native AKS YAML checks against an AKS JSON document or live AKS cluster",
		RunE: func(cmd *cobra.Command, args []string) error {
			result, err := scan.RunAKS(opts)
			if err != nil {
				return err
			}
			return output.WriteScanResultWithMetadata(cmd.OutOrStdout(), result, output.Mode(outputMode), output.Metadata{
				ClusterName: opts.ClusterName,
				AKS: &output.AKSMetadata{
					SubscriptionID: opts.SubscriptionID,
					ResourceGroup:  opts.ResourceGroup,
					ClusterName:    opts.ClusterName,
				},
			})
		},
	}
	cmd.Flags().StringVar(&opts.ChecksDir, "checks-dir", "checks/aks", "Directory containing AKS check YAML files.")
	cmd.Flags().StringVar(&opts.InputFile, "input", "", "Path to an AKS cluster JSON document.")
	cmd.Flags().StringVar(&opts.SubscriptionID, "subscription-id", "", "AKS subscription ID for live collection.")
	cmd.Flags().StringVar(&opts.ResourceGroup, "resource-group", "", "AKS resource group for live collection.")
	cmd.Flags().StringVar(&opts.ClusterName, "cluster-name", "", "AKS cluster name for live collection.")
	cmd.Flags().StringVar(&outputMode, "output", "text", "Output format: text, json, csv, or html.")
	return cmd
}

func newRunCommand() *cobra.Command {
	opts := compat.RunOptions{}
	cmd := &cobra.Command{
		Use:   "run",
		Short: "Run the native KubeBuddy report workflow",
		RunE: func(cmd *cobra.Command, args []string) error {
			return runner.Execute(opts)
		},
	}

	cmd.Flags().BoolVar(&opts.HTMLReport, "html-report", false, "Generate the HTML report.")
	cmd.Flags().BoolVar(&opts.TxtReport, "txt-report", false, "Generate the text report.")
	cmd.Flags().BoolVar(&opts.JSONReport, "json-report", false, "Generate the JSON report.")
	cmd.Flags().BoolVar(&opts.CSVReport, "csv-report", false, "Generate the CSV report.")
	cmd.Flags().BoolVar(&opts.AKS, "aks", false, "Enable AKS mode.")
	cmd.Flags().BoolVar(&opts.ExcludeNamespaces, "exclude-namespaces", false, "Exclude configured namespaces.")
	cmd.Flags().StringSliceVar(&opts.AdditionalExcludedNamespaces, "additional-excluded-namespaces", nil, "Additional namespaces to exclude.")
	cmd.Flags().BoolVar(&opts.Yes, "yes", false, "Skip interactive confirmation prompts.")
	cmd.Flags().StringVar(&opts.SubscriptionID, "subscription-id", "", "AKS subscription ID.")
	cmd.Flags().StringVar(&opts.ResourceGroup, "resource-group", "", "AKS resource group.")
	cmd.Flags().StringVar(&opts.ClusterName, "cluster-name", "", "AKS cluster name.")
	cmd.Flags().StringVar(&opts.OutputPath, "outputpath", "", "Report output path.")
	cmd.Flags().StringVar(&opts.OutputPath, "output-path", "", "Report output path.")
	cmd.Flags().BoolVar(&opts.UseAKSRestAPI, "use-aks-rest-api", false, "Use the AKS REST API path.")
	cmd.Flags().StringVar(&opts.ConfigPath, "config-path", "", "KubeBuddy config file path.")
	cmd.Flags().BoolVar(&opts.IncludePrometheus, "include-prometheus", false, "Include Prometheus data.")
	cmd.Flags().StringVar(&opts.PrometheusURL, "prometheus-url", "", "Prometheus URL.")
	cmd.Flags().StringVar(&opts.PrometheusMode, "prometheus-mode", "", "Prometheus auth mode.")
	cmd.Flags().StringVar(&opts.PrometheusBearerTokenEnv, "prometheus-bearer-token-env", "", "Environment variable containing the bearer token.")
	cmd.Flags().BoolVar(&opts.RadarUpload, "radar-upload", false, "Upload the JSON scan to Radar.")
	cmd.Flags().BoolVar(&opts.RadarCompare, "radar-compare", false, "Compare the uploaded run in Radar.")
	cmd.Flags().BoolVar(&opts.RadarFetchConfig, "radar-fetch-config", false, "Fetch cluster config from Radar before running.")
	cmd.Flags().StringVar(&opts.RadarConfigID, "radar-config-id", "", "Radar cluster config ID.")
	cmd.Flags().StringVar(&opts.RadarAPIBaseURL, "radar-api-base-url", "", "Radar API base URL.")
	cmd.Flags().StringVar(&opts.RadarEnvironment, "radar-environment", "", "Radar environment name.")
	cmd.Flags().StringVar(&opts.RadarAPIUserEnv, "radar-api-user-env", "", "Environment variable containing the Radar API user.")
	cmd.Flags().StringVar(&opts.RadarAPISecretEnv, "radar-api-secret-env", "", "Environment variable containing the Radar API secret.")

	return cmd
}

func newRunEnvCommand() *cobra.Command {
	return &cobra.Command{
		Use:   "run-env",
		Short: "Run the container-style env-driven workflow from the native CLI",
		RunE: func(cmd *cobra.Command, args []string) error {
			return containerenv.Run()
		},
	}
}
