$securityChecks = @(
    @{
        ID          = "AKSSEC001";
        Category    = "Security";
        Name        = "Private Cluster";
        Value       = { $clusterInfo.properties.apiServerAccessProfile.enablePrivateCluster };
        Expected    = $true;
        FailMessage = "Cluster API server is publicly accessible, increasing security risks.";
        Severity    = "High";
        Recommendation = "Configure the cluster as a private cluster to restrict API server access to your virtual network.";
        URL         = "https://learn.microsoft.com/azure/aks/private-clusters";
    },
    @{
        ID          = "AKSSEC002";
        Category    = "Security";
        Name        = "Azure Policy Add-on";
        Value       = { $clusterInfo.properties.addonProfiles.azurepolicy.enabled };
        Expected    = $true;
        FailMessage = "Azure Policy add-on is not enabled, which may lead to policy violations and compliance risks.";
        Severity    = "Medium";
        Recommendation = "Enable the Azure Policy add-on to enforce security, governance, and compliance requirements.";
        URL         = "https://learn.microsoft.com/azure/aks/policy-reference";
    },
    @{
        ID          = "AKSSEC003";
        Category    = "Security";
        Name        = "Defender for Containers";
        Value       = { ($clusterInfo.properties.securityProfile.defender.securityMonitoring).enabled };
        Expected    = $true;
        FailMessage = "Defender for Containers is not enabled, leaving workloads vulnerable to security threats.";
        Severity    = "High";
        Recommendation = "Enable Defender for Containers to monitor and protect containerized workloads in AKS.";
        URL         = "https://learn.microsoft.com/azure/defender-for-cloud/defender-for-containers-introduction";
    },
    @{
        ID          = "AKSSEC004";
        Category    = "Security";
        Name        = "OIDC Issuer Enabled";
        Value       = { ($clusterInfo.properties.oidcIssuerProfile).enabled };
        Expected    = $true;
        FailMessage = "OIDC issuer is not enabled, which may limit secure authentication options.";
        Severity    = "Medium";
        Recommendation = "Enable the OIDC issuer to enhance security and authentication flexibility for workloads.";
        URL         = "https://learn.microsoft.com/azure/aks/workload-identity-deploy-cluster";
    },
    @{
        ID          = "AKSSEC005";
        Category    = "Security";
        Name        = "Azure Key Vault Integration";
        Value       = { ($clusterInfo.properties.addonProfiles.azureKeyvaultSecretsProvider.enabled) };
        Expected    = $true;
        FailMessage = "Azure Key Vault integration is not enabled, making secret management less secure.";
        Severity    = "High";
        Recommendation = "Enable Azure Key Vault integration to store and manage Kubernetes secrets securely.";
        URL         = "https://learn.microsoft.com/azure/aks/csi-secrets-store-driver";
    },
    @{
        ID             = "AKSSEC006";
        Category       = "Security";
        Name           = "Image Cleaner Enabled";
        Value          = { ($clusterInfo.properties.securityProfile.imageCleaner).enabled };
        Expected       = $true;
        FailMessage    = "Image Cleaner is not enabled. Stale, vulnerable images may accumulate on cluster nodes.";
        Severity       = "Medium";
        Recommendation = "Enable Image Cleaner to automatically remove unused images and reduce security risk.";
        URL            = "https://learn.microsoft.com/azure/aks/image-cleaner";
    },
    @{
        ID             = "AKSSEC007";
        Category       = "Security";
        Name           = "Kubernetes Dashboard Disabled";
        Value          = {
            if ($clusterInfo.properties.addonProfiles.kubeDashboard) {
                $clusterInfo.properties.addonProfiles.kubeDashboard.enabled
            } else {
                $false
            }
        };
        Expected       = $false;
        FailMessage    = "Kubernetes Dashboard is enabled. It should be disabled to reduce security risks.";
        Severity       = "High";
        Recommendation = "Disable the Kubernetes dashboard using: az aks disable-addons --addons kube-dashboard --resource-group <RG_NAME> --name <CLUSTER_NAME>.";
        URL            = "https://learn.microsoft.com/azure/aks/kubernetes-dashboard";
    }
)
