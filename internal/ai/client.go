package ai

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"os"
	"strings"
	"time"

	anthropic "github.com/anthropics/anthropic-sdk-go"
	anthropicopt "github.com/anthropics/anthropic-sdk-go/option"
	"github.com/openai/openai-go/v3"
	openaiopt "github.com/openai/openai-go/v3/option"
)

const (
	defaultProvider = "openai"
	defaultBaseURL  = "https://api.openai.com/v1/"
	defaultModel    = "gpt-5-mini"
)

type Recommendation struct {
	Text string
	HTML string
}

type Client struct {
	provider string
	apiKey   string
	baseURL  string
	model    string
	openai   openai.Client
	claude   anthropic.Client
}

type clientConfig struct {
	provider string
	apiKey   string
	baseURL  string
	model    string
	native   string
}

func NewFromEnv() *Client {
	cfg := configFromEnv()
	if cfg.apiKey == "" {
		return nil
	}
	return newClient(cfg, &http.Client{Timeout: 45 * time.Second})
}

func newClient(cfg clientConfig, httpClient *http.Client) *Client {
	c := &Client{
		provider: cfg.provider,
		apiKey:   cfg.apiKey,
		baseURL:  cfg.baseURL,
		model:    cfg.model,
	}
	if cfg.native == "anthropic" {
		opts := []anthropicopt.RequestOption{
			anthropicopt.WithAPIKey(cfg.apiKey),
			anthropicopt.WithBaseURL(cfg.baseURL),
		}
		if httpClient != nil {
			opts = append(opts, anthropicopt.WithHTTPClient(httpClient))
		}
		c.claude = anthropic.NewClient(opts...)
		return c
	}

	opts := []openaiopt.RequestOption{
		openaiopt.WithAPIKey(cfg.apiKey),
		openaiopt.WithBaseURL(cfg.baseURL),
	}
	if httpClient != nil {
		opts = append(opts, openaiopt.WithHTTPClient(httpClient))
	}
	c.openai = openai.NewClient(opts...)
	return c
}

func configFromEnv() clientConfig {
	provider := normalizeProvider(firstNonEmpty(
		os.Getenv("AI_PROVIDER"),
		os.Getenv("KUBEBUDDY_AI_PROVIDER"),
	))

	// Preserve the older Azure-specific setup even when AI_PROVIDER is not set.
	if provider == "" && strings.TrimSpace(os.Getenv("AZURE_OPENAI_ENDPOINT")) != "" {
		provider = "azure-openai"
	}
	if provider == "" {
		provider = defaultProvider
	}

	cfg := clientConfig{provider: provider}
	switch provider {
	case "azure-openai":
		cfg.apiKey = firstNonEmpty(os.Getenv("AI_API_KEY"), os.Getenv("AZURE_OPENAI_API_KEY"), os.Getenv("AZURE_OPENAI_AUTH_TOKEN"))
		cfg.baseURL = firstNonEmpty(os.Getenv("AI_BASE_URL"), os.Getenv("AZURE_OPENAI_BASE_URL"), azureOpenAIBaseURL(os.Getenv("AZURE_OPENAI_ENDPOINT")))
		cfg.model = firstNonEmpty(os.Getenv("AI_MODEL"), os.Getenv("AZURE_OPENAI_DEPLOYMENT"), os.Getenv("KUBEBUDDY_AZURE_OPENAI_DEPLOYMENT"), os.Getenv("KUBEBUDDY_OPENAI_MODEL"))
	case "foundry":
		cfg.apiKey = firstNonEmpty(os.Getenv("AI_API_KEY"), os.Getenv("FOUNDRY_API_KEY"), os.Getenv("AZURE_AI_FOUNDRY_API_KEY"), os.Getenv("AZURE_OPENAI_API_KEY"))
		cfg.baseURL = firstNonEmpty(os.Getenv("AI_BASE_URL"), os.Getenv("FOUNDRY_BASE_URL"), os.Getenv("AZURE_AI_FOUNDRY_BASE_URL"), foundryBaseURL(os.Getenv("FOUNDRY_ENDPOINT")), foundryBaseURL(os.Getenv("AZURE_AI_FOUNDRY_ENDPOINT")))
		cfg.model = firstNonEmpty(os.Getenv("AI_MODEL"), os.Getenv("FOUNDRY_MODEL"), os.Getenv("AZURE_AI_FOUNDRY_MODEL"), os.Getenv("AZURE_OPENAI_DEPLOYMENT"), os.Getenv("KUBEBUDDY_OPENAI_MODEL"))
	case "gemini":
		cfg.apiKey = firstNonEmpty(os.Getenv("AI_API_KEY"), os.Getenv("GEMINI_API_KEY"), os.Getenv("GOOGLE_API_KEY"))
		cfg.baseURL = firstNonEmpty(os.Getenv("AI_BASE_URL"), os.Getenv("GEMINI_BASE_URL"), "https://generativelanguage.googleapis.com/v1beta/openai/")
		cfg.model = firstNonEmpty(os.Getenv("AI_MODEL"), os.Getenv("GEMINI_MODEL"), os.Getenv("KUBEBUDDY_OPENAI_MODEL"))
	case "anthropic":
		cfg.apiKey = firstNonEmpty(os.Getenv("AI_API_KEY"), os.Getenv("ANTHROPIC_API_KEY"), os.Getenv("CLAUDE_API_KEY"))
		cfg.baseURL = firstNonEmpty(os.Getenv("AI_BASE_URL"), os.Getenv("ANTHROPIC_BASE_URL"), os.Getenv("CLAUDE_BASE_URL"), "https://api.anthropic.com/")
		cfg.model = firstNonEmpty(os.Getenv("AI_MODEL"), os.Getenv("ANTHROPIC_MODEL"), os.Getenv("CLAUDE_MODEL"), os.Getenv("KUBEBUDDY_OPENAI_MODEL"))
		cfg.native = "anthropic"
	default:
		cfg.apiKey = firstNonEmpty(os.Getenv("AI_API_KEY"), os.Getenv("OpenAIKey"), os.Getenv("OPENAI_API_KEY"))
		cfg.baseURL = firstNonEmpty(os.Getenv("AI_BASE_URL"), os.Getenv("OPENAI_BASE_URL"), defaultBaseURL)
		cfg.model = firstNonEmpty(os.Getenv("AI_MODEL"), os.Getenv("KUBEBUDDY_OPENAI_MODEL"))
	}

	if cfg.baseURL == "" {
		cfg.baseURL = defaultBaseURL
	}
	if cfg.model == "" {
		cfg.model = defaultModel
		if cfg.native == "anthropic" {
			cfg.model = "claude-sonnet-4-5"
		}
	}
	cfg.baseURL = ensureTrailingSlash(cfg.baseURL)
	return cfg
}

