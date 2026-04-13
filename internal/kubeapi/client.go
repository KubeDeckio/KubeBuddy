package kubeapi

import (
	"context"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"net/url"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"time"

	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/apis/meta/v1/unstructured"
	"k8s.io/apimachinery/pkg/runtime/schema"
	"k8s.io/client-go/discovery"
	"k8s.io/client-go/dynamic"
	"k8s.io/client-go/kubernetes"
	"k8s.io/client-go/rest"
	"k8s.io/client-go/tools/clientcmd"
)

type Client struct {
	config      *rest.Config
	clientset   *kubernetes.Clientset
	dynamic     dynamic.Interface
	discovery   discovery.DiscoveryInterface
	once        sync.Once
	resourceErr error
	resources   map[string]resourceInfo
	currentCtx  string
	clusterHost string
}

type resourceInfo struct {
	GVR        schema.GroupVersionResource
	Namespaced bool
	Kind       string
}

func New() (*Client, error) {
	loadingRules := clientcmd.NewDefaultClientConfigLoadingRules()
	overrides := &clientcmd.ConfigOverrides{}
	return newWithLoader(clientcmd.NewNonInteractiveDeferredLoadingClientConfig(loadingRules, overrides))
}

func NewFromPath(path string) (*Client, error) {
	loadingRules := &clientcmd.ClientConfigLoadingRules{ExplicitPath: path}
	overrides := &clientcmd.ConfigOverrides{}
	return newWithLoader(clientcmd.NewNonInteractiveDeferredLoadingClientConfig(loadingRules, overrides))
}

func NewFromBase64(value string) (*Client, error) {
	decoded, err := base64.StdEncoding.DecodeString(strings.TrimSpace(value))
	if err != nil {
		return nil, err
	}
	tempDir, err := os.MkdirTemp("", "kubebuddy-kubeconfig-*")
	if err != nil {
		return nil, err
	}
	path := filepath.Join(tempDir, "config")
	if err := os.WriteFile(path, decoded, 0o600); err != nil {
		_ = os.RemoveAll(tempDir)
		return nil, err
	}
	client, err := NewFromPath(path)
	if err != nil {
		_ = os.RemoveAll(tempDir)
		return nil, err
	}
	return client, nil
}

func newWithLoader(loader clientcmd.ClientConfig) (*Client, error) {
	rawConfig, err := loader.RawConfig()
	if err != nil {
		return nil, err
	}
	cfg, err := loader.ClientConfig()
	if err != nil {
		return nil, err
	}
	cfg.Timeout = 30 * time.Second
	cfg.WarningHandler = rest.NoWarnings{}
	clientset, err := kubernetes.NewForConfig(cfg)
	if err != nil {
		return nil, err
	}
	dyn, err := dynamic.NewForConfig(cfg)
	if err != nil {
		return nil, err
	}
	return &Client{
		config:      cfg,
		clientset:   clientset,
		dynamic:     dyn,
		discovery:   clientset.Discovery(),
		currentCtx:  rawConfig.CurrentContext,
		clusterHost: cfg.Host,
	}, nil
}

func (c *Client) CurrentContext() string {
	return strings.TrimSpace(c.currentCtx)
}

func (c *Client) ClusterHost() string {
	return strings.TrimSpace(c.clusterHost)
}

func (c *Client) ClusterInfoText() string {
	host := strings.TrimSpace(c.clusterHost)
	if host == "" {
		return ""
	}
	parsed, err := url.Parse(host)
	if err != nil {
		return "Kubernetes control plane is running at " + host
	}
	return "Kubernetes control plane is running at " + parsed.String()
}

func (c *Client) ServerVersion(ctx context.Context) (string, error) {
	info, err := c.discovery.ServerVersion()
	if err != nil {
		return "", err
	}
	return strings.TrimSpace(info.GitVersion), nil
}

func (c *Client) Ping(ctx context.Context) error {
	_, err := c.discovery.ServerVersion()
	return err
}

func (c *Client) Raw(ctx context.Context, path string) ([]byte, error) {
	absPath, rawQuery, _ := strings.Cut(path, "?")
	req := c.restClient().Get().AbsPath(absPath)
	if rawQuery != "" {
		vals, err := url.ParseQuery(rawQuery)
		if err == nil {
			for k, vs := range vals {
				for _, v := range vs {
					req = req.Param(k, v)
				}
			}
		}
	}
	return req.DoRaw(ctx)
}

func (c *Client) List(ctx context.Context, resource string, allNamespaces bool) ([]map[string]any, error) {
	info, err := c.resource(resource)
	if err != nil {
		return nil, err
	}
	return c.listByResource(ctx, info, allNamespaces)
}

func (c *Client) ListByGVR(ctx context.Context, gvr schema.GroupVersionResource, namespaced bool, allNamespaces bool) ([]map[string]any, error) {
	return c.listByResource(ctx, resourceInfo{GVR: gvr, Namespaced: namespaced}, allNamespaces)
}

func (c *Client) GatekeeperConstraints(ctx context.Context) ([]map[string]any, error) {
	if err := c.ensureResources(); err != nil {
		return nil, err
	}
	var out []map[string]any
	for _, info := range c.resources {
		if info.GVR.Group != "constraints.gatekeeper.sh" {
			continue
		}
		items, err := c.listByResource(ctx, info, true)
		if err != nil {
			continue
		}
		out = append(out, items...)
	}
	return out, nil
}

