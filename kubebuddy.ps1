function Get-KubeBuddyThresholds {
    param(
        [switch]$Silent  # Suppress output when set
    )

    $configPath = "$HOME/.kube/kubebuddy-config.yaml"

    if (Test-Path $configPath) {
        try {
            # Read the YAML file and convert it to a PowerShell object
            $configContent = Get-Content -Raw $configPath | ConvertFrom-Yaml
            
            if ($configContent -and $configContent.thresholds) {
                return $configContent.thresholds
            }
            else {
                if (-not $Silent) {
                    Write-Host "⚠️ Config found, but missing 'thresholds' section. Using defaults..." -ForegroundColor Yellow
                }
            }
        }
        catch {
            if (-not $Silent) {
                Write-Host "❌ Failed to parse config file. Using defaults..." -ForegroundColor Red
            }
        }
    }
    else {
        if (-not $Silent) {
            Write-Host "⚠️ No config found. Using default thresholds..." -ForegroundColor Yellow
        }
    }

    # Return default thresholds if no valid config is found
    return @{
        cpu_warning       = 50
        cpu_critical      = 75
        mem_warning       = 50
        mem_critical      = 75
        restarts_warning  = 3
        restarts_critical = 5
        pod_age_warning   = 15
        pod_age_critical  = 40
    }
}

function Show-ClusterInfo {
    Write-Host "`n[Cluster Information]" -ForegroundColor Cyan
    $versionInfo = kubectl version -o json | ConvertFrom-Json
    $k8sVersion = if ($versionInfo.serverVersion.gitVersion) { $versionInfo.serverVersion.gitVersion } else { "Unknown" }
    $clusterName = (kubectl config current-context)
    Write-Host "Cluster Name " -NoNewline -ForegroundColor Green
    Write-Host "is " -NoNewline
    Write-Host "$clusterName" -ForegroundColor Yellow
    Write-Host "Kubernetes Version " -NoNewline -ForegroundColor Green
    Write-Host "is " -NoNewline
    Write-Host "$k8sVersion" -ForegroundColor Yellow

    kubectl cluster-info

}

# Summary functions
# Function: Get Node Summary
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
    $thresholds = Get-KubeBuddyThresholds -Silent
    
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



# Overview functions
function Show-NodeConditions {
    param(
        [int]$PageSize = 10  # Number of nodes per page
    )

    Write-Host "`n[Node Conditions]" -ForegroundColor Cyan
    $nodes = kubectl get nodes -o json | ConvertFrom-Json
    $totalNodes = $nodes.items.Count

    if ($totalNodes -eq 0) {
        Write-Host "No nodes found." -ForegroundColor Red
        return
    }

    $currentPage = 0
    $totalPages = [math]::Ceiling($totalNodes / $PageSize)

    do {
        Clear-Host
        Write-Host "`n[Node Conditions - Page $($currentPage + 1) of $totalPages]" -ForegroundColor Cyan

        $startIndex = $currentPage * $PageSize
        $endIndex = [math]::Min($startIndex + $PageSize, $totalNodes)

        $tableData = @()

        for ($i = $startIndex; $i -lt $endIndex; $i++) {
            $node = $nodes.items[$i]
            $name = $node.metadata.name
            $conditions = $node.status.conditions

            $readyCondition = $conditions | Where-Object { $_.type -eq "Ready" }
            $issueConditions = $conditions | Where-Object { $_.type -ne "Ready" -and $_.status -ne "False" }

            if ($readyCondition -and $readyCondition.status -eq "True") {
                $status = "✅ Healthy"
                $issues = "None"
            }
            else {
                $status = "❌ Not Ready"
                $issues = if ($issueConditions) {
                    ($issueConditions | ForEach-Object { "$($_.type): $($_.message)" }) -join " | "
                }
                else {
                    "Unknown Issue"
                }
            }

            $tableData += [PSCustomObject]@{
                Node   = $name
                Status = $status
                Issues = $issues
            }
        }

        $tableData | Format-Table -AutoSize

        # Pagination controls
        Write-Host "`nPage $($currentPage + 1) of $totalPages"

        $options = @()
        if ($currentPage -lt ($totalPages - 1)) { $options += "N = Next" }
        if ($currentPage -gt 0) { $options += "P = Previous" }
        $options += "C = Continue"
        
        Write-Host ($options -join ", ") -ForegroundColor Yellow

        do {
            $paginationInput = Read-Host "Enter your choice"
        } while ($paginationInput -notmatch "^[NnPpCc]$" -or 
                 ($paginationInput -match "^[Nn]$" -and $currentPage -eq ($totalPages - 1)) -or 
                 ($paginationInput -match "^[Pp]$" -and $currentPage -eq 0))

        if ($paginationInput -match "^[Nn]$") {
            $currentPage++
        }
        elseif ($paginationInput -match "^[Pp]$") {
            $currentPage--
        }
        elseif ($paginationInput -match "^[Cc]$") {
            break # Exit pagination and continue script
        }

    } while ($true)
    

}


function Show-NodeResourceUsage {
    param(
        [int]$PageSize = 10  # Number of nodes per page
    )

    Write-Host "`n[Node Resource Usage]" -ForegroundColor Cyan
    $thresholds = Get-KubeBuddyThresholds
    $allocatableRaw = kubectl get nodes -o json | ConvertFrom-Json
    $nodeUsageRaw = kubectl top nodes --no-headers

    $totalNodes = $allocatableRaw.items.Count

    if ($totalNodes -eq 0) {
        Write-Host "No nodes found." -ForegroundColor Red
        return
    }

    $currentPage = 0
    $totalPages = [math]::Ceiling($totalNodes / $PageSize)

    do {
        Clear-Host
        Write-Host "`n[Node Resource Usage - Page $($currentPage + 1) of $totalPages]" -ForegroundColor Cyan

        $startIndex = $currentPage * $PageSize
        $endIndex = [math]::Min($startIndex + $PageSize, $totalNodes)

        $tableData = @()

        for ($i = $startIndex; $i -lt $endIndex; $i++) {
            $node = $allocatableRaw.items[$i]
            $nodeName = $node.metadata.name
            $allocatableCPU = [int]($node.status.allocatable.cpu -replace "m", "")
            $allocatableMem = [math]::Round(([int]($node.status.allocatable.memory -replace "Ki", "")) / 1024)

            $nodeStats = $nodeUsageRaw | Where-Object { $_ -match "^$nodeName\s" }
            if ($nodeStats) {
                $values = $nodeStats -split "\s+"
                $usedCPU = if ($values[1] -match "^\d+m?$") { [int]($values[1] -replace "m", "") } else { 0 }
                $usedMem = if ($values[3] -match "^\d+Mi?$") { [math]::Round([int]($values[3] -replace "Mi", "")) } else { 0 }

                $cpuUsagePercent = [math]::Round(($usedCPU / $allocatableCPU) * 100, 2)
                $memUsagePercent = [math]::Round(($usedMem / $allocatableMem) * 100, 2)

                $cpuAlert = if ($cpuUsagePercent -gt $thresholds.cpu_critical) { "🔴 Critical" }
                elseif ($cpuUsagePercent -gt $thresholds.cpu_warning) { "🟡 Warning" }
                else { "✅ Normal" }

                $memAlert = if ($memUsagePercent -gt $thresholds.mem_critical) { "🔴 Critical" }
                elseif ($memUsagePercent -gt $thresholds.mem_warning) { "🟡 Warning" }
                else { "✅ Normal" }

                # Add disk usage check
                $diskUsagePercent = "<unknown>"
                $diskStatus = "⚠️ Unknown"

                if ($values.Length -ge 5 -and $values[4] -match "^\d+%$") {
                    $diskUsagePercent = [int]($values[4] -replace "%", "")

                    $diskStatus = if ($diskUsagePercent -gt 80) { "🔴 Critical" }
                    elseif ($diskUsagePercent -gt 60) { "🟡 Warning" }
                    else { "✅ Normal" }
                }

                $tableData += [PSCustomObject]@{
                    Node          = $nodeName
                    "CPU %"       = "$cpuUsagePercent%"
                    "CPU Used"    = "$usedCPU mC"
                    "CPU Total"   = "$allocatableCPU mC"
                    "CPU Status"  = $cpuAlert
                    "Mem %"       = "$memUsagePercent%"
                    "Mem Used"    = "$usedMem Mi"
                    "Mem Total"   = "$allocatableMem Mi"
                    "Mem Status"  = $memAlert
                    "Disk %"      = if ($diskUsagePercent -eq "<unknown>") { "⚠️ Unknown" } else { "$diskUsagePercent%" }
                    "Disk Status" = $diskStatus
                }
            }
        }

        $tableData | Format-Table -Property Node, "CPU %", "CPU Used", "CPU Total", "CPU Status", "Mem %", "Mem Used", "Mem Total", "Mem Status", "Disk %", "Disk Status" -AutoSize

        # Pagination controls
        Write-Host "`nPage $($currentPage + 1) of $totalPages"

        $options = @()
        if ($currentPage -lt ($totalPages - 1)) { $options += "N = Next" }
        if ($currentPage -gt 0) { $options += "P = Previous" }
        $options += "C = Continue"

        Write-Host ($options -join ", ") -ForegroundColor Yellow

        do {
            $paginationInput = Read-Host "Enter your choice"
        } while ($paginationInput -notmatch "^[NnPpCc]$" -or 
                 ($paginationInput -match "^[Nn]$" -and $currentPage -eq ($totalPages - 1)) -or 
                 ($paginationInput -match "^[Pp]$" -and $currentPage -eq 0))

        if ($paginationInput -match "^[Nn]$") {
            $currentPage++
        }
        elseif ($paginationInput -match "^[Pp]$") {
            $currentPage--
        }
        elseif ($paginationInput -match "^[Cc]$") {
            break # Exit pagination and continue script
        }

    } while ($true)


}

