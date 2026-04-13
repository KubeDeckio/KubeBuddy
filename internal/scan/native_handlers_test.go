package scan

import (
	"testing"

	"github.com/KubeDeckio/KubeBuddy/internal/checks"
)

func TestExecuteNativeHandlerSEC003(t *testing.T) {
	t.Helper()

	check := checks.Check{ID: "SEC003", NativeHandler: "SEC003"}
	pod := map[string]any{
		"metadata": map[string]any{
			"name":      "demo",
			"namespace": "default",
		},
		"spec": map[string]any{
			"containers": []any{
				map[string]any{"name": "web"},
				map[string]any{
					"name": "sidecar",
					"securityContext": map[string]any{
						"runAsUser": float64(1000),
					},
				},
			},
		},
	}

	findings, ok, err := executeNativeHandler(check, []map[string]any{pod}, map[string][]map[string]any{})
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if !ok {
		t.Fatalf("expected native handler to be registered")
	}
	if len(findings) != 3 {
		t.Fatalf("expected 3 findings, got %d", len(findings))
	}
	if findings[0].Value != "Not Set (Defaults to root)" {
		t.Fatalf("unexpected value: %+v", findings[0])
	}
}

func TestExecuteNativeHandlerSEC004(t *testing.T) {
	t.Helper()

	check := checks.Check{ID: "SEC004", NativeHandler: "SEC004"}
	pod := map[string]any{
		"metadata": map[string]any{
			"name":      "demo",
			"namespace": "default",
		},
		"spec": map[string]any{
			"containers": []any{
				map[string]any{
					"name": "privileged",
					"securityContext": map[string]any{
						"privileged": true,
					},
				},
				map[string]any{"name": "normal"},
			},
		},
	}

	findings, ok, err := executeNativeHandler(check, []map[string]any{pod}, map[string][]map[string]any{})
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if !ok {
		t.Fatalf("expected native handler to be registered")
	}
	if len(findings) != 1 {
		t.Fatalf("expected 1 finding, got %d", len(findings))
	}
	if findings[0].Value != "privileged=true" {
		t.Fatalf("unexpected finding: %+v", findings[0])
	}
}

func TestExecuteNativeHandlerSEC010(t *testing.T) {
	t.Helper()

	check := checks.Check{ID: "SEC010", NativeHandler: "SEC010"}
	pod := map[string]any{
		"metadata": map[string]any{
			"name":      "demo",
			"namespace": "default",
		},
		"spec": map[string]any{
			"volumes": []any{
				map[string]any{
					"name": "host",
					"hostPath": map[string]any{
						"path": "/var/run",
					},
				},
				map[string]any{"name": "config"},
			},
		},
	}

	findings, ok, err := executeNativeHandler(check, []map[string]any{pod}, map[string][]map[string]any{})
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if !ok {
		t.Fatalf("expected native handler to be registered")
	}
	if len(findings) != 1 {
		t.Fatalf("expected 1 finding, got %d", len(findings))
	}
	if findings[0].Value != "/var/run" {
		t.Fatalf("unexpected finding: %+v", findings[0])
	}
}

func TestRunSEC014UsesConfiguredTrustedRegistries(t *testing.T) {
	t.Helper()

	setRuntimeContext(runtimeContext{
		TrustedRegistries: []string{"ghcr.io/approved/", "mcr.microsoft.com/"},
	})
	defer clearRuntimeContext()

	check := checks.Check{ID: "SEC014", NativeHandler: "SEC014"}
	pod := map[string]any{
		"metadata": map[string]any{
			"name":      "demo",
			"namespace": "default",
		},
		"spec": map[string]any{
			"containers": []any{
				map[string]any{"name": "good", "image": "ghcr.io/approved/app:v1"},
				map[string]any{"name": "bad", "image": "docker.io/library/nginx:latest"},
			},
		},
	}

	findings, ok, err := executeNativeHandler(check, []map[string]any{pod}, map[string][]map[string]any{})
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if !ok {
		t.Fatalf("expected native handler to be registered")
	}
	if len(findings) != 1 {
		t.Fatalf("expected 1 finding, got %d", len(findings))
	}
	if findings[0].Value != "docker.io/library/nginx:latest" {
		t.Fatalf("unexpected finding: %+v", findings[0])
	}
}
