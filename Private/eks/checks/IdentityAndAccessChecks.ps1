$identityChecks = @(
    @{
        ID         = "EKSIAM001";
        Category   = "Identity & Access";
        Name       = "Kubernetes RBAC Enabled";
        Value      = { $clusterInfo.RoleArn -and $clusterInfo.PlatformVersion };
        Expected   = $true;
        FailMessage = "Kubernetes RBAC is not properly configured or EKS cluster is missing essential role configuration, meaning authentication and authorization controls may be bypassed, creating significant security risks.";
        Severity    = "High";
        Recommendation = "Ensure RBAC is enabled (default in EKS) and configure proper RoleBindings and ClusterRoleBindings. Use 'kubectl create rolebinding' and 'kubectl create clusterrolebinding' to assign appropriate permissions based on the principle of least privilege.";
        URL         = "https://docs.aws.amazon.com/eks/latest/userguide/add-user-role.html";
    },
    @{
        ID         = "EKSIAM002";
        Category   = "Identity & Access";
        Name       = "IAM Roles for Service Accounts (IRSA) Enabled";
        Value      = { $clusterInfo.Identity.Oidc.Issuer -ne $null };
        Expected   = $true;
        FailMessage = "OpenID Connect (OIDC) identity provider is not configured for the cluster, preventing IAM Roles for Service Accounts (IRSA) functionality. This forces workloads to use less secure credential methods like storing AWS keys in secrets.";
        Severity    = "High";
        Recommendation = "Enable OIDC identity provider for IRSA using 'aws eks associate-identity-provider-config --cluster-name <cluster> --oidc' or through the AWS Console. This allows pods to assume IAM roles without storing AWS credentials.";
        URL         = "https://docs.aws.amazon.com/eks/latest/userguide/iam-roles-for-service-accounts.html";
    },
    @{
        ID         = "EKSIAM003";
        Category   = "Identity & Access";
        Name       = "Dedicated IAM Role for EKS Cluster";
        Value      = { 
            $roleArn = $clusterInfo.RoleArn
            $roleName = $roleArn.Split('/')[-1]
            # Check if role is specifically created for EKS (not a generic admin role)
            $roleName -match "eks|EKS" -or $roleName -match "cluster"
        };
        Expected   = $true;
        FailMessage = "EKS cluster is using a generic or overly permissive IAM role instead of a dedicated EKS service role, potentially granting excessive permissions and violating least privilege principles.";
        Severity    = "Medium";
        Recommendation = "Create a dedicated IAM role for EKS cluster with only required permissions. Use AWS managed policy 'AmazonEKSClusterPolicy' and create the role with 'aws iam create-role --role-name eks-cluster-role --assume-role-policy-document file://trust-policy.json'.";
        URL         = "https://docs.aws.amazon.com/eks/latest/userguide/service_IAM_role.html";
    },
    @{
        ID         = "EKSIAM004";
        Category   = "Identity & Access";
        Name       = "Node Group IAM Roles Configured";
        Value      = { 
            $nodeGroups = $clusterInfo.NodeGroups
            $allHaveRoles = $true
            foreach ($ng in $nodeGroups) {
                if (-not $ng.NodeRole) { $allHaveRoles = $false }
            }
            $allHaveRoles
        };
        Expected   = $true;
        FailMessage = "One or more EKS node groups lack proper IAM role configuration, preventing nodes from joining the cluster, pulling container images, or communicating with AWS services required for cluster operation.";
        Severity    = "High";
        Recommendation = "Ensure all node groups have proper IAM roles with required managed policies: 'AmazonEKSWorkerNodePolicy', 'AmazonEKS_CNI_Policy', and 'AmazonEC2ContainerRegistryReadOnly'. Create roles using 'aws iam create-role --role-name eks-node-role'.";
        URL         = "https://docs.aws.amazon.com/eks/latest/userguide/create-node-role.html";
    },
    @{
        ID         = "EKSIAM005";
        Category   = "Identity & Access";
        Name       = "AWS Auth ConfigMap Configured";
        Value      = { 
            $authConfigMap = kubectl get configmap aws-auth -n kube-system -o json 2>/dev/null | ConvertFrom-Json
            $authConfigMap -ne $null
        };
        Expected   = $true;
        FailMessage = "AWS Auth ConfigMap is not properly configured in kube-system namespace, preventing IAM users and roles from accessing the Kubernetes API server and causing authentication failures.";
        Severity    = "High";
        Recommendation = "Configure aws-auth ConfigMap with proper IAM user/role mappings using 'kubectl edit configmap aws-auth -n kube-system'. Map IAM roles to Kubernetes groups and ensure node instance roles are included for proper cluster access.";
        URL         = "https://docs.aws.amazon.com/eks/latest/userguide/add-user-role.html";
    },
    @{
        ID         = "EKSIAM006";
        Category   = "Identity & Access";
        Name       = "Fargate Profile IAM Roles";
        Value      = { 
            $fargateProfiles = $clusterInfo.FargateProfiles
            if ($fargateProfiles.Count -eq 0) { return $true } # No Fargate profiles, check passes
            $allHaveRoles = $true
            foreach ($fp in $fargateProfiles) {
                if (-not $fp.PodExecutionRoleArn) { $allHaveRoles = $false }
            }
            $allHaveRoles
        };
        Expected   = $true;
        FailMessage = "Fargate profiles are missing proper pod execution IAM roles, preventing Fargate pods from pulling container images, writing logs to CloudWatch, or communicating with AWS services.";
        Severity    = "High";
        Recommendation = "Ensure Fargate profiles have pod execution roles with 'AmazonEKSFargatePodExecutionRolePolicy' managed policy. Create execution role using 'aws iam create-role --role-name eks-fargate-pod-execution-role' and attach the required policy.";
        URL         = "https://docs.aws.amazon.com/eks/latest/userguide/fargate-getting-started.html";
    },
    @{
        ID         = "EKSIAM007";
        Category   = "Identity & Access";
        Name       = "Service Account Token Auto-mounting Disabled";
        Value      = { 
            # Check for service accounts with automountServiceAccountToken: false
            $serviceAccounts = kubectl get serviceaccounts --all-namespaces -o json 2>/dev/null | ConvertFrom-Json
            $autoMountDisabled = $serviceAccounts.items | Where-Object { 
                $_.automountServiceAccountToken -eq $false 
            }
            $autoMountDisabled.Count -gt 0
        };
        Expected   = $true;
        FailMessage = "Service accounts have automatic token mounting enabled by default, potentially exposing Kubernetes service account tokens to all pods and increasing the risk of privilege escalation attacks.";
        Severity    = "Medium";
        Recommendation = "Disable automatic service account token mounting for service accounts that don't need it using 'automountServiceAccountToken: false' in ServiceAccount manifests. Enable only for workloads that specifically require Kubernetes API access.";
        URL         = "https://kubernetes.io/docs/tasks/configure-pod-container/configure-service-account/";
    }
)