function Show-PodsWithHighRestarts {
    param(
        [string]$Namespace = "",
        [int]$PageSize = 10  # Number of pods per page
    )

    Write-Host "`n[Pods with High Restarts]`n" -ForegroundColor Cyan
    $thresholds = Get-KubeBuddyThresholds

    if ($Namespace -ne "") {
        try {
            $restartPods = kubectl get pods -n $Namespace -o json 2>&1 | ConvertFrom-Json
        }
        catch {
            Write-Host "⚠️ Error retrieving pod data: $_" -ForegroundColor Red
            return
        }
        
    }
    else {
        try {
            $restartPods = kubectl get pods --all-namespaces -o json 2>&1 | ConvertFrom-Json
        }
        catch {
            Write-Host "⚠️ Error retrieving pod data: $_" -ForegroundColor Red
            return
        }
    }
    

    # Filter out pods with normal restarts
    $filteredPods = @()

    foreach ($pod in $restartPods.items) {
        $ns = $pod.metadata.namespace
        $podName = $pod.metadata.name
        $deployment = if ($pod.metadata.ownerReferences) { $pod.metadata.ownerReferences[0].name } else { "N/A" }

        # Retrieve restart count from the first container
        $restarts = if ($pod.status.containerStatuses -and $pod.status.containerStatuses.Count -gt 0) { 
            [int]$pod.status.containerStatuses[0].restartCount 
        }
        else { 
            0 
        }

        # Determine restart status and filter
        $restartStatus = $null
        if ($restarts -gt $thresholds.restarts_critical) {
            $restartStatus = "🔴 Critical"
        }
        elseif ($restarts -gt $thresholds.restarts_warning) {
            $restartStatus = "🟡 Warning"
        }

        # Only include pods with issues
        if ($restartStatus) {
            $filteredPods += [PSCustomObject]@{
                Namespace  = $ns
                Pod        = $podName
                Deployment = $deployment
                Restarts   = $restarts
                Status     = $restartStatus
            }
        }
    }

    $totalPods = $filteredPods.Count

    if ($totalPods -eq 0) {
        Write-Host "✅ No pods with excessive restarts." -ForegroundColor Green
        Read-Host "🤖 Press Enter to return to the menu"
        return
    }

    $currentPage = 0
    $totalPages = [math]::Ceiling($totalPods / $PageSize)

    do {
        Clear-Host
        Write-Host "`n[Pods with High Restarts - Page $($currentPage + 1) of $totalPages]" -ForegroundColor Cyan

        $startIndex = $currentPage * $PageSize
        $endIndex = [math]::Min($startIndex + $PageSize, $totalPods)

        $tableData = $filteredPods[$startIndex..($endIndex - 1)]

        if ($tableData) {
            $tableData | Format-Table -AutoSize
        }

        # Pagination controls
        Write-Host "`nPage $($currentPage + 1) of $totalPages"

        $options = @()
        if ($currentPage -lt ($totalPages - 1)) { $options += "N = Next" }
        if ($currentPage -gt 0) { $options += "P = Previous" }
        $options += "C = Continue"

        Write-Host ($options -join ", ") -ForegroundColor Yellow

        do {
            $paginationInput = Read-Host "Enter your choice"
        } while ($paginationInput -notmatch "^[NnPpCc]$" -or 
                 ($paginationInput -match "^[Nn]$" -and $currentPage -eq ($totalPages - 1)) -or 
                 ($paginationInput -match "^[Pp]$" -and $currentPage -eq 0))

        if ($paginationInput -match "^[Nn]$") {
            $currentPage++
        }
        elseif ($paginationInput -match "^[Pp]$") {
            $currentPage--
        }
        elseif ($paginationInput -match "^[Cc]$") {
            break # Exit pagination and continue script
        }

    } while ($true)


}

function Show-LongRunningPods {
    param(
        [string]$Namespace = "",
        [int]$PageSize = 10  # Number of pods per page
    )

    Write-Host "`n[Long Running Pods]`n" -ForegroundColor Cyan
    $thresholds = Get-KubeBuddyThresholds
    if ($Namespace -ne "") {
        try {
            $stalePods = kubectl get pods -n $Namespace -o json 2>&1 | ConvertFrom-Json
        }
        catch {
            Write-Host "⚠️ Error retrieving pod data: $_" -ForegroundColor Red
            return
        }
        
    }
    else {
        try {
            $stalePods = kubectl get pods --all-namespaces -o json 2>&1 | ConvertFrom-Json
        }
        catch {
            Write-Host "⚠️ Error retrieving pod data: $_" -ForegroundColor Red
            return
        }
    }
    

    # Filter only pods exceeding warning/critical threshold
    $filteredPods = @()

    foreach ($pod in $stalePods.items) {
        $ns = $pod.metadata.namespace
        $podName = $pod.metadata.name
        $status = $pod.status.phase  

        # Only check Running pods with a valid startTime
        if ($status -eq "Running" -and $pod.status.PSObject.Properties['startTime'] -and $pod.status.startTime) {
            $startTime = [datetime]$pod.status.startTime
            $ageDays = ((Get-Date) - $startTime).Days

            $podStatus = $null
            if ($ageDays -gt $thresholds.pod_age_critical) {
                $podStatus = "🔴 Critical"
            }
            elseif ($ageDays -gt $thresholds.pod_age_warning) {
                $podStatus = "🟡 Warning"
            }

            # Only add pods that exceed thresholds
            if ($podStatus) {
                $filteredPods += [PSCustomObject]@{
                    Namespace = $ns
                    Pod       = $podName
                    Age_Days  = $ageDays
                    Status    = $podStatus
                }
            }
        }
    }

    $totalPods = $filteredPods.Count

    if ($totalPods -eq 0) {
        Write-Host "✅ No long-running pods." -ForegroundColor Green
        Read-Host "🤖 Press Enter to return to the menu"
        return
    }

    $currentPage = 0
    $totalPages = [math]::Ceiling($totalPods / $PageSize)

    do {
        Clear-Host
        Write-Host "`n[Long Running Pods - Page $($currentPage + 1) of $totalPages]" -ForegroundColor Cyan

        $startIndex = $currentPage * $PageSize
        $endIndex = [math]::Min($startIndex + $PageSize, $totalPods)

        $tableData = $filteredPods[$startIndex..($endIndex - 1)]

        if ($tableData) {
            $tableData | Format-Table -AutoSize
        }

        # Pagination controls
        Write-Host "`nPage $($currentPage + 1) of $totalPages"

        $options = @()
        if ($currentPage -lt ($totalPages - 1)) { $options += "N = Next" }
        if ($currentPage -gt 0) { $options += "P = Previous" }
        $options += "C = Continue"

        Write-Host ($options -join ", ") -ForegroundColor Yellow

        do {
            $paginationInput = Read-Host "Enter your choice"
        } while ($paginationInput -notmatch "^[NnPpCc]$" -or 
                 ($paginationInput -match "^[Nn]$" -and $currentPage -eq ($totalPages - 1)) -or 
                 ($paginationInput -match "^[Pp]$" -and $currentPage -eq 0))

        if ($paginationInput -match "^[Nn]$") {
            $currentPage++
        }
        elseif ($paginationInput -match "^[Pp]$") {
            $currentPage--
        }
        elseif ($paginationInput -match "^[Cc]$") {
            break # Exit pagination and continue script
        }

    } while ($true)


}

function Show-DaemonSetIssues {
    param(
        [int]$PageSize = 10  # Number of daemonsets per page
    )

    Write-Host "`n[DaemonSets Not Fully Running]" -ForegroundColor Cyan
    $daemonsets = kubectl get daemonsets --all-namespaces -o json | ConvertFrom-Json

    # Filter only DaemonSets with issues
    $filteredDaemonSets = @()

    foreach ($ds in $daemonsets.items) {
        $ns = $ds.metadata.namespace
        $name = $ds.metadata.name
        $desired = $ds.status.desiredNumberScheduled
        $current = $ds.status.currentNumberScheduled
        $running = $ds.status.numberReady

        # Only include DaemonSets that are NOT fully running
        if ($desired -ne $running) {
            $filteredDaemonSets += [PSCustomObject]@{
                Namespace   = $ns
                DaemonSet   = $name
                "Desired"   = $desired
                "Running"   = $running
                "Scheduled" = $current
                "Status"    = "⚠️ Incomplete"
            }
        }
    }

    $totalDaemonSets = $filteredDaemonSets.Count

    if ($totalDaemonSets -eq 0) {
        Write-Host "✅ All DaemonSets are fully running." -ForegroundColor Green
        Read-Host "🤖 Press Enter to return to the menu"
        return
    }

    $currentPage = 0
    $totalPages = [math]::Ceiling($totalDaemonSets / $PageSize)

    do {
        Clear-Host
        Write-Host "`n[DaemonSets Not Fully Running - Page $($currentPage + 1) of $totalPages]" -ForegroundColor Cyan

        $startIndex = $currentPage * $PageSize
        $endIndex = [math]::Min($startIndex + $PageSize, $totalDaemonSets)

        $tableData = $filteredDaemonSets[$startIndex..($endIndex - 1)]

        if ($tableData) {
            $tableData | Format-Table -AutoSize
        }

        # Pagination controls
        Write-Host "`nPage $($currentPage + 1) of $totalPages"

        $options = @()
        if ($currentPage -lt ($totalPages - 1)) { $options += "N = Next" }
        if ($currentPage -gt 0) { $options += "P = Previous" }
        $options += "C = Continue"

        Write-Host ($options -join ", ") -ForegroundColor Yellow

        do {
            $paginationInput = Read-Host "Enter your choice"
        } while ($paginationInput -notmatch "^[NnPpCc]$" -or 
                 ($paginationInput -match "^[Nn]$" -and $currentPage -eq ($totalPages - 1)) -or 
                 ($paginationInput -match "^[Pp]$" -and $currentPage -eq 0))

        if ($paginationInput -match "^[Nn]$") {
            $currentPage++
        }
        elseif ($paginationInput -match "^[Pp]$") {
            $currentPage--
        }
        elseif ($paginationInput -match "^[Cc]$") {
            break # Exit pagination and continue script
        }

    } while ($true)

    # Write-Host "`nContinuing with the rest of the script..." -ForegroundColor Green
}

