package scan

import (
	"strings"
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

func TestNewRiskHandlers(t *testing.T) {
	tests := []struct {
		name     string
		check    checks.Check
		items    []map[string]any
		cache    map[string][]map[string]any
		want     int
		wantText string
	}{
		{
			name:  "sec027 gitrepo volume",
			check: checks.Check{ID: "SEC027", NativeHandler: "SEC027"},
			items: []map[string]any{{
				"metadata": map[string]any{"name": "demo", "namespace": "apps"},
				"spec": map[string]any{"volumes": []any{
					map[string]any{"name": "code", "gitRepo": map[string]any{"repository": "https://example.test/repo.git"}},
				}},
			}},
			cache:    map[string][]map[string]any{},
			want:     1,
			wantText: "repo.git",
		},
		{
			name:  "pod009 unhealthy device",
			check: checks.Check{ID: "POD009", NativeHandler: "POD009"},
			items: []map[string]any{{
				"metadata": map[string]any{"name": "gpu-job", "namespace": "apps"},
				"status": map[string]any{"containerStatuses": []any{
					map[string]any{
						"name": "worker",
						"allocatedResourcesStatus": []any{
							map[string]any{"name": "nvidia.com/gpu", "resources": []any{map[string]any{"health": "Unhealthy"}}},
						},
					},
				}},
			}},
			cache:    map[string][]map[string]any{},
			want:     1,
			wantText: "Unhealthy",
		},
		{
			name:  "pvc005 expansion event",
			check: checks.Check{ID: "PVC005", NativeHandler: "PVC005"},
			items: []map[string]any{{"metadata": map[string]any{"name": "data", "namespace": "apps"}}},
			cache: map[string][]map[string]any{
				"events": {{
					"metadata":       map[string]any{"name": "data-event", "namespace": "apps"},
					"involvedObject": map[string]any{"kind": "PersistentVolumeClaim", "name": "data"},
					"reason":         "VolumeResizeFailed",
					"message":        "resize failed",
				}},
			},
			want:     1,
			wantText: "resize failed",
		},
		{
			name:  "net020 ingress nginx",
			check: checks.Check{ID: "NET020", NativeHandler: "NET020"},
			items: []map[string]any{{}},
			cache: map[string][]map[string]any{
				"deployments": {{
					"metadata": map[string]any{"name": "ingress-nginx-controller", "namespace": "ingress-nginx"},
					"spec":     map[string]any{"containers": []any{map[string]any{"image": "registry.k8s.io/ingress-nginx/controller:v1.12.0"}}},
				}},
				"daemonsets":     {},
				"statefulsets":   {},
				"pods":           {},
				"services":       {},
				"ingressclasses": {},
			},
			want:     1,
			wantText: "Ingress-NGINX",
		},
		{
			name:  "rbac005 nodes proxy",
			check: checks.Check{ID: "RBAC005", NativeHandler: "RBAC005"},
			items: []map[string]any{{}},
			cache: map[string][]map[string]any{
				"clusterroles": {{
					"metadata": map[string]any{"name": "metrics-reader"},
					"rules":    []any{map[string]any{"resources": []any{"nodes/proxy"}, "verbs": []any{"get"}}},
				}},
				"roles":        {},
				"rolebindings": {},
				"clusterrolebindings": {{
					"metadata": map[string]any{"name": "metrics-reader"},
					"roleRef":  map[string]any{"kind": "ClusterRole", "name": "metrics-reader"},
					"subjects": []any{map[string]any{"kind": "ServiceAccount", "name": "reader", "namespace": "apps"}},
				}},
			},
			want:     1,
			wantText: "nodes/proxy",
		},
		{
			name:  "sec028 direct pod image pull secret",
			check: checks.Check{ID: "SEC028", NativeHandler: "SEC028"},
			items: []map[string]any{{}},
			cache: map[string][]map[string]any{
				"pods": {{
					"metadata":         map[string]any{"name": "web", "namespace": "apps"},
					"spec":             map[string]any{"imagePullSecrets": []any{map[string]any{"name": "registry-creds"}}},
					"imagePullSecrets": []any{},
				}},
				"serviceaccounts": {{
					"metadata":         map[string]any{"name": "builder", "namespace": "apps"},
					"imagePullSecrets": []any{map[string]any{"name": "ignored-non-default"}},
				}},
			},
			want:     1,
			wantText: "registry-creds",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			findings, ok, err := executeNativeHandler(tt.check, tt.items, tt.cache)
			if err != nil {
				t.Fatalf("unexpected error: %v", err)
			}
			if !ok {
				t.Fatalf("expected native handler to be registered")
			}
			if len(findings) != tt.want {
				t.Fatalf("expected %d findings, got %d: %#v", tt.want, len(findings), findings)
			}
			if tt.want > 0 && !strings.Contains(findings[0].Value+" "+findings[0].Message, tt.wantText) {
				t.Fatalf("expected finding to contain %q, got %+v", tt.wantText, findings[0])
			}
		})
	}
}

