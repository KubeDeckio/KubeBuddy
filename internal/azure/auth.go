package azure

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"os"
	"strings"
	"time"

	"github.com/Azure/azure-sdk-for-go/sdk/azcore/policy"
	"github.com/Azure/azure-sdk-for-go/sdk/azidentity"
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
	return defaultCredentialToken(armResource + ".default")
}

func PrometheusToken() (string, error) {
	if HasClientCredentials() {
		return clientCredentialToken(prometheusResource)
	}
	return defaultCredentialToken(strings.TrimSuffix(prometheusResource, "/") + "/.default")
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

func defaultCredentialToken(scope string) (string, error) {
	cred, err := azidentity.NewDefaultAzureCredential(nil)
	if err != nil {
		return "", err
	}
	ctx, cancel := context.WithTimeout(context.Background(), 20*time.Second)
	defer cancel()
	token, err := cred.GetToken(ctx, policy.TokenRequestOptions{Scopes: []string{scope}})
	if err != nil {
		return "", err
	}
	if strings.TrimSpace(token.Token) == "" {
		return "", fmt.Errorf("azure credential chain returned an empty access token")
	}
	return strings.TrimSpace(token.Token), nil
}
