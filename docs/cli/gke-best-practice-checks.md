---
title: GKE Configuration & Best Practices Checks
parent: Usage
nav_order: 5
---

# GKE Best Practice Checks

KubeBuddy evaluates various aspects of your **Google Kubernetes Engine (GKE)** setup, highlighting potential misconfigurations and confirming best practices aligned with the Google Cloud CIS Kubernetes Benchmark.

## Prerequisites

### GCP Permissions

The authenticated principal (user or service account) needs the following IAM permission:

- `container.clusters.get` — included in the `roles/container.viewer` role

### Authentication

KubeBuddy uses **Application Default Credentials (ADC)** for live GKE collection. Set up ADC with:

```bash
gcloud auth application-default login
```

For service accounts (CI/CD), set the `GOOGLE_APPLICATION_CREDENTIALS` environment variable:

```bash
export GOOGLE_APPLICATION_CREDENTIALS="/path/to/service-account-key.json"
```

## Usage

### Option 1: Offline Scan (Recommended for Testing)

Export your cluster configuration to a JSON file:

```bash
gcloud container clusters describe <cluster-name> \
  --zone <zone> \
  --format json > cluster.json
```

Run the scan:

```bash
kubebuddy scan-gke --input cluster.json
```

### Option 2: Live Collection

Connect directly to the GKE API:

```bash
kubebuddy scan-gke \
  --project-id <gcp-project-id> \
  --location <zone-or-region> \
  --cluster-name <cluster-name>
```

### Output Formats

```bash
kubebuddy scan-gke --input cluster.json --output text   # Terminal output (default)
kubebuddy scan-gke --input cluster.json --output json   # JSON output
kubebuddy scan-gke --input cluster.json --output html   # HTML report with GKE tab
kubebuddy scan-gke --input cluster.json --output csv    # CSV output
```

### Command Flags

| Flag             | Description                                                     |
|------------------|-----------------------------------------------------------------|
| `--input`        | Path to a GKE cluster JSON file (`gcloud ... --format json`)    |
| `--project-id`   | GCP project ID for live collection                              |
| `--location`     | GKE cluster zone or region for live collection                  |
| `--cluster-name` | GKE cluster name                                                |
| `--checks-dir`   | Directory containing GKE check YAML files (default: `checks/gke`) |
| `--config-path`  | Path to KubeBuddy config file                                   |
| `--output`       | Output format: `text`, `json`, `csv`, or `html`                 |

## Checks Overview

Below is a categorized list of all GKE checks, ordered by ID and category.

### Best Practices

| ID       | Check                              | Severity |
|----------|-------------------------------------|----------|
| GKEBP001 | Workload Identity Enabled           | High     |
| GKEBP002 | Shielded GKE Nodes Enabled          | High     |
| GKEBP003 | Node Auto-Upgrade Enabled           | High     |
| GKEBP004 | Node Auto-Repair Enabled            | High     |
| GKEBP005 | Cloud Logging Agent Enabled         | Medium   |
| GKEBP006 | Cloud Monitoring Agent Enabled      | Medium   |
| GKEBP007 | VPC-Native Cluster (Alias IP)       | High     |
| GKEBP008 | Release Channel Configured          | Medium   |
| GKEBP009 | Cluster Autoscaler Configured       | Medium   |
| GKEBP010 | Binary Authorization Enabled        | High     |

### Security

| ID        | Check                                      | Severity |
|-----------|---------------------------------------------|----------|
| GKESEC001 | Private Cluster Enabled                     | High     |
| GKESEC002 | Master Authorized Networks Configured       | High     |
| GKESEC003 | Network Policy Enforcement Enabled          | High     |
| GKESEC004 | GKE Dataplane V2 (Cilium) Enabled           | Medium   |
| GKESEC005 | Intranode Visibility Enabled                | Medium   |
| GKESEC006 | Application-Layer Secrets Encryption        | High     |

### Monitoring

| ID         | Check                              | Severity |
|------------|-------------------------------------|----------|
| GKEMON001  | Managed Prometheus Enabled          | Medium   |
| GKEMON002  | Control Plane Logging Enabled       | High     |
| GKEMON003  | GKE Usage Metering Enabled          | Low      |

### Networking

| ID         | Check                              | Severity |
|------------|-------------------------------------|----------|
| GKENET001  | Gateway API Controller Enabled      | Low      |
| GKENET002  | HTTP Load Balancing Enabled         | Low      |
| GKENET003  | DNS Caching Enabled                 | Low      |

Each check provides insights into security, performance, and cost optimization for GKE clusters.
