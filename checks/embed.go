package checkcatalog

import "embed"

// FS contains the built-in check catalog used when external check files are not present.
//
//go:embed aks/*.yaml gke/*.yaml kubernetes/*.yaml
var FS embed.FS
