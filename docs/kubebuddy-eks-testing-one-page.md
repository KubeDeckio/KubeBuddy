# KubeBuddy EKS End-to-End Testing Guide
# Your complete one-page reference for testing EKS with Whizlabs

## 🎯 **Quick Start: Real EKS Testing in Whizlabs (15 minutes setup)**

### Prerequisites
- Whizlabs AWS Sandbox account
- Browser access to AWS Console

---

## 🚀 **STEP 1: AWS CloudShell Setup**

1. **Open AWS Console** → Click **CloudShell icon** (terminal) in top toolbar
2. **Wait 30 seconds** for initialization
3. **Choose region**: us-east-1 (works best with Whizlabs)

---

## 🔑 **STEP 2: Get Your Account Info**
```bash
# Get your account and user details (save these!)
aws sts get-caller-identity
# Note: Account ID and your username from the ARN
```

---

## 🛠️ **STEP 3: Create EKS IAM Policy & Role (Whizlabs Workaround)**

### Create Policy
```bash
aws iam create-policy \
  --policy-name EKSFullAccessPolicy \
  --policy-document '{
    "Version": "2012-10-17",
    "Statement": [{
      "Effect": "Allow",
      "Action": [
        "eks:*", "ec2:*", "iam:CreateRole", "iam:AttachRolePolicy", 
        "iam:PassRole", "iam:GetRole", "iam:ListRoles", "iam:ListAttachedRolePolicies",
        "iam:CreateOpenIDConnectProvider", "iam:GetOpenIDConnectProvider",
        "iam:CreateInstanceProfile", "iam:AddRoleToInstanceProfile",
        "cloudformation:*", "autoscaling:*", "cloudtrail:*", "ecr:*",
        "logs:*", "elasticloadbalancing:*", "ssm:GetParameter*"
      ],
      "Resource": "*"
    }]
  }'
```

### Create Role (Replace YOUR_ACCOUNT_ID and YOUR_USERNAME)
```bash
aws iam create-role \
  --role-name EKSTestRole \
  --assume-role-policy-document '{
    "Version": "2012-10-17",
    "Statement": [{
      "Effect": "Allow",
      "Principal": {"AWS": "arn:aws:iam::YOUR_ACCOUNT_ID:user/YOUR_USERNAME"},
      "Action": "sts:AssumeRole"
    }]
  }'
```

### Attach Policies to Role
```bash
aws iam attach-role-policy --role-name EKSTestRole --policy-arn arn:aws:iam::YOUR_ACCOUNT_ID:policy/EKSFullAccessPolicy
aws iam attach-role-policy --role-name EKSTestRole --policy-arn arn:aws:iam::aws:policy/AmazonEC2FullAccess
aws iam attach-role-policy --role-name EKSTestRole --policy-arn arn:aws:iam::aws:policy/IAMFullAccess
aws iam attach-role-policy --role-name EKSTestRole --policy-arn arn:aws:iam::aws:policy/CloudFormationFullAccess
```

---

## 🔐 **STEP 4: Assume Role (Get EKS Permissions)**
```bash
# Assume the role
aws sts assume-role \
  --role-arn arn:aws:iam::YOUR_ACCOUNT_ID:role/EKSTestRole \
  --role-session-name EKSTestSession

# Export the credentials from the output above
export AWS_ACCESS_KEY_ID="ASIA..."
export AWS_SECRET_ACCESS_KEY="..."
export AWS_SESSION_TOKEN="..."

# Verify role assumption worked
aws sts get-caller-identity
# Should show: assumed-role/EKSTestRole/EKSTestSession
```

---

## 🔧 **STEP 5: Install Tools**
```bash
# Install eksctl
curl -sL "https://github.com/weaveworks/eksctl/releases/latest/download/eksctl_$(uname -s)_amd64.tar.gz" | tar xz -C /tmp
mkdir -p ~/bin && mv /tmp/eksctl ~/bin/ && export PATH=$HOME/bin:$PATH

# Install PowerShell
curl -L https://github.com/PowerShell/PowerShell/releases/download/v7.3.8/powershell-7.3.8-linux-x64.tar.gz -o /tmp/powershell.tar.gz
mkdir -p ~/powershell && tar zxf /tmp/powershell.tar.gz -C ~/powershell
ln -s ~/powershell/pwsh ~/bin/pwsh
```

---

## 🏗️ **STEP 6: Create EKS Cluster**

### 🚀 **FAST Option: Quick Test Cluster (5-8 minutes)**
```bash
# Minimal cluster for testing only
eksctl create cluster \
  --name kubebuddy-quick \
  --region us-east-1 \
  --version 1.28 \
  --nodes 1 \
  --node-type t3.small \
  --managed \
  --node-volume-size 20

# Verify cluster
kubectl get nodes
kubectl cluster-info
```

### 🔧 **FULL Option: Production-like Cluster (15-20 minutes)**
```bash
# Full cluster with better specs (if you have time)
eksctl create cluster \
  --name kubebuddy-test \
  --region us-east-1 \
  --version 1.28 \
  --nodes 2 \
  --node-type t3.medium \
  --managed

# Verify cluster
kubectl get nodes
kubectl cluster-info
```

