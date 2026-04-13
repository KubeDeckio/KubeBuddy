package prometheus

import (
	"encoding/base64"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"os"
	"strings"
	"time"

	"github.com/KubeDeckio/KubeBuddy/internal/azure"
)

type Client struct {
	BaseURL    string
	Headers    map[string]string
	HTTPClient *http.Client
}

type Options struct {
	URL                string
	Mode               string
	BearerTokenEnv     string
	TimeoutSeconds     int
	RetryCount         int
	RetryDelaySeconds  int
}

type Response struct {
	Status string `json:"status"`
	Data   struct {
		ResultType string     `json:"resultType"`
		Result     []Result   `json:"result"`
	} `json:"data"`
	Error string `json:"error"`
}

type Result struct {
	Metric map[string]string `json:"metric"`
	Value  []any             `json:"value"`
	Values [][]any           `json:"values"`
}

func New(options Options) (*Client, error) {
	headers, err := authHeaders(options.Mode, options.BearerTokenEnv)
	if err != nil {
		return nil, err
	}
	timeout := time.Duration(maxInt(options.TimeoutSeconds, 60)) * time.Second
	return &Client{
		BaseURL: strings.TrimRight(options.URL, "/"),
		Headers: headers,
		HTTPClient: &http.Client{Timeout: timeout},
	}, nil
}

func (c *Client) QueryRange(query, start, end, step string, retries int, retryDelaySeconds int) ([]Result, error) {
	values := url.Values{}
	values.Set("query", query)
	values.Set("start", start)
	values.Set("end", end)
	values.Set("step", step)
	return c.get("/api/v1/query_range", values, retries, retryDelaySeconds)
}

func (c *Client) Query(query string, retries int, retryDelaySeconds int) ([]Result, error) {
	values := url.Values{}
	values.Set("query", query)
	return c.get("/api/v1/query", values, retries, retryDelaySeconds)
}

func (c *Client) get(path string, values url.Values, retries int, retryDelaySeconds int) ([]Result, error) {
	fullURL := c.BaseURL + path + "?" + values.Encode()
	attempts := maxInt(retries, 0) + 1
	delay := time.Duration(maxInt(retryDelaySeconds, 2)) * time.Second
	var lastErr error
	for attempt := 1; attempt <= attempts; attempt++ {
		req, err := http.NewRequest(http.MethodGet, fullURL, nil)
		if err != nil {
			return nil, err
		}
		for key, value := range c.Headers {
			req.Header.Set(key, value)
		}
		resp, err := c.HTTPClient.Do(req)
		if err == nil {
			body, readErr := io.ReadAll(resp.Body)
			resp.Body.Close()
			if readErr != nil {
				return nil, readErr
			}
			if resp.StatusCode >= 200 && resp.StatusCode < 300 {
				var payload Response
				if err := json.Unmarshal(body, &payload); err != nil {
					return nil, err
				}
				if payload.Status != "success" {
					return nil, fmt.Errorf("prometheus query failed: %s", payload.Error)
				}
				return payload.Data.Result, nil
			}
			lastErr = fmt.Errorf("prometheus returned %s", resp.Status)
		} else {
			lastErr = err
		}
		if attempt < attempts {
			time.Sleep(delay)
		}
	}
	return nil, lastErr
}

func authHeaders(mode, bearerTokenEnv string) (map[string]string, error) {
	headers := map[string]string{}
	switch strings.ToLower(strings.TrimSpace(mode)) {
	case "", "local":
		return headers, nil
	case "bearer":
		token := os.Getenv(strings.TrimSpace(bearerTokenEnv))
		if token == "" {
			return nil, fmt.Errorf("prometheus bearer token env %q is empty", bearerTokenEnv)
		}
		headers["Authorization"] = "Bearer " + token
		return headers, nil
	case "azure":
		token, err := azure.PrometheusToken()
		if err != nil {
			return nil, err
		}
		headers["Authorization"] = "Bearer " + token
		return headers, nil
	case "basic":
		user := os.Getenv("PROMETHEUS_USERNAME")
		pass := os.Getenv("PROMETHEUS_PASSWORD")
		pair := base64.StdEncoding.EncodeToString([]byte(user + ":" + pass))
		headers["Authorization"] = "Basic " + pair
		return headers, nil
	default:
		return nil, fmt.Errorf("unsupported prometheus auth mode %q", mode)
	}
}

func maxInt(value int, fallback int) int {
	if value > 0 {
		return value
	}
	return fallback
}
