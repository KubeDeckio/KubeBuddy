$networkingChecks = @(
    @{
        ID          = "AKSNET001";
        Category    = "Networking";
        Name        = "Authorized IP Ranges Configured (Public Clusters)";
        Value       = { 
            # Skip this check for private clusters as authorized IP ranges aren't applicable
            if ($clusterInfo.properties.apiServerAccessProfile.enablePrivateCluster) {
                return $true
            }
            return ($clusterInfo.properties.apiServerAccessProfile.authorizedIpRanges).count -gt 0
        };
        Expected    = $true;
        FailMessage = "API server accepts connections from any internet IP address, creating a large attack surface for brute force attacks, credential stuffing, and vulnerability exploitation. This violates network security best practices and most compliance frameworks.";
        Severity    = "High";
        Recommendation = "Configure authorized IP ranges using 'az aks update --resource-group <rg> --name <cluster> --api-server-authorized-ip-ranges <ip-ranges>'. Include management networks, CI/CD systems, and jump boxes using CIDR notation. Alternatively, migrate to a private cluster for enhanced security.";
        URL         = "https://learn.microsoft.com/azure/aks/api-server-authorized-ip-ranges";
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
        Name        = "Azure CNI with Cilium Dataplane Recommended";
        Value       = { 
            # Check if using Azure CNI (not kubenet)
            $usingAzureCNI = ($clusterInfo.properties.networkProfile.networkPlugin -ne "kubenet")
            # Check if using Cilium dataplane (eBPF-based)
            $usingCilium = ($clusterInfo.properties.networkProfile.networkDataplane -eq "cilium")
            return $usingAzureCNI -and $usingCilium
        };
        Expected    = $true;
        FailMessage = "Cluster is not using Azure CNI with Cilium dataplane. Cilium leverages eBPF for high-performance networking, improved observability, and efficient network policy enforcement compared to traditional iptables-based solutions. Kubenet provides limited VNet integration and lacks advanced networking features.";
        Severity    = "Medium";
        Recommendation = "For new clusters, use '--network-plugin azure --network-dataplane cilium --network-plugin-mode overlay' for optimal performance. Azure CNI powered by Cilium provides eBPF-based packet processing, better scalability, and advanced L3-L7 network policies. Existing clusters should migrate by creating a new cluster with Cilium enabled.";
        URL         = "https://learn.microsoft.com/azure/aks/azure-cni-powered-by-cilium";
