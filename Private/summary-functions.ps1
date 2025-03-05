function Check-KubernetesVersion {
    $versionInfo = kubectl version -o json | ConvertFrom-Json
    $k8sVersion = $versionInfo.serverVersion.gitVersion

    # Fetch latest stable Kubernetes version
    $latestVersion = (Invoke-WebRequest -Uri "https://dl.k8s.io/release/stable.txt").Content.Trim()

    if ($k8sVersion -lt $latestVersion) {
        return "⚠️  Cluster is running an outdated version: $k8sVersion (Latest: $latestVersion)"
    }
    else {
        return "✅ Cluster is up to date ($k8sVersion)"
    }
}

function Show-ClusterSummary {
    param(
        [switch]$Html
    )

    if (-not $Global:MakeReport -and -not $Html ) { Clear-Host }
    Write-Host "`n[🌐 Cluster Summary]" -ForegroundColor Cyan

    # Retrieve Kubernetes Version
    Write-Host -NoNewline "`n🤖 Fetching Cluster Information..." -ForegroundColor Yellow
    $versionInfo = kubectl version -o json | ConvertFrom-Json
    $k8sVersion = if ($versionInfo.serverVersion.gitVersion) { $versionInfo.serverVersion.gitVersion } else { "Unknown" }
    $clusterName = (kubectl config current-context)
    Write-Host "`r🤖 Cluster Information fetched." -ForegroundColor Green

    if (-not $Global:MakeReport) {
        Write-Host "`nCluster Name " -NoNewline -ForegroundColor Green
        Write-Host "is " -NoNewline
        Write-Host "$clusterName" -ForegroundColor Yellow
        Write-Host "Kubernetes Version " -NoNewline -ForegroundColor Green
        Write-Host "is " -NoNewline
        Write-Host "$k8sVersion" -ForegroundColor Yellow
        kubectl cluster-info
    }

    # Kubernetes Version Check
    Write-Host -NoNewline "`n🤖 Checking Kubernetes Version Compatibility..." -ForegroundColor Yellow
    $versionCheck = Check-KubernetesVersion
    Write-Host "`r🤖 Kubernetes Version Compatibility checked." -ForegroundColor Green
    if (-not $Global:MakeReport ) { Write-Host "`n$versionCheck" }

    # Cluster Metrics
    Write-Host -NoNewline "`n🤖 Fetching Cluster Metrics..." -ForegroundColor Yellow
    $summary = Show-HeroMetrics
    Write-Host "`r🤖 Cluster Metrics fetched." -ForegroundColor Green
    if (-not $Global:MakeReport ) { Write-Host "`n$summary" }

    # **Fetch Event Counts**
    Write-Host -NoNewline "`n🤖 Counting Kubernetes Events..." -ForegroundColor Yellow
    $events = kubectl get events -A --sort-by=.metadata.creationTimestamp -o json | ConvertFrom-Json

    $warningCount = ($events.items | Where-Object { $_.type -eq "Warning" }).Count
    $errorCount = ($events.items | Where-Object { $_.reason -match "Failed|Error" }).Count

    Write-Host "`r🤖 Kubernetes Events counted." -ForegroundColor Green

    Write-Host "`n❌ Errors: $errorCount   ⚠️ Warnings: $warningCount" -ForegroundColor Yellow

    # Log to report if in report mode
    if ($Global:MakeReport) {
    Write-ToReport "Cluster Name: $clusterName"
    Write-ToReport "Kubernetes Version: $k8sVersion"
    if ($Global:MakeReport) {
        $info = kubectl cluster-info | Out-String
        Write-ToReport $info
    }
    Write-ToReport "Compatibility Check: $versionCheck"
    Write-ToReport "`nMetrics: $summary"
    Write-ToReport "`n❌ Errors: $errorCount   ⚠️ Warnings: $warningCount"
    }

    if (-not $Global:MakeReport -and -not $Html) {
        Read-Host "`nPress Enter to return to the main menu"
    }
}

