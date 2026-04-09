package kubernetes

import (
	"encoding/json"
	"testing"
)

func TestListResponseDecoding(t *testing.T) {
	t.Helper()

	data := []byte(`{"items":[{"metadata":{"name":"a"}},{"metadata":{"name":"b"}}]}`)
	var response listResponse
	if err := json.Unmarshal(data, &response); err != nil {
		t.Fatalf("decode list response: %v", err)
	}

	if len(response.Items) != 2 {
		t.Fatalf("expected 2 items, got %d", len(response.Items))
	}
}