func (c *Client) NodeMetrics(ctx context.Context) (map[string]NodeMetric, error) {
	items, err := c.ListByGVR(ctx, schema.GroupVersionResource{
		Group:    "metrics.k8s.io",
		Version:  "v1beta1",
		Resource: "nodes",
	}, false, false)
	if err != nil {
		return nil, err
	}
	out := map[string]NodeMetric{}
	for _, item := range items {
		name := lookup(item, "metadata.name")
		if name == "" {
			continue
		}
		out[name] = NodeMetric{
			CPUMilli: parseCPUQuantity(lookup(item, "usage.cpu")),
			MemBytes: parseBytesQuantity(lookup(item, "usage.memory")),
		}
	}
	return out, nil
}

type NodeMetric struct {
	CPUMilli int64
	MemBytes int64
}

func DefaultKubeconfigPath() string {
	if env := strings.TrimSpace(os.Getenv("KUBECONFIG")); env != "" {
		return env
	}
	home, err := os.UserHomeDir()
	if err != nil {
		return ""
	}
	return filepath.Join(home, ".kube", "config")
}

func (c *Client) restClient() rest.Interface {
	return c.clientset.CoreV1().RESTClient()
}

func (c *Client) ensureResources() error {
	c.once.Do(func() {
		c.resources = map[string]resourceInfo{}
		lists, err := c.discovery.ServerPreferredResources()
		if err != nil && len(lists) == 0 {
			c.resourceErr = err
			return
		}
		for _, list := range lists {
			gv, err := schema.ParseGroupVersion(list.GroupVersion)
			if err != nil {
				continue
			}
			for _, api := range list.APIResources {
				if strings.Contains(api.Name, "/") {
					continue
				}
				info := resourceInfo{
					GVR:        gv.WithResource(api.Name),
					Namespaced: api.Namespaced,
					Kind:       api.Kind,
				}
				keys := []string{
					strings.ToLower(api.Name),
					strings.ToLower(api.Kind),
					strings.ToLower(strings.TrimSuffix(api.Name, "s")),
				}
				for _, key := range keys {
					if key == "" {
						continue
					}
					if _, ok := c.resources[key]; !ok {
						c.resources[key] = info
					}
				}
			}
		}
	})
	return c.resourceErr
}

func (c *Client) resource(name string) (resourceInfo, error) {
	if err := c.ensureResources(); err != nil {
		return resourceInfo{}, err
	}
	key := strings.ToLower(strings.TrimSpace(name))
	if info, ok := c.resources[key]; ok {
		return info, nil
	}
	return resourceInfo{}, fmt.Errorf("kubernetes resource %q not found", name)
}

func (c *Client) listByResource(ctx context.Context, info resourceInfo, allNamespaces bool) ([]map[string]any, error) {
	ns := ""
	if info.Namespaced && allNamespaces {
		ns = metav1.NamespaceAll
	}
	var list *unstructured.UnstructuredList
	var err error
	if info.Namespaced {
		list, err = c.dynamic.Resource(info.GVR).Namespace(ns).List(ctx, metav1.ListOptions{})
	} else {
		list, err = c.dynamic.Resource(info.GVR).List(ctx, metav1.ListOptions{})
	}
	if err != nil {
		return nil, err
	}
	out := make([]map[string]any, 0, len(list.Items))
	for _, item := range list.Items {
		out = append(out, item.Object)
	}
	return out, nil
}

func lookup(item map[string]any, path string) string {
	parts := strings.Split(path, ".")
	current := any(item)
	for _, part := range parts {
		obj, ok := current.(map[string]any)
		if !ok {
			return ""
		}
		current = obj[part]
	}
	switch typed := current.(type) {
	case string:
		return strings.TrimSpace(typed)
	default:
		data, _ := json.Marshal(typed)
		return strings.Trim(strings.TrimSpace(string(data)), "\"")
	}
}

func parseCPUQuantity(value string) int64 {
	value = strings.TrimSpace(value)
	switch {
	case strings.HasSuffix(value, "m"):
		return parseInt(strings.TrimSuffix(value, "m"))
	case value == "":
		return 0
	default:
		return parseInt(value) * 1000
	}
}

func parseBytesQuantity(value string) int64 {
	value = strings.TrimSpace(strings.ToLower(value))
	type suffix struct {
		unit string
		mult int64
	}
	suffixes := []suffix{
		{"ki", 1024},
		{"mi", 1024 * 1024},
		{"gi", 1024 * 1024 * 1024},
		{"ti", 1024 * 1024 * 1024 * 1024},
		{"k", 1000},
		{"m", 1000 * 1000},
		{"g", 1000 * 1000 * 1000},
	}
	for _, item := range suffixes {
		if strings.HasSuffix(value, item.unit) {
			return parseInt(strings.TrimSuffix(value, item.unit)) * item.mult
		}
	}
	return parseInt(value)
}

func parseInt(value string) int64 {
	var out int64
	fmt.Sscan(strings.TrimSpace(value), &out)
	return out
}
