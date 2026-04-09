package scan

import "time"

type runtimeContext struct {
	Thresholds map[string]any
	Prometheus prometheusOptions
	Excluded   map[string]struct{}
	Now        time.Time
}

type prometheusOptions struct {
	Enabled        bool
	URL            string
	Mode           string
	BearerTokenEnv string
}

var currentRuntime runtimeContext

func setRuntimeContext(ctx runtimeContext) {
	if ctx.Now.IsZero() {
		ctx.Now = time.Now().UTC()
	}
	currentRuntime = ctx
}

func clearRuntimeContext() {
	currentRuntime = runtimeContext{}
}
