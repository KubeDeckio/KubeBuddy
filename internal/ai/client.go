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

const (
	// defaultModel is used when KUBEBUDDY_OPENAI_MODEL is not set.
	defaultModel = "gpt-5.6-terra"
	// defaultReasoningEffort is sent only with defaultModel. Reasoning tokens
	// count toward maxOutputTokens, so a low effort leaves room for the JSON.
	defaultReasoningEffort = "low"
	// maxOutputTokens caps reasoning plus the JSON recommendation.
	maxOutputTokens = 2000
)

type Recommendation struct {
	Text string
	HTML string
}

type Client struct {
	apiKey          string
	baseURL         string
	model           string
	reasoningEffort string
	client          *http.Client
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
	reasoningEffort := ""
	if model == "" {
		model = defaultModel
		reasoningEffort = defaultReasoningEffort
	}
	return &Client{
		apiKey:          key,
		baseURL:         baseURL,
		model:           model,
		reasoningEffort: reasoningEffort,
		client:          &http.Client{Timeout: 45 * time.Second},
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
		"max_output_tokens": maxOutputTokens,
	}
	if c.reasoningEffort != "" {
		reqBody["reasoning"] = map[string]string{"effort": c.reasoningEffort}
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
		Status            string `json:"status"`
		IncompleteDetails *struct {
			Reason string `json:"reason"`
		} `json:"incomplete_details"`
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

	// A response cut off by max_output_tokens comes back with status
	// "incomplete"; name the reason instead of a bare parse error.
	incomplete := ""
	if payload.Status == "incomplete" {
		incomplete = "unknown reason"
		if payload.IncompleteDetails != nil && payload.IncompleteDetails.Reason != "" {
			incomplete = payload.IncompleteDetails.Reason
		}
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
		if incomplete != "" {
			return nil, fmt.Errorf("incomplete ai response (%s)", incomplete)
		}
		return nil, fmt.Errorf("empty ai response")
	}

	var result Recommendation
	if err := json.Unmarshal([]byte(extractJSONObject(text)), &result); err != nil {
		if incomplete != "" {
			return nil, fmt.Errorf("incomplete ai response (%s): %w", incomplete, err)
		}
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