function Get-NodeSummary {
    $nodes = kubectl get nodes -o json | ConvertFrom-Json
    $totalNodes = $nodes.items.Count
    $healthyNodes = ($nodes.items | Where-Object { ($_ | Select-Object -ExpandProperty status).conditions | Where-Object { $_.type -eq "Ready" -and $_.status -eq "True" } }).Count
    $issueNodes = $totalNodes - $healthyNodes

    return [PSCustomObject]@{
        Total   = $totalNodes
        Healthy = $healthyNodes
        Issues  = $issueNodes
    }
}

# Function: Get Pod Summary
function Get-PodSummary {
    $pods = kubectl get pods --all-namespaces -o json | ConvertFrom-Json
    $totalPods = $pods.items.Count
    $runningPods = ($pods.items | Where-Object { $_.status.phase -eq "Running" }).Count
    $failedPods = ($pods.items | Where-Object { $_.status.phase -eq "Failed" }).Count

    return [PSCustomObject]@{
        Total   = $totalPods
        Running = $runningPods
        Failed  = $failedPods
    }
}

# Function: Get Restart Summary (Now Uses Configurable Thresholds)
function Get-RestartSummary {
    # Load thresholds
    if (-not $Global:MakeReport -and -not $Html) { $thresholds = Get-KubeBuddyThresholds }
    else {
        $thresholds = Get-KubeBuddyThresholds -Silent
    }
    
    $pods = kubectl get pods --all-namespaces -o json | ConvertFrom-Json

    # Ensure restart counts are always integers (default to 0 if null)
    $totalRestarts = ($pods.items | ForEach-Object { 
        ($_.status.containerStatuses | Where-Object { $_.restartCount -gt 0 }).restartCount 
        } | Measure-Object -Sum).Sum

    # Convert to integer explicitly to avoid any decimal issues
    $totalRestarts = [int]($totalRestarts -as [int])

    $warningRestarts = ($pods.items | Where-Object { 
        ($_.status.containerStatuses | Where-Object { $_.restartCount -ge $thresholds.restarts_warning }).Count -gt 0 
        }).Count

    $criticalRestarts = ($pods.items | Where-Object { 
        ($_.status.containerStatuses | Where-Object { $_.restartCount -ge $thresholds.restarts_critical }).Count -gt 0 
        }).Count

    return [PSCustomObject]@{
        Total    = $totalRestarts
        Warning  = $warningRestarts
        Critical = $criticalRestarts
    }
}

