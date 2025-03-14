$disasterRecoveryChecks = @(
    @{
        ID          = "BP017";
        Category    = "Disaster Recovery";
        Name        = "Agent Pools with Availability Zones";
        Value       = ($clusterInfo.agentPoolProfiles | Where-Object { $_.availabilityZones.Count -lt 3 }).Count;
        Expected    = 0;
        FailMessage = "Ensure all agent pools use three or more availability zones."
    },
    @{
        ID          = "BP019";
        Category    = "Disaster Recovery";
        Name        = "Control Plane SLA";
        Value       = ($clusterInfo.sku.tier -eq "Standard");
        Expected    = $true;
        FailMessage = "Enable SLA for AKS control plane for guaranteed uptime."
    }
)
