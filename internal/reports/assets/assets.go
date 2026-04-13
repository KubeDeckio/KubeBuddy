package assets

import _ "embed"

var (
	//go:embed report-styles.css
	ReportStyles string

	//go:embed report-scripts.js
	ReportScripts string
)
