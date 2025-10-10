# EKS Mock Data Generator for Testing
# This script creates realistic EKS cluster data for testing KubeBuddy checks

function New-MockEKSClusterData {
    param(
        [string]$ClusterName = "test-eks-cluster",
        [string]$Region = "us-west-2",
        [switch]$IncludeIssues # Include common configuration issues for testing
    )

    $mockData = @{
        EksCluster = @{
            Name = $ClusterName
            Arn = "arn:aws:eks:$Region:123456789012:cluster/$ClusterName"
            CreatedAt = (Get-Date).AddDays(-30)
            Version = "1.28"
            Status = "ACTIVE"
            Endpoint = @{
                PrivateAccess = if ($IncludeIssues) { $false } else { $true }
                PublicAccess = if ($IncludeIssues) { $true } else { $false }
                PublicAccessCidrs = if ($IncludeIssues) { @("0.0.0.0/0") } else { @("10.0.0.0/8") }
            }
            ResourcesVpcConfig = @{
                VpcId = "vpc-12345678"
                SubnetIds = @("subnet-12345678", "subnet-87654321", "subnet-11111111")
                SecurityGroupIds = @("sg-12345678")
                ClusterSecurityGroupId = "sg-cluster123"
            }
            Logging = @{
                ClusterLogging = @(
                    @{ Types = @("api", "audit"); Enabled = if ($IncludeIssues) { $false } else { $true } },
                    @{ Types = @("authenticator"); Enabled = $true },
                    @{ Types = @("controllerManager", "scheduler"); Enabled = $false }
                )
            }
            Identity = @{
                Oidc = @{
                    Issuer = if ($IncludeIssues) { $null } else { "https://oidc.eks.$Region.amazonaws.com/id/EXAMPLED539D4633E53DE1B716D3041E" }
                }
            }
            EncryptionConfig = if ($IncludeIssues) { 
                @() 
            } else { 
                @(@{
                    Resources = @("secrets")
                    Provider = @{
                        KeyArn = "arn:aws:kms:$Region:123456789012:key/12345678-1234-1234-1234-123456789012"
                    }
                })
            }
            RoleArn = "arn:aws:iam::123456789012:role/eks-cluster-role"
            PlatformVersion = "eks.1"
            
            # Node Groups
            NodeGroups = @(
                @{
                    NodegroupName = "worker-nodes"
                    NodeRole = "arn:aws:iam::123456789012:role/eks-node-role"
                    ScalingConfig = @{
                        MinSize = 1
                        MaxSize = if ($IncludeIssues) { 1 } else { 5 }
                        DesiredSize = 2
                    }
                    InstanceTypes = @("t3.medium")
                    CapacityType = if ($IncludeIssues) { "ON_DEMAND" } else { "SPOT" }
                    Subnets = @("subnet-12345678", "subnet-87654321")
                    AmiType = "AL2_x86_64"
                    Version = "1.28"
                },
                @{
                    NodegroupName = "system-nodes"
                    NodeRole = "arn:aws:iam::123456789012:role/eks-node-role"
                    ScalingConfig = @{
                        MinSize = 1
                        MaxSize = 3
                        DesiredSize = 1
                    }
                    InstanceTypes = @("t3.small")
                    CapacityType = "ON_DEMAND"
                    Subnets = @("subnet-12345678")
                    AmiType = "AL2_x86_64"
                    Version = "1.28"
                }
            )
            
            # Addons
            Addons = @(
                @{
                    AddonName = "vpc-cni"
                    AddonVersion = "v1.15.1-eksbuild.1"
                    Status = "ACTIVE"
                },
                @{
                    AddonName = "coredns"
                    AddonVersion = "v1.10.1-eksbuild.1"
                    Status = "ACTIVE"
                },
                @{
                    AddonName = "kube-proxy"
                    AddonVersion = "v1.28.1-eksbuild.1"
                    Status = "ACTIVE"
                }
            )
            
            # Fargate Profiles
            FargateProfiles = @()
            
            # VPC Information
            Vpc = @{
                VpcId = "vpc-12345678"
                CidrBlock = "10.0.0.0/16"
                State = "available"
            }
            
            Subnets = @(
                @{
                    SubnetId = "subnet-12345678"
                    AvailabilityZone = "$Region" + "a"
                    CidrBlock = "10.0.1.0/24"
                    VpcId = "vpc-12345678"
                    MapPublicIpOnLaunch = $false
                },
                @{
                    SubnetId = "subnet-87654321"
                    AvailabilityZone = "$Region" + "b"
                    CidrBlock = "10.0.2.0/24"
                    VpcId = "vpc-12345678"
                    MapPublicIpOnLaunch = $false
                },
                @{
                    SubnetId = "subnet-11111111"
                    AvailabilityZone = "$Region" + "c"
                    CidrBlock = "10.0.3.0/24"
                    VpcId = "vpc-12345678"
                    MapPublicIpOnLaunch = $false
                }
            )
            
            SecurityGroups = @(
                @{
                    GroupId = "sg-12345678"
                    GroupName = "eks-cluster-sg-$ClusterName"
                    VpcId = "vpc-12345678"
                }
            )
            
            # IAM Role Information
            ClusterRole = @{
                RoleName = "eks-cluster-role"
                AssumeRolePolicyDocument = '{\"Version\":\"2012-10-17\",\"Statement\":[{\"Effect\":\"Allow\",\"Principal\":{\"Service\":\"eks.amazonaws.com\"},\"Action\":\"sts:AssumeRole\"}]}'
            }
            
            NodeGroupRoles = @(
                @{
                    NodeGroup = "worker-nodes"
                    Role = @{
                        RoleName = "eks-node-role"
                        AssumeRolePolicyDocument = '{\"Version\":\"2012-10-17\",\"Statement\":[{\"Effect\":\"Allow\",\"Principal\":{\"Service\":\"ec2.amazonaws.com\"},\"Action\":\"sts:AssumeRole\"}]}'
                    }
                }
            )
            
            # OIDC Provider
            OidcProvider = if ($IncludeIssues) { 
                $null 
            } else { 
                @{
                    Url = "https://oidc.eks.$Region.amazonaws.com/id/EXAMPLED539D4633E53DE1B716D3041E"
                    CreateDate = (Get-Date).AddDays(-30)
                }
            }
            
            # ECR Repositories
            EcrRepositories = @(
                @{
                    RepositoryName = "my-app"
                    ImageScanningConfiguration = @{
                        ScanOnPush = if ($IncludeIssues) { $false } else { $true }
                    }
                },
                @{
                    RepositoryName = "nginx"
                    ImageScanningConfiguration = @{
                        ScanOnPush = $true
                    }
                }
            )
            
            # CloudTrail
            CloudTrails = if ($IncludeIssues) { 
                @() 
            } else { 
                @(
                    @{
                        Name = "management-trail"
                        IncludeGlobalServiceEvents = $true
                        IsMultiRegionTrail = $true
                        IsLogging = $true
                    }
                )
            }
        }
        
        # Kubernetes Constraints (OPA Gatekeeper)
        Constraints = @()
        ConstraintTemplates = @()
    }
    
    # Add EBS CSI Driver if not including issues
    if (-not $IncludeIssues) {
        $mockData.EksCluster.Addons += @{
            AddonName = "aws-ebs-csi-driver"
            AddonVersion = "v1.24.0-eksbuild.1"
            Status = "ACTIVE"
        }
    }
    
    return $mockData
}

