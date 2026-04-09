package compat

import (
	"strings"
	"testing"
)

func TestBuildArgs(t *testing.T) {
	t.Helper()

	args := BuildArgs("/tmp/KubeBuddy.psm1", RunOptions{
		JSONReport:       true,
		Yes:              true,
		OutputPath:       "/tmp/out",
		AKS:              true,
		ClusterName:      "demo",
		ResourceGroup:    "rg",
		SubscriptionID:   "sub",
		RadarFetchConfig: true,
	})

	command := strings.Join(args, " ")
	for _, expected := range []string{
		"Import-Module '/tmp/KubeBuddy.psm1' -Force",
		"$params.jsonReport = $true",
		"$params.yes = $true",
		"$params.Aks = $true",
		"$params.outputpath = '/tmp/out'",
		"$params.ClusterName = 'demo'",
		"$params.ResourceGroup = 'rg'",
		"$params.SubscriptionId = 'sub'",
		"$params.RadarFetchConfig = $true",
		"Invoke-KubeBuddy @params",
	} {
		if !strings.Contains(command, expected) {
			t.Fatalf("expected command to contain %q, got %s", expected, command)
		}
	}
}