function Show-FailedPods {
    param(
        [string]$Namespace = "",
        [int]$PageSize = 10  # Number of pods per page
    )

    Write-Host "`n[Failed Pods]" -ForegroundColor Cyan

    # Fetch failed pods

    if ($Namespace -ne "") {
        try {
            $failedPods = kubectl get pods -n $namespace -o json 2>&1 | ConvertFrom-Json |
            Select-Object -ExpandProperty items |
            Where-Object { $_.status.phase -eq "Failed" }
            
        }
        catch {
            Write-Host "⚠️ Error retrieving pod data: $_" -ForegroundColor Red
            return
        }
        
    }
    else {
        try {
            $failedPods = kubectl get pods --all-namespaces -o json 2>&1 | ConvertFrom-Json |
            Select-Object -ExpandProperty items |
            Where-Object { $_.status.phase -eq "Failed" }
        }
        catch {
            Write-Host "⚠️ Error retrieving pod data: $_" -ForegroundColor Red
            return
        }
    }
    

    $totalPods = $failedPods.Count

    if ($totalPods -eq 0) {
        Write-Host "✅ No failed pods found." -ForegroundColor Green
        Read-Host "🤖 Press Enter to return to the menu"
        return
    }

    $currentPage = 0
    $totalPages = [math]::Ceiling($totalPods / $PageSize)

    do {
        Clear-Host
        Write-Host "`n[Failed Pods - Page $($currentPage + 1) of $totalPages]" -ForegroundColor Cyan

        $startIndex = $currentPage * $PageSize
        $endIndex = [math]::Min($startIndex + $PageSize, $totalPods)

        $tableData = @()

        for ($i = $startIndex; $i -lt $endIndex; $i++) {
            $pod = $failedPods[$i]
            $ns = $pod.metadata.namespace
            $podName = $pod.metadata.name
            $reason = $pod.status.reason
            $message = $pod.status.message -replace "`n", " "  # Remove newlines for cleaner output

            $tableData += [PSCustomObject]@{
                Namespace = $ns
                Pod       = $podName
                Reason    = $reason
                Message   = $message
            }
        }

        $tableData | Format-Table -AutoSize

        # Pagination controls
        Write-Host "`nPage $($currentPage + 1) of $totalPages"

        $options = @()
        if ($currentPage -lt ($totalPages - 1)) { $options += "N = Next" }
        if ($currentPage -gt 0) { $options += "P = Previous" }
        $options += "C = Continue"
        
        Write-Host ($options -join ", ") -ForegroundColor Yellow

        do {
            $paginationInput = Read-Host "Enter your choice"
        } while ($paginationInput -notmatch "^[NnPpCc]$" -or 
                 ($paginationInput -match "^[Nn]$" -and $currentPage -eq ($totalPages - 1)) -or 
                 ($paginationInput -match "^[Pp]$" -and $currentPage -eq 0))

        if ($paginationInput -match "^[Nn]$") {
            $currentPage++
        }
        elseif ($paginationInput -match "^[Pp]$") {
            $currentPage--
        }
        elseif ($paginationInput -match "^[Cc]$") {
            break # Exit pagination and continue script
        }

    } while ($true)
    

}

function Show-EmptyNamespaces {
    param(
        [int]$PageSize = 10  # Number of namespaces per page
    )

    Write-Host "`n[Empty Namespaces]" -ForegroundColor Cyan

    # Get all namespaces
    $namespaces = kubectl get namespaces -o json | ConvertFrom-Json |
    Select-Object -ExpandProperty items |
    Select-Object -ExpandProperty metadata |
    Select-Object -ExpandProperty name

    # Get all pods and their namespaces
    $pods = kubectl get pods --all-namespaces -o json | ConvertFrom-Json |
    Select-Object -ExpandProperty items |
    Group-Object { $_.metadata.namespace }

    # Extract namespaces that have at least one pod
    $namespacesWithPods = $pods.Name

    # Get only namespaces that are completely empty
    $emptyNamespaces = $namespaces | Where-Object { $_ -notin $namespacesWithPods }

    $totalNamespaces = $emptyNamespaces.Count

    if ($totalNamespaces -eq 0) {
        Write-Host "✅ No empty namespaces found." -ForegroundColor Green
        Read-Host "🤖 Press Enter to return to the menu"
        return
    }

    $currentPage = 0
    $totalPages = [math]::Ceiling($totalNamespaces / $PageSize)

    do {
        Clear-Host
        Write-Host "`n[Empty Namespaces - Page $($currentPage + 1) of $totalPages]" -ForegroundColor Cyan

        $startIndex = $currentPage * $PageSize
        $endIndex = [math]::Min($startIndex + $PageSize, $totalNamespaces)

        $tableData = @()

        for ($i = $startIndex; $i -lt $endIndex; $i++) {
            $namespace = $emptyNamespaces[$i]

            $tableData += [PSCustomObject]@{
                "Namespace" = $namespace
            }
        }

        $tableData | Format-Table -AutoSize

        # Pagination controls
        Write-Host "`nPage $($currentPage + 1) of $totalPages"

        $options = @()
        if ($currentPage -lt ($totalPages - 1)) { $options += "N = Next" }
        if ($currentPage -gt 0) { $options += "P = Previous" }
        $options += "C = Continue"
        
        Write-Host ($options -join ", ") -ForegroundColor Yellow

        do {
            $paginationInput = Read-Host "Enter your choice"
        } while ($paginationInput -notmatch "^[NnPpCc]$" -or 
                 ($paginationInput -match "^[Nn]$" -and $currentPage -eq ($totalPages - 1)) -or 
                 ($paginationInput -match "^[Pp]$" -and $currentPage -eq 0))

        if ($paginationInput -match "^[Nn]$") {
            $currentPage++
        }
        elseif ($paginationInput -match "^[Pp]$") {
            $currentPage--
        }
        elseif ($paginationInput -match "^[Cc]$") {
            break # Exit pagination and continue script
        }

    } while ($true)
    

}

function Show-PendingPods {
    param(
        [string]$Namespace = "",
        [int]$PageSize = 10
    )

    Write-Host "`n[Pending Pods]" -ForegroundColor Cyan


    if ($Namespace -ne "") {
        try {
            $pendingPods = kubectl get pods -n $namespace -o json 2>&1 | ConvertFrom-Json |
            Select-Object -ExpandProperty items |
            Where-Object { $_.status.phase -eq "Pending" }
            # if (-not $pendingPods -or -not $pendingPods.items) { throw "No pods found or failed to retrieve pods." }
        }
        catch {
            Write-Host "⚠️ Error retrieving pod data: $_" -ForegroundColor Red
            return
        }
        
    }
    else {
        try {
            $pendingPods = kubectl get pods --all-namespaces -o json 2>&1 | ConvertFrom-Json |
            Select-Object -ExpandProperty items |
            Where-Object { $_.status.phase -eq "Pending" }
            # if (-not $pendingPods -or -not $pendingPods.items) { throw "No pods found or failed to retrieve pods." }
        }
        catch {
            Write-Host "⚠️ Error retrieving pod data: $_" -ForegroundColor Red
            return
        }
    }
    

    $totalPods = $pendingPods.Count

    if ($totalPods -eq 0) {
        Write-Host "✅ No pending pods found." -ForegroundColor Green
        Read-Host "🤖 Press Enter to return to the menu"
        return
    }

    $currentPage = 0
    $totalPages = [math]::Ceiling($totalPods / $PageSize)

    do {
        Clear-Host
        Write-Host "`n[Pending Pods - Page $($currentPage + 1) of $totalPages]" -ForegroundColor Cyan

        $startIndex = $currentPage * $PageSize
        $endIndex = [math]::Min($startIndex + $PageSize, $totalPods)

        $tableData = @()

        for ($i = $startIndex; $i -lt $endIndex; $i++) {
            $pod = $pendingPods[$i]
            $ns = $pod.metadata.namespace
            $podName = $pod.metadata.name
            $reason = $pod.status.conditions[0].reason
            $message = $pod.status.conditions[0].message -replace "`n", " "

            $tableData += [PSCustomObject]@{
                Namespace = $ns
                Pod       = $podName
                Reason    = $reason
                Message   = $message
            }
        }

        $tableData | Format-Table -AutoSize

        # Pagination controls
        Write-Host "`nPage $($currentPage + 1) of $totalPages"

        $options = @()
        if ($currentPage -lt ($totalPages - 1)) { $options += "N = Next" }
        if ($currentPage -gt 0) { $options += "P = Previous" }
        $options += "C = Continue"
        
        Write-Host ($options -join ", ") -ForegroundColor Yellow

        do {
            $paginationInput = Read-Host "Enter your choice"
        } while ($paginationInput -notmatch "^[NnPpCc]$" -or 
                 ($paginationInput -match "^[Nn]$" -and $currentPage -eq ($totalPages - 1)) -or 
                 ($paginationInput -match "^[Pp]$" -and $currentPage -eq 0))

        if ($paginationInput -match "^[Nn]$") {
            $currentPage++
        }
        elseif ($paginationInput -match "^[Pp]$") {
            $currentPage--
        }
        elseif ($paginationInput -match "^[Cc]$") {
            break # Exit pagination and continue script
        }

    } while ($true)
    

}

