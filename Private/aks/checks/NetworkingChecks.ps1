$networkingChecks = @(
    @{
        ID          = "AKSNET001";
        Category    = "Networking";
        Name        = "Authorized IP Ranges";
        Value       = { ($clusterInfo.properties.apiServerAccessProfile.authorizedIpRanges).count };
        Expected    = { $_ -gt 0 };
        FailMessage = "API server accepts connections from any internet IP address (0.0.0.0/0), creating a massive attack surface for brute force attacks, credential stuffing, and vulnerability exploitation. This violates network security best practices and most compliance frameworks.";
        Severity    = "High";
        Recommendation = "Configure authorized IP ranges using 'az aks update --resource-group <rg> --name <cluster> --api-server-authorized-ip-ranges <ip-ranges>'. Include your management networks, CI/CD systems, and jump boxes. Use CIDR notation (e.g., 10.0.0.0/24) and consider Azure Firewall or NAT Gateway public IPs.";
        URL         = "https://learn.microsoft.com/azure/aks/operator-best-practices-cluster-security#secure-access-to-the-api-server-and-cluster-nodes";
    },
    @{
        ID          = "AKSNET002";
        Category    = "Networking";
        Name        = "Network Policy Check";
        Value       = { $clusterInfo.properties.networkProfile.networkPolicy -ne "none" };
        Expected    = $true;
        FailMessage = "Network policies are disabled, allowing unrestricted pod-to-pod communication across all namespaces and services. This creates a flat network where compromised workloads can freely access databases, APIs, and other sensitive services without segmentation controls.";
        Severity    = "Medium";
        Recommendation = "Enable network policy during cluster creation with '--network-policy azure' (Azure CNI) or '--network-policy calico' (kubenet). Create NetworkPolicy resources to define ingress/egress rules for pods, implementing micro-segmentation and zero-trust networking principles.";
        URL         = "https://learn.microsoft.com/azure/aks/operator-best-practices-network#control-traffic-flow-with-network-policies";
    },
    @{
        ID          = "AKSNET003";
        Category    = "Networking";
        Name        = "Web App Routing Enabled";
        Value       = { ($clusterInfo.properties.ingressProfile.webAppRouting).enabled };
        Expected    = $true;
        FailMessage = "Web App Routing add-on is disabled, requiring manual ingress controller management, DNS configuration, and SSL certificate handling. This increases operational overhead and may lead to inconsistent external access patterns and security configurations.";
        Severity    = "Low";
        Recommendation = "Enable Web App Routing using 'az aks enable-addons --resource-group <rg> --name <cluster> --addons web_application_routing'. Configure DNS zones and SSL certificates for automatic ingress management. Consider using Application Gateway Ingress Controller (AGIC) for enterprise scenarios.";
        URL         = "https://learn.microsoft.com/azure/aks/web-app-routing";
    },
    @{
        ID          = "AKSNET004";
        Category    = "Networking";
        Name        = "Azure CNI Networking Recommended";
        Value       = { ($clusterInfo.properties.networkProfile.networkPlugin -ne "kubenet") };
        Expected    = $true;
        FailMessage = "Kubenet networking provides limited integration with Azure VNets, lacks support for advanced networking features like network policies with Azure CNI, requires NAT gateways for outbound connectivity, and complicates IP address management and network security group configurations.";
        Severity    = "Medium";
        Recommendation = "Migrate to Azure CNI by creating a new cluster with '--network-plugin azure --vnet-subnet-id <subnet-id>'. Plan IP address allocation carefully, as each pod gets a VNet IP. Consider Azure CNI Overlay mode for efficient IP usage while maintaining VNet integration benefits.";
        URL         = "https://learn.microsoft.com/azure/aks/concepts-network#networking-options";
    }
)
