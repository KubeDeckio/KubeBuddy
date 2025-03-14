$bestPracticesChecks = @(
    @{
        ID             = "BP025";
        Category       = "Best Practices";
        Name           = "Allowed Container Images Policy Enforcement";
        Value          = if ($allowedPolicies = ($kubeResources.ConstraintTemplates.items | Where-Object { $_.metadata.name -eq "k8sazurev2containerallowedimages" })) {
                                $enforcingCount = 0;
                                foreach ($policy in $allowedPolicies) {
                                    if ($policy.status -and $policy.status.byPod) {
                                        foreach ($entry in $policy.status.byPod) {
                                            if (($entry.operations -contains "mutation-webhook") -or ($entry.operations -contains "webhook")) {
                                                $enforcingCount++;
                                            }
                                        }
                                    }
                                }
                                $enforcingCount -gt 0;
                            }
                            else {
                                $false;
                            };
        Expected       = $true;
        FailMessage    = "The 'Only Allowed Images' policy is either missing or not enforcing deny mode.";
        Severity       = "High";
        Recommendation = "Deploy and enforce the 'Only Allowed Images' policy with 'deny' mode to restrict unapproved images.";
        URL            = "https://learn.microsoft.com/en-us/azure/aks/azure-policy";
    },    
    @{
        ID             = "BP026";
        Category       = "Best Practices";
        Name           = "No Privileged Containers Policy Enforcement";
        Value          = if ($noPrivPolicies = ($kubeResources.ConstraintTemplates.items | Where-Object { $_.metadata.name -eq "k8sazurev2noprivilege" })) {
                              $enforcingCount = 0
                              foreach ($policy in $noPrivPolicies) {
                                  if ($policy.status -and $policy.status.byPod) {
                                      foreach ($entry in $policy.status.byPod) {
                                          if (($entry.operations -contains "mutation-webhook") -or ($entry.operations -contains "webhook")) {
                                              $enforcingCount++
                                          }
                                      }
                                  }
                              }
                              $enforcingCount -gt 0
                          }
                          else {
                              $false
                          };
        Expected       = $true;
        FailMessage    = "The 'No Privileged Containers' policy is either missing or not enforcing deny mode.";
        Severity       = "High";
        Recommendation = "Deploy and enforce the 'No Privileged Containers' policy with 'deny' mode (i.e. using mutation-webhook/webhook) to block privileged containers.";
        URL            = "https://learn.microsoft.com/en-us/azure/aks/azure-policy"
    },    
    @{
        ID          = "BP027";
        Category    = "Best Practices";
        Name        = "Multiple node pools";
        Value       = ($clusterInfo.agentPoolProfiles.Count -gt 1);
        Expected    = $true;
        FailMessage = "Use multiple node pools for better resource management."
    },
    @{
        ID             = "BP036";
        Category       = "Best Practices";
        Name           = "Azure Linux as Host OS";
        Value          = ($clusterInfo.agentPoolProfiles | Where-Object { $_.osType -eq "Linux" -and $_.osSKU -ne "AzureLinux" }).Count;
        Expected       = 0;
        FailMessage    = "One or more Linux node pools are not using Azure Linux as the host OS.";
        Severity       = "High";
        Recommendation = "Update all Linux node pools to use Azure Linux.";
        URL            = "https://learn.microsoft.com/en-us/AZURE/aks/use-azure-linux"
    },    
    @{
        ID             = "BP038";
        Category       = "Best Practices";
        Name           = "Ephemeral OS Disks Enabled";
        Value          = ($clusterInfo.agentPoolProfiles | Where-Object { $_.osDiskType -ne "Ephemeral" }).Count;
        Expected       = 0;
        FailMessage    = "One or more agent pools do not use ephemeral OS disks. Ephemeral OS disks lower latency and speed up cluster operations.";
        Severity       = "Medium";
        Recommendation = "Configure all agent pools to use ephemeral OS disks for better performance.";
        URL            = "https://learn.microsoft.com/en-us/azure/aks/ephemeral-os-disks"
    },
    @{
        ID             = "BP039";
        Category       = "Best Practices";
        Name           = "Non-Ephemeral Disks with Adequate Size";
        Value          = ($clusterInfo.agentPoolProfiles | Where-Object { $_.osDiskType -ne "Ephemeral" -and $_.osDiskSizeGb -lt 128 }).Count;
        Expected       = 0;
        FailMessage    = "For non-ephemeral disks, use high IOPS and larger OS disks when running many pods. One or more node pools have OS disks below the recommended size.";
        Severity       = "Medium";
        Recommendation = "Increase the OS disk size (e.g. 128GB or more) for non-ephemeral disks to handle high workloads and log volumes.";
        URL            = "https://learn.microsoft.com/en-us/azure/aks/availability-zone-support"
    },
    @{
        ID             = "BP040";
        Category       = "Best Practices";
        Name           = "System Node Pool Taint";
        Value          = ($clusterInfo.agentPoolProfiles | Where-Object { $_.mode -eq "System" }).nodeTaints -contains "CriticalAddonsOnly=true:NoSchedule";
        Expected       = $true;
        FailMessage    = "The system node pool must have the taint 'CriticalAddonsOnly=true:NoSchedule'.";
        Severity       = "High";
        Recommendation = "Apply the 'CriticalAddonsOnly=true:NoSchedule' taint to the system node pool to restrict scheduling to critical pods only.";
        URL            = "https://learn.microsoft.com/en-us/azure/aks/use-system-node-pools"
    },
    @{
        ID             = "BP034A";
        Category       = "Best Practices";
        Name           = "Auto Upgrade Channel Configured";
        Value          = ($clusterInfo.autoUpgradeProfile.upgradeChannel -ne "none");
        Expected       = $true;
        FailMessage    = "Auto upgrade channel is not properly configured. It should not be 'none'.";
        Severity       = "Medium";
        Recommendation = "Set the auto upgrade channel to a valid option (e.g. 'patch' or 'stable').";
        URL            = "https://learn.microsoft.com/en-us/azure/aks/auto-upgrade";
    },    
    @{
        ID             = "BP034B";
        Category       = "Best Practices";
        Name           = "Node OS Upgrade Channel Configured";
        Value          = ($clusterInfo.autoUpgradeProfile.nodeOSUpgradeChannel -ne "None");
        Expected       = $true;
        FailMessage    = "Node OS upgrade channel is not properly configured. It should not be 'None'.";
        Severity       = "Medium";
        Recommendation = "Set the node OS upgrade channel to a valid option.";
        URL            = "https://learn.microsoft.com/en-us/azure/aks/auto-upgrade";
    },
    @{
        ID             = "BP051";
        Category       = "Best Practices";
        Name           = "Customized MC_ Resource Group Name";
        Value          = -not ($clusterInfo.nodeResourceGroup -like "MC_*");
        Expected       = $true;
        FailMessage    = "The node resource group name is using the default 'MC_' prefix. Customize it for easier management.";
        Severity       = "Medium";
        Recommendation = "Customize the node resource group name by specifying a custom name during AKS creation.";
        URL            = "https://learn.microsoft.com/en-us/azure/aks/concepts-clusters-resource-group"
    }
    
)