function Show-CrashLoopBackOffPods {
    param(
        [string]$Namespace = "",
        [int]$PageSize = 10
    )

    Write-Host "`n[CrashLoopBackOff Pods]" -ForegroundColor Cyan

    if ($Namespace -ne "") {
        try {
            $crashPods = kubectl get pods -n $namespace -o json 2>&1 | ConvertFrom-Json |
            Select-Object -ExpandProperty items |
            Where-Object { $_.status.containerStatuses.restartCount -gt 5 -and $_.status.containerStatuses.state.waiting.reason -eq "CrashLoopBackOff" }
        }
        catch {
            Write-Host "⚠️ Error retrieving pod data: $_" -ForegroundColor Red
            return
        }
        
    }
    else {
        try {
            $crashPods = kubectl get pods --all-namespaces -o json 2>&1 | ConvertFrom-Json |
            Select-Object -ExpandProperty items |
            Where-Object { $_.status.containerStatuses.restartCount -gt 5 -and $_.status.containerStatuses.state.waiting.reason -eq "CrashLoopBackOff" }
        }
        catch {
            Write-Host "⚠️ Error retrieving pod data: $_" -ForegroundColor Red
            return
        }
    }

    $totalPods = $crashPods.Count

    if ($totalPods -eq 0) {
        Write-Host "✅ No CrashLoopBackOff pods found." -ForegroundColor Green
        Read-Host "🤖 Press Enter to return to the menu"
        return
    }

    $currentPage = 0
    $totalPages = [math]::Ceiling($totalPods / $PageSize)

    do {
        Clear-Host
        Write-Host "`n[CrashLoopBackOff Pods - Page $($currentPage + 1) of $totalPages]" -ForegroundColor Cyan

        $startIndex = $currentPage * $PageSize
        $endIndex = [math]::Min($startIndex + $PageSize, $totalPods)

        $tableData = @()

        for ($i = $startIndex; $i -lt $endIndex; $i++) {
            $pod = $crashPods[$i]
            $ns = $pod.metadata.namespace
            $podName = $pod.metadata.name
            $restarts = $pod.status.containerStatuses.restartCount

            $tableData += [PSCustomObject]@{
                Namespace = $ns
                Pod       = $podName
                Restarts  = $restarts
                Status    = "🔴 CrashLoopBackOff"
            }
        }

        $tableData | Format-Table -AutoSize

        # Pagination controls
        Write-Host "`nPage $($currentPage + 1) of $totalPages"

        $options = @()
        if ($currentPage -lt ($totalPages - 1)) { $options += "N = Next" }
        if ($currentPage -gt 0) { $options += "P = Previous" }
        $options += "C = Continue"
        
        Write-Host ($options -join ", ") -ForegroundColor Yellow

        do {
            $paginationInput = Read-Host "Enter your choice"
        } while ($paginationInput -notmatch "^[NnPpCc]$" -or 
                 ($paginationInput -match "^[Nn]$" -and $currentPage -eq ($totalPages - 1)) -or 
                 ($paginationInput -match "^[Pp]$" -and $currentPage -eq 0))

        if ($paginationInput -match "^[Nn]$") {
            $currentPage++
        }
        elseif ($paginationInput -match "^[Pp]$") {
            $currentPage--
        }
        elseif ($paginationInput -match "^[Cc]$") {
            break # Exit pagination and continue script
        }

    } while ($true)
    

}

function Show-ServicesWithoutEndpoints {
    param(
        [int]$PageSize = 10  # Number of services per page
    )

    Write-Host "`n[Services Without Endpoints]" -ForegroundColor Cyan

    # Fetch all services
    $services = kubectl get services --all-namespaces -o json | ConvertFrom-Json |
    Select-Object -ExpandProperty items |
    Where-Object { $_.spec.type -ne "ExternalName" }  # Exclude ExternalName services

    # Fetch endpoints
    $endpoints = kubectl get endpoints --all-namespaces -o json | ConvertFrom-Json |
    Select-Object -ExpandProperty items |
    Group-Object { $_.metadata.namespace + "/" + $_.metadata.name }

    # Convert to a lookup table for fast checking
    $endpointsLookup = @{}
    foreach ($ep in $endpoints) {
        $endpointsLookup[$ep.Name] = $true
    }

    # Filter services that have no matching endpoints
    $servicesWithoutEndpoints = $services | Where-Object { 
        -not $endpointsLookup.ContainsKey($_.metadata.namespace + "/" + $_.metadata.name)
    }

    $totalServices = $servicesWithoutEndpoints.Count

    if ($totalServices -eq 0) {
        Write-Host "✅ All services have endpoints." -ForegroundColor Green
        Read-Host "🤖 Press Enter to return to the menu"
        return
    }

    $currentPage = 0
    $totalPages = [math]::Ceiling($totalServices / $PageSize)

    do {
        Clear-Host
        Write-Host "`n[Services Without Endpoints - Page $($currentPage + 1) of $totalPages]" -ForegroundColor Cyan

        $startIndex = $currentPage * $PageSize
        $endIndex = [math]::Min($startIndex + $PageSize, $totalServices)

        $tableData = @()

        for ($i = $startIndex; $i -lt $endIndex; $i++) {
            $svc = $servicesWithoutEndpoints[$i]
            $ns = $svc.metadata.namespace
            $name = $svc.metadata.name
            $type = $svc.spec.type

            $tableData += [PSCustomObject]@{
                Namespace = $ns
                Service   = $name
                Type      = $type
                Status    = "⚠️"
            }
        }

        $tableData | Format-Table -AutoSize

        # Pagination controls
        Write-Host "`nPage $($currentPage + 1) of $totalPages"

        $options = @()
        if ($currentPage -lt ($totalPages - 1)) { $options += "N = Next" }
        if ($currentPage -gt 0) { $options += "P = Previous" }
        $options += "C = Continue"
        
        Write-Host ($options -join ", ") -ForegroundColor Yellow

        do {
            $paginationInput = Read-Host "Enter your choice"
        } while ($paginationInput -notmatch "^[NnPpCc]$" -or 
                 ($paginationInput -match "^[Nn]$" -and $currentPage -eq ($totalPages - 1)) -or 
                 ($paginationInput -match "^[Pp]$" -and $currentPage -eq 0))

        if ($paginationInput -match "^[Nn]$") {
            $currentPage++
        }
        elseif ($paginationInput -match "^[Pp]$") {
            $currentPage--
        }
        elseif ($paginationInput -match "^[Cc]$") {
            break # Exit pagination and continue script
        }

    } while ($true)
    

}

function Show-UnusedPVCs {
    param(
        [int]$PageSize = 10  # Number of PVCs per page
    )

    Write-Host "`n[Unused Persistent Volume Claims]" -ForegroundColor Cyan
    $pvcs = kubectl get pvc --all-namespaces -o json | ConvertFrom-Json | Select-Object -ExpandProperty items
    $pods = kubectl get pods --all-namespaces -o json | ConvertFrom-Json | Select-Object -ExpandProperty items

    # Get all PVCs that are not attached to any pod
    $attachedPVCs = $pods | ForEach-Object { $_.spec.volumes | Where-Object { $_.persistentVolumeClaim } } | Select-Object -ExpandProperty persistentVolumeClaim
    $unusedPVCs = $pvcs | Where-Object { $_.metadata.name -notin $attachedPVCs.name }

    $totalPVCs = $unusedPVCs.Count

    if ($totalPVCs -eq 0) {
        Write-Host "✅ No unused PVCs found." -ForegroundColor Green
        Read-Host "🤖 Press Enter to return to the menu"
        return
    }

    $currentPage = 0
    $totalPages = [math]::Ceiling($totalPVCs / $PageSize)

    do {
        Clear-Host
        Write-Host "`n[Unused Persistent Volume Claims - Page $($currentPage + 1) of $totalPages]" -ForegroundColor Cyan

        $startIndex = $currentPage * $PageSize
        $endIndex = [math]::Min($startIndex + $PageSize, $totalPVCs)

        $tableData = $unusedPVCs[$startIndex..($endIndex - 1)]

        if ($tableData) {
            $tableData | Format-Table -Property @{Label = "Namespace"; Expression = { $_.metadata.namespace } }, 
                                              @{Label = "PVC"; Expression = { $_.metadata.name } }, 
                                              @{Label = "Storage"; Expression = { $_.spec.resources.requests.storage } } -AutoSize
        }

        # Pagination controls
        Write-Host "`nPage $($currentPage + 1) of $totalPages"

        $options = @()
        if ($currentPage -lt ($totalPages - 1)) { $options += "[N] Next" }
        if ($currentPage -gt 0) { $options += "[P] Previous" }
        $options += "[C] Continue"

        Write-Host ($options -join ", ") -ForegroundColor Yellow

        do {
            $paginationInput = Read-Host "Enter your choice"
        } while ($paginationInput -notmatch "^[NnPpCc]$" -or 
                 ($paginationInput -match "^[Nn]$" -and $currentPage -eq ($totalPages - 1)) -or 
                 ($paginationInput -match "^[Pp]$" -and $currentPage -eq 0))

        if ($paginationInput -match "^[Nn]$") {
            $currentPage++
        }
        elseif ($paginationInput -match "^[Pp]$") {
            $currentPage--
        }
        elseif ($paginationInput -match "^[Cc]$") {
            return  # Exit pagination immediately without asking for confirmation
        }

    } while ($true)

    # Only pause **if user didn't select [C]**
    Read-Host "`n🤖 Press Enter to return to the storage menu"
}


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

