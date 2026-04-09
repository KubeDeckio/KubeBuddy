package version

var (
	// These values are set at build time via -ldflags.
	Version = "dev"
	Commit  = "unknown"
	Date    = "unknown"
)
