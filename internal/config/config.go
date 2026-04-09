package config

import (
	"os"
	"path/filepath"
	"strings"

	"gopkg.in/yaml.v3"
)

type File struct {
	Thresholds map[string]any `yaml:"thresholds"`
}

func Thresholds(configPath string) map[string]any {
	out := defaults()
	path := resolveConfigPath(configPath)
	if strings.TrimSpace(path) == "" {
		return out
	}
	data, err := os.ReadFile(path)
	if err != nil {
		return out
	}
	var cfg File
	if err := yaml.Unmarshal(data, &cfg); err != nil {
		return out
	}
	for key, value := range cfg.Thresholds {
		out[key] = value
	}
	return out
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

func defaults() map[string]any {
	return map[string]any{
		"cpu_warning":                       50,
		"cpu_critical":                      75,
		"mem_warning":                       50,
		"mem_critical":                      75,
		"disk_warning":                      60,
		"disk_critical":                     80,
		"restarts_warning":                  3,
		"restarts_critical":                 5,
		"pod_age_warning":                   15,
		"pod_age_critical":                  40,
		"stuck_job_hours":                   2,
		"failed_job_hours":                  2,
		"event_errors_warning":              10,
		"event_errors_critical":             20,
		"event_warnings_warning":            50,
		"event_warnings_critical":           100,
		"pods_per_node_warning":             80,
		"pods_per_node_critical":            90,
		"storage_usage_threshold":           80,
		"node_sizing_downsize_cpu_p95":      35,
		"node_sizing_downsize_mem_p95":      40,
		"node_sizing_upsize_cpu_p95":        80,
		"node_sizing_upsize_mem_p95":        85,
		"pod_sizing_profile":                "balanced",
		"pod_sizing_compare_profiles":       true,
		"pod_sizing_target_cpu_utilization": 65,
		"pod_sizing_target_mem_utilization": 75,
		"pod_sizing_cpu_request_floor_mcores": 25,
		"pod_sizing_mem_request_floor_mib":    128,
		"pod_sizing_mem_limit_buffer_percent": 20,
		"prometheus_timeout_seconds":          60,
		"prometheus_query_retries":            2,
		"prometheus_retry_delay_seconds":      2,
	}
}