function Show-StuckJobs {
    param(
        [int]$StuckThresholdHours = 2,
        [int]$PageSize = 10
    )

    Write-Host "`n[Stuck Kubernetes Jobs]" -ForegroundColor Cyan

    # Fetch jobs, capturing both stdout and stderr
    $kubectlOutput = kubectl get jobs --all-namespaces -o json 2>&1 | Out-String

    # Check for actual errors in kubectl output
    if ($kubectlOutput -match "error|not found|forbidden") {
        Write-Host "⚠️ Error retrieving job data: $kubectlOutput" -ForegroundColor Red
        Read-Host "🤖 Press Enter to return to the menu"
        return
    }

    # Ensure valid JSON before parsing
    if ($kubectlOutput -match "^{") {
        $jobs = $kubectlOutput | ConvertFrom-Json | Select-Object -ExpandProperty items
    }
    else {
        Write-Host "⚠️ Unexpected response from kubectl. No valid JSON received." -ForegroundColor Red
        Read-Host "🤖 Press Enter to return to the menu"
        return
    }

    # Ensure $jobs is an array before processing
    if (-not $jobs -or $jobs.Count -eq 0) {
        Write-Host "✅ No jobs found in the cluster." -ForegroundColor Green
        Read-Host "🤖 Press Enter to return to the menu"
        return
    }

    # Filter stuck jobs
    $stuckJobs = $jobs | Where-Object { 
        (-not $_.status.conditions -or $_.status.conditions.type -notcontains "Complete") -and # Not marked complete
        $_.status.PSObject.Properties['active'] -and $_.status.active -gt 0 -and # Has active pods
        (-not $_.status.PSObject.Properties['ready'] -or $_.status.ready -eq 0) -and # No ready pods
        (-not $_.status.PSObject.Properties['succeeded'] -or $_.status.succeeded -eq 0) -and # Not succeeded
        (-not $_.status.PSObject.Properties['failed'] -or $_.status.failed -eq 0) -and # Not failed
        $_.status.PSObject.Properties['startTime'] -and # Has a startTime
        ((New-TimeSpan -Start $_.status.startTime -End (Get-Date)).TotalHours -gt $StuckThresholdHours)
    }

    # No stuck jobs found
    if (-not $stuckJobs -or $stuckJobs.Count -eq 0) {
        Write-Host "✅ No stuck jobs found." -ForegroundColor Green
        Read-Host "🤖 Press Enter to return to the menu"
        return
    }

    # Pagination Setup
    $totalJobs = $stuckJobs.Count
    $currentPage = 0
    $totalPages = [math]::Ceiling($totalJobs / $PageSize)

    do {
        Clear-Host
        Write-Host "`n[Stuck Kubernetes Jobs - Page $($currentPage + 1) of $totalPages]" -ForegroundColor Cyan

        $startIndex = $currentPage * $PageSize
        $endIndex = [math]::Min($startIndex + $PageSize, $totalJobs)

        $tableData = @()

        for ($i = $startIndex; $i -lt $endIndex; $i++) {
            $job = $stuckJobs[$i]
            $ns = $job.metadata.namespace
            $jobName = $job.metadata.name
            $ageHours = ((New-TimeSpan -Start $job.status.startTime -End (Get-Date)).TotalHours) -as [int]

            $tableData += [PSCustomObject]@{
                Namespace = $ns
                Job       = $jobName
                Age_Hours = $ageHours
                Status    = "🟡 Stuck"
            }
        }

        $tableData | Format-Table -AutoSize

        # Pagination controls
        Write-Host "`nPage $($currentPage + 1) of $totalPages"

        $options = @()
        if ($currentPage -lt ($totalPages - 1)) { $options += "N = Next" }
        if ($currentPage -gt 0) { $options += "P = Previous" }
        $options += "C = Continue"

        Write-Host ($options -join ", ") -ForegroundColor Yellow

        do {
            $paginationInput = Read-Host "Enter your choice"
        } while ($paginationInput -notmatch "^[NnPpCc]$" -or 
                 ($paginationInput -match "^[Nn]$" -and $currentPage -eq ($totalPages - 1)) -or 
                 ($paginationInput -match "^[Pp]$" -and $currentPage -eq 0))

        if ($paginationInput -match "^[Nn]$") {
            $currentPage++
        }
        elseif ($paginationInput -match "^[Pp]$") {
            $currentPage--
        }
        elseif ($paginationInput -match "^[Cc]$") {
            break # Exit pagination and continue script
        }

    } while ($true)
}

function Show-FailedJobs {
    param(
        [int]$StuckThresholdHours = 2,
        [int]$PageSize = 10
    )

    Write-Host "`n[Failed Kubernetes Jobs]" -ForegroundColor Cyan

    # Fetch jobs, capturing both stdout and stderr
    $kubectlOutput = kubectl get jobs --all-namespaces -o json 2>&1 | Out-String

    # Check for actual errors in kubectl output
    if ($kubectlOutput -match "error|not found|forbidden") {
        Write-Host "⚠️ Error retrieving job data: $kubectlOutput" -ForegroundColor Red
        Read-Host "🤖 Press Enter to return to the menu"
        return
    }

    # Ensure valid JSON before parsing
    if ($kubectlOutput -match "^{") {
        $jobs = $kubectlOutput | ConvertFrom-Json | Select-Object -ExpandProperty items
    }
    else {
        Write-Host "⚠️ Unexpected response from kubectl. No valid JSON received." -ForegroundColor Red
        Read-Host "🤖 Press Enter to return to the menu"
        return
    }

    # Ensure $jobs is an array before processing
    if (-not $jobs -or $jobs.Count -eq 0) {
        Write-Host "✅ No jobs found in the cluster." -ForegroundColor Green
        Read-Host "🤖 Press Enter to return to the menu"
        return
    }

    # Filter failed jobs
    $failedJobs = $jobs | Where-Object { 
        $_.status.PSObject.Properties['failed'] -and $_.status.failed -gt 0 -and # Job has failed
        (-not $_.status.PSObject.Properties['succeeded'] -or $_.status.succeeded -eq 0) -and # Not succeeded
        $_.status.PSObject.Properties['startTime'] -and # Has a startTime
        ((New-TimeSpan -Start $_.status.startTime -End (Get-Date)).TotalHours -gt $StuckThresholdHours)
    }

    # No failed jobs found
    if (-not $failedJobs -or $failedJobs.Count -eq 0) {
        Write-Host "✅ No failed jobs found." -ForegroundColor Green
        Read-Host "🤖 Press Enter to return to the menu"
        return
    }

    # Pagination Setup
    $totalJobs = $failedJobs.Count
    $currentPage = 0
    $totalPages = [math]::Ceiling($totalJobs / $PageSize)

    do {
        Clear-Host
        Write-Host "`n[Failed Kubernetes Jobs - Page $($currentPage + 1) of $totalPages]" -ForegroundColor Cyan

        $startIndex = $currentPage * $PageSize
        $endIndex = [math]::Min($startIndex + $PageSize, $totalJobs)

        $tableData = @()

        for ($i = $startIndex; $i -lt $endIndex; $i++) {
            $job = $failedJobs[$i]
            $ns = $job.metadata.namespace
            $jobName = $job.metadata.name
            $ageHours = ((New-TimeSpan -Start $job.status.startTime -End (Get-Date)).TotalHours) -as [int]
            $failCount = if ($job.status.PSObject.Properties['failed']) { $job.status.failed } else { "Unknown" }

            $tableData += [PSCustomObject]@{
                Namespace = $ns
                Job       = $jobName
                Age_Hours = $ageHours
                Failures  = $failCount
                Status    = "🔴 Failed"
            }
        }

        $tableData | Format-Table -AutoSize

        # Pagination controls
        Write-Host "`nPage $($currentPage + 1) of $totalPages"

        $options = @()
        if ($currentPage -lt ($totalPages - 1)) { $options += "N = Next" }
        if ($currentPage -gt 0) { $options += "P = Previous" }
        $options += "C = Continue"

        Write-Host ($options -join ", ") -ForegroundColor Yellow

        do {
            $paginationInput = Read-Host "Enter your choice"
        } while ($paginationInput -notmatch "^[NnPpCc]$" -or 
                 ($paginationInput -match "^[Nn]$" -and $currentPage -eq ($totalPages - 1)) -or 
                 ($paginationInput -match "^[Pp]$" -and $currentPage -eq 0))

        if ($paginationInput -match "^[Nn]$") {
            $currentPage++
        }
        elseif ($paginationInput -match "^[Pp]$") {
            $currentPage--
        }
        elseif ($paginationInput -match "^[Cc]$") {
            break # Exit pagination and continue script
        }

    } while ($true)
}

