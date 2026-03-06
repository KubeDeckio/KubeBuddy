function Create-JsonReport {
    param (
        [string]$OutputPath,
        [object]$KubeData,
        [switch]$ExcludeNamespaces,
        [switch]$aks,
        [string]$SubscriptionId,
        [string]$ResourceGroup,
        [string]$ClusterName,
        [switch]$IncludeRadarArtifacts
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
        checks   = @{}
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

    # Handle AKS metadata/checks if -aks switch is provided
    if ($aks) {
        # Prefer values discovered in KubeData, but always fall back to explicit CLI parameters.
        $aksSubscriptionId = $null
        $aksResourceGroup = $null
        $aksClusterName = $null

        if ($KubeData -and $KubeData.AksCluster) {
            $aksSubscriptionId = $KubeData.AksCluster.subscriptionId
            $aksResourceGroup = $KubeData.AksCluster.resourceGroup
            $aksClusterName = $KubeData.AksCluster.clusterName
        }

        if (-not $aksSubscriptionId) { $aksSubscriptionId = $SubscriptionId }
        if (-not $aksResourceGroup) { $aksResourceGroup = $ResourceGroup }
        if (-not $aksClusterName) { $aksClusterName = $ClusterName }

        $results.metadata.aks = @{
            subscriptionId = $aksSubscriptionId
            resourceGroup  = $aksResourceGroup
            clusterName    = $aksClusterName
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

    $validChecks = $allChecks | Where-Object {
        $_.Weight -ne $null -and
        -not $_.Error -and
        $_.ID -ne $null
    }
    
    $results.metadata.score = Get-ClusterHealthScore -Checks $validChecks
    
    # ----- Add Prometheus Metrics to JSON -----
    if ($KubeData.PrometheusMetrics) {
        # Cluster-level averages
        $cpuValues = $KubeData.PrometheusMetrics.NodeCpuUsagePercent | ForEach-Object { $_.values | ForEach-Object { [double]$_[1] } }
        $memValues = $KubeData.PrometheusMetrics.NodeMemoryUsagePercent | ForEach-Object { $_.values | ForEach-Object { [double]$_[1] } }
        $clusterMetrics = [PSCustomObject]@{
            avgCpuPercent = [math]::Round(($cpuValues | Measure-Object -Average).Average, 2)
            avgMemPercent = [math]::Round(($memValues | Measure-Object -Average).Average, 2)
            cpuTimeSeries = (
                $KubeData.PrometheusMetrics.NodeCpuUsagePercent |
                ForEach-Object { $_.values | ForEach-Object { [PSCustomObject]@{ timestamp = [int64]($_[0] * 1000); value = [double]$_[1] } } } |
                Group-Object timestamp |
                ForEach-Object { [PSCustomObject]@{ timestamp = $_.Name; value = [math]::Round(($_.Group | Measure-Object -Property value -Average).Average, 2) } } |
                Sort-Object timestamp
            )
            memTimeSeries = (
                $KubeData.PrometheusMetrics.NodeMemoryUsagePercent |
                ForEach-Object { $_.values | ForEach-Object { [PSCustomObject]@{ timestamp = [int64]($_[0] * 1000); value = [double]$_[1] } } } |
                Group-Object timestamp |
                ForEach-Object { [PSCustomObject]@{ timestamp = $_.Name; value = [math]::Round(($_.Group | Measure-Object -Property value -Average).Average, 2) } } |
                Sort-Object timestamp
            )
        }

        # Node-level metrics
        $nodeMetricsList = @()
        foreach ($node in $KubeData.Nodes.items) {
            $name = $node.metadata.name
        
            $cpuMatch = $KubeData.PrometheusMetrics.NodeCpuUsagePercent | Where-Object { $_.metric.instance -match $name }
            $memMatch = $KubeData.PrometheusMetrics.NodeMemoryUsagePercent | Where-Object { $_.metric.instance -match $name }
            $diskMatch = $KubeData.PrometheusMetrics.NodeDiskUsagePercent | Where-Object { $_.metric.instance -match $name }
        
            $cpuSeries = if ($cpuMatch -and $cpuMatch.values) {
                $cpuMatch.values | ForEach-Object {
                    [PSCustomObject]@{ timestamp = [int64]($_[0] * 1000); value = [double]$_[1] }
                }
            } else { @() }
        
            $memSeries = if ($memMatch -and $memMatch.values) {
                $memMatch.values | ForEach-Object {
                    [PSCustomObject]@{ timestamp = [int64]($_[0] * 1000); value = [double]$_[1] }
                }
            } else { @() }
        
            $diskSeries = if ($diskMatch -and $diskMatch.values) {
                $diskMatch.values | ForEach-Object {
                    [PSCustomObject]@{ timestamp = [int64]($_[0] * 1000); value = [double]$_[1] }
                }
            } else { @() }
        
            $nodeMetricsList += [PSCustomObject]@{
                nodeName   = $name
                cpuAvg     = if ($cpuSeries.Count -gt 0) { [math]::Round(($cpuSeries.value | Measure-Object -Average).Average, 2) } else { 'N/A' }
                memAvg     = if ($memSeries.Count -gt 0) { [math]::Round(($memSeries.value | Measure-Object -Average).Average, 2) } else { 'N/A' }
                diskAvg    = if ($diskSeries.Count -gt 0) { [math]::Round(($diskSeries.value | Measure-Object -Average).Average, 2) } else { 'N/A' }
                cpuSeries  = $cpuSeries
                memSeries  = $memSeries
                diskSeries = $diskSeries
            }
        }

        $results.metrics = @{ cluster = $clusterMetrics; nodes = $nodeMetricsList }
    }

    if ($IncludeRadarArtifacts) {
        $results.artifacts = Get-KubeBuddyRadarArtifactInventory -KubeData $KubeData
    }

    # Write JSON
    $results | ConvertTo-Json -Depth 10 | Set-Content -Encoding UTF8 $OutputPath
}
