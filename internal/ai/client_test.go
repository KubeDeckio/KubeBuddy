package ai

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

func clearAIEnv(t *testing.T) {
	t.Helper()
	for _, key := range []string{
		"AI_PROVIDER",
		"KUBEBUDDY_AI_PROVIDER",
		"AI_API_KEY",
		"AI_BASE_URL",
		"AI_MODEL",
		"OpenAIKey",
		"OPENAI_API_KEY",
		"OPENAI_BASE_URL",
		"KUBEBUDDY_OPENAI_MODEL",
		"AZURE_OPENAI_ENDPOINT",
		"AZURE_OPENAI_BASE_URL",
		"AZURE_OPENAI_API_KEY",
		"AZURE_OPENAI_AUTH_TOKEN",
		"AZURE_OPENAI_DEPLOYMENT",
		"KUBEBUDDY_AZURE_OPENAI_DEPLOYMENT",
		"FOUNDRY_API_KEY",
		"FOUNDRY_BASE_URL",
		"FOUNDRY_ENDPOINT",
		"FOUNDRY_MODEL",
		"AZURE_AI_FOUNDRY_API_KEY",
		"AZURE_AI_FOUNDRY_BASE_URL",
		"AZURE_AI_FOUNDRY_ENDPOINT",
		"AZURE_AI_FOUNDRY_MODEL",
		"GEMINI_API_KEY",
		"GEMINI_BASE_URL",
		"GEMINI_MODEL",
		"GOOGLE_API_KEY",
		"ANTHROPIC_API_KEY",
		"ANTHROPIC_BASE_URL",
		"ANTHROPIC_MODEL",
		"CLAUDE_API_KEY",
		"CLAUDE_BASE_URL",
		"CLAUDE_MODEL",
	} {
		t.Setenv(key, "")
	}
}

func TestConfigFromEnvUsesAzureOpenAIAPIKey(t *testing.T) {
	clearAIEnv(t)
	t.Setenv("AZURE_OPENAI_ENDPOINT", "https://example.openai.azure.com")
	t.Setenv("AZURE_OPENAI_API_KEY", "azure-key")
	t.Setenv("AZURE_OPENAI_DEPLOYMENT", "kb-deployment")
	t.Setenv("OpenAIKey", "openai-key")

	cfg := configFromEnv()
	if cfg.provider != "azure-openai" {
		t.Fatalf("unexpected provider: %s", cfg.provider)
	}
	if cfg.baseURL != "https://example.openai.azure.com/openai/v1/" {
		t.Fatalf("unexpected baseURL: %s", cfg.baseURL)
	}
	if cfg.model != "kb-deployment" {
		t.Fatalf("unexpected model: %s", cfg.model)
	}
	if cfg.apiKey != "azure-key" {
		t.Fatalf("unexpected api key: %s", cfg.apiKey)
	}
}

func TestConfigFromEnvUsesFoundryAlias(t *testing.T) {
	clearAIEnv(t)
	t.Setenv("AI_PROVIDER", "ms-foundry")
	t.Setenv("FOUNDRY_ENDPOINT", "https://example.services.ai.azure.com")
	t.Setenv("FOUNDRY_API_KEY", "foundry-key")
	t.Setenv("FOUNDRY_MODEL", "MAI-DS-R1")

	cfg := configFromEnv()
	if cfg.provider != "foundry" {
		t.Fatalf("unexpected provider: %s", cfg.provider)
	}
	if cfg.baseURL != "https://example.services.ai.azure.com/openai/v1/" {
		t.Fatalf("unexpected baseURL: %s", cfg.baseURL)
	}
	if cfg.model != "MAI-DS-R1" {
		t.Fatalf("unexpected model: %s", cfg.model)
	}
}

func TestConfigFromEnvUsesGeminiDefaults(t *testing.T) {
	clearAIEnv(t)
	t.Setenv("AI_PROVIDER", "gemini")
	t.Setenv("GEMINI_API_KEY", "gemini-key")
	t.Setenv("GEMINI_MODEL", "gemini-3.5-flash")

	cfg := configFromEnv()
	if cfg.baseURL != "https://generativelanguage.googleapis.com/v1beta/openai/" {
		t.Fatalf("unexpected baseURL: %s", cfg.baseURL)
	}
	if cfg.model != "gemini-3.5-flash" {
		t.Fatalf("unexpected model: %s", cfg.model)
	}
}

func TestConfigFromEnvUsesAnthropicDefaults(t *testing.T) {
	clearAIEnv(t)
	t.Setenv("AI_PROVIDER", "claude")
	t.Setenv("ANTHROPIC_API_KEY", "anthropic-key")
	t.Setenv("ANTHROPIC_MODEL", "claude-sonnet-4-5")

	cfg := configFromEnv()
	if cfg.provider != "anthropic" {
		t.Fatalf("unexpected provider: %s", cfg.provider)
	}
	if cfg.baseURL != "https://api.anthropic.com/" {
		t.Fatalf("unexpected baseURL: %s", cfg.baseURL)
	}
	if cfg.model != "claude-sonnet-4-5" {
		t.Fatalf("unexpected model: %s", cfg.model)
	}
	if cfg.native != "anthropic" {
		t.Fatalf("unexpected native provider: %s", cfg.native)
	}
}

