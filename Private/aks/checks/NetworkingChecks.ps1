$networkingChecks = @(
    @{
        ID          = "BP011";
        Category    = "Networking";
        Name        = "Authorized IP Ranges";
        Value       = ($clusterInfo.apiServerAccessProfile.authorizedIpRanges).count;
        Expected    = { $_ -gt 0 };
        FailMessage = "At least one authorized IP range is required."
    },
    @{
        ID          = "BP012";
        Category    = "Networking";
        Name        = "Network Policy Check";
        Value       = ($clusterInfo.networkProfile.networkPolicy -ne "none");
        Expected    = $true;
        FailMessage = "Network policy must be configured (cannot be 'none')."
    },
    @{
        ID          = "BP013";
        Category    = "Networking";
        Name        = "Web app routing is enabled";
        Value       = ($clusterInfo.addonProfiles.ingressProfile.enabled).enabled;
        Expected    = $true;
        FailMessage = "Consider enabling web app routing for external access management."
    },
    @{
        ID             = "BP049";
        Category       = "Networking";
        Name           = "Azure CNI Networking Recommended";
        Value          = ($clusterInfo.networkProfile.networkPlugin -ne "kubenet");
        Expected       = $true;
        FailMessage    = "The network plugin is set to 'kubenet'. Consider using Azure CNI or a compatible CNI overlay for enhanced network integration and IP management.";
        Severity       = "Medium";
        Recommendation = "Switch to Azure CNI networking for better integration with existing virtual networks and more advanced IP allocation features.";
        URL            = "https://learn.microsoft.com/en-us/azure/aks/concepts-network#networking-options"
    }
    
)
