package scan

import (
	"context"
	"time"

	"github.com/KubeDeckio/KubeBuddy/internal/kubeapi"
)

type runtimeContext struct {
	Thresholds        map[string]any
	Prometheus        prometheusOptions
	Excluded          map[string]struct{}
	TrustedRegistries []string
	Now               time.Time
	KubeClient        *kubeapi.Client
	KubeContext       context.Context
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