func TestRBACHandlersIgnoreExcludedAndSystemBindings(t *testing.T) {
	setRuntimeContext(runtimeContext{
		Excluded: map[string]struct{}{"kube-system": {}},
	})
	defer clearRuntimeContext()

	clusterRoles := []map[string]any{
		{
			"metadata": map[string]any{"name": "cluster-admin"},
			"rules":    []any{map[string]any{"apiGroups": []any{"*"}, "resources": []any{"*"}, "verbs": []any{"*"}}},
		},
		{
			"metadata": map[string]any{"name": "system:kubelet-api-admin"},
			"rules":    []any{map[string]any{"resources": []any{"nodes/proxy"}, "verbs": []any{"get"}}},
		},
	}
	clusterRoleBindings := []map[string]any{
		{
			"metadata": map[string]any{
				"name": "cluster-admin",
				"labels": map[string]any{
					"kubernetes.io/bootstrapping": "rbac-defaults",
				},
			},
			"roleRef":  map[string]any{"kind": "ClusterRole", "name": "cluster-admin"},
			"subjects": []any{map[string]any{"kind": "Group", "name": "system:masters"}},
		},
		{
			"metadata": map[string]any{"name": "kube-system-proxy"},
			"roleRef":  map[string]any{"kind": "ClusterRole", "name": "system:kubelet-api-admin"},
			"subjects": []any{map[string]any{"kind": "ServiceAccount", "name": "metrics-agent", "namespace": "kube-system"}},
		},
	}
	cache := map[string][]map[string]any{
		"clusterroles":        clusterRoles,
		"roles":               {},
		"rolebindings":        {},
		"clusterrolebindings": clusterRoleBindings,
	}

	rbac002, ok, err := executeNativeHandler(checks.Check{ID: "RBAC002", NativeHandler: "RBAC002"}, []map[string]any{{}}, cache)
	if err != nil {
		t.Fatalf("unexpected RBAC002 error: %v", err)
	}
	if !ok {
		t.Fatalf("expected RBAC002 native handler")
	}
	if len(rbac002) != 0 {
		t.Fatalf("expected system/excluded RBAC002 findings to be ignored, got %#v", rbac002)
	}

	rbac005, ok, err := executeNativeHandler(checks.Check{ID: "RBAC005", NativeHandler: "RBAC005"}, []map[string]any{{}}, cache)
	if err != nil {
		t.Fatalf("unexpected RBAC005 error: %v", err)
	}
	if !ok {
		t.Fatalf("expected RBAC005 native handler")
	}
	if len(rbac005) != 0 {
		t.Fatalf("expected excluded kubelet proxy binding to be ignored, got %#v", rbac005)
	}
}

func TestRBAC001AllowsRoleBindingToExistingClusterRole(t *testing.T) {
	cache := map[string][]map[string]any{
		"rolebindings": {{
			"metadata": map[string]any{"name": "viewers", "namespace": "apps"},
			"roleRef":  map[string]any{"kind": "ClusterRole", "name": "view"},
			"subjects": []any{map[string]any{"kind": "ServiceAccount", "name": "viewer", "namespace": "apps"}},
		}},
		"clusterrolebindings": {},
		"roles":               {},
		"clusterroles": {{
			"metadata": map[string]any{"name": "view"},
			"rules":    []any{map[string]any{"resources": []any{"pods"}, "verbs": []any{"get", "list"}}},
		}},
		"namespaces":      {{"metadata": map[string]any{"name": "apps"}}},
		"serviceaccounts": {{"metadata": map[string]any{"name": "viewer", "namespace": "apps"}}},
	}

	findings, ok, err := executeNativeHandler(checks.Check{ID: "RBAC001", NativeHandler: "RBAC001"}, []map[string]any{{}}, cache)
	if err != nil {
		t.Fatalf("unexpected RBAC001 error: %v", err)
	}
	if !ok {
		t.Fatalf("expected RBAC001 native handler")
	}
	if len(findings) != 0 {
		t.Fatalf("expected valid RoleBinding to ClusterRole to pass, got %#v", findings)
	}
}
