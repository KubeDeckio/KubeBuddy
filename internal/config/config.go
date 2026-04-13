package config

import (
	"fmt"
	"os"
	"path/filepath"
	"slices"
	"strings"

	"gopkg.in/yaml.v3"
)

type File struct {
	Thresholds         map[string]any `yaml:"thresholds"`
	ExcludedNamespaces []string       `yaml:"excluded_namespaces"`
	ExcludedChecks     []string       `yaml:"excluded_checks"`
	TrustedRegistries  []string       `yaml:"trusted_registries"`
	Radar              *RadarFile     `yaml:"radar"`
}

type RadarFile struct {
	Enabled              *bool   `yaml:"enabled"`
	APIBaseURL           *string `yaml:"api_base_url"`
	Environment          *string `yaml:"environment"`
	APIUser              *string `yaml:"api_user"`
	APIPassword          *string `yaml:"api_password"`
	APIUserEnv           *string `yaml:"api_user_env"`
	APIPasswordEnv       *string `yaml:"api_password_env"`
	UploadTimeoutSeconds *int    `yaml:"upload_timeout_seconds"`
	UploadRetries        *int    `yaml:"upload_retries"`
}

type Radar struct {
	Enabled              bool
	APIBaseURL           string
	Environment          string
	APIUser              string
	APIPassword          string
	APIUserEnv           string
	APIPasswordEnv       string
	UploadTimeoutSeconds int
	UploadRetries        int
}

type Resolved struct {
	Thresholds         map[string]any
	ExcludedNamespaces []string
	ExcludedChecks     []string
	TrustedRegistries  []string
	Radar              Radar
}

func Load(configPath string) Resolved {
	resolved := Resolved{
		Thresholds:         defaults(),
		ExcludedNamespaces: DefaultExcludedNamespaces(),
		ExcludedChecks:     []string{},
		TrustedRegistries:  DefaultTrustedRegistries(),
		Radar:              defaultRadar(),
	}

	path := resolveConfigPath(configPath)
	if strings.TrimSpace(path) == "" {
		return resolved
	}

	data, err := os.ReadFile(path)
	if err != nil {
		return resolved
	}

	var cfg File
	if err := yaml.Unmarshal(data, &cfg); err != nil {
		return resolved
	}

	resolved.Thresholds = mergeThresholds(cfg.Thresholds)
	if cfg.ExcludedNamespaces != nil {
		resolved.ExcludedNamespaces = normalizeNames(cfg.ExcludedNamespaces)
	}
	if cfg.ExcludedChecks != nil {
		resolved.ExcludedChecks = normalizeCheckIDs(cfg.ExcludedChecks)
	}
	if cfg.TrustedRegistries != nil {
		resolved.TrustedRegistries = normalizeRegistries(cfg.TrustedRegistries)
	}
	if cfg.Radar != nil {
		resolved.Radar = mergeRadar(cfg.Radar)
	}

	return resolved
}

func Thresholds(configPath string) map[string]any {
	return Load(configPath).Thresholds
}

func DefaultExcludedNamespaces() []string {
	return []string{
		"kube-system", "kube-public", "kube-node-lease",
		"local-path-storage", "kube-flannel",
		"tigera-operator", "calico-system", "coredns", "aks-istio-system", "gatekeeper-system",
	}
}

func DefaultTrustedRegistries() []string {
	return []string{"mcr.microsoft.com/"}
}

func resolveConfigPath(configPath string) string {
	if strings.TrimSpace(configPath) != "" {
		return configPath
	}
	if env := strings.TrimSpace(os.Getenv("KUBEBUDDY_CONFIG")); env != "" {
		return env
	}
	home, err := os.UserHomeDir()
	if err != nil {
		return ""
	}
	return filepath.Join(home, ".kube", "kubebuddy-config.yaml")
}

func mergeThresholds(overrides map[string]any) map[string]any {
	out := defaults()
	profile := normalizeProfile("")
	if overrides != nil {
		if raw, ok := overrides["pod_sizing_profile"]; ok {
			profile = normalizeProfile(strings.TrimSpace(strings.ToLower(toString(raw))))
		}
	}
	applyProfileDefaults(out, profile)
	for key, value := range overrides {
		out[key] = value
	}
	out["pod_sizing_profile"] = profile
	return out
}

