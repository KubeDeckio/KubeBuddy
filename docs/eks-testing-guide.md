# Testing EKS Checks with Local Kubernetes Clusters
# This guide shows how to test EKS checks using local k8s clusters

## Option 1: Using Kind (Kubernetes in Docker)

### Install Kind
```bash
# On macOS
brew install kind

# On Linux
curl -Lo ./kind https://kind.sigs.k8s.io/dl/v0.20.0/kind-linux-amd64
chmod +x ./kind
sudo mv ./kind /usr/local/bin/kind
```

### Create a Multi-Node Cluster
```bash
# Create kind cluster config
cat > kind-config.yaml << EOF
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
- role: control-plane
- role: worker
- role: worker
- role: worker
networking:
  disableDefaultCNI: false
  podSubnet: "10.244.0.0/16"
EOF

# Create the cluster
kind create cluster --name eks-test --config kind-config.yaml

# Verify cluster
kubectl cluster-info --context kind-eks-test
```

### Test EKS Checks (Some Will Work)
```powershell
# In PowerShell, test the kubectl-based checks
cd /Users/pixelrobots/Documents/Git/KubeBuddy/Private/eks

# Test individual categories that work with any k8s cluster
./Test-IndividualChecks.ps1 -CheckCategory BestPractices
./Test-IndividualChecks.ps1 -CheckCategory Networking
```

## Option 2: Using Minikube

### Install and Start Minikube
```bash
# On macOS
brew install minikube

# Start cluster
minikube start --nodes 3 --driver=docker

# Enable useful addons
minikube addons enable metrics-server
minikube addons enable ingress
```

## Option 3: AWS EKS Anywhere (Local Testing)

### Install EKS Anywhere
```bash
curl "https://anywhere-assets.eks.amazonaws.com/releases/eks-a/1/artifacts/eks-a/v0.18.0/linux/amd64/eksctl-anywhere-v0.18.0-linux-amd64.tar.gz" \
    --silent --location \
    | tar xz ./eksctl-anywhere
sudo mv ./eksctl-anywhere /usr/local/bin/eksctl-anywhere
```

### Create Local EKS Cluster
```bash
# Generate cluster config
eksctl anywhere generate clusterconfig test-cluster \
   --provider docker > eks-anywhere-cluster.yaml

# Create cluster
eksctl anywhere create cluster -f eks-anywhere-cluster.yaml
```

## Option 4: Mock kubectl Commands

You can also create a mock kubectl script for testing:

```bash
#!/bin/bash
# mock-kubectl.sh - Simulates kubectl responses for testing

case "$1 $2" in
    "get namespaces")
        echo '{"items":[{"metadata":{"name":"default"}},{"metadata":{"name":"kube-system"}}]}'
        ;;
    "get nodes")
        echo '{"items":[{"metadata":{"name":"node1"}},{"metadata":{"name":"node2"}}]}'
        ;;
    "get deployments")
        echo '{"items":[{"metadata":{"name":"test-app","namespace":"default"}}]}'
        ;;
    *)
        echo '{"items":[]}'
        ;;
esac
```

## Option 5: Docker-based Testing

### Run KubeBuddy in Container with Mock Data
```bash
# Build test container
docker build -t kubebuddy-test -f - . << EOF
FROM mcr.microsoft.com/powershell:7.3-ubuntu-22.04
COPY . /app
WORKDIR /app
RUN pwsh -c "Install-Module -Name AWS.Tools.EKS -Force"
CMD ["pwsh", "-c", "./Private/eks/Run-EKSTests.ps1"]
EOF

# Run tests
docker run --rm kubebuddy-test
```

## Testing Strategy Recommendations

### 1. Start with Mock Data (Fastest)
```powershell
# Test basic functionality
./Private/eks/Run-EKSTests.ps1

# Test specific categories
./Private/eks/Test-IndividualChecks.ps1 -CheckCategory Security
```

### 2. Use Local K8s for kubectl-based Checks
```powershell
# After setting up kind/minikube
kubectl config use-context kind-eks-test
./Private/eks/Test-IndividualChecks.ps1 -CheckCategory BestPractices
```

### 3. AWS Sandbox Account (Most Realistic)
- Use AWS free tier or sandbox account
- Create minimal EKS cluster for testing
- Delete immediately after testing

### 4. CI/CD Integration
```yaml
# .github/workflows/test-eks.yml
name: Test EKS Checks
on: [push, pull_request]
jobs:
  test:
    runs-on: ubuntu-latest
    steps:
    - uses: actions/checkout@v3
    - name: Setup PowerShell
      uses: microsoft/setup-powershell@v1
    - name: Run EKS Mock Tests
      run: pwsh -c "./Private/eks/Run-EKSTests.ps1"
```

## Which Checks Work Where

| Check Type | Mock Data | Local K8s | EKS Anywhere | Real EKS |
|------------|-----------|-----------|--------------|----------|
| AWS API-based | ✅ | ❌ | ❌ | ✅ |
| kubectl-based | ✅ | ✅ | ✅ | ✅ |
| Combined checks | ✅ | ⚠️ | ⚠️ | ✅ |

Legend: ✅ = Works fully, ⚠️ = Partially works, ❌ = Won't work