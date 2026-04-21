package gcp

import (
	"context"
	"fmt"
	"strings"
	"time"

	"golang.org/x/oauth2/google"
)

const prometheusReadScope = "https://www.googleapis.com/auth/monitoring.read"

func PrometheusToken() (string, error) {
	ctx, cancel := context.WithTimeout(context.Background(), 20*time.Second)
	defer cancel()

	creds, err := google.FindDefaultCredentials(ctx, prometheusReadScope)
	if err != nil {
		return "", err
	}

	token, err := creds.TokenSource.Token()
	if err != nil {
		return "", err
	}
	if strings.TrimSpace(token.AccessToken) == "" {
		return "", fmt.Errorf("google credential chain returned an empty access token")
	}
	return strings.TrimSpace(token.AccessToken), nil
}
