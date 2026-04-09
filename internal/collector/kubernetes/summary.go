package kubernetes

import (
	"bytes"
	"encoding/json"
	"fmt"
	"os/exec"
	"strings"
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

type listResponse struct {
	Items []json.RawMessage `json:"items"`
}

func CollectSummary() (Summary, error) {
	context, err := kubectlOutput("config", "current-context")
	if err != nil {
		return Summary{}, fmt.Errorf("resolve current context: %w", err)
	}

	nodes, err := countKind("nodes")
	if err != nil {
		return Summary{}, err
	}
	namespaces, err := countKind("namespaces")
	if err != nil {
		return Summary{}, err
	}
	pods, err := countKindAllNamespaces("pods")
	if err != nil {
		return Summary{}, err
	}
	deployments, err := countKindAllNamespaces("deployments")
	if err != nil {
		return Summary{}, err
	}
	statefulSets, err := countKindAllNamespaces("statefulsets")
	if err != nil {
		return Summary{}, err
	}
	daemonSets, err := countKindAllNamespaces("daemonsets")
	if err != nil {
		return Summary{}, err
	}
	services, err := countKindAllNamespaces("services")
	if err != nil {
		return Summary{}, err
	}
	ingresses, err := countKindAllNamespaces("ingresses")
	if err != nil {
		return Summary{}, err
	}

	return Summary{
		Context:      strings.TrimSpace(context),
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

func countKind(kind string) (int, error) {
	return countKubectlJSON("get", kind, "-o", "json")
}

func countKindAllNamespaces(kind string) (int, error) {
	return countKubectlJSON("get", kind, "-A", "-o", "json")
}

func countKubectlJSON(args ...string) (int, error) {
	output, err := kubectlOutput(args...)
	if err != nil {
		return 0, fmt.Errorf("%s: %w", strings.Join(args, " "), err)
	}

	var response listResponse
	if err := json.Unmarshal([]byte(output), &response); err != nil {
		return 0, err
	}

	return len(response.Items), nil
}

func kubectlOutput(args ...string) (string, error) {
	cmd := exec.Command("kubectl", args...)
	var stdout bytes.Buffer
	var stderr bytes.Buffer
	cmd.Stdout = &stdout
	cmd.Stderr = &stderr
	if err := cmd.Run(); err != nil {
		if stderr.Len() > 0 {
			return "", fmt.Errorf("%w: %s", err, strings.TrimSpace(stderr.String()))
		}
		return "", err
	}
	return stdout.String(), nil
}
