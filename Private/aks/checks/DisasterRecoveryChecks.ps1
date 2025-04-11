$disasterRecoveryChecks = @(
    @{
        ID          = "DR001";
        Category    = "Disaster Recovery";
        Name        = "Agent Pools with Availability Zones";
        Value       = { ($clusterInfo.agentPoolProfiles | Where-Object { $_.availabilityZones.Count -lt 3 }).Count };
        Expected    = 0;
        FailMessage = "Not all agent pools are using three or more availability zones, reducing fault tolerance.";
        Severity    = "High";
        Recommendation = "Configure all agent pools to use at least three availability zones to improve availability and fault tolerance.";
        URL         = "https://learn.microsoft.com/azure/aks/availability-zones";
    },
    @{
        ID          = "DR002";
        Category    = "Disaster Recovery";
        Name        = "Control Plane SLA";
        Value       = { $clusterInfo.sku.tier -eq "Standard" };
        Expected    = $true;
        FailMessage = "AKS control plane SLA is not enabled, which may affect uptime guarantees.";
        Severity    = "Medium";
        Recommendation = "Upgrade to the Standard SKU to benefit from the AKS control plane SLA for better availability and reliability.";
        URL         = "https://learn.microsoft.com/azure/aks/free-standard-pricing-tiers";
    }
)
