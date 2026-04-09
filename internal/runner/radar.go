package runner

import (
	"encoding/json"
	"fmt"
	"os"
	"strings"

	"github.com/KubeDeckio/KubeBuddy/internal/compat"
	"github.com/KubeDeckio/KubeBuddy/internal/radar"
	"github.com/KubeDeckio/KubeBuddy/internal/scan"
)

func radarSettings(opts compat.RunOptions) radar.Settings {
	return radar.Settings{
		Enabled:            opts.RadarUpload || opts.RadarCompare || opts.RadarFetchConfig,
		UploadEnabled:      opts.RadarUpload,
		CompareEnabled:     opts.RadarCompare,
		FetchConfigEnabled: opts.RadarFetchConfig,
		ConfigID:           opts.RadarConfigID,
		APIBaseURL:         firstNonEmpty(opts.RadarAPIBaseURL, "https://radar.kubebuddy.io/api/kb-radar/v1"),
		Environment:        firstNonEmpty(opts.RadarEnvironment, "prod"),
		APIUserEnv:         firstNonEmpty(opts.RadarAPIUserEnv, "KUBEBUDDY_RADAR_API_USER"),
		APIPasswordEnv:     firstNonEmpty(opts.RadarAPISecretEnv, "KUBEBUDDY_RADAR_API_PASSWORD"),
		TimeoutSeconds:     30,
		Retries:            2,
	}
}

func maybeFetchRadarConfig(opts *compat.RunOptions) (func(), error) {
	settings := radarSettings(*opts)
	if !settings.FetchConfigEnabled {
		return func() {}, nil
	}
	fmt.Printf("[Radar] fetching cluster config %s from %s\n", settings.ConfigID, settings.APIBaseURL)
	client, err := radar.New(settings)
	if err != nil {
		return nil, err
	}
	data, err := client.FetchConfigFile(settings.ConfigID)
	if err != nil {
		return nil, err
	}
	f, err := os.CreateTemp("", "kubebuddy-radar-config-*.yaml")
	if err != nil {
		return nil, err
	}
	if _, err := f.Write(data); err != nil {
		f.Close()
		return nil, err
	}
	f.Close()
	opts.ConfigPath = f.Name()
	fmt.Printf("[Radar] config saved to %s\n", f.Name())
	return func() { _ = os.Remove(f.Name()) }, nil
}

func maybeUploadRadarReport(opts compat.RunOptions, jsonReportPath string, result scan.Result) error {
	settings := radarSettings(opts)
	if !settings.UploadEnabled {
		return nil
	}
	fmt.Printf("[Radar] uploading JSON report %s\n", jsonReportPath)
	client, err := radar.New(settings)
	if err != nil {
		return err
	}
	reportPayload := map[string]any{}
	if strings.TrimSpace(jsonReportPath) != "" {
		if data, err := os.ReadFile(jsonReportPath); err == nil {
			if err := json.Unmarshal(data, &reportPayload); err != nil {
				fmt.Printf("[Radar] failed to parse JSON report, falling back to in-memory payload: %v\n", err)
			}
		}
	}
	if len(reportPayload) == 0 {
		reportPayload = map[string]any{
			"checks": result.Checks,
		}
		if result.AutomaticReadiness != nil {
			reportPayload["aksAutomaticReadiness"] = result.AutomaticReadiness
		}
	}
	payload := map[string]any{
		"source":         "kubebuddy-cli",
		"source_version": "go-native",
		"environment":    settings.Environment,
		"cluster": map[string]any{
			"name": opts.ClusterName,
			"provider": func() string {
				if opts.AKS || opts.UseAKSRestAPI {
					return "aks"
				}
				return "kubernetes"
			}(),
		},
		"run": map[string]any{
			"started_at":       "",
			"finished_at":      "",
			"duration_seconds": 0,
		},
		"report": reportPayload,
	}
	resp, err := client.UploadReport(payload)
	if err != nil {
		return err
	}
	fmt.Printf("[Radar] upload complete\n")
	if settings.CompareEnabled {
		runID := stringify(resp["run_id"])
		fmt.Printf("[Radar] comparing run %s\n", runID)
		_, _ = client.Compare(runID)
		fmt.Printf("[Radar] compare complete\n")
	}
	_ = jsonReportPath
	return nil
}

func stringify(value any) string {
	switch v := value.(type) {
	case string:
		return v
	default:
		data, _ := json.Marshal(v)
		return string(data)
	}
}

func firstNonEmpty(values ...string) string {
	for _, value := range values {
		if value != "" {
			return value
		}
	}
	return ""
}
