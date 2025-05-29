$bestPracticesChecks = @(
    @{
        ID             = "AKSBP001";
        Category       = "Best Practices";
        Name           = "Allowed Container Images Policy Enforcement";
        Value          = { ($clusterInfo.properties.kubeData.Constraints.items | Where-Object { $_.kind -eq "K8sAzureV2ContainerAllowedImages"}).spec.enforcementAction -contains "deny" };
        Expected       = $true;
        FailMessage    = "The 'Only Allowed Images' policy is either missing or not enforcing deny mode, increasing the risk of running untrusted images.";
        Severity       = "High";
        Recommendation = "Deploy and enforce the 'Only Allowed Images' policy with deny mode to restrict unapproved images.";
        URL            = "https://learn.microsoft.com/azure/aks/policy-reference";
    },    
    @{
        ID             = "AKSBP002";
        Category       = "Best Practices";
        Name           = "No Privileged Containers Policy Enforcement";
        Value          = { ($clusterInfo.properties.kubeData.Constraints.items | Where-Object { $_.kind -eq "K8sAzureV2NoPrivilege"}).spec.enforcementAction -contains "deny" };
        Expected       = $true;
        FailMessage    = "The 'No Privileged Containers' policy is either missing or not enforcing deny mode, allowing potentially insecure workloads.";
        Severity       = "High";
        Recommendation = "Deploy and enforce the 'No Privileged Containers' policy in deny mode to block privileged containers and enhance security.";
        URL            = "https://learn.microsoft.com/azure/aks/policy-reference";
    },
    @{
        ID          = "AKSBP003";
        Category    = "Best Practices";
        Name        = "Multiple Node Pools";
        Value       = { $clusterInfo.properties.agentPoolProfiles.Count -gt 1 };
        Expected    = $true;
        FailMessage = "Only a single node pool is in use, reducing flexibility and workload separation.";
        Severity    = "Medium";
        Recommendation = "Use multiple node pools to optimize workload performance, security, and resource utilization.";
        URL         = "https://learn.microsoft.com/azure/aks/use-multiple-node-pools";
    },
    @{
        ID             = "AKSBP004";
        Category       = "Best Practices";
        Name           = "Azure Linux as Host OS";
        Value          = { ($clusterInfo.properties.agentPoolProfiles | Where-Object { $_.osType -eq "Linux" -and $_.osSKU -ne "AzureLinux" }).Count };
        Expected       = 0;
        FailMessage    = "One or more Linux node pools are not using Azure Linux as the host OS, which may impact compatibility and support.";
        Severity       = "High";
        Recommendation = "Migrate Linux node pools to Azure Linux to ensure better performance and compatibility.";
        URL            = "https://learn.microsoft.com/azure/aks/use-azure-linux";
    },    
    @{
        ID             = "AKSBP005";
        Category       = "Best Practices";
        Name           = "Ephemeral OS Disks Enabled";
        Value          = { ($clusterInfo.properties.agentPoolProfiles | Where-Object { $_.osDiskType -ne "Ephemeral" }).Count };
        Expected       = 0;
        FailMessage    = "One or more agent pools are not using ephemeral OS disks, leading to slower disk performance and increased costs.";
        Severity       = "Medium";
        Recommendation = "Configure all agent pools to use ephemeral OS disks for faster disk performance and lower costs.";
        URL            = "https://learn.microsoft.com/azure/aks/concepts-storage#ephemeral-os-disk";
    },
    @{
        ID             = "AKSBP006";
        Category       = "Best Practices";
        Name           = "Non-Ephemeral Disks with Adequate Size";
        Value          = { ($clusterInfo.properties.agentPoolProfiles | Where-Object { $_.osDiskType -ne "Ephemeral" -and $_.osDiskSizeGb -lt 128 }).Count };
        Expected       = 0;
        FailMessage    = "One or more node pools have OS disks smaller than 128GB, which may impact performance under high workloads.";
        Severity       = "Medium";
        Recommendation = "Increase OS disk size to 128GB or more for non-ephemeral disks to optimize workload performance.";
        URL            = "https://learn.microsoft.com/azure/aks/concepts-storage#managed-os-disks";
    },
    @{
        ID             = "AKSBP007";
        Category       = "Best Practices";
        Name           = "System Node Pool Taint";
        Value          = { ($clusterInfo.properties.agentPoolProfiles | Where-Object { $_.mode -eq "System" }).nodeTaints -contains "CriticalAddonsOnly=true:NoSchedule" };
        Expected       = $true;
        FailMessage    = "The system node pool does not have the required taint 'CriticalAddonsOnly=true:NoSchedule', potentially affecting system pod placement.";
        Severity       = "High";
        Recommendation = "Apply the 'CriticalAddonsOnly=true:NoSchedule' taint to the system node pool to ensure only critical system pods run on it.";
        URL            = "https://learn.microsoft.com/azure/aks/use-system-pools?tabs=azure-cli#system-and-user-node-pools";
    },
    @{
        ID             = "AKSBP008";
        Category       = "Best Practices";
        Name           = "Auto Upgrade Channel Configured";
        Value          = { $clusterInfo.properties.autoUpgradeProfile.upgradeChannel -ne "none" };
        Expected       = $true;
        FailMessage    = "Auto upgrade channel is not configured, meaning the cluster will not automatically receive security patches and updates.";
        Severity       = "Medium";
        Recommendation = "Set the auto upgrade channel to an appropriate option (e.g., 'patch' or 'stable') to keep your AKS cluster updated.";
        URL            = "https://learn.microsoft.com/azure/aks/auto-upgrade-cluster?tabs=azure-cli";
    },    
    @{
        ID             = "AKSBP009";
        Category       = "Best Practices";
        Name           = "Node OS Upgrade Channel Configured";
        Value          = { ($clusterInfo.properties.autoUpgradeProfile.nodeOSUpgradeChannel -ne "None") };
        Expected       = $true;
        FailMessage    = "Node OS upgrade channel is not configured, which may leave your node OS outdated and vulnerable.";
        Severity       = "Medium";
        Recommendation = "Configure the node OS upgrade channel to ensure timely updates and security patches.";
        URL            = "https://learn.microsoft.com/azure/aks/auto-upgrade-node-os-image?tabs=azure-cli";
    },
    @{
        ID             = "AKSBP010";
        Category       = "Best Practices";
        Name           = "Customized MC_ Resource Group Name";
        Value          =  { -not ($clusterInfo.properties.nodeResourceGroup -like "MC_*") };
        Expected       = $true;
        FailMessage    = "The node resource group is using the default 'MC_' prefix, which makes management less intuitive.";
        Severity       = "Medium";
        Recommendation = "Specify a custom node resource group name during AKS cluster creation for better organization and clarity.";
        URL            = "https://learn.microsoft.com/azure/aks/faq#can-i-provide-my-own-name-for-the-aks-node-resource-group-";
    },
    @{
        ID             = "AKSBP011";
        Category       = "Best Practices";
        Name           = "System Node Pool Minimum Size";
        Value          = { ($clusterInfo.properties.agentPoolProfiles | Where-Object { $_.mode -eq "System" }).count -ge 2 };
        Expected       = $true;
        FailMessage    = "System node pool has fewer than 2 nodes. This may impact reliability and cluster operations.";
        Severity       = "High";
        Recommendation = "Set the system node pool to have at least 2 nodes to meet HA and AKS supportability guidance.";
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
        Recommendation = "Align all node pool versions with the control plane to simplify upgrades and reduce risk.";
        URL            = "https://learn.microsoft.com/azure/aks/upgrade-cluster#check-the-current-kubernetes-version"
    },
    @{
        ID             = "AKSBP013";
        Category       = "Best Practices";
        Name           = "No B-Series VMs in Node Pools";
        Value          = { ($clusterInfo.properties.agentPoolProfiles | Where-Object { $_.vmSize -like "Standard_B*" }).Count };
        Expected       = 0;
        FailMessage    = "One or more node pools are using B-series VMs, which are not recommended for production workloads due to their burstable performance.";
        Severity       = "High";
        Recommendation = "Replace B-series VMs with general-purpose VM sizes (e.g., D-series or E-series) for consistent performance in production workloads.";
        URL            = "https://learn.microsoft.com/en-us/azure/aks/best-practices-app-cluster-reliability#do-not-use-b-series-vms";
    },
    @{
        ID             = "AKSBP014";
        Category       = "Best Practices";
        Name           = "Use v5 or Newer SKU VMs for Node Pools";
        Value          = { ($clusterInfo.properties.agentPoolProfiles | Where-Object { $_.vmSize -notmatch "_v[5-9][0-9]*$" }).Count };
        Expected       = 0;
        FailMessage    = "One or more node pools are not using v5 or newer SKU VMs, which may result in reduced performance and reliability during updates.";
        Severity       = "Medium";
        Recommendation = "Configure all node pools to use v5 or newer SKU VMs (e.g., Standard_D2_v5, Standard_E4_v6) with ephemeral OS disks for optimal performance and reliability.";
        URL            = "https://learn.microsoft.com/en-us/azure/aks/best-practices-app-cluster-reliability#v5-sku-vms";
    }
)
