function Check-KubernetesVersion {

  $versionInfo = kubectl version -o json | ConvertFrom-Json
  $k8sVersion = $versionInfo.serverVersion.gitVersion

  $latestVersion = (Invoke-WebRequest -Uri "https://dl.k8s.io/release/stable.txt").Content.Trim()

  if ($k8sVersion -lt $latestVersion) {
    return "⚠️  Cluster is running an outdated version: $k8sVersion (Latest: $latestVersion)"
  } else {
    return "✅ Cluster is up to date ($k8sVersion)"
  }
}

function Show-ClusterSummary {
    param(
        [switch]$Html,
        [switch]$Json,
        [switch]$Text,
        [object]$KubeData
    )

    if (-not $Text -and -not $Html -and -not $Json) { Clear-Host }
    Write-Host "`n[🌐 Cluster Summary]" -ForegroundColor Cyan
    Write-Host -NoNewline "`n🤖 Fetching Cluster Information..." -ForegroundColor Yellow

    $versionInfo = kubectl version -o json | ConvertFrom-Json
    $k8sVersion = $versionInfo.serverVersion.gitVersion
    $clusterName = kubectl config current-context

    Write-Host "`r🤖 Cluster Information fetched.   " -ForegroundColor Green

    Write-Host -NoNewline "`n🤖 Checking Kubernetes Version Compatibility..." -ForegroundColor Yellow
    $versionCheckResult = Check-KubernetesVersion
    Write-Host "`r🤖 Kubernetes Version Compatibility checked.   " -ForegroundColor Green

    Write-Host -NoNewline "`n🤖 Fetching Cluster Metrics..." -ForegroundColor Yellow
    $summaryText = Show-HeroMetrics -KubeData:$KubeData -Json:$Json
    Write-Host "`r🤖 Cluster Metrics fetched.   " -ForegroundColor Green

    Write-Host -NoNewline "`n🤖 Counting Kubernetes Events..." -ForegroundColor Yellow
    $events = if ($KubeData) { $KubeData.events } else {
        kubectl get events -A --sort-by=.metadata.creationTimestamp -o json | ConvertFrom-Json
    }

    $warningCount = ($events | Where-Object { $_.type -eq "Warning" }).Count
    $errorCount = ($events | Where-Object { $_.reason -match "Failed|Error" }).Count
    Write-Host "`r🤖 Kubernetes Events counted.   " -ForegroundColor Green

    if ($Json) {
        return @{
            ClusterName   = $clusterName
            KubernetesVersion = $k8sVersion
            VersionStatus = $versionCheckResult
            ErrorEvents   = $errorCount
            WarningEvents = $warningCount
            MetricsSummary = $summaryText
        }
    }

    if (-not $Text) {
        Write-Host "`nCluster Name " -NoNewline -ForegroundColor Green
        Write-Host "is " -NoNewline
        Write-Host "$clusterName" -ForegroundColor Yellow
        Write-Host "Kubernetes Version " -NoNewline -ForegroundColor Green
        Write-Host "is " -NoNewline
        Write-Host "$k8sVersion" -ForegroundColor Yellow
        if (-not $KubeData) { kubectl cluster-info }
        Write-Host "`n$($versionCheckResult)"
        Write-Host "`n$summaryText"
        Write-Host "`n❌ Errors: $errorCount   ⚠️ Warnings: $warningCount" -ForegroundColor Yellow
    }

    if ($Text) {
        Write-ToReport "Cluster Name: $clusterName"
        Write-ToReport "Kubernetes Version: $k8sVersion"
        if (-not $KubeData) {
            $info = kubectl cluster-info | Out-String
            Write-ToReport $info
        }
        Write-ToReport "Compatibility Check: $($versionCheckResult)"
        Write-ToReport "`nMetrics: $summaryText"
        Write-ToReport "`n❌ Errors: $errorCount   ⚠️ Warnings: $warningCount"
    }

    if (-not $Text -and -not $Html) {
        Read-Host "`nPress Enter to return to the main menu"
    }
}

  
function Show-HeroMetrics {
    param (
      [object]$KubeData = $null,
      [switch]$Json
    )
  
    $thresholds = if (-not $Text -and -not $Json) {
      Get-KubeBuddyThresholds
    } else {
      Get-KubeBuddyThresholds -Silent
    }
  
    $nodeData = if ($KubeData) { $KubeData.nodes } else { kubectl get nodes -o json | ConvertFrom-Json }
    $podData = if ($KubeData) { $KubeData.pods } else { kubectl get pods --all-namespaces -o json | ConvertFrom-Json }
    $jobData = if ($KubeData) { $KubeData.jobs } else { kubectl get jobs --all-namespaces -o json | ConvertFrom-Json }
    $topNodes = if ($KubeData) { $KubeData.topNodes } else { kubectl top nodes --no-headers }
  
    $totalNodes = $nodeData.items.Count
    $healthyNodes = ($nodeData.items | Where-Object { $_.status.conditions | Where-Object { $_.type -eq 'Ready' -and $_.status -eq 'True' } }).Count
    $issueNodes = $totalNodes - $healthyNodes
  
    $totalPods = $podData.items.Count
    $runningPods = ($podData.items | Where-Object { $_.status.phase -eq "Running" }).Count
    $failedPods = ($podData.items | Where-Object { $_.status.phase -eq "Failed" }).Count
  
    $restartCounts = $podData.items | ForEach-Object { ($_.status.containerStatuses | Where-Object { $_.restartCount -gt 0 }).restartCount } | Measure-Object -Sum
    $totalRestarts = [int]($restartCounts.Sum)
    $warningRestarts = ($podData.items | Where-Object { ($_.status.containerStatuses | Where-Object { $_.restartCount -ge $thresholds.restarts_warning }).Count -gt 0 }).Count
    $criticalRestarts = ($podData.items | Where-Object { ($_.status.containerStatuses | Where-Object { $_.restartCount -ge $thresholds.restarts_critical }).Count -gt 0 }).Count
  
    $pendingPods = ($podData.items | Where-Object { $_.status.phase -eq "Pending" }).Count
    $stuckPods = ($podData.items | Where-Object {
      ($_.status.containerStatuses.state.waiting.reason -match "CrashLoopBackOff") -or
      ($_.status.phase -eq "Pending" -and $_.status.startTime -and ((New-TimeSpan -Start $_.status.startTime -End (Get-Date)).TotalMinutes -gt 15)) -or
      ($_.status.conditions.reason -match "ContainersNotReady|PodInitializing|ImagePullBackOff")
    }).Count
  
    $failedJobs = ($jobData.items | Where-Object { $_.status.failed -gt 0 }).Count
  
    $nodePodCounts = $podData.items | Group-Object { $_.spec.nodeName }
    $podCounts = $nodePodCounts | ForEach-Object { $_.Count }
    $avgPods = [math]::Round(($podCounts | Measure-Object -Average).Average, 1)
    $maxPods = ($podCounts | Measure-Object -Maximum).Maximum
    $minPods = ($podCounts | Measure-Object -Minimum).Minimum
  
    $usedCPU = 0; $usedMem = 0; $totalCPU = 0; $totalMem = 0
  
    $topNodes | ForEach-Object {
      $fields = $_ -split "\s+"
      if ($fields.Count -ge 5) {
        $cpu = $fields[1] -replace "m", ""
        $mem = $fields[3] -replace "Mi", ""
        if ($cpu -match "^\d+$") { $usedCPU += [int]$cpu }
        if ($mem -match "^\d+$") { $usedMem += [int]$mem }
        $totalCPU += 1000
        $totalMem += 65536
      }
    }
  
    $cpuUsagePercent = if ($totalCPU -gt 0) { [math]::Round(($usedCPU / $totalCPU) * 100, 2) } else { 0 }
    $memUsagePercent = if ($totalMem -gt 0) { [math]::Round(($usedMem / $totalMem) * 100, 2) } else { 0 }
  
    $cpuStatus = if ($cpuUsagePercent -ge 80) { "🔴 Critical" } elseif ($cpuUsagePercent -ge 50) { "🟡 Warning" } else { "🟩 Normal" }
    $memStatus = if ($memUsagePercent -ge 80) { "🔴 Critical" } elseif ($memUsagePercent -ge 50) { "🟡 Warning" } else { "🟩 Normal" }
  
    $col2 = 10; $col3 = 14; $col4 = 16
    $out = @()
    $out += "`n📊 Cluster Metrics Summary"
    $out += "------------------------------------------------------------------------------------------"
    $out += "🚀 Nodes:          {0,$col2}   🟩 Healthy: {1,$col3}   🟥 Issues:   {2,$col4}" -f $totalNodes, $healthyNodes, $issueNodes
    $out += "📦 Pods:           {0,$col2}   🟩 Running: {1,$col3}   🟥 Failed:   {2,$col4}" -f $totalPods, $runningPods, $failedPods
    $out += "🔄 Restarts:       {0,$col2}   🟨 Warnings:{1,$col3}   🟥 Critical: {2,$col4}" -f $totalRestarts, $warningRestarts, $criticalRestarts
    $out += "⏳ Pending Pods:   {0,$col2}   🟡 Waiting: {1,$col3}   " -f $pendingPods, $pendingPods
    $out += "⚠️ Stuck Pods:     {0,$col2}   ❌ Stuck:   {1,$col3}     " -f $stuckPods, $stuckPods
    $out += "📉 Job Failures:   {0,$col2}   🔴 Failed:  {1,$col3}   " -f $failedJobs, $failedJobs
    $out += "------------------------------------------------------------------------------------------"
    $out += ""
    $out += "📊 Pod Distribution: Avg: {0} | Max: {1} | Min: {2} | Total Nodes: {3}" -f $avgPods, $maxPods, $minPods, $totalNodes
    $out += ""
    $out += ""
    $out += "💾 Resource Usage"
    $out += "------------------------------------------------------------------------------------------"
    $out += "🖥  CPU Usage:      {0,$col2}%   {1,$col3}" -f $cpuUsagePercent, $cpuStatus
    $out += "💾 Memory Usage:   {0,$col2}%   {1,$col3}" -f $memUsagePercent, $memStatus
    $out += "------------------------------------------------------------------------------------------"
  
    return $out -join "`n"
  }
  