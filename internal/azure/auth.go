package azure

import (
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"os"
	"os/exec"
	"strings"
	"time"
)

const (
	armResource        = "https://management.azure.com/"
	prometheusResource = "https://prometheus.monitor.azure.com/"
)

type tokenResponse struct {
	AccessToken string `json:"access_token"`
}

func HasClientCredentials() bool {
	return strings.TrimSpace(os.Getenv("AZURE_CLIENT_ID")) != "" &&
		strings.TrimSpace(os.Getenv("AZURE_CLIENT_SECRET")) != "" &&
		strings.TrimSpace(os.Getenv("AZURE_TENANT_ID")) != ""
}

func ARMToken() (string, error) {
	if HasClientCredentials() {
		return clientCredentialToken(armResource)
	}
	out, err := exec.Command("az", "account", "get-access-token", "--resource", armResource, "--query", "accessToken", "-o", "tsv").Output()
	if err != nil {
		return "", err
	}
	return strings.TrimSpace(string(out)), nil
}

func PrometheusToken() (string, error) {
	if HasClientCredentials() {
		return clientCredentialToken(prometheusResource)
	}
	out, err := exec.Command("az", "account", "get-access-token", "--resource", strings.TrimSuffix(prometheusResource, "/"), "--query", "accessToken", "-o", "tsv").Output()
	if err != nil {
		return "", err
	}
	return strings.TrimSpace(string(out)), nil
}

func clientCredentialToken(resource string) (string, error) {
	clientID := strings.TrimSpace(os.Getenv("AZURE_CLIENT_ID"))
	clientSecret := strings.TrimSpace(os.Getenv("AZURE_CLIENT_SECRET"))
	tenantID := strings.TrimSpace(os.Getenv("AZURE_TENANT_ID"))
	if clientID == "" || clientSecret == "" || tenantID == "" {
		return "", fmt.Errorf("missing AZURE_CLIENT_ID, AZURE_CLIENT_SECRET, or AZURE_TENANT_ID")
	}
	form := url.Values{}
	form.Set("grant_type", "client_credentials")
	form.Set("client_id", clientID)
	form.Set("client_secret", clientSecret)
	form.Set("resource", resource)
	req, err := http.NewRequest(http.MethodPost, "https://login.microsoftonline.com/"+tenantID+"/oauth2/token", strings.NewReader(form.Encode()))
	if err != nil {
		return "", err
	}
	req.Header.Set("Content-Type", "application/x-www-form-urlencoded")
	client := &http.Client{Timeout: 20 * time.Second}
	resp, err := client.Do(req)
	if err != nil {
		return "", err
	}
	defer resp.Body.Close()
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		body, _ := io.ReadAll(resp.Body)
		return "", fmt.Errorf("azure token endpoint returned %s: %s", resp.Status, strings.TrimSpace(string(body)))
	}
	var payload tokenResponse
	if err := json.NewDecoder(resp.Body).Decode(&payload); err != nil {
		return "", err
	}
	if strings.TrimSpace(payload.AccessToken) == "" {
		return "", fmt.Errorf("azure token response did not include an access token")
	}
	return strings.TrimSpace(payload.AccessToken), nil
}