function Show-OrphanedConfigMapsSecrets {
    param(
        [int]$PageSize = 10
    )

    Write-Host "`n[🔍 Orphaned ConfigMaps & Secrets]" -ForegroundColor Cyan

    # Fetch ConfigMaps & Secrets (excluding Helm-related and system-managed ones)
    Write-Host -NoNewline "`n🤖 Fetching ConfigMaps & Secrets..." -ForegroundColor Yellow
    $excludedSecretPatterns = @("^sh\.helm\.release\.v1\.", "^bootstrap-token-", "^default-token-", "^kube-root-ca.crt$", "^kubernetes.io/service-account-token")

    $configMaps = kubectl get configmaps --all-namespaces -o json | ConvertFrom-Json | Select-Object -ExpandProperty items |
        Where-Object { $_.metadata.name -notmatch ($excludedSecretPatterns -join "|") }

    $secrets = kubectl get secrets --all-namespaces -o json | ConvertFrom-Json | Select-Object -ExpandProperty items |
        Where-Object { $_.metadata.name -notmatch ($excludedSecretPatterns -join "|") }

    Write-Host "`r✅ ConfigMaps & Secrets fetched." -ForegroundColor Green

    # Fetch workloads (Pods, Deployments, StatefulSets, DaemonSets, Ingress, and ServiceAccounts)
    Write-Host -NoNewline "`n🤖 Fetching workloads & service accounts..." -ForegroundColor Yellow
    $pods = kubectl get pods --all-namespaces -o json | ConvertFrom-Json | Select-Object -ExpandProperty items
    $workloads = @(kubectl get deployments,statefulsets,daemonsets --all-namespaces -o json | ConvertFrom-Json | Select-Object -ExpandProperty items)
    $ingresses = kubectl get ingress --all-namespaces -o json | ConvertFrom-Json | Select-Object -ExpandProperty items
    $serviceAccounts = kubectl get serviceaccounts --all-namespaces -o json | ConvertFrom-Json | Select-Object -ExpandProperty items

    Write-Host "`r✅ Workloads & ServiceAccounts fetched." -ForegroundColor Green

    # **Detect Used Secrets**
    Write-Host -NoNewline "`n🤖 Analyzing ConfigMap & Secret usage..." -ForegroundColor Yellow
    $usedSecrets = @()
    $usedConfigMaps = @()

    # Collect used Secrets & ConfigMaps from Pods & Workloads
    foreach ($resource in $pods + $workloads) {
        $usedSecrets += $resource.spec.volumes | Where-Object { $_.secret } | Select-Object -ExpandProperty secret | Select-Object -ExpandProperty secretName
        $usedConfigMaps += $resource.spec.volumes | Where-Object { $_.configMap } | Select-Object -ExpandProperty configMap | Select-Object -ExpandProperty name

        foreach ($container in $resource.spec.containers) {
            if ($container.env) {
                $usedSecrets += $container.env | Where-Object { $_.valueFrom.secretKeyRef } | Select-Object -ExpandProperty valueFrom | Select-Object -ExpandProperty secretKeyRef | Select-Object -ExpandProperty name
                $usedConfigMaps += $container.env | Where-Object { $_.valueFrom.configMapKeyRef } | Select-Object -ExpandProperty valueFrom | Select-Object -ExpandProperty configMapKeyRef | Select-Object -ExpandProperty name
            }
            if ($container.envFrom) {
                $usedSecrets += $container.envFrom | Where-Object { $_.secretRef } | Select-Object -ExpandProperty secretRef | Select-Object -ExpandProperty name
                $usedConfigMaps += $container.envFrom | Where-Object { $_.configMapRef } | Select-Object -ExpandProperty configMapRef | Select-Object -ExpandProperty name
            }
        }
    }

    # **Collect used Secrets from Ingress TLS**
    $usedSecrets += $ingresses | ForEach-Object { $_.spec.tls | Select-Object -ExpandProperty secretName }

    # **Collect used Secrets from ServiceAccounts**
    $usedSecrets += $serviceAccounts | ForEach-Object {
        $_.secrets | Select-Object -ExpandProperty name
        $_.imagePullSecrets | Select-Object -ExpandProperty name
    }

    # **Collect service account token secrets**
    $usedSecrets += kubectl get secrets --field-selector=type=kubernetes.io/service-account-token -o json | ConvertFrom-Json | Select-Object -ExpandProperty items |
        Select-Object -ExpandProperty metadata | Select-Object -ExpandProperty name

    # Remove duplicates & nulls
    $usedSecrets = $usedSecrets | Where-Object { $_ } | Sort-Object -Unique
    $usedConfigMaps = $usedConfigMaps | Where-Object { $_ } | Sort-Object -Unique

    # **Find orphaned ConfigMaps & Secrets**
    $orphanedConfigMaps = $configMaps | Where-Object { $_.metadata.name -notin $usedConfigMaps }
    $orphanedSecrets = $secrets | Where-Object { $_.metadata.name -notin $usedSecrets }

    if ($orphanedConfigMaps.Count -eq 0 -and $orphanedSecrets.Count -eq 0) {
        Write-Host "✅ No orphaned ConfigMaps or Secrets found." -ForegroundColor Green
        Read-Host "🤖 Press Enter to return to the menu"
        return
    }

    # **Store orphaned items**
    $orphanedItems = @()
    foreach ($cm in $orphanedConfigMaps) {
        $orphanedItems += [PSCustomObject]@{
            "Namespace" = $cm.metadata.namespace
            "Type"      = "📜 ConfigMap"
            "Name"      = $cm.metadata.name
        }
    }
    foreach ($secret in $orphanedSecrets) {
        $orphanedItems += [PSCustomObject]@{
            "Namespace" = $secret.metadata.namespace
            "Type"      = "🔑 Secret"
            "Name"      = $secret.metadata.name
        }
    }

    # **Pagination Setup**
    $totalItems = $orphanedItems.Count
    $currentPage = 0
    $totalPages = [math]::Ceiling($totalItems / $PageSize)

    do {
        Clear-Host
        Write-Host "`n[🔍 Orphaned ConfigMaps & Secrets - Page $($currentPage + 1) of $totalPages]" -ForegroundColor Cyan
        Write-Host "`nThis check identifies unused ConfigMaps and Secrets that might be safe to delete."
        Write-Host "Secrets are checked in Pods, Deployments, StatefulSets, DaemonSets, Ingress, and ServiceAccounts." -ForegroundColor Yellow

        # Display current page
        $startIndex = $currentPage * $PageSize
        $endIndex = [math]::Min($startIndex + $PageSize, $totalItems)

        $tableData = $orphanedItems[$startIndex..($endIndex - 1)]
        if ($tableData) {
            $tableData | Format-Table -AutoSize
        }

        # Pagination controls
        Write-Host "`nPage $($currentPage + 1) of $totalPages"

        $options = @()
        if ($currentPage -lt ($totalPages - 1)) { $options += "N = Next" }
        if ($currentPage -gt 0) { $options += "P = Previous" }
        $options += "C = Continue"

        Write-Host ($options -join ", ") -ForegroundColor Yellow

        do {
            $paginationInput = Read-Host "Enter your choice"
        } while ($paginationInput -notmatch "^[NnPpCc]$" -or 
                 ($paginationInput -match "^[Nn]$" -and $currentPage -eq ($totalPages - 1)) -or 
                 ($paginationInput -match "^[Pp]$" -and $currentPage -eq 0))

        if ($paginationInput -match "^[Nn]$") {
            $currentPage++
        }
        elseif ($paginationInput -match "^[Pp]$") {
            $currentPage--
        }
        elseif ($paginationInput -match "^[Cc]$") {
            break
        }

    } while ($true)
}

