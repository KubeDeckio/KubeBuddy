$securityChecks = @(
    @{
        ID          = "EKSSEC001";
        Category    = "Security";
        Name        = "Private API Server Endpoint";
        Value       = { $clusterInfo.Endpoint -notmatch "^https://[A-F0-9]+\.eks\.[a-z0-9-]+\.amazonaws\.com" -or $clusterInfo.ResourcesVpcConfig.EndpointConfigState.PrivateAccess -eq $true };
        Expected    = $true;
        FailMessage = "EKS API server endpoint is publicly accessible without VPC private access enabled, exposing your cluster to potential attacks from the internet, unauthorized access attempts, and compliance violations.";
        Severity    = "High";
        Recommendation = "Enable private API server access using 'aws eks update-cluster-config --name <cluster> --resources-vpc-config endpointConfigState={privateAccess=true,publicAccess=false}' or configure restricted public access with specific CIDR blocks for authorized networks only.";
        URL         = "https://docs.aws.amazon.com/eks/latest/userguide/cluster-endpoint.html";
    },
    @{
        ID          = "EKSSEC002";
        Category    = "Security";
        Name        = "Cluster Encryption at Rest";
        Value       = { $clusterInfo.EncryptionConfig -and $clusterInfo.EncryptionConfig.Count -gt 0 };
        Expected    = $true;
        FailMessage = "EKS cluster does not have encryption at rest enabled for etcd, leaving Kubernetes secrets, ConfigMaps, and other sensitive data stored in plaintext, violating security best practices and compliance requirements.";
        Severity    = "High";
        Recommendation = "Enable encryption at rest during cluster creation using '--encryption-config' with a KMS key, or create a new cluster with encryption enabled. Use 'aws eks create-cluster --encryption-config resources=secrets,provider={keyArn=arn:aws:kms:region:account:key/key-id}' for new clusters.";
        URL         = "https://docs.aws.amazon.com/eks/latest/userguide/encryption-at-rest.html";
    },
    @{
        ID          = "EKSSEC003";
        Category    = "Security";
        Name        = "VPC Subnets in Private Subnets";
        Value       = { 
            $privateSubnets = $clusterInfo.ResourcesVpcConfig.SubnetIds | Where-Object { 
                $subnet = aws ec2 describe-subnets --subnet-ids $_ --query 'Subnets[0]' --output json | ConvertFrom-Json
                $routeTable = aws ec2 describe-route-tables --filters "Name=association.subnet-id,Values=$_" --query 'RouteTables[0]' --output json | ConvertFrom-Json
                $hasIGW = $routeTable.Routes | Where-Object { $_.GatewayId -like "igw-*" }
                return -not $hasIGW
            }
            $privateSubnets.Count -gt 0
        };
        Expected    = $true;
        FailMessage = "EKS cluster nodes are deployed in public subnets with direct internet access, exposing worker nodes to internet-based attacks and violating network security isolation principles.";
        Severity    = "High";
        Recommendation = "Deploy EKS node groups in private subnets that route internet traffic through NAT Gateway or NAT Instance. Use 'aws eks create-nodegroup --subnet-ids subnet-private1,subnet-private2' and ensure proper VPC configuration with private subnets.";
        URL         = "https://docs.aws.amazon.com/eks/latest/userguide/network_reqs.html";
    },
    @{
        ID          = "EKSSEC004";
        Category    = "Security";
        Name        = "Pod Security Standards Enabled";
        Value       = { 
            # Check if Pod Security Standards are configured via admission controllers
            $podSecurityConfig = kubectl get pod --all-namespaces -o json 2>/dev/null | ConvertFrom-Json
            # This is a placeholder - in real implementation, check for PSS configuration
            $false
        };
        Expected    = $true;
        FailMessage = "Pod Security Standards are not configured, allowing pods to run with excessive privileges, access host resources, or use insecure configurations. This increases container escape risks and lateral movement opportunities.";
        Severity    = "High";
        Recommendation = "Configure Pod Security Standards by applying pod security labels to namespaces: 'kubectl label namespace <namespace> pod-security.kubernetes.io/enforce=restricted pod-security.kubernetes.io/audit=restricted pod-security.kubernetes.io/warn=restricted'. Use 'baseline' for less restrictive environments.";
        URL         = "https://kubernetes.io/docs/concepts/security/pod-security-standards/";
    },
    @{
        ID          = "EKSSEC005";
        Category    = "Security";
        Name        = "AWS Load Balancer Controller Addon";
        Value       = { 
            $addons = $clusterInfo.Addons | Where-Object { $_.AddonName -eq "aws-load-balancer-controller" }
            $addons -and $addons.Status -eq "ACTIVE"
        };
        Expected    = $true;
        FailMessage = "AWS Load Balancer Controller addon is not installed, forcing use of legacy in-tree cloud provider which lacks advanced security features, proper security group management, and modern load balancing capabilities.";
        Severity    = "Medium";
        Recommendation = "Install AWS Load Balancer Controller addon using 'aws eks create-addon --cluster-name <cluster> --addon-name aws-load-balancer-controller' or via Helm. This provides better security group management, WAF integration, and modern ALB/NLB features.";
        URL         = "https://docs.aws.amazon.com/eks/latest/userguide/aws-load-balancer-controller.html";
    },
    @{
        ID          = "EKSSEC006";
        Category    = "Security";
        Name        = "EBS CSI Driver Addon";
        Value       = { 
            $addons = $clusterInfo.Addons | Where-Object { $_.AddonName -eq "aws-ebs-csi-driver" }
            $addons -and $addons.Status -eq "ACTIVE"
        };
        Expected    = $true;
        FailMessage = "AWS EBS CSI Driver addon is not installed, preventing encryption of EBS volumes, proper volume management, and potentially forcing use of deprecated in-tree volume plugins with security limitations.";
        Severity    = "Medium";
        Recommendation = "Install AWS EBS CSI Driver addon using 'aws eks create-addon --cluster-name <cluster> --addon-name aws-ebs-csi-driver'. This enables EBS volume encryption, snapshots, and modern storage management with proper IAM integration.";
        URL         = "https://docs.aws.amazon.com/eks/latest/userguide/ebs-csi.html";
    },
    @{
        ID          = "EKSSEC007";
        Category    = "Security";
        Name        = "Restricted Security Groups";
        Value       = { 
            $sgId = $clusterInfo.ResourcesVpcConfig.ClusterSecurityGroupId
            $sg = aws ec2 describe-security-groups --group-ids $sgId --query 'SecurityGroups[0]' --output json | ConvertFrom-Json
            $openRules = $sg.IpPermissions | Where-Object { 
                $_.IpRanges | Where-Object { $_.CidrIp -eq "0.0.0.0/0" }
            }
            $openRules.Count -eq 0
        };
        Expected    = $true;
        FailMessage = "EKS cluster security groups contain overly permissive rules allowing unrestricted access (0.0.0.0/0), creating potential attack vectors and violating network security best practices.";
        Severity    = "High";
        Recommendation = "Review and restrict security group rules to allow only necessary traffic from specific CIDR blocks. Use 'aws ec2 describe-security-groups --group-ids <sg-id>' to audit rules and 'aws ec2 revoke-security-group-ingress' to remove overly permissive rules.";
        URL         = "https://docs.aws.amazon.com/eks/latest/userguide/sec-group-reqs.html";
    },
    @{
        ID          = "EKSSEC008";
        Category    = "Security";
        Name        = "CloudTrail Logging Enabled";
        Value       = { 
            # Check if CloudTrail is enabled for the region/account
            # This requires additional AWS API calls - placeholder for now
            $false
        };
        Expected    = $true;
        FailMessage = "AWS CloudTrail is not enabled for the region, preventing audit logging of API calls, security events, and administrative actions. This limits incident response capabilities and compliance monitoring.";
        Severity    = "Medium";
        Recommendation = "Enable AWS CloudTrail for comprehensive audit logging using 'aws cloudtrail create-trail --name eks-audit-trail --s3-bucket-name <bucket>' and ensure EKS control plane logging is enabled with 'aws eks update-cluster-config --logging enable=api,audit,authenticator,controllerManager,scheduler'.";
        URL         = "https://docs.aws.amazon.com/eks/latest/userguide/control-plane-logs.html";
    }
)