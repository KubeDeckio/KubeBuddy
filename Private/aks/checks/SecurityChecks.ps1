$securityChecks = @(
    @{
        ID          = "AKSSEC001";
        Category    = "Security";
        Name        = "Private Cluster";
        Value       = { $clusterInfo.properties.apiServerAccessProfile.enablePrivateCluster };
        Expected    = $true;
        FailMessage = "API server is publicly accessible from the internet, exposing your cluster to potential attacks, unauthorized access attempts, and compliance violations. This creates a significant security risk as attackers can attempt to exploit Kubernetes API vulnerabilities.";
        Severity    = "High";
        Recommendation = "Configure as a private cluster using 'az aks create --enable-private-cluster' or 'az aks update --enable-private-cluster' for existing clusters. This routes API server traffic through private endpoints within your VNet. Configure private DNS zones and ensure network connectivity from management machines.";
        URL         = "https://learn.microsoft.com/azure/aks/private-clusters";
    },
    @{
        ID          = "AKSSEC002";
        Category    = "Security";
        Name        = "Azure Policy Add-on";
        Value       = { $clusterInfo.properties.addonProfiles.azurepolicy.enabled };
        Expected    = $true;
        FailMessage = "Azure Policy add-on is disabled, preventing enforcement of organizational security policies, compliance standards (like PCI-DSS, SOC2), and governance rules. This increases risk of policy violations and makes it difficult to maintain consistent security configurations across workloads.";
        Severity    = "Medium";
        Recommendation = "Enable Azure Policy add-on using 'az aks enable-addons --resource-group <rg> --name <cluster> --addons azure-policy'. Deploy built-in policy initiatives like 'Kubernetes cluster pod security restricted standards' and create custom policies for your organization's requirements.";
        URL         = "https://learn.microsoft.com/azure/aks/policy-reference";
    },
    @{
        ID          = "AKSSEC003";
        Category    = "Security";
        Name        = "Defender for Containers";
        Value       = { ($clusterInfo.properties.securityProfile.defender.securityMonitoring).enabled };
        Expected    = $true;
        FailMessage = "Microsoft Defender for Containers is not active, leaving your cluster without runtime threat detection, vulnerability scanning, or security recommendations. This means potential malware, suspicious activities, or known CVEs in container images may go undetected.";
        Severity    = "High";
        Recommendation = "Enable Defender for Containers using 'az aks update --resource-group <rg> --name <cluster> --enable-defender' or through Security Center in Azure Portal. Configure vulnerability scanning, runtime threat detection, and compliance monitoring for comprehensive container security.";
        URL         = "https://learn.microsoft.com/azure/defender-for-cloud/defender-for-containers-introduction";
    },
    @{
        ID          = "AKSSEC004";
        Category    = "Security";
        Name        = "OIDC Issuer Enabled";
        Value       = { ($clusterInfo.properties.oidcIssuerProfile).enabled };
        Expected    = $true;
        FailMessage = "OIDC issuer is disabled, preventing workload identity federation and forcing applications to use less secure authentication methods like stored secrets or service principal credentials. This limits your ability to implement zero-trust security for pod-to-Azure service authentication.";
        Severity    = "Medium";
        Recommendation = "Enable OIDC issuer using 'az aks update --resource-group <rg> --name <cluster> --enable-oidc-issuer'. This enables workload identity federation, allowing pods to authenticate to Azure services using service account tokens instead of secrets.";
        URL         = "https://learn.microsoft.com/azure/aks/workload-identity-deploy-cluster";
    },
    @{
        ID          = "AKSSEC005";
        Category    = "Security";
        Name        = "Azure Key Vault Integration";
        Value       = { ($clusterInfo.properties.addonProfiles.azureKeyvaultSecretsProvider.enabled) };
        Expected    = $true;
        FailMessage = "Azure Key Vault CSI driver is not enabled, forcing applications to store secrets directly in Kubernetes as base64-encoded values or environment variables. This creates security risks as secrets are visible in cluster etcd, pod specifications, and logs, and cannot leverage Key Vault's access policies or audit capabilities.";
        Severity    = "High";
        Recommendation = "Enable Key Vault CSI driver using 'az aks enable-addons --resource-group <rg> --name <cluster> --addons azure-keyvault-secrets-provider'. Create SecretProviderClass resources to mount secrets, certificates, and keys from Azure Key Vault as volumes in pods.";
        URL         = "https://learn.microsoft.com/azure/aks/csi-secrets-store-driver";
    },
    @{
        ID             = "AKSSEC006";
        Category       = "Security";
        Name           = "Image Cleaner Enabled";
        Value          = { ($clusterInfo.properties.securityProfile.imageCleaner).enabled };
        Expected       = $true;
        FailMessage    = "Image Cleaner is disabled, allowing stale and potentially vulnerable container images to accumulate on node disks. This increases storage costs, extends attack surface with outdated images containing known CVEs, and can impact node performance due to disk space consumption.";
        Severity       = "Medium";
        Recommendation = "Enable Image Cleaner using 'az aks update --resource-group <rg> --name <cluster> --enable-image-cleaner'. Configure cleaning interval and retention policies to automatically remove unused container images and reduce attack surface.";
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
        FailMessage    = "Kubernetes Dashboard is active and publicly accessible, creating a significant security vulnerability. The dashboard has historically been targeted by attackers and provides broad cluster access if compromised. It lacks robust authentication mechanisms and can expose sensitive cluster information.";
        Severity       = "High";
        Recommendation = "Disable the Kubernetes dashboard using 'az aks disable-addons --addons kube-dashboard --resource-group <rg> --name <cluster>'. Use Azure Portal, kubectl, or other secure management tools instead. If dashboard access is required, implement proper authentication and network restrictions.";
        URL            = "https://learn.microsoft.com/azure/aks/kubernetes-dashboard";
    },
    @{
        ID             = "AKSSEC08";
        Category       = "Security";
        Name           = "Pod Security Admission Enabled";
        Value          = { $clusterInfo.properties.podSecurityAdmissionConfiguration -ne $null };
        Expected       = $true;
        FailMessage    = "Pod Security Admission is not configured on this cluster, meaning there are no built-in Kubernetes security controls to prevent insecure pod configurations. Without PSA, pods can run with dangerous settings like privileged mode, host network access, or unsafe capabilities, increasing container escape risks.";
        Severity       = "High";
        Recommendation = "Configure Pod Security Admission by setting pod security standards on namespaces. Use 'kubectl label namespace <namespace> pod-security.kubernetes.io/enforce=restricted pod-security.kubernetes.io/audit=restricted pod-security.kubernetes.io/warn=restricted' for production namespaces. Consider 'baseline' for less restrictive environments. This is separate from Azure Policy and provides Kubernetes-native security controls.";
        URL            = "https://learn.microsoft.com/azure/aks/use-psa"
    }
    
)
