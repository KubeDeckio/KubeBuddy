package radar

import (
	"bytes"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"os"
	"strings"
	"time"
)

type Settings struct {
	Enabled             bool
	UploadEnabled       bool
	CompareEnabled      bool
	FetchConfigEnabled  bool
	ConfigID            string
	APIBaseURL          string
	Environment         string
	APIUser             string
	APIPassword         string
	APIUserEnv          string
	APIPasswordEnv      string
	TimeoutSeconds      int
	Retries             int
}

type Client struct {
	baseURL string
	headers map[string]string
	client  *http.Client
	retries int
}

func New(settings Settings) (*Client, error) {
	if !settings.Enabled {
		return nil, fmt.Errorf("radar is not enabled")
	}
	user := strings.TrimSpace(settings.APIUser)
	pass := strings.TrimSpace(settings.APIPassword)
	if user == "" && strings.TrimSpace(settings.APIUserEnv) != "" {
		user = strings.TrimSpace(os.Getenv(settings.APIUserEnv))
	}
	if pass == "" && strings.TrimSpace(settings.APIPasswordEnv) != "" {
		pass = strings.TrimSpace(os.Getenv(settings.APIPasswordEnv))
	}
	if user == "" || pass == "" {
		return nil, fmt.Errorf("radar credentials missing")
	}
	raw := base64.StdEncoding.EncodeToString([]byte(user + ":" + pass))
	timeout := time.Duration(maxInt(settings.TimeoutSeconds, 30)) * time.Second
	return &Client{
		baseURL: strings.TrimRight(settings.APIBaseURL, "/"),
		headers: map[string]string{
			"Authorization": "Basic " + raw,
			"Content-Type":  "application/json",
		},
		client:  &http.Client{Timeout: timeout},
		retries: maxInt(settings.Retries, 2),
	}, nil
}

func (c *Client) FetchConfigFile(configID string) ([]byte, error) {
	return c.do(http.MethodGet, "/cluster-configs/"+configID+"/config-file", nil)
}

func (c *Client) UploadReport(payload any) (map[string]any, error) {
	body, _ := json.Marshal(payload)
	data, err := c.do(http.MethodPost, "/cluster-reports", body)
	if err != nil {
		return nil, err
	}
	var out map[string]any
	if err := json.Unmarshal(data, &out); err != nil {
		return nil, err
	}
	return out, nil
}

func (c *Client) Compare(toRunID string) (map[string]any, error) {
	path := "/cluster-reports/compare"
	if strings.TrimSpace(toRunID) != "" {
		path += "?to_run_id=" + toRunID
	}
	data, err := c.do(http.MethodGet, path, nil)
	if err != nil {
		return nil, err
	}
	var out map[string]any
	if err := json.Unmarshal(data, &out); err != nil {
		return nil, err
	}
	return out, nil
}

func (c *Client) do(method string, path string, body []byte) ([]byte, error) {
	url := c.baseURL + path
	var lastErr error
	for attempt := 0; attempt <= c.retries; attempt++ {
		req, err := http.NewRequest(method, url, bytes.NewReader(body))
		if err != nil {
			return nil, err
		}
		for k, v := range c.headers {
			req.Header.Set(k, v)
		}
		resp, err := c.client.Do(req)
		if err == nil {
			defer resp.Body.Close()
			data, readErr := io.ReadAll(resp.Body)
			if readErr != nil {
				return nil, readErr
			}
			if resp.StatusCode >= 200 && resp.StatusCode < 300 {
				return data, nil
			}
			lastErr = fmt.Errorf("radar returned %s", resp.Status)
		} else {
			lastErr = err
		}
		time.Sleep(time.Second)
	}
	return nil, lastErr
}

func maxInt(value, fallback int) int {
	if value > 0 {
		return value
	}
	return fallback
}
