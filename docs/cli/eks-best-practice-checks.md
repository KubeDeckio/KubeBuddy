# EKS Best Practice Checks

KubeBuddy can scan AWS EKS clusters for best-practice compliance across security, networking, monitoring, and operational categories.

## Prerequisites

### AWS Permissions

The IAM identity used for scanning needs the following permissions:

| Permission | Purpose |
|---|---|
| `eks:DescribeCluster` | Read cluster configuration |
| `eks:ListNodegroups` | Enumerate managed node groups |
| `eks:DescribeNodegroup` | Read node group configuration |
| `eks:ListAddons` | Enumerate installed add-ons |
| `eks:DescribeAddon` | Read add-on configuration |

These permissions are included in the `AmazonEKSReadOnlyAccess` managed policy.

### Authentication

KubeBuddy uses the [AWS SDK default credential chain](https://docs.aws.amazon.com/sdkref/latest/guide/standardized-credentials.html):

1. Environment variables (`AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`)
2. Shared credentials file (`~/.aws/credentials`)
3. IAM instance role (EC2, ECS, Lambda)
4. SSO / `aws sso login`

```bash
# Option 1: Environment variables
export AWS_ACCESS_KEY_ID=AKIA...
export AWS_SECRET_ACCESS_KEY=...
export AWS_DEFAULT_REGION=us-east-1

# Option 2: AWS SSO
aws sso login --profile my-profile
export AWS_PROFILE=my-profile

# Option 3: Assume role
aws sts assume-role --role-arn arn:aws:iam::123456789012:role/KubeBuddyRole ...
```

## Usage

### Scan from a JSON file

Export the cluster configuration and scan it offline:

```bash
aws eks describe-cluster --name my-cluster --query cluster > cluster.json
kubebuddy scan-eks --input cluster.json --output html
```

> **Note:** Scanning from a JSON file only evaluates checks based on the `describe-cluster` output. Add-on and node group checks require live collection to populate the enriched fields.

### Scan a live cluster

```bash
kubebuddy scan-eks --cluster-name my-cluster --region us-east-1 --output html
```

Live scanning calls `DescribeCluster`, `ListAddons`, `DescribeAddon`, `ListNodegroups`, and `DescribeNodegroup` to build a complete cluster document.

## CLI Flags

| Flag | Description | Default |
|---|---|---|
| `--cluster-name` | EKS cluster name for live collection | (required for live) |
| `--region` | AWS region | SDK default |
| `--input` | Path to a JSON file (`aws eks describe-cluster --query cluster`) | |
| `--checks-dir` | Directory containing EKS check YAML files | `checks/eks` |
| `--config-path` | Path to `kubebuddy-config.yaml` | |
| `--output` | Output format: `text`, `json`, `csv`, `html` | `text` |

## Check Catalog

### Best Practices (EKSBP)

| ID | Name | Severity |
|---|---|---|
| EKSBP001 | IAM Roles for Service Accounts (IRSA) Enabled | High |
| EKSBP002 | Platform Version Is Current | Medium |
| EKSBP003 | Cluster Kubernetes Version Supported | High |
| EKSBP004 | Managed Node Groups Used | Medium |
| EKSBP005 | EKS Add-ons Managed by EKS | Medium |
| EKSBP006 | EKS Auto Mode or Karpenter Configured | Low |
| EKSBP007 | Access Configuration Uses API Mode | Medium |
| EKSBP008 | Cluster Tags Applied | Low |

### Security (EKSSEC)

| ID | Name | Severity |
|---|---|---|
| EKSSEC001 | Private Cluster Endpoint Enabled | High |
| EKSSEC002 | Public Endpoint Access Restricted | High |
| EKSSEC003 | Public Access CIDR Restricted | High |
| EKSSEC004 | Envelope Encryption for Secrets Enabled | High |
| EKSSEC005 | Security Groups Properly Scoped | Medium |
| EKSSEC006 | EKS Pod Identity Agent Installed | Medium |
| EKSSEC007 | Cluster Service Role Has Minimum Permissions | Medium |

### Monitoring (EKSMON)

| ID | Name | Severity |
|---|---|---|
| EKSMON001 | Control Plane Logging Fully Enabled | High |
| EKSMON002 | All Five Control Plane Log Types Enabled | High |
| EKSMON003 | CloudWatch Container Insights Configured | Medium |

### Networking (EKSNET)

| ID | Name | Severity |
|---|---|---|
| EKSNET001 | VPC CNI Managed Add-on Installed | Medium |
| EKSNET002 | CoreDNS Managed Add-on Installed | Medium |
| EKSNET003 | Kube-Proxy Managed Add-on Installed | Medium |

## Excluding Checks

Add check IDs to your `kubebuddy-config.yaml`:

```yaml
excluded_checks:
  - EKSBP006
  - EKSNET003
```
