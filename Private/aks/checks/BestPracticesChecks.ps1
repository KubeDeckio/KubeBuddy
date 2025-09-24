$bestPracticesChecks = @(
    @{
        ID             = "AKSBP001";
        Category       = "Best Practices";
        Name           = "Allowed Container Images Policy Enforcement";
        Value          = { ($clusterInfo.properties.kubeData.Constraints.items | Where-Object { $_.kind -eq "K8sAzureV2ContainerAllowedImages"}).spec.enforcementAction -contains "deny" };
        Expected       = $true;
        FailMessage    = "Container image restriction policies are not enforced, allowing deployment of images from any registry including public registries, untrusted sources, or images with known vulnerabilities. This significantly increases supply chain attack risks and compliance violations.";
        Severity       = "High";
        Recommendation = "Deploy the Azure Policy initiative 'Kubernetes cluster pod security restricted standards' and configure specific allowed container registries. Use 'az policy assignment create' to assign the policy and set enforcement to 'deny' mode for production environments.";
        URL            = "https://learn.microsoft.com/azure/aks/policy-reference";
    },    
    @{
        ID             = "AKSBP002";
        Category       = "Best Practices";
        Name           = "No Privileged Containers Policy Enforcement";
        Value          = { ($clusterInfo.properties.kubeData.Constraints.items | Where-Object { $_.kind -eq "K8sAzureV2NoPrivilege"}).spec.enforcementAction -contains "deny" };
        Expected       = $true;
        FailMessage    = "Privileged container policies are not enforced, allowing workloads to run with full root privileges, access host devices, mount host file systems, and potentially escape container boundaries. This creates severe security risks and violates least-privilege principles.";
        Severity       = "High";
        Recommendation = "Enable the 'Do not allow privileged containers' Azure Policy definition in enforce mode. Use Pod Security Standards with 'restricted' profile to block privileged containers and ensure security baseline compliance.";
        URL            = "https://learn.microsoft.com/azure/aks/policy-reference";
    },
    @{
        ID          = "AKSBP003";
        Category    = "Best Practices";
        Name        = "Multiple Node Pools";
        Value       = { $clusterInfo.properties.agentPoolProfiles.Count -gt 1 };
        Expected    = $true;
        FailMessage = "Single node pool configuration limits workload isolation, scaling flexibility, and security boundaries. All workloads share the same VM size, OS configuration, and scaling parameters, making it impossible to optimize for different application requirements or implement proper security zones.";
        Severity    = "Medium";
        Recommendation = "Create separate node pools for different workload types using 'az aks nodepool add --resource-group <rg> --cluster-name <cluster> --name <pool-name>'. Use system pools for system pods, user pools for applications, and specialized pools (GPU, memory-optimized) for specific workloads.";
        URL         = "https://learn.microsoft.com/azure/aks/use-multiple-node-pools";
    },
    @{
        ID             = "AKSBP004";
        Category       = "Best Practices";
        Name           = "Azure Linux as Host OS";
        Value          = { ($clusterInfo.properties.agentPoolProfiles | Where-Object { $_.osType -eq "Linux" -and $_.osSKU -ne "AzureLinux" }).Count };
        Expected       = 0;
        FailMessage    = "Node pools are using Ubuntu instead of Azure Linux, missing out on Microsoft's optimized container host OS with reduced attack surface, faster boot times, improved security updates, and better integration with Azure services and support.";
        Severity       = "High";
        Recommendation = "Migrate to Azure Linux using 'az aks nodepool update --resource-group <rg> --cluster-name <cluster> --name <nodepool> --os-sku AzureLinux' or create new node pools with '--os-sku AzureLinux'. Azure Linux provides better performance, security, and reduced attack surface for container workloads.";
        URL            = "https://learn.microsoft.com/azure/aks/use-azure-linux";
    },    
    @{
        ID             = "AKSBP005";
        Category       = "Best Practices";
        Name           = "Ephemeral OS Disks Enabled";
        Value          = { ($clusterInfo.properties.agentPoolProfiles | Where-Object { $_.osDiskType -ne "Ephemeral" }).Count };
        Expected       = 0;
        FailMessage    = "Node pools are using managed OS disks instead of ephemeral disks, resulting in higher costs, slower disk performance, increased boot times, and additional complexity in disk management. Managed disks also limit the VM sizes available for use.";
        Severity       = "Medium";
        Recommendation = "Enable ephemeral OS disks using 'az aks nodepool add --os-disk-type Ephemeral' for new pools or plan node pool replacement. This provides faster disk I/O, lower latency, and reduced costs by using local VM storage instead of managed disks.";
        URL            = "https://learn.microsoft.com/azure/aks/concepts-storage#ephemeral-os-disk";
    },
    @{
        ID             = "AKSBP006";
        Category       = "Best Practices";
        Name           = "Non-Ephemeral Disks with Adequate Size";
        Value          = { ($clusterInfo.properties.agentPoolProfiles | Where-Object { $_.osDiskType -ne "Ephemeral" -and $_.osDiskSizeGb -lt 128 }).Count };
        Expected       = 0;
        FailMessage    = "Managed OS disks are undersized (less than 128GB), which constrains IOPS performance, limits container image caching capacity, causes disk space issues during image pulls, and may impact node performance under heavy workloads with multiple large images.";
        Severity       = "Medium";
        Recommendation = "Increase OS disk size using 'az aks nodepool update --resource-group <rg> --cluster-name <cluster> --name <nodepool> --os-disk-size-gb 128' or higher. Larger disks provide better IOPS performance and accommodate container image layers and temporary storage needs.";
        URL            = "https://learn.microsoft.com/azure/aks/concepts-storage#managed-os-disks";
    },
    @{
        ID             = "AKSBP007";
        Category       = "Best Practices";
        Name           = "System Node Pool Taint";
        Value          = { ($clusterInfo.properties.agentPoolProfiles | Where-Object { $_.mode -eq "System" }).nodeTaints -contains "CriticalAddonsOnly=true:NoSchedule" };
        Expected       = $true;
        FailMessage    = "System node pool lacks the CriticalAddonsOnly taint, allowing user workloads to be scheduled on system nodes. This can cause resource contention with critical system components (kube-proxy, DNS, CNI), potentially leading to cluster instability and system pod eviction.";
        Severity       = "High";
        Recommendation = "Apply system node pool taint using 'az aks nodepool update --resource-group <rg> --cluster-name <cluster> --name <system-pool> --node-taints CriticalAddonsOnly=true:NoSchedule'. This ensures only critical system pods run on system nodes, improving reliability and resource isolation.";
        URL            = "https://learn.microsoft.com/azure/aks/use-system-pools?tabs=azure-cli#system-and-user-node-pools";
    },
    @{
        ID             = "AKSBP008";
        Category       = "Best Practices";
        Name           = "Auto Upgrade Channel Configured";
        Value          = { $clusterInfo.properties.autoUpgradeProfile.upgradeChannel -ne "none" };
        Expected       = $true;
        FailMessage    = "Automatic cluster upgrades are disabled, leaving the cluster vulnerable to security patches, bug fixes, and Kubernetes version support expiration. Manual upgrade management increases operational overhead and delays critical security updates.";
        Severity       = "Medium";
        Recommendation = "Configure auto upgrade using 'az aks update --resource-group <rg> --name <cluster> --auto-upgrade-channel patch' for security patches or 'stable' for minor version updates. Use maintenance windows to control upgrade timing and minimize disruption.";
        URL            = "https://learn.microsoft.com/azure/aks/auto-upgrade-cluster?tabs=azure-cli";
    },    
    @{
        ID             = "AKSBP009";
        Category       = "Best Practices";
        Name           = "Node OS Upgrade Channel Configured";
        Value          = { ($clusterInfo.properties.autoUpgradeProfile.nodeOSUpgradeChannel -ne "None") };
        Expected       = $true;
        FailMessage    = "Node OS automatic updates are disabled, leaving nodes running outdated OS versions with potential security vulnerabilities, missing security patches, and outdated system libraries. This increases the attack surface and compliance risks.";
        Severity       = "Medium";
        Recommendation = "Enable node OS upgrade using 'az aks update --resource-group <rg> --name <cluster> --node-os-upgrade-channel NodeImage' for automatic OS updates. Use 'SecurityPatch' for security-only updates or configure maintenance windows for controlled updates.";
        URL            = "https://learn.microsoft.com/azure/aks/auto-upgrade-node-os-image?tabs=azure-cli";
    },
    @{
        ID             = "AKSBP010";
        Category       = "Best Practices";
        Name           = "Customized MC_ Resource Group Name";
        Value          =  { -not ($clusterInfo.properties.nodeResourceGroup -like "MC_*") };
        Expected       = $true;
        FailMessage    = "Node resource group uses the default auto-generated 'MC_' naming convention, creating confusing resource organization and making it difficult to identify cluster resources, implement proper tagging strategies, or maintain clear cost allocation across multiple clusters.";
        Severity       = "Medium";
        Recommendation = "Use a custom node resource group name during cluster creation with 'az aks create --node-resource-group <custom-name>'. This cannot be changed after cluster creation, so plan accordingly for better resource organization and management.";
        URL            = "https://learn.microsoft.com/azure/aks/faq#can-i-provide-my-own-name-for-the-aks-node-resource-group-";
    },
    @{
        ID             = "AKSBP011";
        Category       = "Best Practices";
        Name           = "System Node Pool Minimum Size";
        Value          = { ($clusterInfo.properties.agentPoolProfiles | Where-Object { $_.mode -eq "System" }).count -ge 2 };
        Expected       = $true;
        FailMessage    = "System node pool has only 1 node, creating a single point of failure for critical cluster components (kube-proxy, CoreDNS, CNI). Node failure or maintenance will cause system pod disruption, potential cluster instability, and possible workload connectivity issues.";
        Severity       = "High";
        Recommendation = "Scale system node pool to minimum 2 nodes using 'az aks nodepool scale --resource-group <rg> --cluster-name <cluster> --name <system-pool> --node-count 2'. Configure cluster autoscaler with min-count 2 to ensure high availability of system components.";
        URL            = "https://learn.microsoft.com/azure/aks/use-system-pools?tabs=azure-cli#recommendations";
    },
    @{
        ID             = "AKSBP012";
        Category       = "Best Practices";
        Name           = "Node Pool Version Matches Control Plane";
        Value          = {
            $controlPlaneVersion = $clusterInfo.properties.currentKubernetesVersion
            $mismatches = $clusterInfo.properties.agentPoolProfiles | Where-Object {
                $_.currentOrchestratorVersion -ne $controlPlaneVersion
            }
    
            # Save mismatch info for fail message
            Set-Variable -Name 'AKSBP012_MismatchDetails' -Value $mismatches -Scope Script
    
            return ($mismatches.Count -eq 0)
        };
        Expected       = $true;
        FailMessage    = {
            $details = $script:AKSBP012_MismatchDetails | ForEach-Object {
                "$($_.name): $($_.currentOrchestratorVersion)"
            } -join ", "
            $controlPlaneVersion = $clusterInfo.properties.currentKubernetesVersion
            "Node pools out of sync with control plane version ($controlPlaneVersion): $details"
        };
        Severity       = "Medium";
        Recommendation = "Upgrade node pools to match control plane version using 'az aks nodepool upgrade --resource-group <rg> --cluster-name <cluster> --name <nodepool> --kubernetes-version <version>'. Plan coordinated upgrades to maintain version consistency and avoid compatibility issues.";
        URL            = "https://learn.microsoft.com/azure/aks/upgrade-cluster#check-the-current-kubernetes-version"
    },
    @{
        ID             = "AKSBP013";
        Category       = "Best Practices";
        Name           = "No B-Series VMs in Node Pools";
        Value          = { ($clusterInfo.properties.agentPoolProfiles | Where-Object { $_.vmSize -like "Standard_B*" }).Count };
        Expected       = 0;
        FailMessage    = "B-series VMs provide burstable CPU performance that can be exhausted under sustained workloads, leading to unpredictable performance degradation, throttling, and potential application failures. They are unsuitable for production workloads requiring consistent compute performance.";
        Severity       = "High";
        Recommendation = "Replace B-series VMs with consistent performance VMs like Standard_D2s_v5 or Standard_E2s_v5 using 'az aks nodepool add' with new VM size, then drain and delete old node pools. B-series VMs have burstable CPU that can cause performance issues in production.";
        URL            = "https://learn.microsoft.com/en-us/azure/aks/best-practices-app-cluster-reliability#do-not-use-b-series-vms";
    },
    @{
        ID             = "AKSBP014";
        Category       = "Best Practices";
        Name           = "Use v5 or Newer SKU VMs for Node Pools";
        Value          = { ($clusterInfo.properties.agentPoolProfiles | Where-Object { $_.vmSize -notmatch "_v[5-9][0-9]*$" }).Count };
        Expected       = 0;
        FailMessage    = "Node pools are using older VM generations (v4 or earlier) that have reduced performance, lack modern security features, don't support ephemeral OS disks by default, and may experience more frequent maintenance events affecting availability and reliability.";
        Severity       = "Medium";
        Recommendation = "Upgrade to v5 or newer VM SKUs using 'az aks nodepool add --vm-size Standard_D2s_v5' for new node pools. v5 SKUs provide better performance, support ephemeral OS disks by default, and have improved reliability during maintenance events and upgrades.";
        URL            = "https://learn.microsoft.com/en-us/azure/aks/best-practices-app-cluster-reliability#v5-sku-vms";
    }
)