func (c *Client) Recommend(checkID string, checkName string, description string, findings any) (*Recommendation, error) {
	text, err := c.recommendText(checkID, checkName, description, findings)
	if err != nil {
		return nil, err
	}
	text = strings.TrimSpace(strings.Trim(text, "`"))
	if text == "" {
		return nil, fmt.Errorf("empty ai response")
	}

	var result Recommendation
	if err := json.Unmarshal([]byte(extractJSONObject(text)), &result); err != nil {
		return nil, err
	}
	if strings.TrimSpace(result.HTML) == "" {
		return nil, fmt.Errorf("missing ai html recommendation")
	}
	result.Text = strings.TrimSpace(result.Text)
	result.HTML = strings.TrimSpace(result.HTML)
	return &result, nil
}

func (c *Client) recommendText(checkID string, checkName string, description string, findings any) (string, error) {
	findingsJSON, _ := json.Marshal(findings)
	prompt := fmt.Sprintf(`You are an expert Kubernetes advisor.

A check called "%s - %s" returned issues.

Description:
%s

Findings JSON:
%s

Return JSON only with this exact shape:
{"text":"short actionable summary in 1-3 sentences","html":"HTML snippet wrapped in <div> or <ul> with practical remediation steps"}

Do not use markdown fences.`, checkID, checkName, description, string(findingsJSON))

	if c.provider == "anthropic" {
		resp, err := c.claude.Messages.New(context.Background(), anthropic.MessageNewParams{
			Model:     anthropic.Model(c.model),
			MaxTokens: 800,
			Messages: []anthropic.MessageParam{
				anthropic.NewUserMessage(anthropic.NewTextBlock(prompt)),
			},
		})
		if err != nil {
			return "", fmt.Errorf("%s ai returned error: %w", c.provider, err)
		}
		var raw strings.Builder
		for _, content := range resp.Content {
			if content.Text != "" {
				raw.WriteString(content.Text)
			}
		}
		return raw.String(), nil
	}

	resp, err := c.openai.Chat.Completions.New(context.Background(), openai.ChatCompletionNewParams{
		Model: openai.ChatModel(c.model),
		Messages: []openai.ChatCompletionMessageParamUnion{
			openai.UserMessage(prompt),
		},
		MaxCompletionTokens: openai.Int(800),
	})
	if err != nil {
		return "", fmt.Errorf("%s ai returned error: %w", c.provider, err)
	}
	if len(resp.Choices) == 0 {
		return "", fmt.Errorf("empty ai response")
	}
	return resp.Choices[0].Message.Content, nil
}

func normalizeProvider(value string) string {
	switch strings.ToLower(strings.TrimSpace(value)) {
	case "", "openai":
		return strings.ToLower(strings.TrimSpace(value))
	case "azure", "azureopenai", "azure-openai", "azure_openai":
		return "azure-openai"
	case "ms-foundry", "microsoft-foundry", "azure-foundry", "azure_ai_foundry", "foundry":
		return "foundry"
	case "google", "google-gemini", "gemini":
		return "gemini"
	case "anthropic", "claude":
		return "anthropic"
	case "compatible", "openai-compatible", "openai_compatible", "custom":
		return "openai-compatible"
	default:
		return strings.ToLower(strings.TrimSpace(value))
	}
}

func azureOpenAIBaseURL(endpoint string) string {
	trimmed := strings.TrimRight(strings.TrimSpace(endpoint), "/")
	if trimmed == "" {
		return ""
	}
	if strings.HasSuffix(trimmed, "/openai/v1") {
		return trimmed + "/"
	}
	return trimmed + "/openai/v1/"
}

func foundryBaseURL(endpoint string) string {
	trimmed := strings.TrimRight(strings.TrimSpace(endpoint), "/")
	if trimmed == "" {
		return ""
	}
	if strings.HasSuffix(trimmed, "/openai/v1") {
		return trimmed + "/"
	}
	return trimmed + "/openai/v1/"
}

func ensureTrailingSlash(value string) string {
	trimmed := strings.TrimSpace(value)
	if trimmed == "" || strings.HasSuffix(trimmed, "/") {
		return trimmed
	}
	return trimmed + "/"
}

func firstNonEmpty(values ...string) string {
	for _, value := range values {
		if strings.TrimSpace(value) != "" {
			return strings.TrimSpace(value)
		}
	}
	return ""
}

func extractJSONObject(value string) string {
	start := strings.Index(value, "{")
	end := strings.LastIndex(value, "}")
	if start >= 0 && end > start {
		return value[start : end+1]
	}
	return value
}