function Check-RBACMisconfigurations {
    param(
        [int]$PageSize = 10
    )

    Write-Host "`n[RBAC Misconfigurations]" -ForegroundColor Cyan

    # Fetch RoleBindings and ClusterRoleBindings
    Write-Host -NoNewline "`n🤖 Fetching RoleBindings & ClusterRoleBindings..." -ForegroundColor Yellow
    $roleBindings = kubectl get rolebindings --all-namespaces -o json | ConvertFrom-Json | Select-Object -ExpandProperty items
    $clusterRoleBindings = kubectl get clusterrolebindings -o json | ConvertFrom-Json | Select-Object -ExpandProperty items
    $roles = kubectl get roles --all-namespaces -o json | ConvertFrom-Json | Select-Object -ExpandProperty items
    $clusterRoles = kubectl get clusterroles -o json | ConvertFrom-Json | Select-Object -ExpandProperty items

    # Get existing namespaces to check for deleted ones
    $existingNamespaces = kubectl get namespaces -o json | ConvertFrom-Json | Select-Object -ExpandProperty items |
        Select-Object -ExpandProperty metadata | Select-Object -ExpandProperty name

    Write-Host "`r🤖 ✅ Fetched RoleBindings & ClusterRoleBindings.`n" -ForegroundColor Green

    $invalidRBAC = @()

    Write-Host "🤖 Analyzing RBAC configurations..." -ForegroundColor Yellow

    foreach ($rb in $roleBindings) {
        $rbNamespace = $rb.metadata.namespace
        $namespaceExists = $rbNamespace -in $existingNamespaces

        # Check if the Role exists
        $roleExists = $roles | Where-Object { $_.metadata.name -eq $rb.roleRef.name -and $_.metadata.namespace -eq $rbNamespace }
        if (-not $roleExists) {
            $invalidRBAC += [PSCustomObject]@{
                "Namespace"   = if ($namespaceExists) { $rbNamespace } else { "🛑 Namespace Missing" }
                "Type"        = "🔹 Namespace Role"
                "RoleBinding" = $rb.metadata.name
                "Subject"     = "N/A"
                "Issue"       = "❌ Missing Role/ClusterRole: $($rb.roleRef.name)"
            }
        }

        foreach ($subject in $rb.subjects) {
            if ($subject.kind -eq "User" -or $subject.kind -eq "Group") {
                continue  # Skip user/group bindings (cannot validate users/groups)
            }
            elseif ($subject.kind -eq "ServiceAccount") {
                # If namespace is missing, we mark it here instead
                if (-not $namespaceExists) {
                    $invalidRBAC += [PSCustomObject]@{
                        "Namespace"   = "🛑 Namespace Missing"
                        "Type"        = "🔹 Namespace Role"
                        "RoleBinding" = $rb.metadata.name
                        "Subject"     = "$($subject.kind)/$($subject.name)"
                        "Issue"       = "🛑 Namespace does not exist"
                    }
                }
                else {
                    # Namespace exists, check if ServiceAccount exists
                    $exists = kubectl get serviceaccount -n $subject.namespace $subject.name -o json 2>$null
                    if (-not $exists) {
                        $invalidRBAC += [PSCustomObject]@{
                            "Namespace"   = $rbNamespace
                            "Type"        = "🔹 Namespace Role"
                            "RoleBinding" = $rb.metadata.name
                            "Subject"     = "$($subject.kind)/$($subject.name)"
                            "Issue"       = "❌ ServiceAccount does not exist"
                        }
                    }
                }
            }
        }
    }

    foreach ($crb in $clusterRoleBindings) {
        foreach ($subject in $crb.subjects) {
            if ($subject.kind -eq "User" -or $subject.kind -eq "Group") {
                continue  # Skip user/group bindings
            }
            elseif ($subject.kind -eq "ServiceAccount") {
                # If namespace is missing, flag it correctly
                if ($subject.namespace -notin $existingNamespaces) {
                    $invalidRBAC += [PSCustomObject]@{
                        "Namespace"   = "🛑 Namespace Missing"
                        "Type"        = "🔸 Cluster Role"
                        "RoleBinding" = $crb.metadata.name
                        "Subject"     = "$($subject.kind)/$($subject.name)"
                        "Issue"       = "🛑 Namespace does not exist"
                    }
                }
                else {
                    # Namespace exists, check if ServiceAccount exists
                    $exists = kubectl get serviceaccount -n $subject.namespace $subject.name -o json 2>$null
                    if (-not $exists) {
                        $invalidRBAC += [PSCustomObject]@{
                            "Namespace"   = "🌍 Cluster-Wide"
                            "Type"        = "🔸 Cluster Role"
                            "RoleBinding" = $crb.metadata.name
                            "Subject"     = "$($subject.kind)/$($subject.name)"
                            "Issue"       = "❌ ServiceAccount does not exist"
                        }
                    }
                }
            }
        }
    }

    if ($invalidRBAC.Count -eq 0) {
        Write-Host "✅ No RBAC misconfigurations found." -ForegroundColor Green
        Read-Host "🤖 Press Enter to return to the menu"
        return
    }

    # Pagination Setup
    $totalBindings = $invalidRBAC.Count
    $currentPage = 0
    $totalPages = [math]::Ceiling($totalBindings / $PageSize)

    do {
        Clear-Host
        Write-Host "`n[RBAC Misconfigurations - Page $($currentPage + 1) of $totalPages]" -ForegroundColor Cyan

        # Explanation for clarity
        Write-Host "`nRBAC (Role-Based Access Control) defines who can do what in your cluster." -ForegroundColor Yellow
        Write-Host "This check identifies misconfigurations, missing references, and overly permissive roles." -ForegroundColor Yellow

        # Display summary of issues found
        Write-Host "`n⚠️ Found $totalBindings potential misconfigurations in RoleBindings and ClusterRoleBindings.`n" -ForegroundColor Red

        $startIndex = $currentPage * $PageSize
        $endIndex = [math]::Min($startIndex + $PageSize, $totalBindings)

        $tableData = $invalidRBAC[$startIndex..($endIndex - 1)]
        if ($tableData) {
            $tableData | Format-Table -AutoSize
        }

        # Pagination controls
        Write-Host "`nPage $($currentPage + 1) of $totalPages"

        $options = @()
        if ($currentPage -lt ($totalPages - 1)) { $options += "N = Next" }
        if ($currentPage -gt 0) { $options += "P = Previous" }
        $options += "C = Continue"

        Write-Host ($options -join ", ") -ForegroundColor Yellow

        do {
            $paginationInput = Read-Host "Enter your choice"
        } while ($paginationInput -notmatch "^[NnPpCc]$" -or 
                 ($paginationInput -match "^[Nn]$" -and $currentPage -eq ($totalPages - 1)) -or 
                 ($paginationInput -match "^[Pp]$" -and $currentPage -eq 0))

        if ($paginationInput -match "^[Nn]$") {
            $currentPage++
        }
        elseif ($paginationInput -match "^[Pp]$") {
            $currentPage--
        }
        elseif ($paginationInput -match "^[Cc]$") {
            break # Exit pagination and continue script
        }

    } while ($true)
}


function Show-ClusterSummary {
    Clear-Host
    Write-Host "`n[Cluster Summary]" -ForegroundColor Cyan

    # Cluster Information (Integrated)
    Write-Host -NoNewline "`n🤖 Retrieving Cluster Information...             ⏳ Fetching..." -ForegroundColor Yellow
    
    # Fetch Kubernetes Version & Cluster Name
    $versionInfo = kubectl version -o json | ConvertFrom-Json
    $k8sVersion = if ($versionInfo.serverVersion.gitVersion) { $versionInfo.serverVersion.gitVersion } else { "Unknown" }
    $clusterName = (kubectl config current-context)

    # Overwrite "Fetching..." with "Done!" before displaying details
    Write-Host "`r🤖 Retrieving Cluster Information...             ✅ Done!      " -ForegroundColor Green

    # Print Cluster Information
    
    Write-Host "`nCluster Name " -NoNewline -ForegroundColor Green
    Write-Host "is " -NoNewline
    Write-Host "$clusterName" -ForegroundColor Yellow
    Write-Host "Kubernetes Version " -NoNewline -ForegroundColor Green
    Write-Host "is " -NoNewline
    Write-Host "$k8sVersion" -ForegroundColor Yellow

    # Print Remaining Cluster Info
    kubectl cluster-info

    # Kubernetes Version Check
    Write-Host -NoNewline "`n🤖 Checking Kubernetes Version Compatibility...   ⏳ Fetching..." -ForegroundColor Yellow
    $versionCheck = Check-KubernetesVersion
    Write-Host "`r🤖 Checking Kubernetes Version Compatibility...  ✅ Done!       " -ForegroundColor Green
    Write-Host "`n$versionCheck"

    # Cluster Metrics
    Write-Host -NoNewline "`n🤖 Fetching Cluster Metrics...                    ⏳ Fetching..." -ForegroundColor Yellow
    $summary = Show-HeroMetrics
    Write-Host "`r🤖 Fetching Cluster Metrics...                   ✅ Done!       " -ForegroundColor Green
    Write-Host "`n$summary"

    Read-Host "`nPress Enter to return to the main menu"
    Clear-Host
}


function Invoke-KubeBuddy {

    Clear-Host
    Write-Host "KubeBuddy: Your Kubernetes Assistant 🤖" -ForegroundColor Cyan
    Write-Host "------------------------------------------" -ForegroundColor DarkGray

    # Thinking animation
    Write-Host -NoNewline "`r🤖 Starting KubeBuddy..." -ForegroundColor Yellow
    Start-Sleep -Seconds 2  
    Write-Host "`r🤖 KubeBuddy is ready!  " -ForegroundColor Green

    do {
        Write-Host "`nHello! I'm KubeBuddy, your Kubernetes helper. What would you like to do today?`n" -ForegroundColor Yellow

        # Main menu options
        $options = @(
            "[1]  Cluster Summary 📊"
            "[2]  Node Details 🖥️"
            "[3]  Namespace Management 📂"
            "[4]  Pod Management 🚀"
            "[5]  Kubernetes Jobs 🏢"
            "[6]  Service & Networking 🌐"
            "[7]  Storage Management 📦"
            "[8]  RBAC & Security 🔐"
            "[Q]  Exit ❌"
        )

        foreach ($option in $options) { Write-Host $option }

        # Get user choice
        $choice = Read-Host "`n🤖 Enter your choice"
        Clear-Host

        switch ($choice) {
            "1" { Show-ClusterSummary }
            "2" { Show-NodeMenu }
            "3" { show-NamespaceMenu }
            "4" { Show-PodMenu }
            "5" { Show-JobsMenu }
            "6" { Show-ServiceMenu }
            "7" { Show-StorageMenu }
            "8" { Show-RBACMenu }
            "Q" { Write-Host "👋 Goodbye! Have a great day! 🚀"; return }
            default { Write-Host "⚠️ Invalid choice. Please try again!" -ForegroundColor Red }
        }

    } while ($true)
}

function Show-NodeMenu {
    do {
        Write-Host "`n🔍 Node Details Menu" -ForegroundColor Cyan
        Write-Host "----------------------------------"

        $nodeOptions = @(
            "[1]  List all nodes and node conditions"
            "[2]  Get node resource usage"
            "🔙  Back [B] | ❌ Exit [Q]"
        )

        foreach ($option in $nodeOptions) {
            Write-Host $option
        }

        # Get user choice
        $nodeChoice = Read-Host "`n🤖 Enter a number"
        Clear-Host

        switch ($nodeChoice) {
            "1" { 
                Write-Host -NoNewline "`r🤖 Checking node status for issues..." -ForegroundColor Yellow
                Show-NodeConditions
            }
            "2" { 
                Write-Host -NoNewline "`r🤖 Retrieving node resource usage..." -ForegroundColor Yellow
                Show-NodeResourceUsage
            }
            "B" { return }  # Back to main menu
            "Q" { Write-Host "👋 Exiting KubeBuddy. Have a great day! 🚀"; exit }
            default { Write-Host "⚠️ Invalid choice. Please try again!" -ForegroundColor Red }
        }

        Clear-Host

    } while ($true)
}

