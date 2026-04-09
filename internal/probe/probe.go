package probe

import (
	"bytes"
	"fmt"
	"os/exec"
	"strconv"
	"strings"
)

type Result struct {
	Context    string
	NodeCount  int
	PodCount   int
	Namespaces []string
}

func Run() (Result, error) {
	context, err := kubectlOutput("config", "current-context")
	if err != nil {
		return Result{}, fmt.Errorf("resolve current context: %w", err)
	}

	nodes, err := kubectlOutput("get", "nodes", "--no-headers")
	if err != nil {
		return Result{}, fmt.Errorf("list nodes: %w", err)
	}

	podsCountText, err := kubectlOutput("get", "pods", "-A", "--no-headers")
	if err != nil {
		return Result{}, fmt.Errorf("list pods: %w", err)
	}

	namespacesText, err := kubectlOutput("get", "ns", "-o", "name")
	if err != nil {
		return Result{}, fmt.Errorf("list namespaces: %w", err)
	}

	return Result{
		Context:    strings.TrimSpace(context),
		NodeCount:  countNonEmptyLines(nodes),
		PodCount:   countNonEmptyLines(podsCountText),
		Namespaces: parseNamespaces(namespacesText),
	}, nil
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

func countNonEmptyLines(value string) int {
	count := 0
	for _, line := range strings.Split(value, "\n") {
		if strings.TrimSpace(line) != "" {
			count++
		}
	}
	return count
}

func parseNamespaces(value string) []string {
	var out []string
	for _, line := range strings.Split(value, "\n") {
		line = strings.TrimSpace(line)
		if line == "" {
			continue
		}
		out = append(out, strings.TrimPrefix(line, "namespace/"))
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
