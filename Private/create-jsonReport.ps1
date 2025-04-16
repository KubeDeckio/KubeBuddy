function Create-JsonReport {
    param (
        [string]$OutputPath,
        [object]$KubeData,
        [switch]$aks,
        [string]$SubscriptionId,
        [string]$ResourceGroup,
        [string]$ClusterName
    )

    $clusterName = (kubectl config current-context)
    $versionInfo = kubectl version -o json | ConvertFrom-Json
    $k8sVersion = $versionInfo.serverVersion.gitVersion
    $generatedAt = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")

    # Run YAML-based checks
    $yamlCheckResults = Invoke-yamlChecks -Json -KubeData $KubeData

    # Flatten checks so each check ID is a top-level property
    $checksMap = @{}
    foreach ($check in $yamlCheckResults.Items) {
        if ($check.ID) {
            $checksMap[$check.ID] = $check
        }
    }

    # Build the final JSON structure
    $results = @{
        metadata = @{
            clusterName       = $clusterName
            kubernetesVersion = $k8sVersion
            generatedAt       = $generatedAt
        }
        checks = $checksMap
    }

    if ($aks -and $KubeData.AksCluster) {
        $results.metadata.aks = $KubeData.AksCluster
        $results.checks.AKSBestPractices = Invoke-AKSBestPractices -Json -KubeData $KubeData
    }

    # Calculate score from individual check statuses
    $results.metadata.score = Get-ClusterHealthScore -Checks $yamlCheckResults.Items

    # Write JSON
    $results | ConvertTo-Json -Depth 10 | Set-Content -Encoding UTF8 $OutputPath
}
