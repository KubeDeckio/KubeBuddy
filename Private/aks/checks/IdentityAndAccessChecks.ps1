$identityChecks = @(
    @{
        ID         = "AKSIAM001";
        Category   = "Identity & Access";
        Name       = "RBAC Enabled";
        Value      = { $clusterInfo.properties.enableRbac };
        Expected   = $true;
        FailMessage = "Role-Based Access Control (RBAC) is not enabled, increasing security risks.";
        Severity    = "High";
        Recommendation = "Enable RBAC to control access to your cluster resources based on user roles.";
        URL         = "https://learn.microsoft.com/azure/aks/manage-azure-rbac?tabs=azure-cli";
    },
    @{
        ID         = "AKSIAM002";
        Category   = "Identity & Access";
        Name       = "Managed Identity";
        Value      = { $clusterInfo.identity.type };
        Expected   = "UserAssigned";
        FailMessage = "Identity type is not user-assigned. This creates unnecessary credential management and security risks.";
        Severity    = "High";
        Recommendation = "Use a user-assigned Managed Identity to simplify credential management and reduce security risks.";
        URL         = "https://learn.microsoft.com/azure/aks/use-managed-identity";
    },
    @{
        ID         = "AKSIAM003";
        Category   = "Identity & Access";
        Name       = "Workload Identity Enabled";
        Value      = { $clusterInfo.properties.securityProfile.workloadIdentity.enabled };
        Expected   = { $_ -eq $true };
        FailMessage = "Workload Identity is not enabled, reducing security for Kubernetes workloads.";
        Severity    = "Medium";
        Recommendation = "Enable Workload Identity to securely bind Kubernetes workloads to Azure identities.";
        URL         = "https://learn.microsoft.com/azure/aks/workload-identity-overview";
    },
    @{
        ID         = "AKSIAM004";
        Category   = "Identity & Access";
        Name       = "Managed Identity Used";
        Value      = { $clusterInfo.identity.type };
        Expected   = "UserAssigned";
        FailMessage = "Service Principal is being used instead of a Managed Identity, which is less secure.";
        Severity    = "High";
        Recommendation = "Use a Managed Identity instead of a Service Principal to improve security and simplify authentication.";
        URL         = "https://learn.microsoft.com/azure/aks/use-managed-identity";
    },
    @{
        ID         = "AKSIAM005";
        Category   = "Identity & Access";
        Name       = "AAD RBAC Authorization Integrated";
        Value      = { $clusterInfo.properties.aadProfile.enableAzureRBAC };
        Expected   = $true;
        FailMessage = "Azure Active Directory (AAD) RBAC is not enabled, leading to weak access control.";
        Severity    = "High";
        Recommendation = "Enable AAD RBAC to enforce access policies based on Azure AD identities.";
        URL         = "https://learn.microsoft.com/azure/aks/enable-authentication-microsoft-entra-id";
    },
    @{
        ID         = "AKSIAM006";
        Category   = "Identity & Access";
        Name       = "AAD Managed Authentication Enabled";
        Value      = { $clusterInfo.properties.aadProfile.managed };
        Expected   = $true;
        FailMessage = "AKS is not using managed Azure AD authentication, increasing security risks.";
        Severity    = "High";
        Recommendation = "Enable managed Azure AD authentication and disable local accounts to enhance security.";
        URL         = "https://learn.microsoft.com/azure/aks/manage-azure-rbac?tabs=azure-cli";
    },
    @{
        ID         = "AKSIAM007";
        Category   = "Identity & Access";
        Name       = "Local Accounts Disabled";
        Value      = { $clusterInfo.properties.disableLocalAccounts };
        Expected   = $true;
        FailMessage = "AKS local accounts are enabled, increasing the risk of unauthorized access.";
        Severity    = "High";
        Recommendation = "Disable local accounts to enforce authentication via Azure Active Directory.";
        URL         = "https://learn.microsoft.com/azure/aks/manage-local-accounts-managed-azure-ad";
    }
)