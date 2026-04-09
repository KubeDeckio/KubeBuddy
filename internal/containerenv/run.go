package containerenv

import (
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"

	"github.com/KubeDeckio/KubeBuddy/internal/compat"
	"github.com/KubeDeckio/KubeBuddy/internal/runner"
)

func Run() error {
	opts, err := Load()
	if err != nil {
		return err
	}

	if err := prepareKubeconfig(); err != nil {
		return err
	}

	if opts.AKS {
		if err := prepareAKSLogin(); err != nil {
			return err
		}
	}

	return runner.Execute(opts)
}

func Load() (compat.RunOptions, error) {
	opts := compat.RunOptions{
		ClusterName:                  os.Getenv("CLUSTER_NAME"),
		ResourceGroup:                os.Getenv("RESOURCE_GROUP"),
		SubscriptionID:               os.Getenv("SUBSCRIPTION_ID"),
		ExcludeNamespaces:            envBool("EXCLUDE_NAMESPACES"),
		HTMLReport:                   envBool("HTML_REPORT"),
		CSVReport:                    envBool("CSV_REPORT"),
		TxtReport:                    envBool("TXT_REPORT"),
		JSONReport:                   envBool("JSON_REPORT"),
		AKS:                          envBool("AKS_MODE"),
		UseAKSRestAPI:                envBool("USE_AKS_REST_API"),
		ConfigPath:                   os.Getenv("KUBEBUDDY_CONFIG_PATH"),
		RadarUpload:                  envBool("RADAR_UPLOAD"),
		RadarCompare:                 envBool("RADAR_COMPARE"),
		RadarFetchConfig:             envBool("RADAR_FETCH_CONFIG"),
		RadarConfigID:                os.Getenv("RADAR_CONFIG_ID"),
		RadarAPIBaseURL:              os.Getenv("RADAR_API_BASE_URL"),
		RadarEnvironment:             os.Getenv("RADAR_ENVIRONMENT"),
		RadarAPIUserEnv:              os.Getenv("RADAR_API_USER_ENV"),
		RadarAPISecretEnv:            os.Getenv("RADAR_API_PASSWORD_ENV"),
		IncludePrometheus:            envBool("INCLUDE_PROMETHEUS"),
		PrometheusURL:                os.Getenv("PROMETHEUS_URL"),
		PrometheusMode:               os.Getenv("PROMETHEUS_MODE"),
		PrometheusBearerTokenEnv:     os.Getenv("PROMETHEUS_BEARER_TOKEN_ENV"),
		AdditionalExcludedNamespaces: splitCSVEnv("ADDITIONAL_EXCLUDED_NAMESPACES"),
		OutputPath:                   "/app/Reports",
		Yes:                          true,
	}

	if !(opts.HTMLReport || opts.CSVReport || opts.TxtReport || opts.JSONReport) {
		return compat.RunOptions{}, fmt.Errorf("you must enable at least one report format: HTML_REPORT, CSV_REPORT, TXT_REPORT, or JSON_REPORT")
	}
	if (opts.RadarUpload || opts.RadarCompare) && !opts.JSONReport {
		return compat.RunOptions{}, fmt.Errorf("RADAR_UPLOAD/RADAR_COMPARE requires JSON_REPORT=true in container mode")
	}
	if os.Getenv("KUBECONFIG") == "" {
		return compat.RunOptions{}, fmt.Errorf("KUBECONFIG environment variable not set")
	}
	if opts.AKS && (opts.ClusterName == "" || opts.ResourceGroup == "" || opts.SubscriptionID == "") {
		return compat.RunOptions{}, fmt.Errorf("AKS mode is enabled but missing: CLUSTER_NAME, RESOURCE_GROUP or SUBSCRIPTION_ID")
	}

	return opts, nil
}

func prepareKubeconfig() error {
	kubeConfigPath := os.Getenv("KUBECONFIG")
	originalPath := "/tmp/kubeconfig-original"

	if _, err := os.Stat(originalPath); err != nil {
		return fmt.Errorf("original kubeconfig not found at %s", originalPath)
	}

	if err := os.MkdirAll(filepath.Dir(kubeConfigPath), 0o755); err != nil {
		return err
	}

	data, err := os.ReadFile(originalPath)
	if err != nil {
		return err
	}

	return os.WriteFile(kubeConfigPath, data, 0o600)
}

func prepareAKSLogin() error {
	clientID := os.Getenv("AZURE_CLIENT_ID")
	clientSecret := os.Getenv("AZURE_CLIENT_SECRET")
	tenantID := os.Getenv("AZURE_TENANT_ID")
	if clientID == "" || clientSecret == "" || tenantID == "" {
		return fmt.Errorf("AKS mode is enabled but missing SPN credentials: AZURE_CLIENT_ID, AZURE_CLIENT_SECRET, AZURE_TENANT_ID")
	}

	cmd := exec.Command("kubelogin", "convert-kubeconfig", "-l", "spn", "--client-id", clientID, "--client-secret", clientSecret, "--tenant-id", tenantID)
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr
	return cmd.Run()
}

func envBool(name string) bool {
	return strings.EqualFold(strings.TrimSpace(os.Getenv(name)), "true")
}

func splitCSVEnv(name string) []string {
	raw := strings.TrimSpace(os.Getenv(name))
	if raw == "" {
		return nil
	}
	parts := strings.Split(raw, ",")
	var out []string
	for _, part := range parts {
		part = strings.TrimSpace(part)
		if part != "" {
			out = append(out, part)
		}
	}
	return out
}
