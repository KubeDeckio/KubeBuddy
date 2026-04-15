package compat

import (
	"fmt"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
)

type RunOptions struct {
	HTMLReport                   bool
	TxtReport                    bool
	JSONReport                   bool
	CSVReport                    bool
	AKS                          bool
	ExcludeNamespaces            bool
	AdditionalExcludedNamespaces []string
	Yes                          bool
	SubscriptionID               string
	ResourceGroup                string
	ClusterName                  string
	OutputPath                   string
	UseAKSRestAPI                bool
	ConfigPath                   string
	IncludePrometheus            bool
	PrometheusURL                string
	PrometheusMode               string
	PrometheusBearerTokenEnv     string
	RadarUpload                  bool
	RadarCompare                 bool
	RadarFetchConfig             bool
	RadarConfigID                string
	RadarAPIBaseURL              string
	RadarEnvironment             string
	RadarAPIUserEnv              string
	RadarAPISecretEnv            string
}

func Run(options RunOptions) error {
	return runWithIO(options, os.Stdout, os.Stderr, os.Stdin)
}

func runWithIO(options RunOptions, stdout io.Writer, stderr io.Writer, stdin io.Reader) error {
	wd, err := os.Getwd()
	if err != nil {
		return err
	}
	modulePath := filepath.Join(wd, "KubeBuddy.psm1")
	args := BuildArgs(modulePath, options)

	cmd := exec.Command("pwsh", args...)
	cmd.Stdout = stdout
	cmd.Stderr = stderr
	cmd.Stdin = stdin
	return cmd.Run()
}

func BuildArgs(modulePath string, options RunOptions) []string {
	script := []string{
		"$ErrorActionPreference='Stop'",
		fmt.Sprintf("Import-Module '%s' -Force", escapeSingleQuotes(modulePath)),
		"$params = @{}",
	}

	addBool := func(name string, enabled bool) {
		if enabled {
			script = append(script, fmt.Sprintf("$params.%s = $true", name))
		}
	}
	addString := func(name, value string) {
		if strings.TrimSpace(value) != "" {
			script = append(script, fmt.Sprintf("$params.%s = '%s'", name, escapeSingleQuotes(value)))
		}
	}
	addStringSlice := func(name string, values []string) {
		if len(values) == 0 {
			return
		}
		quoted := make([]string, 0, len(values))
		for _, value := range values {
			if strings.TrimSpace(value) == "" {
				continue
			}
			quoted = append(quoted, fmt.Sprintf("'%s'", escapeSingleQuotes(value)))
		}
		if len(quoted) == 0 {
			return
		}
		script = append(script, fmt.Sprintf("$params.%s = @(%s)", name, strings.Join(quoted, ",")))
	}

	addBool("HtmlReport", options.HTMLReport)
	addBool("txtReport", options.TxtReport)
	addBool("jsonReport", options.JSONReport)
	addBool("CsvReport", options.CSVReport)
	addBool("Aks", options.AKS)
	addBool("ExcludeNamespaces", options.ExcludeNamespaces)
	addBool("yes", options.Yes)
	addBool("UseAksRestApi", options.UseAKSRestAPI)
	addBool("IncludePrometheus", options.IncludePrometheus)
	addBool("RadarUpload", options.RadarUpload)
	addBool("RadarCompare", options.RadarCompare)
	addBool("RadarFetchConfig", options.RadarFetchConfig)

	addStringSlice("AdditionalExcludedNamespaces", options.AdditionalExcludedNamespaces)
	addString("SubscriptionId", options.SubscriptionID)
	addString("ResourceGroup", options.ResourceGroup)
	addString("ClusterName", options.ClusterName)
	addString("outputpath", options.OutputPath)
	addString("ConfigPath", options.ConfigPath)
	addString("PrometheusUrl", options.PrometheusURL)
	addString("PrometheusMode", options.PrometheusMode)
	addString("PrometheusBearerTokenEnv", options.PrometheusBearerTokenEnv)
	addString("RadarConfigId", options.RadarConfigID)
	addString("RadarApiBaseUrl", options.RadarAPIBaseURL)
	addString("RadarEnvironment", options.RadarEnvironment)
	addString("RadarApiUserEnv", options.RadarAPIUserEnv)
	addString("RadarApiSecretEnv", options.RadarAPISecretEnv)

	script = append(script, "Invoke-KubeBuddy @params")

	return []string{"-NoProfile", "-Command", strings.Join(script, "; ")}
}

func escapeSingleQuotes(value string) string {
	return strings.ReplaceAll(value, "'", "''")
}
