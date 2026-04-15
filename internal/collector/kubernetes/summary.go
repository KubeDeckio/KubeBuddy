package kubernetes

import (
	"context"
	"fmt"
	"strings"

	"github.com/KubeDeckio/KubeBuddy/internal/kubeapi"
)

type Summary struct {
	Context      string
	Nodes        int
	Namespaces   int
	Pods         int
	Deployments  int
	StatefulSets int
	DaemonSets   int
	Services     int
	Ingresses    int
}

func CollectSummary() (Summary, error) {
	client, err := kubeapi.New()
	if err != nil {
		return Summary{}, fmt.Errorf("resolve kubeconfig: %w", err)
	}
	ctx := context.Background()
	nodes, err := countKind(ctx, client, "nodes", false)
	if err != nil {
		return Summary{}, err
	}
	namespaces, err := countKind(ctx, client, "namespaces", false)
	if err != nil {
		return Summary{}, err
	}
	pods, err := countKind(ctx, client, "pods", true)
	if err != nil {
		return Summary{}, err
	}
	deployments, err := countKind(ctx, client, "deployments", true)
	if err != nil {
		return Summary{}, err
	}
	statefulSets, err := countKind(ctx, client, "statefulsets", true)
	if err != nil {
		return Summary{}, err
	}
	daemonSets, err := countKind(ctx, client, "daemonsets", true)
	if err != nil {
		return Summary{}, err
	}
	services, err := countKind(ctx, client, "services", true)
	if err != nil {
		return Summary{}, err
	}
	ingresses, err := countKind(ctx, client, "ingresses", true)
	if err != nil {
		return Summary{}, err
	}
	return Summary{
		Context:      strings.TrimSpace(client.CurrentContext()),
		Nodes:        nodes,
		Namespaces:   namespaces,
		Pods:         pods,
		Deployments:  deployments,
		StatefulSets: statefulSets,
		DaemonSets:   daemonSets,
		Services:     services,
		Ingresses:    ingresses,
	}, nil
}

func countKind(ctx context.Context, client *kubeapi.Client, kind string, allNamespaces bool) (int, error) {
	items, err := client.List(ctx, kind, allNamespaces)
	if err != nil {
		return 0, fmt.Errorf("list %s: %w", kind, err)
	}
	return len(items), nil
}