function show-NamespaceMenu {
    do {
        Write-Host "`n🌐 Namespace Menu" -ForegroundColor Cyan
        Write-Host "------------------------------------"

        $namespaceOptions = @(
            "[1]  Show empty namespaces"
            "🔙  Back (B) | ❌ Exit (Q)"
        )

        foreach ($option in $namespaceOptions) { Write-Host $option }

        $namespaceChoice = Read-Host "`n🤖 Enter your choice"
        Clear-Host

        switch ($namespaceChoice) {
            "1" { 
                write-Host -NoNewline "`r🤖 Checking empty namespaces..." -ForegroundColor Yellow
                Show-EmptyNamespaces 
            }
            "B" { return }
            "Q" { Write-Host "👋 Exiting KubeBuddy. Have a great day! 🚀"; exit }
            default { Write-Host "⚠️ Invalid choice. Please try again!" -ForegroundColor Red }
        }

        Clear-Host

    } while ($true)
}


# 🚀 Pod Management Menu
function Show-PodMenu {
    do {
        Write-Host "`n🚀 Pod Management Menu" -ForegroundColor Cyan
        Write-Host "--------------------------------`n"

        # Ask for namespace preference
        Write-Host "🤖 Would you like to check:`n" -ForegroundColor Yellow
        Write-Host "   [1] All namespaces 🌍"
        Write-Host "   [2] Choose a specific namespace"
        Write-Host "   🔙 Back [B]"

        $nsChoice = Read-Host "`nEnter choice"
        Clear-Host

        if ($nsChoice -match "^[Bb]$") { return }

        $namespace = ""
        if ($nsChoice -match "^[2]$") {
            do {
                $selectedNamespace = Read-Host "`n🤖 Enter the namespace (or type 'L' to list available ones)"
                Clear-Host
                if ($selectedNamespace -match "^[Ll]$") {
                    Write-Host -NoNewline "`r🤖 Fetching available namespaces..." -ForegroundColor Yellow
                    Start-Sleep -Seconds 1  # Optional small delay for UX
                    
                    # Capture namespaces first
                    $namespaces = kubectl get namespaces --no-headers | ForEach-Object { $_.Split()[0] }
                    
                    # Clear previous line and print the list properly
                    Write-Host "`r🤖 Namespaces fetched successfully." -ForegroundColor Green
                    Write-Host "`n🤖 Available Namespaces:`n" -ForegroundColor Cyan
                    $namespaces | ForEach-Object { Write-Host $_ }
                    
                    Write-Host ""
                    $selectedNamespace = ""  # Reset to prompt again
                }
            } until ($selectedNamespace -match "^[a-zA-Z0-9-]+$" -and $selectedNamespace -ne "")

            $namespace = "$selectedNamespace"
        }



        do {
            # Clear screen but keep the "Using namespace" message
            Clear-Host
            Write-Host "`n🤖 Using namespace: " -NoNewline -ForegroundColor Cyan
            Write-Host $(if ($namespace -eq "") { "All Namespaces 🌍" } else { $namespace }) -ForegroundColor Yellow
            Write-Host ""
            Write-Host "📦 Choose a pod operation:`n" -ForegroundColor Cyan

            $podOptions = @(
                "[1]  Show pods with high restarts"
                "[2]  Show long-running pods"
                "[3]  Show failed pods"
                "[4]  Show pending pods"
                "[5]  Show CrashLoopBackOff pods"
                "🔙  Back [B] | ❌ Exit [Q]"
            )

            foreach ($option in $podOptions) { Write-Host $option }

            $podChoice = Read-Host "`n🤖 Enter your choice"
            Clear-Host

            switch ($podChoice) {
                "1" { 
                    Write-Host -NoNewline "`r🤖 Checking pods with high restarts...`n" -ForegroundColor Yellow
                    Show-PodsWithHighRestarts -Namespace $Namespace
                }
                "2" { 
                    Write-Host -NoNewline "`r🤖 Checking long-running pods...`n" -ForegroundColor Yellow
                    Show-LongRunningPods -Namespace $Namespace
                }
                "3" { 
                    write-Host -NoNewline "`r🤖 Checking failed pods...`n" -ForegroundColor Yellow
                    Show-FailedPods -Namespace $Namespace
                }
                "4" { 
                    Write-Host -NoNewline "`r🤖 Checking pending pods...`n" -ForegroundColor Yellow
                    Show-PendingPods -Namespace $Namespace
                }
                "5" {
                    write-Host -NoNewline "`r🤖 Checking CrashLoopBackOff pods...`n" -ForegroundColor Yellow
                    Show-CrashLoopBackOffPods -Namespace $Namespace
                }
                "B" { return }
                "Q" { Write-Host "👋 Exiting KubeBuddy. Have a great day! 🚀"; exit }
                default { Write-Host "⚠️ Invalid choice. Please try again!" -ForegroundColor Red }
            }

            Clear-Host

        } while ($true)

    } while ($true)
}

# 🌐 Service & Networking Menu
function Show-ServiceMenu {
    do {
        Write-Host "`n🌐 Service & Networking Menu" -ForegroundColor Cyan
        Write-Host "------------------------------------"

        $serviceOptions = @(
            "[1]  Show services without endpoints"
            "🔙  Back [B] | ❌ Exit [Q]"
        )

        foreach ($option in $serviceOptions) { Write-Host $option }

        $serviceChoice = Read-Host "`n🤖 Enter your choice"
        Clear-Host

        switch ($serviceChoice) {
            "1" { 
                Write-Host -NoNewline "`r🤖 Checking services without endpoints..." -ForegroundColor Yellow
                Show-ServicesWithoutEndpoints 
            }
            "B" { return }
            "Q" { Write-Host "👋 Exiting KubeBuddy. Have a great day! 🚀"; exit }
            default { Write-Host "⚠️ Invalid choice. Please try again!" -ForegroundColor Red }
        }

        Clear-Host

    } while ($true)
}

# 📦 Storage Management Menu
function Show-StorageMenu {
    do {
        Write-Host "`n📦 Storage Management Menu" -ForegroundColor Cyan
        Write-Host "------------------------------------"

        $storageOptions = @(
            "[1]  Show unused PVCs"
            "🔙  Back [B] | ❌ Exit [Q]"
        )

        foreach ($option in $storageOptions) { Write-Host $option }

        $storageChoice = Read-Host "`n🤖 Enter your choice"
        Clear-Host

        switch ($storageChoice) {
            "1" { 
                write-Host -NoNewline "`r🤖 Checking unused PVCs..." -ForegroundColor Yellow
                Show-UnusedPVCs 
            }
            "B" { return }
            "Q" { Write-Host "👋 Exiting KubeBuddy. Have a great day! 🚀"; exit }
            default { Write-Host "⚠️ Invalid choice. Please try again!" -ForegroundColor Red }
        }

        Clear-Host

    } while ($true)
}

# 🔐 RBAC & Security Menu
function Show-RBACMenu {
    do {
        Write-Host "`n🔐 RBAC & Security Menu" -ForegroundColor Cyan
        Write-Host "------------------------------------"

        $rbacOptions = @(
            "[1]  Check RBAC misconfigurations"
            "[2]  Show orphaned ConfigMaps & Secrets"
            "🔙  Back [B] | ❌ Exit [Q]"
        )

        foreach ($option in $rbacOptions) { Write-Host $option }

        $rbacChoice = Read-Host "`n🤖 Enter your choice"
        Clear-Host

        switch ($rbacChoice) {
            "1" { 
                write-host -NoNewline "`r🤖 Checking RBAC misconfigurations..." -ForegroundColor Yellow
                Check-RBACMisconfigurations 
            }
            "2" { 
                Write-Host -NoNewline "`r🤖 Checking orphaned ConfigMaps & Secrets..." -ForegroundColor Yellow
                Show-OrphanedConfigMapsSecrets 
            }
            "B" { return }
            "Q" { Write-Host "👋 Exiting KubeBuddy. Have a great day! 🚀"; exit }
            default { Write-Host "⚠️ Invalid choice. Please try again!" -ForegroundColor Red }
        }

        Clear-Host

    } while ($true)
}

# 🏗️ Kubernetes Jobs Menu
function Show-JobsMenu {
    do {
        Write-Host "`n🏢 Kubernetes Jobs Menu" -ForegroundColor Cyan
        Write-Host "------------------------------------"

        $jobOptions = @(
            "[1]  Show stuck Kubernetes jobs"
            "[2]  Show failed Kubernetes jobs"
            "🔙  Back [B] | ❌ Exit [Q]"
        )

        foreach ($option in $jobOptions) { Write-Host $option }

        $jobChoice = Read-Host "`n🤖 Enter your choice"
        Clear-Host

        switch ($jobChoice) {
            "1" { 
                write-Host -NoNewline "`r🤖 Checking stuck Kubernetes jobs..." -ForegroundColor Yellow
                Show-StuckJobs 
            }
            "2" { 
                write-Host -NoNewline "`r🤖 Checking stuck Kubernetes jobs..." -ForegroundColor Yellow
                Show-FailedJobs 
            }
            "B" { return }
            "Q" { Write-Host "👋 Exiting KubeBuddy. Have a great day! 🚀"; exit }
            default { Write-Host "⚠️ Invalid choice. Please try again!" -ForegroundColor Red }
        }

        Clear-Host

    } while ($true)
}
