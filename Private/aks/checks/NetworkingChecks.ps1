$networkingChecks = @(
    @{
        ID          = "AKSNET001";
        Category    = "Networking";
        Name        = "Authorized IP Ranges";
        Value       = { ($clusterInfo.properties.apiServerAccessProfile.authorizedIpRanges).count };
        Expected    = { $_ -gt 0 };
        FailMessage = "No authorized IP ranges configured. This allows unrestricted access to the API server.";
        Severity    = "High";
        Recommendation = "Define authorized IP ranges to restrict API server access to specific IP addresses or ranges.";
        URL         = "https://learn.microsoft.com/azure/aks/operator-best-practices-cluster-security#secure-access-to-the-api-server-and-cluster-nodes";
    },
    @{
        ID          = "AKSNET002";
        Category    = "Networking";
        Name        = "Network Policy Check";
        Value       = { $clusterInfo.properties.networkProfile.networkPolicy -ne "none" };
        Expected    = $true;
        FailMessage = "Network policy is not configured. Pods can communicate without restrictions.";
        Severity    = "Medium";
        Recommendation = "Implement network policies to control traffic between pods and enhance security.";
        URL         = "https://learn.microsoft.com/azure/aks/operator-best-practices-network#control-traffic-flow-with-network-policies";
    },
    @{
        ID          = "AKSNET003";
        Category    = "Networking";
        Name        = "Web App Routing Enabled";
        Value       = { ($clusterInfo.properties.ingressProfile.webAppRouting).enabled };
        Expected    = $true;
        FailMessage = "Web App Routing is not enabled, which may limit external access management.";
        Severity    = "Low";
        Recommendation = "Enable Web App Routing to simplify external access management and integrate with Azure DNS.";
        URL         = "https://learn.microsoft.com/azure/aks/web-app-routing";
    },
    @{
        ID          = "AKSNET004";
        Category    = "Networking";
        Name        = "Azure CNI Networking Recommended";
        Value       = { ($clusterInfo.properties.networkProfile.networkPlugin -ne "kubenet") };
        Expected    = $true;
        FailMessage = "The network plugin is set to 'kubenet', which has limited networking capabilities compared to Azure CNI.";
        Severity    = "Medium";
        Recommendation = "Switch to Azure CNI networking for better integration with existing virtual networks and advanced IP allocation features.";
        URL         = "https://learn.microsoft.com/azure/aks/concepts-network#networking-options";
    }
)
