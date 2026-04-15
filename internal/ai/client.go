package ai

import (
	"bytes"
	"encoding/json"
	"fmt"
	"net/http"
	"os"
	"strings"
	"time"
)

type Recommendation struct {
	Text string
	HTML string
}

type Client struct {
	apiKey  string
	baseURL string
	model   string
	client  *http.Client
}

func NewFromEnv() *Client {
	key := strings.TrimSpace(os.Getenv("OpenAIKey"))
	if key == "" {
		key = strings.TrimSpace(os.Getenv("OPENAI_API_KEY"))
	}
	if key == "" {
		return nil
	}
	baseURL := strings.TrimSpace(os.Getenv("OPENAI_BASE_URL"))
	if baseURL == "" {
		baseURL = "https://api.openai.com/v1/responses"
	}
	model := strings.TrimSpace(os.Getenv("KUBEBUDDY_OPENAI_MODEL"))
	if model == "" {
		model = "gpt-5-mini"
	}
	return &Client{
		apiKey:  key,
		baseURL: baseURL,
		model:   model,
		client:  &http.Client{Timeout: 45 * time.Second},
	}
}

func (c *Client) Recommend(checkID string, checkName string, description string, findings any) (*Recommendation, error) {
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

	reqBody := map[string]any{
		"model":             c.model,
		"input":             prompt,
		"max_output_tokens": 800,
	}
	body, _ := json.Marshal(reqBody)
	req, err := http.NewRequest(http.MethodPost, c.baseURL, bytes.NewReader(body))
	if err != nil {
		return nil, err
	}
	req.Header.Set("Authorization", "Bearer "+c.apiKey)
	req.Header.Set("Content-Type", "application/json")

	resp, err := c.client.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		return nil, fmt.Errorf("openai returned %s", resp.Status)
	}

	var payload struct {
		Output []struct {
			Content []struct {
				Type string `json:"type"`
				Text string `json:"text"`
			} `json:"content"`
		} `json:"output"`
	}
	if err := json.NewDecoder(resp.Body).Decode(&payload); err != nil {
		return nil, err
	}

	var raw strings.Builder
	for _, item := range payload.Output {
		for _, content := range item.Content {
			if strings.TrimSpace(content.Text) != "" {
				raw.WriteString(content.Text)
			}
		}
	}
	text := strings.TrimSpace(strings.Trim(raw.String(), "`"))
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

func extractJSONObject(value string) string {
	start := strings.Index(value, "{")
	end := strings.LastIndex(value, "}")
	if start >= 0 && end > start {
		return value[start : end+1]
	}
	return value
}