function Show-HeroMetrics {
    # Get summaries
    $nodeSummary = Get-NodeSummary
    $podSummary = Get-PodSummary
    $restartSummary = Get-RestartSummary

    # Fetch pod distribution per node
    $nodePodCounts = (kubectl get pods --all-namespaces -o json | ConvertFrom-Json).items | Group-Object { $_.spec.nodeName }
    $podCounts = $nodePodCounts | ForEach-Object { $_.Count }
    $avgPods = [math]::Round(($podCounts | Measure-Object -Average).Average, 1)
    $maxPods = ($podCounts | Measure-Object -Maximum).Maximum
    $minPods = ($podCounts | Measure-Object -Minimum).Minimum

    # Fetch live CPU & Memory usage
    $nodeUsageRaw = kubectl top nodes --no-headers
    $totalCPU = 0; $totalMem = 0; $usedCPU = 0; $usedMem = 0

    $nodeUsageRaw | ForEach-Object {
        $fields = $_ -split "\s+"
        if ($fields.Count -ge 5) {
            $cpuValue = $fields[1] -replace "m", ""
            $memValue = $fields[3] -replace "Mi", ""

            # Only add if not "<unknown>"
            if ($cpuValue -match "^\d+$") { $usedCPU += [int]$cpuValue }
            if ($memValue -match "^\d+$") { $usedMem += [int]$memValue }

            # Assume 1000m per core for CPU, 64GB per node for memory
            $totalCPU += 1000
            $totalMem += 65536
        }
    }

    # Prevent divide-by-zero issues
    $cpuUsagePercent = if ($totalCPU -gt 0) { [math]::Round(($usedCPU / $totalCPU) * 100, 2) } else { 0 }
    $memUsagePercent = if ($totalMem -gt 0) { [math]::Round(($usedMem / $totalMem) * 100, 2) } else { 0 }

    $cpuStatus = if ($cpuUsagePercent -ge 80) { "🔴 Critical" }
    elseif ($cpuUsagePercent -ge 50) { "🟡 Warning" }
    else { "🟩 Normal" }

    $memStatus = if ($memUsagePercent -ge 80) { "🔴 Critical" }
    elseif ($memUsagePercent -ge 50) { "🟡 Warning" }
    else { "🟩 Normal" }

    # Get pending pods count
    $pendingPods = (kubectl get pods --all-namespaces -o json | ConvertFrom-Json).items | Where-Object { $_.status.phase -eq "Pending" }
    $totalPending = $pendingPods.Count

    $stuckPods = (kubectl get pods --all-namespaces -o json | ConvertFrom-Json).items | Where-Object {
        ($_.status.containerStatuses.state.waiting.reason -match "CrashLoopBackOff") -or
        ($_.status.phase -eq "Pending" -and $_.status.PSObject.Properties['startTime'] -and `
        ((New-TimeSpan -Start $_.status.startTime -End (Get-Date)).TotalMinutes -gt 15)) -or
        ($_.status.conditions.reason -match "ContainersNotReady") -or
        ($_.status.conditions.reason -match "PodInitializing") -or
        ($_.status.conditions.reason -match "ImagePullBackOff")
    }
    
    $totalStuckPods = $stuckPods.Count
    
    # Get failed jobs count
    $failedJobs = (kubectl get jobs --all-namespaces -o json | ConvertFrom-Json).items | Where-Object { $_.status.failed -gt 0 }
    $totalFailedJobs = $failedJobs.Count

    $totalNodes = $nodeSummary.Total

    # Table formatting
    $col2 = 10  # Total Count
    $col3 = 14  # Status
    $col4 = 16  # Issues

    # Store output
    $output = @()
    $output += "`n📊 Cluster Metrics Summary"
    $output += "------------------------------------------------------------------------------------------"
    $output += "🚀 Nodes:          {0,$col2}   🟩 Healthy: {1,$col3}   🟥 Issues:   {2,$col4}" -f $nodeSummary.Total, $nodeSummary.Healthy, $nodeSummary.Issues
    $output += "📦 Pods:           {0,$col2}   🟩 Running: {1,$col3}   🟥 Failed:   {2,$col4}" -f $podSummary.Total, $podSummary.Running, $podSummary.Failed
    $output += "🔄 Restarts:       {0,$col2}   🟨 Warnings:{1,$col3}   🟥 Critical: {2,$col4}" -f $restartSummary.Total, $restartSummary.Warning, $restartSummary.Critical
    $output += "⏳ Pending Pods:   {0,$col2}   🟡 Waiting: {1,$col3}   " -f $totalPending, $totalPending
    $output += "⚠️ Stuck Pods:     {0,$col2}   ❌ Stuck:   {1,$col3}     " -f $totalStuckPods, $totalStuckPods
    $output += "📉 Job Failures:   {0,$col2}   🔴 Failed:  {1,$col3}   " -f $totalFailedJobs, $totalFailedJobs
    $output += "------------------------------------------------------------------------------------------"
    $output += ""
    $output += "📊 Pod Distribution: Avg: {0} | Max: {1} | Min: {2} | Total Nodes: {3}" -f $avgPods, $maxPods, $minPods, $totalNodes
    $output += ""
    $output += ""
    $output += "💾 Resource Usage"
    $output += "------------------------------------------------------------------------------------------"
    $output += "🖥  CPU Usage:      {0,$col2}%   {1,$col3}" -f $cpuUsagePercent, $cpuStatus
    $output += "💾 Memory Usage:   {0,$col2}%   {1,$col3}" -f $memUsagePercent, $memStatus
    $output += "------------------------------------------------------------------------------------------"

    return $output -join "`n"
}