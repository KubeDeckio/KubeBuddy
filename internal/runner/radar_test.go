package runner

import (
	"testing"

	"github.com/KubeDeckio/KubeBuddy/internal/compat"
	"github.com/KubeDeckio/KubeBuddy/internal/config"
)

func TestRadarSettingsMergeConfigAndFlags(t *testing.T) {
	t.Helper()

	cfg := config.Resolved{
		Radar: config.Radar{
			Enabled:              false,
			APIBaseURL:           "https://radar.example.test/api",
			Environment:          "staging",
			APIUserEnv:           "CFG_USER",
			APIPasswordEnv:       "CFG_PASS",
			UploadTimeoutSeconds: 45,
			UploadRetries:        4,
		},
	}

	settings := radarSettings(compat.RunOptions{
		RadarUpload:       true,
		RadarEnvironment:  "prod",
		RadarAPISecretEnv: "FLAG_PASS",
	}, cfg)

	if !settings.Enabled || !settings.UploadEnabled {
		t.Fatalf("expected radar upload to force radar enabled: %#v", settings)
	}
	if settings.APIBaseURL != "https://radar.example.test/api" {
		t.Fatalf("unexpected API base URL: %#v", settings)
	}
	if settings.Environment != "prod" {
		t.Fatalf("expected flag environment override, got %#v", settings)
	}
	if settings.APIUserEnv != "CFG_USER" || settings.APIPasswordEnv != "FLAG_PASS" {
		t.Fatalf("unexpected env resolution: %#v", settings)
	}
	if settings.TimeoutSeconds != 45 || settings.Retries != 4 {
		t.Fatalf("unexpected timeout/retries: %#v", settings)
	}
}
