$bestPracticesChecks = @(
    @{
        ID         = "EKSBP001";
        Category   = "Best Practices";
        Name       = "Container Image Scanning Enabled";
        Value      = { 
            # Check if ECR image scanning is configured for repositories
            $ecrRepos = aws ecr describe-repositories --query 'repositories[?imageScanningConfiguration.scanOnPush==`true`]' --output json 2>/dev/null | ConvertFrom-Json
            $ecrRepos.Count -gt 0
        };
        Expected   = $true;
        FailMessage = "Container image vulnerability scanning is not enabled in ECR repositories, leaving potential security vulnerabilities in container images undetected and increasing the risk of deploying compromised workloads.";
        Severity    = "High";
        Recommendation = "Enable image scanning in ECR repositories using 'aws ecr put-image-scanning-configuration --repository-name <repo> --image-scanning-configuration scanOnPush=true'. Consider implementing admission controllers to prevent deployment of images with high-severity vulnerabilities.";
        URL         = "https://docs.aws.amazon.com/AmazonECR/latest/userguide/image-scanning.html";
    },
    @{
        ID         = "EKSBP002";
        Category   = "Best Practices";
        Name       = "Resource Quotas Implemented";
        Value      = { 
            $resourceQuotas = kubectl get resourcequota --all-namespaces -o json 2>/dev/null | ConvertFrom-Json
            $resourceQuotas.items.Count -gt 0
        };
        Expected   = $true;
        FailMessage = "Resource quotas are not configured for namespaces, allowing unlimited resource consumption that could lead to resource exhaustion, noisy neighbor problems, and potential cluster instability.";
        Severity    = "Medium";
        Recommendation = "Implement ResourceQuota objects in namespaces to limit CPU, memory, and storage consumption. Use 'kubectl create quota <name> --hard=cpu=2,memory=4Gi,pods=10' to set appropriate limits based on application requirements and cluster capacity.";
        URL         = "https://kubernetes.io/docs/concepts/policy/resource-quotas/";
    },
    @{
        ID         = "EKSBP003";
        Category   = "Best Practices";
        Name       = "Pod Disruption Budgets Configured";
        Value      = { 
            $podDisruptionBudgets = kubectl get poddisruptionbudget --all-namespaces -o json 2>/dev/null | ConvertFrom-Json
            $podDisruptionBudgets.items.Count -gt 0
        };
        Expected   = $true;
        FailMessage = "Pod Disruption Budgets are not configured, meaning voluntary disruptions (like node draining during upgrades) could potentially take down all replicas of critical applications simultaneously.";
        Severity    = "Medium";
        Recommendation = "Create PodDisruptionBudget resources for critical applications using 'kubectl create pdb <name> --selector=app=<app> --min-available=1' to ensure minimum availability during voluntary disruptions like cluster upgrades.";
        URL         = "https://kubernetes.io/docs/tasks/run-application/configure-pdb/";
    },
    @{
        ID         = "EKSBP004";
        Category   = "Best Practices";
        Name       = "Horizontal Pod Autoscaler Active";
        Value      = { 
            $hpas = kubectl get hpa --all-namespaces -o json 2>/dev/null | ConvertFrom-Json
            $hpas.items.Count -gt 0
        };
        Expected   = $true;
        FailMessage = "Horizontal Pod Autoscaler (HPA) is not configured for applications, missing opportunities for automatic scaling based on demand and potentially leading to poor resource utilization or application performance issues.";
        Severity    = "Low";
        Recommendation = "Configure HPA for applications that can benefit from horizontal scaling using 'kubectl autoscale deployment <name> --cpu-percent=50 --min=1 --max=10'. Ensure metrics-server addon is installed for CPU/memory-based scaling.";
        URL         = "https://docs.aws.amazon.com/eks/latest/userguide/horizontal-pod-autoscaler.html";
    },
    @{
        ID         = "EKSBP005";
        Category   = "Best Practices";
        Name       = "Cluster Autoscaler Configured";
        Value      = { 
            $clusterAutoscaler = kubectl get deployment cluster-autoscaler -n kube-system -o json 2>/dev/null | ConvertFrom-Json
            $clusterAutoscaler -ne $null
        };
        Expected   = $true;
        FailMessage = "Cluster Autoscaler is not deployed, preventing automatic scaling of worker nodes based on pod resource demands, potentially leading to pod scheduling failures or unnecessary costs from oversized clusters.";
        Severity    = "Medium";
        Recommendation = "Deploy Cluster Autoscaler using the AWS documentation or Helm chart. Ensure node groups have proper autoscaling groups tags and IAM permissions. Configure with 'kubectl apply -f https://raw.githubusercontent.com/kubernetes/autoscaler/master/cluster-autoscaler/cloudprovider/aws/examples/cluster-autoscaler-autodiscover.yaml'.";
        URL         = "https://docs.aws.amazon.com/eks/latest/userguide/cluster-autoscaler.html";
    },
    @{
        ID         = "EKSBP006";
        Category   = "Best Practices";
        Name       = "Multi-AZ Node Distribution";
        Value      = { 
            $nodeGroups = $clusterInfo.NodeGroups
            $multiAZ = $false
            foreach ($ng in $nodeGroups) {
                if ($ng.Subnets.Count -gt 1) { $multiAZ = $true }
            }
            $multiAZ
        };
        Expected   = $true;
        FailMessage = "Node groups are not distributed across multiple Availability Zones, creating a single point of failure and reducing cluster resilience against AZ-level outages.";
        Severity    = "High";
        Recommendation = "Configure node groups to span multiple AZs by specifying subnets from different zones during creation. Use 'aws eks create-nodegroup --subnets subnet-abc,subnet-def,subnet-ghi' where subnets are in different AZs for high availability.";
        URL         = "https://docs.aws.amazon.com/eks/latest/userguide/managed-node-groups.html";
    },
    @{
        ID         = "EKSBP007";
        Category   = "Best Practices";
        Name       = "Workload Right-sizing";
        Value      = { 
            # Check if workloads have resource requests and limits set
            $deployments = kubectl get deployments --all-namespaces -o json 2>/dev/null | ConvertFrom-Json
            $properlyConfigured = 0
            $total = 0
            foreach ($deployment in $deployments.items) {
                $total++
                $containers = $deployment.spec.template.spec.containers
                $hasResourceConfig = $true
                foreach ($container in $containers) {
                    if (-not $container.resources.requests -or -not $container.resources.limits) {
                        $hasResourceConfig = $false
                    }
                }
                if ($hasResourceConfig) { $properlyConfigured++ }
            }
            if ($total -gt 0) { ($properlyConfigured / $total) -gt 0.5 } else { $false }
        };
        Expected   = $true;
        FailMessage = "Many workloads lack proper resource requests and limits configuration, leading to poor resource utilization, potential node resource exhaustion, and unpredictable application performance.";
        Severity    = "Medium";
        Recommendation = "Configure resource requests and limits for all containers. Set requests based on actual usage and limits to prevent resource abuse. Use tools like VPA (Vertical Pod Autoscaler) to get recommendations for appropriate resource settings.";
        URL         = "https://kubernetes.io/docs/concepts/configuration/manage-resources-containers/";
    },
    @{
        ID         = "EKSBP008";
        Category   = "Best Practices";
        Name       = "Application Health Checks";
        Value      = { 
            # Check if deployments have liveness and readiness probes
            $deployments = kubectl get deployments --all-namespaces -o json 2>/dev/null | ConvertFrom-Json
            $withHealthChecks = 0
            $total = 0
            foreach ($deployment in $deployments.items) {
                $total++
                $containers = $deployment.spec.template.spec.containers
                $hasProbes = $true
                foreach ($container in $containers) {
                    if (-not $container.livenessProbe -or -not $container.readinessProbe) {
                        $hasProbes = $false
                    }
                }
                if ($hasProbes) { $withHealthChecks++ }
            }
            if ($total -gt 0) { ($withHealthChecks / $total) -gt 0.5 } else { $false }
        };
        Expected   = $true;
        FailMessage = "Applications lack proper health check configuration (liveness and readiness probes), preventing Kubernetes from automatically detecting and recovering from application failures.";
        Severity    = "High";
        Recommendation = "Configure liveness and readiness probes for all application containers. Liveness probes should check if the application is running, readiness probes should verify if the application is ready to serve requests. Use HTTP, TCP, or exec probes as appropriate.";
        URL         = "https://kubernetes.io/docs/tasks/configure-pod-container/configure-liveness-readiness-startup-probes/";
    },
    @{
        ID         = "EKSBP009";
        Category   = "Best Practices";
        Name       = "Secrets Management";
        Value      = { 
            # Check if AWS Secrets Store CSI Driver is installed
            $secretsStore = kubectl get daemonset secrets-store-csi-driver -n kube-system -o json 2>/dev/null | ConvertFrom-Json
            $awsProvider = kubectl get daemonset secrets-store-csi-driver-provider-aws -n kube-system -o json 2>/dev/null | ConvertFrom-Json
            $secretsStore -and $awsProvider
        };
        Expected   = $true;
        FailMessage = "AWS Secrets Store CSI Driver is not installed, missing integration with AWS Secrets Manager and Parameter Store for secure secrets management, potentially leading to secrets stored as plain Kubernetes secrets.";
        Severity    = "Medium";
        Recommendation = "Install AWS Secrets Store CSI Driver to integrate with AWS Secrets Manager and Parameter Store. Use 'kubectl apply -f https://raw.githubusercontent.com/aws/secrets-store-csi-driver-provider-aws/main/deployment/aws-provider-installer.yaml' and configure SecretProviderClass for your applications.";
        URL         = "https://docs.aws.amazon.com/secretsmanager/latest/userguide/integrating_csi_driver.html";
    }
)