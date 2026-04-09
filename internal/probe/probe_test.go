package probe

import "testing"

func TestCountNonEmptyLines(t *testing.T) {
	t.Helper()

	got := countNonEmptyLines("a\n\nb\n")
	if got != 2 {
		t.Fatalf("expected 2 non-empty lines, got %d", got)
	}
}

func TestParseNamespaces(t *testing.T) {
	t.Helper()

	got := parseNamespaces("namespace/default\nnamespace/kube-system\n")
	if len(got) != 2 || got[0] != "default" || got[1] != "kube-system" {
		t.Fatalf("unexpected namespaces: %#v", got)
	}
}
