package probe

import "testing"

func TestParseNamespaces(t *testing.T) {
	t.Helper()

	got := parseNamespaces([]map[string]any{
		{"metadata": map[string]any{"name": "default"}},
		{"metadata": map[string]any{"name": "kube-system"}},
	})
	if len(got) != 2 || got[0] != "default" || got[1] != "kube-system" {
		t.Fatalf("unexpected namespaces: %#v", got)
	}
}
