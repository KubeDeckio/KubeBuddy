$resourceManagementChecks = @(
    @{
        ID          = "AKSRES001";
        Category    = "Resource Management";
        Name        = "Cluster Autoscaler";
        Value       = { $clusterInfo.properties.autoScalerProfile -ne $null };
        Expected    = $true;
        FailMessage = "Cluster autoscaler is disabled, requiring manual node scaling that leads to over-provisioning during low demand (wasted costs) or under-provisioning during peak times (performance issues and pod scheduling failures). This significantly increases operational overhead and cloud spending.";
        Severity    = "Medium";
        Recommendation = "Enable Cluster Autoscaler using 'az aks update --resource-group <rg> --name <cluster> --enable-cluster-autoscaler --min-count <min> --max-count <max>' on node pools. Configure appropriate min/max node counts, scale-down parameters, and node pool priorities for optimal cost and performance balance.";
        URL         = "https://learn.microsoft.com/azure/aks/cluster-autoscaler";
    },
    @{
        ID             = "AKSRES002";
        Category       = "Resource Management";
        Name           = "AKS Built-in Cost Tooling Enabled";
        Value          = { $clusterInfo.properties.metricsProfile.costAnalysis.enabled };
        Expected       = $true;
        FailMessage    = "Cost analysis and OpenCost integration is disabled, providing no visibility into per-namespace, per-workload, or per-application spending. This makes it impossible to implement cost allocation, identify expensive workloads, optimize resource usage, or implement chargeback policies for different teams.";
        Severity       = "Medium";
        Recommendation = "Enable cost analysis using 'az aks update --resource-group <rg> --name <cluster> --enable-cost-analysis' to track namespace and workload-level costs. Use the cost insights to identify expensive workloads, optimize resource requests, and implement chargeback/showback policies.";
        URL            = "https://learn.microsoft.com/azure/aks/cost-analysis";
    },
    @{
        ID             = "AKSRES003";
        Category       = "Resource Management";
        Name           = "Vertical Pod Autoscaler (VPA) is enabled";
        Value          = { $clusterInfo.properties.workloadAutoScalerProfile.verticalPodAutoscaler.enabled };
        Expected       = $true;
        FailMessage    = "Vertical Pod Autoscaler is disabled, resulting in static resource requests that are often oversized (wasting resources and money) or undersized (causing performance issues and throttling). VPA provides data-driven recommendations to optimize pod resource allocation based on actual usage patterns.";
        Severity       = "Medium";
        Recommendation = "Enable VPA using 'az aks update --resource-group <rg> --name <cluster> --enable-vpa'. Deploy VPA objects with 'updateMode: Auto' or 'Off' for recommendations only. Monitor VPA recommendations and adjust application resource requests/limits accordingly for better resource efficiency.";
        URL            = "https://learn.microsoft.com/azure/aks/vertical-pod-autoscaler";
    }    
)