func TestConfigFromEnvFallsBackToOpenAI(t *testing.T) {
	clearAIEnv(t)
	t.Setenv("OPENAI_API_KEY", "openai-key")
	t.Setenv("KUBEBUDDY_OPENAI_MODEL", "gpt-test")

	cfg := configFromEnv()
	if cfg.provider != "openai" {
		t.Fatalf("unexpected provider: %s", cfg.provider)
	}
	if cfg.baseURL != "https://api.openai.com/v1/" {
		t.Fatalf("unexpected baseURL: %s", cfg.baseURL)
	}
	if cfg.model != "gpt-test" {
		t.Fatalf("unexpected model: %s", cfg.model)
	}
}

func TestRecommendUsesNativeAnthropicMessages(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/v1/messages" {
			t.Fatalf("unexpected path: %s", r.URL.Path)
		}
		if got := r.Header.Get("x-api-key"); got != "anthropic-key" {
			t.Fatalf("unexpected x-api-key header: %s", got)
		}
		var body struct {
			Model     string `json:"model"`
			MaxTokens int    `json:"max_tokens"`
			Messages  []struct {
				Role    string `json:"role"`
				Content []struct {
					Type string `json:"type"`
					Text string `json:"text"`
				} `json:"content"`
			} `json:"messages"`
		}
		if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
			t.Fatal(err)
		}
		if body.Model != "claude-test" {
			t.Fatalf("unexpected model: %s", body.Model)
		}
		if body.MaxTokens != 800 {
			t.Fatalf("unexpected max_tokens: %d", body.MaxTokens)
		}
		if len(body.Messages) != 1 || body.Messages[0].Role != "user" || len(body.Messages[0].Content) != 1 || !strings.Contains(body.Messages[0].Content[0].Text, "Findings JSON") {
			t.Fatalf("unexpected messages: %+v", body.Messages)
		}
		w.Header().Set("Content-Type", "application/json")
		_, _ = w.Write([]byte(`{"id":"msg_test","type":"message","role":"assistant","model":"claude-test","content":[{"type":"text","text":"{\"text\":\"Fix Claude\",\"html\":\"<div>Fix Claude</div>\"}"}],"stop_reason":"end_turn","stop_sequence":null,"usage":{"input_tokens":10,"output_tokens":10}}`))
	}))
	defer server.Close()

	client := newClient(clientConfig{
		provider: "anthropic",
		apiKey:   "anthropic-key",
		baseURL:  server.URL + "/",
		model:    "claude-test",
		native:   "anthropic",
	}, server.Client())

	rec, err := client.Recommend("SEC001", "Test", "description", []string{"finding"})
	if err != nil {
		t.Fatal(err)
	}
	if rec.Text != "Fix Claude" {
		t.Fatalf("unexpected recommendation text: %s", rec.Text)
	}
	if rec.HTML != "<div>Fix Claude</div>" {
		t.Fatalf("unexpected recommendation html: %s", rec.HTML)
	}
}

func TestRecommendUsesOpenAICompatibleChatCompletions(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/v1/chat/completions" {
			t.Fatalf("unexpected path: %s", r.URL.Path)
		}
		if got := r.Header.Get("Authorization"); got != "Bearer test-key" {
			t.Fatalf("unexpected Authorization header: %s", got)
		}
		var body struct {
			Model    string `json:"model"`
			Messages []struct {
				Role    string `json:"role"`
				Content string `json:"content"`
			} `json:"messages"`
		}
		if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
			t.Fatal(err)
		}
		if body.Model != "provider-model" {
			t.Fatalf("unexpected model: %s", body.Model)
		}
		if len(body.Messages) != 1 || body.Messages[0].Role != "user" || !strings.Contains(body.Messages[0].Content, "Findings JSON") {
			t.Fatalf("unexpected messages: %+v", body.Messages)
		}
		w.Header().Set("Content-Type", "application/json")
		_, _ = w.Write([]byte(`{"id":"chatcmpl-test","object":"chat.completion","created":1,"model":"provider-model","choices":[{"index":0,"message":{"role":"assistant","content":"{\"text\":\"Fix it\",\"html\":\"<div>Fix it</div>\"}"},"finish_reason":"stop"}]}`))
	}))
	defer server.Close()

	client := newClient(clientConfig{
		provider: "openai-compatible",
		apiKey:   "test-key",
		baseURL:  server.URL + "/v1/",
		model:    "provider-model",
	}, server.Client())

	rec, err := client.Recommend("SEC001", "Test", "description", []string{"finding"})
	if err != nil {
		t.Fatal(err)
	}
	if rec.Text != "Fix it" {
		t.Fatalf("unexpected recommendation text: %s", rec.Text)
	}
	if rec.HTML != "<div>Fix it</div>" {
		t.Fatalf("unexpected recommendation html: %s", rec.HTML)
	}
}