func defaults() map[string]any {
	return map[string]any{
		"cpu_warning":                         50,
		"cpu_critical":                        75,
		"mem_warning":                         50,
		"mem_critical":                        75,
		"disk_warning":                        60,
		"disk_critical":                       80,
		"restarts_warning":                    3,
		"restarts_critical":                   5,
		"pod_age_warning":                     15,
		"pod_age_critical":                    40,
		"stuck_job_hours":                     2,
		"failed_job_hours":                    2,
		"event_errors_warning":                10,
		"event_errors_critical":               20,
		"event_warnings_warning":              50,
		"event_warnings_critical":             100,
		"pods_per_node_warning":               80,
		"pods_per_node_critical":              90,
		"storage_usage_threshold":             80,
		"node_sizing_downsize_cpu_p95":        35,
		"node_sizing_downsize_mem_p95":        40,
		"node_sizing_upsize_cpu_p95":          80,
		"node_sizing_upsize_mem_p95":          85,
		"pod_sizing_profile":                  "balanced",
		"pod_sizing_compare_profiles":         true,
		"pod_sizing_target_cpu_utilization":   65,
		"pod_sizing_target_mem_utilization":   75,
		"pod_sizing_cpu_request_floor_mcores": 25,
		"pod_sizing_mem_request_floor_mib":    128,
		"pod_sizing_mem_limit_buffer_percent": 20,
		"prometheus_timeout_seconds":          60,
		"prometheus_query_retries":            2,
		"prometheus_retry_delay_seconds":      2,
	}
}

func normalizeProfile(value string) string {
	switch strings.TrimSpace(strings.ToLower(value)) {
	case "conservative", "aggressive":
		return value
	default:
		return "balanced"
	}
}

func applyProfileDefaults(out map[string]any, profile string) {
	switch profile {
	case "conservative":
		out["pod_sizing_target_cpu_utilization"] = 55
		out["pod_sizing_target_mem_utilization"] = 65
		out["pod_sizing_cpu_request_floor_mcores"] = 100
		out["pod_sizing_mem_request_floor_mib"] = 256
		out["pod_sizing_mem_limit_buffer_percent"] = 25
	case "aggressive":
		out["pod_sizing_target_cpu_utilization"] = 75
		out["pod_sizing_target_mem_utilization"] = 85
		out["pod_sizing_cpu_request_floor_mcores"] = 10
		out["pod_sizing_mem_request_floor_mib"] = 64
		out["pod_sizing_mem_limit_buffer_percent"] = 15
	default:
		out["pod_sizing_target_cpu_utilization"] = 65
		out["pod_sizing_target_mem_utilization"] = 75
		out["pod_sizing_cpu_request_floor_mcores"] = 25
		out["pod_sizing_mem_request_floor_mib"] = 128
		out["pod_sizing_mem_limit_buffer_percent"] = 20
	}
}

func defaultRadar() Radar {
	return Radar{
		Enabled:              false,
		APIBaseURL:           "https://radar.kubebuddy.io/api/kb-radar/v1",
		Environment:          "prod",
		APIUser:              "",
		APIPassword:          "",
		APIUserEnv:           "KUBEBUDDY_RADAR_API_USER",
		APIPasswordEnv:       "KUBEBUDDY_RADAR_API_PASSWORD",
		UploadTimeoutSeconds: 30,
		UploadRetries:        2,
	}
}

func mergeRadar(file *RadarFile) Radar {
	out := defaultRadar()
	if file.Enabled != nil {
		out.Enabled = *file.Enabled
	}
	if file.APIBaseURL != nil {
		out.APIBaseURL = strings.TrimSpace(*file.APIBaseURL)
	}
	if file.Environment != nil {
		out.Environment = strings.TrimSpace(*file.Environment)
	}
	if file.APIUser != nil {
		out.APIUser = strings.TrimSpace(*file.APIUser)
	}
	if file.APIPassword != nil {
		out.APIPassword = strings.TrimSpace(*file.APIPassword)
	}
	if file.APIUserEnv != nil {
		out.APIUserEnv = strings.TrimSpace(*file.APIUserEnv)
	}
	if file.APIPasswordEnv != nil {
		out.APIPasswordEnv = strings.TrimSpace(*file.APIPasswordEnv)
	}
	if file.UploadTimeoutSeconds != nil {
		out.UploadTimeoutSeconds = *file.UploadTimeoutSeconds
	}
	if file.UploadRetries != nil {
		out.UploadRetries = *file.UploadRetries
	}
	return out
}

func normalizeNames(values []string) []string {
	return uniqueTrimmed(values, false)
}

func normalizeCheckIDs(values []string) []string {
	out := make([]string, 0, len(values))
	for _, value := range values {
		trimmed := strings.ToUpper(strings.TrimSpace(value))
		if trimmed != "" {
			out = append(out, trimmed)
		}
	}
	return dedupe(out)
}

func normalizeRegistries(values []string) []string {
	return uniqueTrimmed(values, true)
}

func uniqueTrimmed(values []string, preserveCase bool) []string {
	out := make([]string, 0, len(values))
	for _, value := range values {
		trimmed := strings.TrimSpace(value)
		if trimmed == "" {
			continue
		}
		if !preserveCase {
			trimmed = strings.ToLower(trimmed)
		}
		out = append(out, trimmed)
	}
	return dedupe(out)
}

func dedupe(values []string) []string {
	out := make([]string, 0, len(values))
	for _, value := range values {
		if slices.Contains(out, value) {
			continue
		}
		out = append(out, value)
	}
	return out
}

func toString(value any) string {
	switch typed := value.(type) {
	case string:
		return typed
	default:
		return fmt.Sprint(value)
	}
}
