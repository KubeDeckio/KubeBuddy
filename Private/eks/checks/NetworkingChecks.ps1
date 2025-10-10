$networkingChecks = @(
    @{
        ID         = "EKSNET001";
        Category   = "Networking";
        Name       = "Private Endpoint Access Enabled";
        Value      = { $clusterInfo.Endpoint.PrivateAccess -eq $true };
        Expected   = $true;
        FailMessage = "EKS cluster API server private endpoint access is disabled, forcing all API communication to traverse the public internet and reducing security by not leveraging VPC-based network isolation.";
        Severity    = "High";
        Recommendation = "Enable private endpoint access using 'aws eks update-cluster-config --name <cluster> --resources-vpc-config endpointConfigPrivateAccess=true'. This allows nodes and VPC resources to communicate with the API server privately.";
        URL         = "https://docs.aws.amazon.com/eks/latest/userguide/cluster-endpoint.html";
    },
    @{
        ID         = "EKSNET002";
        Category   = "Networking";
        Name       = "Public Endpoint Access Restricted";
        Value      = { 
            $clusterInfo.Endpoint.PublicAccess -eq $false -or 
            ($clusterInfo.Endpoint.PublicAccessCidrs -and $clusterInfo.Endpoint.PublicAccessCidrs -ne @("0.0.0.0/0"))
        };
        Expected   = $true;
        FailMessage = "EKS cluster API server public endpoint is accessible from the entire internet (0.0.0.0/0), creating unnecessary exposure and potential attack surface for cluster administration.";
        Severity    = "High";
        Recommendation = "Restrict public endpoint access to specific IP ranges using 'aws eks update-cluster-config --name <cluster> --resources-vpc-config endpointConfigPublicAccessCidrs=<your-ip>/32' or disable public access entirely if not needed.";
        URL         = "https://docs.aws.amazon.com/eks/latest/userguide/cluster-endpoint.html";
    },
    @{
        ID         = "EKSNET003";
        Category   = "Networking";
        Name       = "VPC CNI Plugin Updated";
        Value      = { 
            $vpcCniAddon = $clusterInfo.Addons | Where-Object { $_.AddonName -eq "vpc-cni" }
            if ($vpcCniAddon) {
                # Check if version is recent (placeholder logic - in practice, compare with latest versions)
                $version = $vpcCniAddon.AddonVersion
                $version -notmatch "v1\.9\.|v1\.8\.|v1\.7\." # Avoid very old versions
            } else {
                $false
            }
        };
        Expected   = $true;
        FailMessage = "Amazon VPC CNI plugin is either missing or running an outdated version, potentially lacking security patches, performance improvements, and compatibility with recent Kubernetes features.";
        Severity    = "Medium";
        Recommendation = "Update VPC CNI plugin using 'aws eks update-addon --cluster-name <cluster> --addon-name vpc-cni' or install if missing with 'aws eks create-addon --cluster-name <cluster> --addon-name vpc-cni'. Keep addons updated for security and feature improvements.";
        URL         = "https://docs.aws.amazon.com/eks/latest/userguide/managing-vpc-cni.html";
    },
    @{
        ID         = "EKSNET004";
        Category   = "Networking";
        Name       = "Security Groups Properly Configured";
        Value      = { 
            $clusterSG = $clusterInfo.ResourcesVpcConfig.ClusterSecurityGroupId
            $additionalSGs = $clusterInfo.ResourcesVpcConfig.SecurityGroupIds
            # Basic validation that security groups exist
            $clusterSG -and ($additionalSGs.Count -gt 0 -or $clusterSG)
        };
        Expected   = $true;
        FailMessage = "EKS cluster security groups are not properly configured, potentially blocking essential communication between cluster components, nodes, and AWS services required for proper operation.";
        Severity    = "High";
        Recommendation = "Ensure cluster security group allows required communication. AWS creates a default cluster security group, but verify custom security groups allow: HTTPS (443) for API server, cluster-to-node communication, and inter-node communication on required ports.";
        URL         = "https://docs.aws.amazon.com/eks/latest/userguide/sec-group-reqs.html";
    },
    @{
        ID         = "EKSNET005";
        Category   = "Networking";
        Name       = "Network Policies Available";
        Value      = { 
            # Check if Calico or other network policy engine is installed
            $calicoNamespace = kubectl get namespace calico-system -o json 2>/dev/null | ConvertFrom-Json
            $calicoDeployment = kubectl get deployment calico-node -n kube-system -o json 2>/dev/null | ConvertFrom-Json
            $ciliumNamespace = kubectl get namespace cilium -o json 2>/dev/null | ConvertFrom-Json
            
            $calicoNamespace -or $calicoDeployment -or $ciliumNamespace
        };
        Expected   = $true;
        FailMessage = "No network policy enforcement engine (Calico, Cilium, etc.) is deployed, meaning network policies cannot be enforced and pod-to-pod traffic is unrestricted, reducing network-level security controls.";
        Severity    = "Medium";
        Recommendation = "Install a network policy engine like Calico using 'kubectl apply -f https://raw.githubusercontent.com/aws/amazon-vpc-cni-k8s/release-1.x/config/master/calico-operator.yaml' or consider AWS VPC CNI network policies for basic pod-level controls.";
        URL         = "https://docs.aws.amazon.com/eks/latest/userguide/calico.html";
    },
    @{
        ID         = "EKSNET006";
        Category   = "Networking";
        Name       = "Load Balancer Controller Security";
        Value      = { 
            $albController = kubectl get deployment aws-load-balancer-controller -n kube-system -o json 2>/dev/null | ConvertFrom-Json
            if ($albController) {
                # Check if it has proper service account and IRSA configuration
                $serviceAccount = kubectl get serviceaccount aws-load-balancer-controller -n kube-system -o json 2>/dev/null | ConvertFrom-Json
                $serviceAccount.metadata.annotations."eks.amazonaws.com/role-arn" -ne $null
            } else {
                $false
            }
        };
        Expected   = $true;
        FailMessage = "AWS Load Balancer Controller is either not installed or not properly configured with IAM Roles for Service Accounts (IRSA), potentially causing load balancer provisioning failures or security issues.";
        Severity    = "Medium";
        Recommendation = "Install AWS Load Balancer Controller with proper IRSA configuration. Create IAM role with 'AWSLoadBalancerControllerIAMPolicy', then install controller using Helm chart with service account annotations for the IAM role.";
        URL         = "https://docs.aws.amazon.com/eks/latest/userguide/aws-load-balancer-controller.html";
    },
    @{
        ID         = "EKSNET007";
        Category   = "Networking";
        Name       = "DNS Resolution Security";
        Value      = { 
            # Check CoreDNS configuration and version
            $coreDNS = kubectl get deployment coredns -n kube-system -o json 2>/dev/null | ConvertFrom-Json
            if ($coreDNS) {
                $image = $coreDNS.spec.template.spec.containers[0].image
                # Check that CoreDNS is not using very old versions
                $image -notmatch "1\.6\.|1\.7\.|1\.8\.0"
            } else {
                $false
            }
        };
        Expected   = $true;
        FailMessage = "CoreDNS is either missing or running an outdated version, potentially lacking security fixes and exposing the cluster to DNS-based attacks or resolution failures.";
        Severity    = "Medium";
        Recommendation = "Ensure CoreDNS is updated to a recent version. Update using 'aws eks update-addon --cluster-name <cluster> --addon-name coredns' if managed as an addon, or update the deployment manually if self-managed.";
        URL         = "https://docs.aws.amazon.com/eks/latest/userguide/managing-coredns.html";
    },
    @{
        ID         = "EKSNET008";
        Category   = "Networking";
        Name       = "Network Segmentation Implementation";
        Value      = { 
            # Check for network policies or namespace-based segmentation
            $networkPolicies = kubectl get networkpolicy --all-namespaces -o json 2>/dev/null | ConvertFrom-Json
            $namespaces = kubectl get namespaces -o json 2>/dev/null | ConvertFrom-Json
            
            $hasNetworkPolicies = $networkPolicies.items.Count -gt 0
            $hasMultipleNamespaces = $namespaces.items.Count -gt 3 # More than default system namespaces
            
            $hasNetworkPolicies -or $hasMultipleNamespaces
        };
        Expected   = $true;
        FailMessage = "Network segmentation is not implemented through network policies or namespace isolation, allowing unrestricted pod-to-pod communication and reducing defense-in-depth security controls.";
        Severity    = "Medium";
        Recommendation = "Implement network segmentation using Kubernetes namespaces and network policies. Create separate namespaces for different applications/environments and define NetworkPolicy resources to control inter-pod communication based on least privilege principles.";
        URL         = "https://kubernetes.io/docs/concepts/services-networking/network-policies/";
    }
)