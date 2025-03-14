$resourceManagementChecks = @(
    @{
        ID          = "BP016";
        Category    = "Resource Management";
        Name        = "Cluster Autoscaler";
        Value       = ($clusterInfo.autoScalerProfile -ne $null);
        Expected    = { $true };
        FailMessage = "Enable Cluster Autoscaler for better resource management."
    },
    @{
        ID             = "BP050";
        Category       = "Resource Management";
        Name           = "AKS Built-in Cost Tooling Enabled";
        Value          = $clusterInfo.metricsProfile.costAnalysis.enabled;
        Expected       = $true;
        FailMessage    = "AKS built-in cost tooling (Open Costs) is not enabled. This feature is useful for cost allocation in multitenancy.";
        Severity       = "Medium";
        Recommendation = "Enable cost analysis in metricsProfile to monitor and allocate resource costs effectively.";
        URL            = "https://learn.microsoft.com/en-us/azure/aks/cost-management"  # Adjust URL as needed.
    }    
    
)
