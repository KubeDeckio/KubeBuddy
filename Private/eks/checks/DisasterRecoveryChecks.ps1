$disasterRecoveryChecks = @(
    @{
        ID         = "EKSDR001";
        Category   = "Disaster Recovery";
        Name       = "Multi-AZ Cluster Configuration";
        Value      = { 
            $subnets = $clusterInfo.ResourcesVpcConfig.SubnetIds
            # Get unique AZs from subnets (simplified check)
            $uniqueAZs = @()
            foreach ($subnet in $subnets) {
                $subnetInfo = aws ec2 describe-subnets --subnet-ids $subnet --query 'Subnets[0].AvailabilityZone' --output text 2>/dev/null
                if ($subnetInfo -and $uniqueAZs -notcontains $subnetInfo) {
                    $uniqueAZs += $subnetInfo
                }
            }
            $uniqueAZs.Count -ge 2
        };
        Expected   = $true;
        FailMessage = "EKS cluster is not distributed across multiple Availability Zones, creating a single point of failure and reducing resilience against AZ-level outages that could cause complete service disruption.";
        Severity    = "High";
        Recommendation = "Configure cluster across at least 2-3 Availability Zones by specifying subnets from different AZs. This ensures high availability and fault tolerance. Update cluster configuration to include subnets from multiple AZs using 'aws eks update-cluster-config'.";
        URL         = "https://docs.aws.amazon.com/eks/latest/userguide/cluster-endpoint.html";
    },
    @{
        ID         = "EKSDR002";
        Category   = "Disaster Recovery";
        Name       = "Backup Strategy Implementation";
        Value      = { 
            # Check for Velero or other backup solutions
            $velero = kubectl get namespace velero -o json 2>/dev/null | ConvertFrom-Json
            $backupJobs = kubectl get cronjob --all-namespaces -o json 2>/dev/null | ConvertFrom-Json
            $backupJobs = $backupJobs.items | Where-Object { $_.metadata.name -match "backup|velero" }
            
            $velero -or ($backupJobs.Count -gt 0)
        };
        Expected   = $true;
        FailMessage = "No backup strategy is implemented for cluster state and persistent data, risking complete data loss in case of cluster failure, accidental deletion, or corruption scenarios.";
        Severity    = "High";
        Recommendation = "Implement Velero for cluster backup and restore capabilities using 'kubectl apply -f https://github.com/vmware-tanzu/velero/releases/latest/download/velero-v1.x.x-linux-amd64.tar.gz'. Configure regular backups of namespaces, persistent volumes, and cluster resources.";
        URL         = "https://velero.io/docs/v1.12/basic-install/";
    },
    @{
        ID         = "EKSDR003";
        Category   = "Disaster Recovery";
        Name       = "Cross-Region Recovery Plan";
        Value      = { 
            # Check if cluster configuration is documented or templated
            $infraAsCode = Test-Path "*.tf" -PathType Leaf
            $cloudFormation = Test-Path "*.yaml" -PathType Leaf -or Test-Path "*.yml" -PathType Leaf
            $eksctl = Test-Path "eksctl.yaml" -PathType Leaf
            
            $infraAsCode -or $cloudFormation -or $eksctl
        };
        Expected   = $true;
        FailMessage = "Infrastructure as Code templates are not available for cross-region disaster recovery, making it difficult to quickly recreate the cluster configuration in a different region during major outages.";
        Severity    = "Medium";
        Recommendation = "Document cluster configuration using Infrastructure as Code tools like Terraform, CloudFormation, or eksctl configuration files. Store these in version control and test deployment in secondary regions periodically.";
        URL         = "https://docs.aws.amazon.com/eks/latest/userguide/eksctl.html";
    },
    @{
        ID         = "EKSDR004";
        Category   = "Disaster Recovery";
        Name       = "Application Data Backup";
        Value      = { 
            # Check for persistent volume snapshots or backup configurations
            $volumeSnapshotClass = kubectl get volumesnapshotclass -o json 2>/dev/null | ConvertFrom-Json
            $volumeSnapshots = kubectl get volumesnapshot --all-namespaces -o json 2>/dev/null | ConvertFrom-Json
            
            $volumeSnapshotClass.items.Count -gt 0 -or $volumeSnapshots.items.Count -gt 0
        };
        Expected   = $true;
        FailMessage = "Application data backup mechanisms are not configured through volume snapshots or other methods, risking data loss for stateful applications during storage failures or corruption.";
        Severity    = "High";
        Recommendation = "Configure EBS volume snapshots using VolumeSnapshotClass and regular VolumeSnapshot resources. Install snapshot controller and configure automated backup schedules. Use 'kubectl apply -f https://raw.githubusercontent.com/kubernetes-csi/external-snapshotter/master/deploy/kubernetes/snapshot-controller/rbac-snapshot-controller.yaml'.";
        URL         = "https://docs.aws.amazon.com/eks/latest/userguide/csi-snapshot-controller.html";
    },
    @{
        ID         = "EKSDR005";
        Category   = "Disaster Recovery";
        Name       = "Cluster Version Upgrade Strategy";
        Value      = { 
            # Check if cluster is not on a deprecated version
            $clusterVersion = $clusterInfo.Version
            $majorMinor = $clusterVersion.Split('.')[0..1] -join '.'
            # Check if not on very old versions (this is a simplified check)
            $majorMinor -notmatch "1\.19|1\.20|1\.21"
        };
        Expected   = $true;
        FailMessage = "Cluster is running on an outdated Kubernetes version that may be approaching end-of-support, lacking security patches and new features, and potentially blocking future upgrade paths.";
        Severity    = "Medium";
        Recommendation = "Develop a regular upgrade strategy and keep cluster within 2-3 versions of the latest supported version. Test upgrades in non-production environments first. Use 'aws eks update-cluster-version --name <cluster> --kubernetes-version <version>' for upgrades.";
        URL         = "https://docs.aws.amazon.com/eks/latest/userguide/update-cluster.html";
    },
    @{
        ID         = "EKSDR006";
        Category   = "Disaster Recovery";
        Name       = "Network Redundancy";
        Value      = { 
            # Check if cluster has multiple subnets across AZs (network redundancy)
            $subnetIds = $clusterInfo.ResourcesVpcConfig.SubnetIds
            $subnetIds.Count -ge 3 # At least 3 subnets for good redundancy
        };
        Expected   = $true;
        FailMessage = "Network redundancy is insufficient with too few subnets configured, increasing the risk of connectivity issues and reducing fault tolerance against network infrastructure failures.";
        Severity    = "Medium";
        Recommendation = "Configure cluster with multiple subnets across different Availability Zones for network redundancy. Use at least 3 subnets (preferably 6: 3 public, 3 private) across different AZs to ensure high availability and fault tolerance.";
        URL         = "https://docs.aws.amazon.com/eks/latest/userguide/network_reqs.html";
    },
    @{
        ID         = "EKSDR007";
        Category   = "Disaster Recovery";
        Name       = "Recovery Testing Procedures";
        Value      = { 
            # Check for chaos engineering or disaster recovery testing tools
            $chaosMonkey = kubectl get deployment chaos-monkey -o json 2>/dev/null | ConvertFrom-Json
            $litmus = kubectl get namespace litmus -o json 2>/dev/null | ConvertFrom-Json
            $chaosEngineering = kubectl get chaosengine --all-namespaces -o json 2>/dev/null | ConvertFrom-Json
            
            $chaosMonkey -or $litmus -or ($chaosEngineering.items.Count -gt 0)
        };
        Expected   = $true;
        FailMessage = "Disaster recovery procedures are not being regularly tested through chaos engineering or automated testing, leaving uncertainty about the actual effectiveness of recovery plans during real incidents.";
        Severity    = "Low";
        Recommendation = "Implement regular disaster recovery testing using chaos engineering tools like Litmus, Gremlin, or custom scripts. Test scenarios like node failures, network partitions, and service outages. Document and automate recovery procedures.";
        URL         = "https://litmuschaos.io/";
    },
    @{
        ID         = "EKSDR008";
        Category   = "Disaster Recovery";
        Name       = "RTO/RPO Documentation";
        Value      = { 
            # Check if disaster recovery documentation exists (simplified check)
            $drDocs = Test-Path "*disaster*" -PathType Leaf
            $recoveryDocs = Test-Path "*recovery*" -PathType Leaf
            $runbooks = Test-Path "*runbook*" -PathType Leaf
            
            $drDocs -or $recoveryDocs -or $runbooks
        };
        Expected   = $true;
        FailMessage = "Recovery Time Objective (RTO) and Recovery Point Objective (RPO) are not documented, making it difficult to meet business continuity requirements and properly plan disaster recovery capabilities.";
        Severity    = "Medium";
        Recommendation = "Document RTO/RPO requirements for different applications and services. Create detailed runbooks for disaster recovery scenarios including step-by-step recovery procedures, contact information, and escalation paths. Store documentation in accessible locations.";
        URL         = "https://docs.aws.amazon.com/whitepapers/latest/disaster-recovery-workloads-on-aws/disaster-recovery-options-in-the-cloud.html";
    }
)