---

## 🧪 **STEP 7: Test KubeBuddy with Real EKS**
```bash
# Clone KubeBuddy
git clone https://github.com/KubeDeckio/KubeBuddy.git
cd KubeBuddy && git checkout aws

# Set AWS Tools V5 and install PowerShell modules
export AWS_TOOLS_VERSION=V5

pwsh -c "
# Set TLS and configure PowerShell Gallery
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12;
Set-PSRepository -Name PSGallery -InstallationPolicy Trusted;

# Install AWS Tools V5
Install-Module -Name AWS.Tools.Installer -Force -Scope CurrentUser;
Install-AWSToolsModule AWS.Tools.EKS,AWS.Tools.EC2,AWS.Tools.IdentityManagement,AWS.Tools.STS,AWS.Tools.ECR,AWS.Tools.CloudTrail -Scope CurrentUser -Force
"

# Run KubeBuddy EKS checks (use cluster name you created)
pwsh -c "
Import-Module ./KubeBuddy.psm1;
Invoke-KubeBuddy -EKS -Region us-east-1 -ClusterName kubebuddy-quick
"
```

---

## 🧹 **STEP 8: Clean Up (IMPORTANT!)**
```bash
# Delete cluster first (most important for cost)
# Use the cluster name you created above
eksctl delete cluster --name kubebuddy-quick --region us-east-1
# OR if you used the full option:
# eksctl delete cluster --name kubebuddy-test --region us-east-1

# Clean up IAM (optional, but good practice)
aws iam detach-role-policy --role-name EKSTestRole --policy-arn arn:aws:iam::YOUR_ACCOUNT_ID:policy/EKSFullAccessPolicy
aws iam detach-role-policy --role-name EKSTestRole --policy-arn arn:aws:iam::aws:policy/AmazonEC2FullAccess
aws iam detach-role-policy --role-name EKSTestRole --policy-arn arn:aws:iam::aws:policy/IAMFullAccess
aws iam detach-role-policy --role-name EKSTestRole --policy-arn arn:aws:iam::aws:policy/CloudFormationFullAccess
aws iam delete-role --role-name EKSTestRole
aws iam delete-policy --policy-arn arn:aws:iam::YOUR_ACCOUNT_ID:policy/EKSFullAccessPolicy
```

---

## 🎯 **Alternative: Mock Testing (No AWS costs)**

If you want to test without AWS charges:

```bash
# In CloudShell or locally
git clone https://github.com/KubeDeckio/KubeBuddy.git
cd KubeBuddy && git checkout aws

# Install PowerShell YAML module (required for mock testing)
pwsh -c "
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12;
Set-PSRepository -Name PSGallery -InstallationPolicy Trusted;
Install-Module -Name powershell-yaml -Force -Scope CurrentUser
"

# Run comprehensive mock tests
pwsh -c "./Private/eks/Run-EKSTests.ps1"

# Test specific categories
pwsh -c "./Private/eks/Test-IndividualChecks.ps1 -CheckCategory Security"
pwsh -c "./Private/eks/Test-IndividualChecks.ps1 -CheckCategory Networking"
```

---

## 📊 **Cost Summary**
- **Quick EKS**: ~$0.08/hour (~$0.25 for 3-hour test session)
- **Full EKS**: ~$0.18/hour (~$0.50 for 3-hour test session)
- **Mock Testing**: $0 (uses simulated data)

## ⏱️ **Time Summary**
- **Quick Setup**: 15 minutes total (10 setup + 5 cluster creation)
- **Full Setup**: 35 minutes total (15 setup + 20 cluster creation)
- **Mock Testing**: 2 minutes (immediate)

---

## 🔍 **What Gets Tested**

### Real EKS Testing Validates:
✅ All 55 EKS best practice checks  
✅ Real AWS API integration  
✅ Actual kubectl commands against live cluster  
✅ Complete KubeBuddy workflow  

### Mock Testing Validates:
✅ All check logic and conditions  
✅ PowerShell module functionality  
✅ Error handling and edge cases  
✅ Report generation  

---

## 🎉 **Success Indicators**

**Real EKS Test Success:**
- Cluster creates successfully
- `kubectl get nodes` shows 2 nodes
- KubeBuddy runs and produces EKS best practice report
- All AWS APIs respond correctly

**Mock Test Success:**
- All check categories execute without errors
- Both passing and failing checks are identified
- Detailed recommendations are provided
- Different configuration scenarios work

---

## 🚨 **Troubleshooting**

**If eksctl fails:** Check you're using the assumed role credentials  
**If permissions fail:** Verify role assumption step worked  
**If cluster creation hangs:** Check CloudFormation console for stack status  
**If cleanup fails:** Focus on cluster deletion first (most expensive)  

**Emergency cleanup:** Go to CloudFormation console → Delete stacks starting with "eksctl-kubebuddy-test"

---

## 💡 **Pro Tips**
- **Save your credentials:** Export commands to a file for reuse during session
- **Monitor costs:** Check AWS billing dashboard during testing
- **Time management:** Budget 45 minutes total (15 setup + 20 cluster creation + 10 testing)
- **Session persistence:** CloudShell keeps your setup between browser sessions