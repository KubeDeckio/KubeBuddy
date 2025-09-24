$disasterRecoveryChecks = @(
    @{
        ID          = "AKSDR001";
        Category    = "Disaster Recovery";
        Name        = "Agent Pools with Availability Zones";
        Value       = { ($clusterInfo.properties.agentPoolProfiles | Where-Object { $_.availabilityZones.Count -lt 3 }).Count };
        Expected    = 0;
        FailMessage = "Node pools are not distributed across multiple availability zones, creating vulnerability to datacenter-level failures, planned maintenance events, and regional outages. Single-zone deployment provides no protection against infrastructure failures and violates high availability best practices.";
        Severity    = "High";
        Recommendation = "Deploy node pools across availability zones using 'az aks nodepool add --availability-zones 1 2 3 --resource-group <rg> --cluster-name <cluster> --name <pool>'. Ensure at least 3 zones are used for production workloads to achieve 99.95% SLA and protect against datacenter failures.";
        URL         = "https://learn.microsoft.com/azure/aks/availability-zones";
    },
    @{
        ID          = "AKSDR002";
        Category    = "Disaster Recovery";
        Name        = "Control Plane SLA";
        Value       = { $clusterInfo.sku.tier -eq "Standard" };
        Expected    = $true;
        FailMessage = "Cluster is using the Free tier without SLA guarantees, providing no financial commitment for uptime and limited support options. Free tier offers best-effort availability but no compensation for outages, making it unsuitable for production workloads requiring reliability commitments.";
        Severity    = "Medium";
        Recommendation = "Upgrade to Standard tier using 'az aks update --resource-group <rg> --name <cluster> --tier Standard' to get 99.95% uptime SLA, financially-backed availability guarantees, and improved support. This is essential for production workloads requiring high availability.";
        URL         = "https://learn.microsoft.com/azure/aks/free-standard-pricing-tiers";
    }
)
