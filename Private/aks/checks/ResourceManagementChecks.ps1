$resourceManagementChecks = @(
    @{
        ID          = "RES001";
        Category    = "Resource Management";
        Name        = "Cluster Autoscaler";
        Value       = { $clusterInfo.autoScalerProfile -ne $null };
        Expected    = $true;
        FailMessage = "Cluster Autoscaler is not enabled, leading to potential resource inefficiencies and over-provisioning.";
        Severity    = "Medium";
        Recommendation = "Enable Cluster Autoscaler to automatically scale nodes up or down based on demand, improving cost efficiency and resource utilization.";
        URL         = "https://learn.microsoft.com/azure/aks/cluster-autoscaler";
    },
    @{
        ID             = "RES002";
        Category       = "Resource Management";
        Name           = "AKS Built-in Cost Tooling Enabled";
        Value          = { $clusterInfo.metricsProfile.costAnalysis.enabled };
        Expected       = $true;
        FailMessage    = "AKS built-in cost tooling (Open Costs) is not enabled, making cost allocation and optimization harder.";
        Severity       = "Medium";
        Recommendation = "Enable cost analysis in the AKS metrics profile to gain insights into resource spending and optimize cost management.";
        URL            = "https://learn.microsoft.com/azure/aks/cost-analysis";
    },
    @{
        ID             = "RES003";
        Category       = "Resource Management";
        Name           = "Vertical Pod Autoscaler (VPA) is enabled";
        Value          = { $clusterInfo.workloadAutoScalerProfile.verticalPodAutoscaler.enabled };
        Expected       = $true;
        FailMessage    = "Vertical Pod Autoscaler (VPA) is not enabled. Without VPA, pods won't automatically adjust CPU and memory based on usage.";
        Severity       = "Medium";
        Recommendation = "Enable Vertical Pod Autoscaler to automatically adjust pod resource requests based on historical usage.";
        URL            = "https://learn.microsoft.com/azure/aks/vertical-pod-autoscaler";
    }    
)
