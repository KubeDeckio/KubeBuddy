$identityChecks = @(
    @{
        ID         = "BP002";
        Category   = "Identity & Access";
        Name       = "RBAC Enabled";
        Value      = $clusterInfo.enableRbac;
        Expected   = $true;
        FailMessage = "Enable RBAC for security."
    },
    @{
        ID         = "BP003";
        Category   = "Identity & Access";
        Name       = "Managed Identity";
        Value      = $clusterInfo.identity.type;
        Expected   = "UserAssigned";
        FailMessage = "Use Managed Identity instead of Service Principal."
    },
    @{
        ID         = "BP04";
        Category   = "Identity & Access";
        Name       = "Workload Identity Enabled";
        Value      = $clusterInfo.securityProfile.workloadIdentity.enabled;
        Expected   = { $_ -eq $true };
        FailMessage = "Workload Identity must be enabled in AKS."
    },
    @{
        ID             = "BP035";
        Category       = "Identity & Access";
        Name           = "Managed Identity Used";
        Value          = $clusterInfo.identity.type;
        Expected       = "UserAssigned";
        FailMessage    = "Use managed identities instead of Service Principals. Each AKS cluster needs either one, but managed identities are recommended.";
        Severity       = "High";
        Recommendation = "Configure your AKS cluster to use a Managed Identity.";
        URL            = "https://docs.microsoft.com/en-us/azure/aks/use-managed-identity"
    },
    @{
        ID             = "BP042";
        Category       = "Identity & Access";
        Name           = "AAD RBAC Authorization Integrated";
        Value          = $clusterInfo.aadProfile.enableAzureRBAC;
        Expected       = $true;
        FailMessage    = "Cluster access is not integrated with AAD RBAC. Limit access via Kubernetes RBAC using Azure AD identities.";
        Severity       = "High";
        Recommendation = "Enable AAD RBAC to control cluster access for users and workloads.";
        URL            = "https://learn.microsoft.com/en-us/azure/aks/aad-integration"
    },
    @{
        ID             = "BP043";
        Category       = "Identity & Access";
        Name           = "AAD Managed Authentication Enabled";
        Value          = $clusterInfo.aadProfile.managed;
        Expected       = $true;
        FailMessage    = "AKS is not configured for managed Azure AD authentication. Local accounts may be enabled.";
        Severity       = "High";
        Recommendation = "Enable managed Azure AD integration to authenticate users via Azure AD and disable local accounts.";
        URL            = "https://learn.microsoft.com/en-us/azure/aks/aad-integration"
    },
    @{
        ID             = "BP044";
        Category       = "Identity & Access";
        Name           = "Local Accounts Disabled";
        Value          = $clusterInfo.disableLocalAccounts;
        Expected       = $true;
        FailMessage    = "AKS local accounts are enabled. Disabling local accounts reduces security risks.";
        Severity       = "High";
        Recommendation = "Disable local accounts using the --disable-local-accounts flag when creating or updating your AKS cluster.";
        URL            = "https://learn.microsoft.com/en-us/azure/aks/disable-local-accounts"
    }    
    
)
