$securityChecks = @(
    @{
        ID          = "BP005";
        Category    = "Security";
        Name        = "Private Cluster";
        Value       = $clusterInfo.apiServerAccessProfile.enablePrivateCluster;
        Expected    = $true;
        FailMessage = "Enable private cluster for security."
    },
    @{
        ID          = "BP006";
        Category    = "Security";
        Name        = "Azure Policy Add-on";
        Value       = $clusterInfo.addonProfiles.azurepolicy.enabled;
        Expected    = $true;
        FailMessage = "Enable Azure Policy add-on to enforce governance."
    },
    @{
        ID          = "BP007";
        Category    = "Security";
        Name        = "Defender for Containers";
        Value       = ($clusterInfo.securityProfile.defender.securityMonitoring).enabled;
        Expected    = $true;
        FailMessage = "Enable Defender for Containers for security monitoring."
    },
    @{
        ID          = "BP009";
        Category    = "Security";
        Name        = "OIDC Issuer Enabled";
        Value       = ($clusterInfo.oidcIssuerProfile).enabled;
        Expected    = $true;
        FailMessage = "Enable OIDC issuer for secure authentication."
    },
    @{
        ID          = "BP010";
        Category    = "Security";
        Name        = "Azure Key Vault Integration";
        Value       = ($clusterInfo.addonProfiles.azureKeyvaultSecretsProvider.enabled);
        Expected    = $true;
        FailMessage = "Enable Azure Key Vault integration for secure secrets management."
    },
    @{
        ID             = "BP037";
        Category       = "Security";
        Name           = "Image Cleaner Enabled";
        Value          = $clusterInfo.addonProfiles.imageCleaner.enabled;
        Expected       = $true;
        FailMessage    = "Image Cleaner is not enabled. Stale, vulnerable images may accumulate on cluster nodes.";
        Severity       = "Medium";
        Recommendation = "Enable Image Cleaner to automatically remove unused images and reduce security risk.";
        URL            = "https://learn.microsoft.com/en-us/azure/aks/image-cleaner"
    },
    @{
        ID             = "BP045";
        Category       = "Security";
        Name           = "Kubernetes Dashboard Disabled";
        Value          = if ($clusterInfo.addonProfiles.kubeDashboard) { $clusterInfo.addonProfiles.kubeDashboard.enabled } else { $false };
        Expected       = $false;
        FailMessage    = "Kubernetes Dashboard is enabled. It must be disabled for security reasons.";
        Severity       = "High";
        Recommendation = "Disable the Kubernetes dashboard using: az aks disable-addons --addons kube-dashboard --resource-group <RG_NAME> --name <CLUSTER_NAME>.";
        URL            = "https://learn.microsoft.com/en-us/azure/aks/kubernetes-dashboard"
    }
    
    
)
