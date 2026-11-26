package ai

import (
	"encoding/json"
	"io"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

// setAIEnv clears every variable NewFromEnv reads, then sets a test key and
// the given model override ("" means unset).
func setAIEnv(t *testing.T, model string) {
	t.Helper()
	t.Setenv("OpenAIKey", "")
	t.Setenv("OPENAI_API_KEY", "test-key")
	t.Setenv("OPENAI_BASE_URL", "")
	t.Setenv("KUBEBUDDY_OPENAI_MODEL", model)
}

// newResponsesServer returns a stub Responses API that replies with body and
// decodes each request into got.
func newResponsesServer(t *testing.T, body string, got *map[string]any) *httptest.Server {
	t.Helper()
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if err := json.NewDecoder(r.Body).Decode(got); err != nil {
			t.Errorf("decode request body: %v", err)
		}
		w.Header().Set("Content-Type", "application/json")
		_, _ = io.WriteString(w, body)
	}))
	t.Cleanup(srv.Close)
	return srv
}

const completedResponse = `{"status":"completed","output":[{"type":"message","content":[{"type":"output_text","text":"{\"text\":\"Set resource limits.\",\"html\":\"<ul><li>Set resource limits.</li></ul>\"}"}]}]}`

func TestNewFromEnvUsesDefaultModel(t *testing.T) {
	setAIEnv(t, "")

	c := NewFromEnv()
	if c == nil {
		t.Fatalf("expected a client when OPENAI_API_KEY is set")
	}
	if c.model != "gpt-6.1-terra" {
		t.Fatalf("expected default model %q, got %q", "gpt-6.1-terra", c.model)
	}
	if c.reasoningEffort != defaultReasoningEffort {
		t.Fatalf("expected default reasoning effort %q, got %q", defaultReasoningEffort, c.reasoningEffort)
	}
}

func TestNewFromEnvHonorsModelOverride(t *testing.T) {
	setAIEnv(t, "  gpt-5.6-luna  ")

	c := NewFromEnv()
	if c == nil {
		t.Fatalf("expected a client when OPENAI_API_KEY is set")
	}
	if c.model != "gpt-5.6-luna" {
		t.Fatalf("expected KUBEBUDDY_OPENAI_MODEL override %q, got %q", "gpt-5.6-luna", c.model)
	}
	if c.reasoningEffort != "" {
		t.Fatalf("expected no reasoning effort for a custom model, got %q", c.reasoningEffort)
	}
}

func TestRecommendSendsDefaultModelSettings(t *testing.T) {
	var got map[string]any
	srv := newResponsesServer(t, completedResponse, &got)
	setAIEnv(t, "")
	t.Setenv("OPENAI_BASE_URL", srv.URL)

	rec, err := NewFromEnv().Recommend("POD001", "Pod resources", "Pods without limits", []string{"default/web"})
	if err != nil {
		t.Fatalf("expected a recommendation, got error: %v", err)
	}
	if rec.HTML != "<ul><li>Set resource limits.</li></ul>" || rec.Text != "Set resource limits." {
		t.Fatalf("unexpected recommendation: %#v", rec)
	}
	if got["model"] != defaultModel {
		t.Fatalf("expected model %q in request, got %v", defaultModel, got["model"])
	}
	if got["max_output_tokens"] != float64(maxOutputTokens) {
		t.Fatalf("expected max_output_tokens %d in request, got %v", maxOutputTokens, got["max_output_tokens"])
	}
	reasoning, ok := got["reasoning"].(map[string]any)
	if !ok || reasoning["effort"] != defaultReasoningEffort {
		t.Fatalf("expected reasoning effort %q in request, got %v", defaultReasoningEffort, got["reasoning"])
	}
}

func TestRecommendOmitsReasoningForModelOverride(t *testing.T) {
	var got map[string]any
	srv := newResponsesServer(t, completedResponse, &got)
	setAIEnv(t, "gpt-4.1")
	t.Setenv("OPENAI_BASE_URL", srv.URL)

	if _, err := NewFromEnv().Recommend("POD001", "Pod resources", "Pods without limits", nil); err != nil {
		t.Fatalf("expected a recommendation, got error: %v", err)
	}
	if got["model"] != "gpt-4.1" {
		t.Fatalf("expected model %q in request, got %v", "gpt-4.1", got["model"])
	}
	if _, ok := got["reasoning"]; ok {
		t.Fatalf("expected no reasoning field for a custom model, got %v", got["reasoning"])
	}
}

func TestRecommendReportsResponseCutOffByOutputLimit(t *testing.T) {
	var got map[string]any
	truncated := `{"status":"incomplete","incomplete_details":{"reason":"max_output_tokens"},"output":[{"type":"message","content":[{"type":"output_text","text":"{\"text\":\"Set resource"}]}]}`
	srv := newResponsesServer(t, truncated, &got)
	setAIEnv(t, "")
	t.Setenv("OPENAI_BASE_URL", srv.URL)

	_, err := NewFromEnv().Recommend("POD001", "Pod resources", "Pods without limits", nil)
	if err == nil || !strings.Contains(err.Error(), "incomplete ai response (max_output_tokens)") {
		t.Fatalf("expected an incomplete-response error naming max_output_tokens, got %v", err)
	}
}
