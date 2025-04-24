function Create-JsonReport {
    param (
        [string]$OutputPath,
        [object]$KubeData,
        [switch]$ExcludeNamespaces,
        [switch]$aks,
        [string]$SubscriptionId,
        [string]$ResourceGroup,
        [string]$ClusterName
    )

    # Get cluster metadata
    $clusterName = (kubectl config current-context)
    $versionInfo = kubectl version -o json | ConvertFrom-Json
    $k8sVersion = $versionInfo.serverVersion.gitVersion
    $generatedAt = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")

    # Initialize results structure
    $results = @{
        metadata = @{
            clusterName       = $clusterName
            kubernetesVersion = $k8sVersion
            generatedAt       = $generatedAt
        }
        checks = @{}
    }

    # Run YAML-based checks
    $yamlCheckResults = Invoke-yamlChecks -Json -KubeData $KubeData -ExcludeNamespaces:$ExcludeNamespaces

    # Flatten YAML checks into checks map
    $checksMap = @{}
    foreach ($check in $yamlCheckResults.Items) {
        if ($check.ID) {
            $checksMap[$check.ID] = $check
        }
    }

    # Handle AKS checks if -aks switch is provided
    if ($aks -and $KubeData.AksCluster) {
        # Add filtered AKS metadata
        $results.metadata.aks = @{
            subscriptionId = $KubeData.AksCluster.subscriptionId
            resourceGroup  = $KubeData.AksCluster.resourceGroup
            clusterName    = $KubeData.AksCluster.clusterName
            # Add other relevant AKS metadata as needed
        }

        # Run AKS best practices checks
        try {
            $aksCheckResults = Invoke-AKSBestPractices -Json -KubeData $KubeData -SubscriptionId $SubscriptionId -ResourceGroup $ResourceGroup -ClusterName $ClusterName

            # Integrate AKS checks into checksMap
            if ($aksCheckResults -and $aksCheckResults.Items) {
                foreach ($aksCheck in $aksCheckResults.Items) {
                    if ($aksCheck.ID) {
                        $checksMap[$aksCheck.ID] = $aksCheck
                    }
                }
            }
            else {
                Write-Warning "Invoke-AKSBestPractices returned no valid check results."
                $checksMap['AKSBestPractices'] = @{
                    ID      = 'AKSBestPractices'
                    Name    = 'AKS Best Practices'
                    Message = 'No AKS best practices checks returned.'
                    Total   = 0
                    Items   = @()
                }
            }
        }
        catch {
            Write-Warning "Failed to run AKS best practices: $_"
            $checksMap['AKSBestPractices'] = @{
                ID      = 'AKSBestPractices'
                Name    = 'AKS Best Practices'
                Message = "Error running AKS checks: $_"
                Total   = 0
                Items   = @()
            }
        }
    }

    # Assign checks to results
    $results.checks = $checksMap

    # Calculate score from all checks
    $allChecks = $yamlCheckResults.Items
    if ($aks -and $aksCheckResults -and $aksCheckResults.Items) {
        $allChecks += $aksCheckResults.Items
    }
    $results.metadata.score = Get-ClusterHealthScore -Checks $allChecks

    # Write JSON
    $results | ConvertTo-Json -Depth 10 | Set-Content -Encoding UTF8 $OutputPath
}