function Test-EKSChecksWithMockData {
    param(
        [switch]$WithIssues,
        [switch]$Verbose
    )
    
    Write-Host "🧪 Testing EKS Checks with Mock Data" -ForegroundColor Cyan
    Write-Host "=====================================" -ForegroundColor Cyan
    
    # Generate mock data
    $mockData = New-MockEKSClusterData -IncludeIssues:$WithIssues
    
    # Load EKS functions
    $eksModulePath = Join-Path $PSScriptRoot "eks-functions.ps1"
    if (Test-Path $eksModulePath) {
        . $eksModulePath
    } else {
        Write-Error "EKS functions not found at $eksModulePath"
        return
    }
    
    try {
        # Simulate the check execution
        Write-Host "📊 Running EKS Best Practices Checks..." -ForegroundColor Yellow
        
        # Use the mock data as if it came from Get-KubeData
        $results = Invoke-EKSBestPractices -Region "us-west-2" -ClusterName "test-cluster" -KubeData $mockData -FailedOnly:$WithIssues
        
        if ($Verbose) {
            Write-Host "`n📋 Test Results:" -ForegroundColor Green
            $results | ConvertTo-Json -Depth 10 | Write-Host
        }
        
        Write-Host "✅ EKS checks test completed successfully!" -ForegroundColor Green
        return $results
    }
    catch {
        Write-Error "❌ Test failed: $($_.Exception.Message)"
        if ($Verbose) {
            Write-Host "Stack trace: $($_.ScriptStackTrace)" -ForegroundColor Red
        }
    }
}

# Example usage:
# Test with a healthy cluster configuration
# Test-EKSChecksWithMockData

# Test with common issues to see failing checks
# Test-EKSChecksWithMockData -WithIssues -Verbose