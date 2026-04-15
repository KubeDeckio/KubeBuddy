package compat

import (
	"bytes"
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"strings"
)

type ReportKind string

const (
	ReportHTML ReportKind = "html"
	ReportText ReportKind = "txt"
	ReportJSON ReportKind = "json"
	ReportCSV  ReportKind = "csv"
)

func RunCapture(options RunOptions, kind ReportKind) ([]byte, error) {
	tempDir, err := os.MkdirTemp("", "kubebuddy-compat-*")
	if err != nil {
		return nil, err
	}
	defer os.RemoveAll(tempDir)

	options.OutputPath = tempDir
	options.Yes = true
	enableReport(&options, kind)

	var stdout bytes.Buffer
	var stderr bytes.Buffer
	if err := runWithIO(options, &stdout, &stderr, nil); err != nil {
		if stderr.Len() > 0 {
			return nil, fmt.Errorf("%w: %s", err, strings.TrimSpace(stderr.String()))
		}
		return nil, err
	}

	reportPath, err := findGeneratedReport(tempDir, kind)
	if err != nil {
		return nil, err
	}

	return os.ReadFile(reportPath)
}

func enableReport(options *RunOptions, kind ReportKind) {
	options.HTMLReport = false
	options.TxtReport = false
	options.JSONReport = false
	options.CSVReport = false

	switch kind {
	case ReportHTML:
		options.HTMLReport = true
	case ReportText:
		options.TxtReport = true
	case ReportJSON:
		options.JSONReport = true
	case ReportCSV:
		options.CSVReport = true
	}
}

func findGeneratedReport(dir string, kind ReportKind) (string, error) {
	pattern := filepath.Join(dir, fmt.Sprintf("kubebuddy-report-*.%s", kind))
	matches, err := filepath.Glob(pattern)
	if err != nil {
		return "", err
	}

	filtered := matches[:0]
	for _, match := range matches {
		base := filepath.Base(match)
		if strings.Contains(base, "aks-automatic-action-plan") {
			continue
		}
		filtered = append(filtered, match)
	}
	sort.Strings(filtered)
	if len(filtered) == 0 {
		return "", fmt.Errorf("no %s report generated in %s", kind, dir)
	}
	return filtered[len(filtered)-1], nil
}
