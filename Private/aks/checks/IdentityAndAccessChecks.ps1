$identityChecks = @(
    @{
        ID         = "AKSIAM001";
        Category   = "Identity & Access";
        Name       = "RBAC Enabled";
        Value      = { $clusterInfo.properties.enableRbac };
        Expected   = $true;
        FailMessage = "Kubernetes RBAC is disabled, meaning all authenticated users have full cluster admin privileges with unrestricted access to all resources, secrets, and namespaces. This violates the principle of least privilege and creates significant security and compliance risks.";
        Severity    = "High";
        Recommendation = "Enable RBAC during cluster creation using '--enable-rbac' or for existing clusters via Azure Portal. Create RoleBindings and ClusterRoleBindings to assign appropriate permissions to users and service accounts based on the principle of least privilege.";
        URL         = "https://learn.microsoft.com/azure/aks/manage-azure-rbac?tabs=azure-cli";
    },
    @{
        ID         = "AKSIAM002";
        Category   = "Identity & Access";
        Name       = "Managed Identity";
        Value      = { $clusterInfo.identity.type };
        Expected   = "UserAssigned";
        FailMessage = "Cluster is using system-assigned managed identity or service principal instead of user-assigned managed identity. This limits control over identity lifecycle, makes cross-resource permissions harder to manage, and creates dependency on cluster lifecycle for identity management.";
        Severity    = "High";
        Recommendation = "Create a user-assigned managed identity using 'az identity create --resource-group <rg> --name <identity-name>' and associate it during cluster creation with '--assign-identity <identity-resource-id>'. This eliminates the need to manage service principal credentials and provides better security.";
        URL         = "https://learn.microsoft.com/azure/aks/use-managed-identity";
    },
    @{
        ID         = "AKSIAM003";
        Category   = "Identity & Access";
        Name       = "Workload Identity Enabled";
        Value      = { $clusterInfo.properties.securityProfile.workloadIdentity.enabled };
        Expected   = $true;
        FailMessage = "Workload Identity is disabled, forcing applications to use less secure authentication methods like storing Azure service principal secrets in Kubernetes, using pod identity (deprecated), or instance metadata. This increases credential exposure risk and limits fine-grained access control.";
        Severity   = "Medium";
        Recommendation = "Enable Workload Identity using 'az aks update --resource-group <rg> --name <cluster> --enable-workload-identity' (requires OIDC issuer). Create Kubernetes service accounts and federate them with Azure managed identities for secure, token-based authentication to Azure services.";
        URL         = "https://learn.microsoft.com/azure/aks/workload-identity-overview";
    },
    @{
        ID         = "AKSIAM004";
        Category   = "Identity & Access";
        Name       = "Managed Identity Used";
        Value      = { $clusterInfo.identity.type };
        Expected   = "UserAssigned";
        FailMessage = "Cluster is using Azure AD Service Principal with client secrets that require manual rotation, have expiration dates, and pose security risks if compromised. Service principals lack the automatic credential management and enhanced security features of managed identities.";
        Severity    = "High";
        Recommendation = "Migrate from Service Principal to User-Assigned Managed Identity using 'az aks update --resource-group <rg> --name <cluster> --assign-identity <identity-resource-id>'. This provides automatic credential rotation and eliminates the need to manage client secrets.";
        URL         = "https://learn.microsoft.com/azure/aks/use-managed-identity";
    },
    @{
        ID         = "AKSIAM005";
        Category   = "Identity & Access";
        Name       = "AAD RBAC Authorization Integrated";
        Value      = { $clusterInfo.properties.aadProfile.enableAzureRBAC };
        Expected   = $true;
        FailMessage = "Azure RBAC for Kubernetes is disabled, requiring manual management of Kubernetes native RoleBindings and ClusterRoleBindings. This creates inconsistent access control between Azure and Kubernetes, limits centralized identity management, and complicates compliance auditing.";
        Severity    = "High";
        Recommendation = "Enable Azure RBAC for Kubernetes authorization using 'az aks update --resource-group <rg> --name <cluster> --enable-azure-rbac'. Assign built-in roles like 'Azure Kubernetes Service RBAC Reader/Writer/Admin' to users and groups for centralized access management through Azure AD.";
        URL         = "https://learn.microsoft.com/azure/aks/enable-authentication-microsoft-entra-id";
    },
    @{
        ID         = "AKSIAM006";
        Category   = "Identity & Access";
        Name       = "AAD Managed Authentication Enabled";
        Value      = { $clusterInfo.properties.aadProfile.managed };
        Expected   = $true;
        FailMessage = "Azure AD integration is not properly configured, potentially using legacy AAD integration or client/server app registrations that require manual maintenance. This limits the ability to leverage modern Azure AD features like conditional access policies and centralized user management.";
        Severity    = "High";
        Recommendation = "Enable Azure AD integration during cluster creation with '--enable-aad --aad-admin-group-object-ids <group-id>' or update existing cluster using 'az aks update --resource-group <rg> --name <cluster> --enable-aad'. Configure admin groups and integrate with conditional access policies.";
        URL         = "https://learn.microsoft.com/azure/aks/manage-azure-rbac?tabs=azure-cli";
    },
    @{
        ID         = "AKSIAM007";
        Category   = "Identity & Access";
        Name       = "Local Accounts Disabled";
        Value      = { $clusterInfo.properties.disableLocalAccounts };
        Expected   = $true;
        FailMessage = "Local cluster admin certificates are enabled, providing a backdoor authentication method that bypasses Azure AD, cannot be audited through Azure AD logs, and creates permanent admin access that doesn't respect conditional access policies or MFA requirements.";
        Severity    = "High";
        Recommendation = "Disable local accounts using 'az aks update --resource-group <rg> --name <cluster> --disable-local-accounts'. This enforces authentication exclusively through Azure AD, eliminating certificate-based admin access and improving audit capabilities.";
        URL         = "https://learn.microsoft.com/azure/aks/manage-local-accounts-managed-azure-ad";
    }
)