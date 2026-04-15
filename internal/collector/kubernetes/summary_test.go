package kubernetes

import (
	"encoding/json"
	"testing"
)

func TestListDecoding(t *testing.T) {
	t.Helper()

	data := []byte(`{"items":[{"metadata":{"name":"a"}},{"metadata":{"name":"b"}}]}`)
	var response struct {
		Items []map[string]any `json:"items"`
	}
	if err := json.Unmarshal(data, &response); err != nil {
		t.Fatalf("decode list response: %v", err)
	}

	if len(response.Items) != 2 {
		t.Fatalf("expected 2 items, got %d", len(response.Items))
	}
}
