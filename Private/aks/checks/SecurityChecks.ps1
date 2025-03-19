$securityChecks = @(
    @{
        ID          = "SEC001";
        Category    = "Security";
        Name        = "Private Cluster";
        Value       = { $clusterInfo.apiServerAccessProfile.enablePrivateCluster };
        Expected    = $true;
        FailMessage = "Cluster API server is publicly accessible, increasing security risks.";
        Severity    = "High";
        Recommendation = "Configure the cluster as a private cluster to restrict API server access to your virtual network.";
        URL         = "https://learn.microsoft.com/en-us/azure/aks/private-clusters";
    },
    @{
        ID          = "SEC002";
        Category    = "Security";
        Name        = "Azure Policy Add-on";
        Value       = { $clusterInfo.addonProfiles.azurepolicy.enabled };
        Expected    = $true;
        FailMessage = "Azure Policy add-on is not enabled, which may lead to policy violations and compliance risks.";
        Severity    = "Medium";
        Recommendation = "Enable the Azure Policy add-on to enforce security, governance, and compliance requirements.";
        URL         = "https://learn.microsoft.com/en-us/azure/aks/policy-reference";
    },
    @{
        ID          = "SEC003";
        Category    = "Security";
        Name        = "Defender for Containers";
        Value       = { ($clusterInfo.securityProfile.defender.securityMonitoring).enabled };
        Expected    = $true;
        FailMessage = "Defender for Containers is not enabled, leaving workloads vulnerable to security threats.";
        Severity    = "High";
        Recommendation = "Enable Defender for Containers to monitor and protect containerized workloads in AKS.";
        URL         = "https://learn.microsoft.com/en-us/azure/defender-for-cloud/defender-for-containers-introduction";
    },
    @{
        ID          = "SEC004";
        Category    = "Security";
        Name        = "OIDC Issuer Enabled";
        Value       = { ($clusterInfo.oidcIssuerProfile).enabled };
        Expected    = $true;
        FailMessage = "OIDC issuer is not enabled, which may limit secure authentication options.";
        Severity    = "Medium";
        Recommendation = "Enable the OIDC issuer to enhance security and authentication flexibility for workloads.";
        URL         = "https://learn.microsoft.com/en-us/azure/aks/oidc-issuer";
    },
    @{
        ID          = "SEC005";
        Category    = "Security";
        Name        = "Azure Key Vault Integration";
        Value       = { ($clusterInfo.addonProfiles.azureKeyvaultSecretsProvider.enabled) };
        Expected    = $true;
        FailMessage = "Azure Key Vault integration is not enabled, making secret management less secure.";
        Severity    = "High";
        Recommendation = "Enable Azure Key Vault integration to store and manage Kubernetes secrets securely.";
        URL         = "https://learn.microsoft.com/en-us/azure/aks/csi-secrets-store-driver";
    },
    @{
        ID             = "SEC006";
        Category       = "Security";
        Name           = "Image Cleaner Enabled";
        Value          = { ($clusterInfo.securityProfile.imageCleaner).enabled };
        Expected       = $true;
        FailMessage    = "Image Cleaner is not enabled. Stale, vulnerable images may accumulate on cluster nodes.";
        Severity       = "Medium";
        Recommendation = "Enable Image Cleaner to automatically remove unused images and reduce security risk.";
        URL            = "https://learn.microsoft.com/en-us/azure/aks/image-cleaner";
    },
    @{
        ID             = "SEC007";
        Category       = "Security";
        Name           = "Kubernetes Dashboard Disabled";
        Value          = { if ($clusterInfo.addonProfiles.kubeDashboard) { $clusterInfo.addonProfiles.kubeDashboard.enabled } else { $false } };
        Expected       = $false;
        FailMessage    = "Kubernetes Dashboard is enabled. It should be disabled to reduce security risks.";
        Severity       = "High";
        Recommendation = "Disable the Kubernetes dashboard using: az aks disable-addons --addons kube-dashboard --resource-group <RG_NAME> --name <CLUSTER_NAME>.";
        URL            = "https://learn.microsoft.com/en-us/azure/aks/kubernetes-dashboard";
    }
)
