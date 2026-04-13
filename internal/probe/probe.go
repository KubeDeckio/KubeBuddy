package probe

import (
	"context"
	"fmt"
	"strconv"
	"strings"

	"github.com/KubeDeckio/KubeBuddy/internal/kubeapi"
)

type Result struct {
	Context    string
	NodeCount  int
	PodCount   int
	Namespaces []string
}

func Run() (Result, error) {
	client, err := kubeapi.New()
	if err != nil {
		return Result{}, fmt.Errorf("resolve kubeconfig: %w", err)
	}
	ctx := context.Background()
	nodes, err := client.List(ctx, "nodes", false)
	if err != nil {
		return Result{}, fmt.Errorf("list nodes: %w", err)
	}
	pods, err := client.List(ctx, "pods", true)
	if err != nil {
		return Result{}, fmt.Errorf("list pods: %w", err)
	}
	namespaces, err := client.List(ctx, "namespaces", false)
	if err != nil {
		return Result{}, fmt.Errorf("list namespaces: %w", err)
	}
	return Result{
		Context:    strings.TrimSpace(client.CurrentContext()),
		NodeCount:  len(nodes),
		PodCount:   len(pods),
		Namespaces: parseNamespaces(namespaces),
	}, nil
}

func parseNamespaces(items []map[string]any) []string {
	out := make([]string, 0, len(items))
	for _, item := range items {
		if metadata, ok := item["metadata"].(map[string]any); ok {
			if name, ok := metadata["name"].(string); ok && strings.TrimSpace(name) != "" {
				out = append(out, strings.TrimSpace(name))
			}
		}
	}
	return out
}

func Format(result Result) string {
	return strings.Join([]string{
		fmt.Sprintf("context: %s", result.Context),
		fmt.Sprintf("nodes: %s", strconv.Itoa(result.NodeCount)),
		fmt.Sprintf("pods: %s", strconv.Itoa(result.PodCount)),
		fmt.Sprintf("namespaces: %s", strings.Join(result.Namespaces, ", ")),
	}, "\n")
}
