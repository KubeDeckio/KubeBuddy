$resourceManagementChecks = @(
    @{
        ID         = "EKSRES001";
        Category   = "Resource Management";
        Name       = "Appropriate Instance Types Selected";
        Value      = { 
            $nodeGroups = $clusterInfo.NodeGroups
            $appropriateTypes = $true
            foreach ($ng in $nodeGroups) {
                # Check for overly expensive or inappropriate instance types
                if ($ng.InstanceTypes -match "\.large|\.xlarge|\.2xlarge" -and $ng.InstanceTypes -notmatch "t3\.|t2\.|m5\.|m5a\.|c5\.|c5n\.") {
                    $appropriateTypes = $false
                }
            }
            $appropriateTypes
        };
        Expected   = $true;
        FailMessage = "Node groups are using potentially oversized or inappropriate instance types that may not be cost-effective for the workload requirements, leading to unnecessary infrastructure costs.";
        Severity    = "Medium";
        Recommendation = "Review instance type selection based on workload requirements. Use burstable instances (t3/t2) for variable workloads, compute-optimized (c5) for CPU-intensive tasks, and general-purpose (m5) for balanced workloads. Consider using mixed instance types in node groups.";
        URL         = "https://docs.aws.amazon.com/eks/latest/userguide/choosing-instance-type.html";
    },
    @{
        ID         = "EKSRES002";
        Category   = "Resource Management";
        Name       = "EBS CSI Driver Configured";
        Value      = { 
            $ebsCSI = $clusterInfo.Addons | Where-Object { $_.AddonName -eq "aws-ebs-csi-driver" }
            $ebsCSI -ne $null
        };
        Expected   = $true;
        FailMessage = "Amazon EBS CSI driver is not installed as an addon, preventing applications from using EBS volumes for persistent storage and limiting storage options for stateful workloads.";
        Severity    = "High";
        Recommendation = "Install EBS CSI driver addon using 'aws eks create-addon --cluster-name <cluster> --addon-name aws-ebs-csi-driver' and ensure the driver's service account has proper IAM permissions for EBS management.";
        URL         = "https://docs.aws.amazon.com/eks/latest/userguide/ebs-csi.html";
    },
    @{
        ID         = "EKSRES003";
        Category   = "Resource Management";
        Name       = "Storage Classes Defined";
        Value      = { 
            $storageClasses = kubectl get storageclass -o json 2>/dev/null | ConvertFrom-Json
            $storageClasses.items.Count -gt 1 # More than just the default
        };
        Expected   = $true;
        FailMessage = "Limited storage class options are available, potentially forcing applications to use inappropriate storage types and missing opportunities for cost optimization or performance tuning.";
        Severity    = "Medium";
        Recommendation = "Create multiple storage classes for different use cases: high-performance SSD (gp3), cost-effective storage (gp2), and high-IOPS storage (io1/io2). Define storage classes with 'kubectl apply -f storage-class.yaml' for various performance and cost requirements.";
        URL         = "https://kubernetes.io/docs/concepts/storage/storage-classes/";
    },
    @{
        ID         = "EKSRES004";
        Category   = "Resource Management";
        Name       = "Persistent Volume Management";
        Value      = { 
            $pvs = kubectl get pv -o json 2>/dev/null | ConvertFrom-Json
            $pvcs = kubectl get pvc --all-namespaces -o json 2>/dev/null | ConvertFrom-Json
            # Check if there are orphaned PVs or proper retention policies
            $orphanedPVs = $pvs.items | Where-Object { $_.status.phase -eq "Available" }
            $orphanedPVs.Count -eq 0
        };
        Expected   = $true;
        FailMessage = "Persistent volumes are not being properly managed, with orphaned volumes consuming unnecessary storage costs or retention policies that may not align with data protection requirements.";
        Severity    = "Medium";
        Recommendation = "Implement proper PV lifecycle management with appropriate retention policies. Use 'Retain' for critical data and 'Delete' for temporary storage. Monitor and clean up orphaned volumes regularly using scripts or automation.";
        URL         = "https://kubernetes.io/docs/concepts/storage/persistent-volumes/";
    },
    @{
        ID         = "EKSRES005";
        Category   = "Resource Management";
        Name       = "Node Group Scaling Configuration";
        Value      = { 
            $nodeGroups = $clusterInfo.NodeGroups
            $properScaling = $true
            foreach ($ng in $nodeGroups) {
                $scaling = $ng.ScalingConfig
                if ($scaling.MaxSize -eq $scaling.MinSize -or $scaling.MaxSize -gt ($scaling.MinSize * 5)) {
                    $properScaling = $false
                }
            }
            $properScaling
        };
        Expected   = $true;
        FailMessage = "Node group autoscaling is not properly configured, either preventing scaling flexibility or allowing excessive scaling that could lead to unexpected costs or resource constraints.";
        Severity    = "Medium";
        Recommendation = "Configure node group autoscaling with appropriate min/max values based on workload patterns. Set min for baseline capacity and max to control costs. Use a reasonable ratio (e.g., max = 2-3x min) to balance scalability and cost control.";
        URL         = "https://docs.aws.amazon.com/eks/latest/userguide/managed-node-groups.html";
    },
    @{
        ID         = "EKSRES006";
        Category   = "Resource Management";
        Name       = "Spot Instance Utilization";
        Value      = { 
            $nodeGroups = $clusterInfo.NodeGroups
            $hasSpotInstances = $false
            foreach ($ng in $nodeGroups) {
                if ($ng.CapacityType -eq "SPOT") {
                    $hasSpotInstances = $true
                }
            }
            $hasSpotInstances
        };
        Expected   = $true;
        FailMessage = "Spot instances are not being utilized for cost optimization, missing potential savings of 50-90% for fault-tolerant workloads and non-critical applications.";
        Severity    = "Low";
        Recommendation = "Consider using spot instances for appropriate workloads by creating node groups with capacity type 'SPOT'. Implement node affinity and tolerations for spot-appropriate applications. Use mixed capacity types for balanced cost and availability.";
        URL         = "https://docs.aws.amazon.com/eks/latest/userguide/managed-node-groups.html#managed-node-group-capacity-types";
    },
    @{
        ID         = "EKSRES007";
        Category   = "Resource Management";
        Name       = "Resource Limits Enforcement";
        Value      = { 
            # Check if LimitRanges are configured
            $limitRanges = kubectl get limitrange --all-namespaces -o json 2>/dev/null | ConvertFrom-Json
            $limitRanges.items.Count -gt 0
        };
        Expected   = $true;
        FailMessage = "LimitRange objects are not configured to enforce resource constraints, allowing individual containers or pods to consume excessive resources and potentially impact cluster stability.";
        Severity    = "Medium";
        Recommendation = "Create LimitRange objects in namespaces to enforce default and maximum resource limits for containers and pods. Use 'kubectl create limitrange <name> --default=cpu=100m,memory=128Mi --max=cpu=1,memory=1Gi' to set appropriate boundaries.";
        URL         = "https://kubernetes.io/docs/concepts/policy/limit-range/";
    },
    @{
        ID         = "EKSRES008";
        Category   = "Resource Management";
        Name       = "Cost Monitoring Implementation";
        Value      = { 
            # Check if cost allocation tags are properly configured
            $nodeGroups = $clusterInfo.NodeGroups
            $properlyTagged = $true
            foreach ($ng in $nodeGroups) {
                if (-not $ng.Tags -or $ng.Tags.Count -lt 2) {
                    $properlyTagged = $false
                }
            }
            $properlyTagged
        };
        Expected   = $true;
        FailMessage = "Cost allocation tags are not properly configured on resources, making it difficult to track and optimize Kubernetes infrastructure costs across different teams, applications, or environments.";
        Severity    = "Low";
        Recommendation = "Implement comprehensive tagging strategy for all EKS resources including cluster, node groups, and associated resources. Use tags for cost center, environment, team, and application identification. Enable cost allocation tags in AWS Billing console.";
        URL         = "https://docs.aws.amazon.com/awsaccountbilling/latest/aboutv2/cost-alloc-tags.html";
    }
)