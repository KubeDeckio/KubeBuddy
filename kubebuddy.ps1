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

# Function: Show Hero Metrics (Summary of Nodes, Pods, Restarts)
function Show-HeroMetrics {
    # Get summaries
    $nodeSummary = Get-NodeSummary
    $podSummary = Get-PodSummary
    $restartSummary = Get-RestartSummary

    # Define fixed-width padding
    $col2 = 10   # Total count width
    $col3 = 14   # Status width
    $col4 = 16   # Issues / warnings width

    # Store output in an array instead of printing directly
    $output = @()
    $output += "🚀 Nodes:    {0,$col2}   🟩 Healthy: {1,$col3}   🟥 Issues:   {2,$col4}" -f $nodeSummary.Total, $nodeSummary.Healthy, $nodeSummary.Issues
    $output += "📦 Pods:     {0,$col2}   🟩 Running: {1,$col3}   🟥 Failed:   {2,$col4}" -f $podSummary.Total, $podSummary.Running, $podSummary.Failed
    $output += "🔄 Restarts: {0,$col2}   🟨 Warnings:{1,$col3}   🟥 Critical: {2,$col4}" -f $restartSummary.Total, $restartSummary.Warning, $restartSummary.Critical

    return $output -join "`n"  # Return the output as a single string with line breaks
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

    Write-Host "`n[Pods with High Restarts]" -ForegroundColor Cyan
    $thresholds = Get-KubeBuddyThresholds
    $restartPods = kubectl get pods $Namespace -o json | ConvertFrom-Json

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

    Write-Host "`n[Long Running Pods]" -ForegroundColor Cyan
    $thresholds = Get-KubeBuddyThresholds
    $stalePods = kubectl get pods $namespace -o json | ConvertFrom-Json

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
    $failedPods = kubectl get pods $namespace -o json | ConvertFrom-Json |
    Select-Object -ExpandProperty items |
    Where-Object { $_.status.phase -eq "Failed" }

    $totalPods = $failedPods.Count

    if ($totalPods -eq 0) {
        Write-Host "✅ No failed pods found." -ForegroundColor Green
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

    $pendingPods = kubectl get pods $namespace -o json | ConvertFrom-Json |
    Select-Object -ExpandProperty items |
    Where-Object { $_.status.phase -eq "Pending" }

    $totalPods = $pendingPods.Count

    if ($totalPods -eq 0) {
        Write-Host "✅ No pending pods found." -ForegroundColor Green
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

    $crashPods = kubectl get pods $namespace -o json | ConvertFrom-Json |
    Select-Object -ExpandProperty items |
    Where-Object { $_.status.containerStatuses.restartCount -gt 5 -and $_.status.containerStatuses.state.waiting.reason -eq "CrashLoopBackOff" }

    $totalPods = $crashPods.Count

    if ($totalPods -eq 0) {
        Write-Host "✅ No CrashLoopBackOff pods found." -ForegroundColor Green
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
    Write-Host "`n[Unused Persistent Volume Claims]" -ForegroundColor Cyan
    $pvcs = kubectl get pvc --all-namespaces -o json | ConvertFrom-Json | Select-Object -ExpandProperty items
    $pods = kubectl get pods --all-namespaces -o json | ConvertFrom-Json | Select-Object -ExpandProperty items

    # Get all PVCs that are not attached to any pod
    $attachedPVCs = $pods | ForEach-Object { $_.spec.volumes | Where-Object { $_.persistentVolumeClaim } } | Select-Object -ExpandProperty persistentVolumeClaim
    $unusedPVCs = $pvcs | Where-Object { $_.metadata.name -notin $attachedPVCs.name }

    if ($unusedPVCs.Count -eq 0) {
        Write-Host "✅ No unused PVCs found." -ForegroundColor Green
        return
    }

    $unusedPVCs | Format-Table -Property @{Label = "Namespace"; Expression = { $_.metadata.namespace } }, @{Label = "PVC"; Expression = { $_.metadata.name } }, @{Label = "Storage"; Expression = { $_.spec.resources.requests.storage } } -AutoSize
}


function Check-KubernetesVersion {
    $versionInfo = kubectl version -o json | ConvertFrom-Json
    $k8sVersion = $versionInfo.serverVersion.gitVersion

    # Fetch latest stable Kubernetes version
    $latestVersion = (Invoke-WebRequest -Uri "https://dl.k8s.io/release/stable.txt").Content.Trim()

    if ($k8sVersion -lt $latestVersion) {
        return "⚠️ Cluster is running an outdated version: $k8sVersion (Latest: $latestVersion)"
    }
    else {
        return "✅ Cluster is up to date ($k8sVersion)"
    }
}

function Show-StuckJobs {
    param([int]$StuckThresholdHours = 2)

    Write-Host "`n[Stuck Kubernetes Jobs]" -ForegroundColor Cyan
    $jobs = kubectl get jobs --all-namespaces -o json | ConvertFrom-Json | Select-Object -ExpandProperty items

    $stuckJobs = $jobs | Where-Object { 
        $_.status.conditions -notmatch "Complete" -and
        ((New-TimeSpan -Start $_.status.startTime -End (Get-Date)).TotalHours -gt $StuckThresholdHours)
    }

    if ($stuckJobs.Count -eq 0) {
        Write-Host "✅ No stuck jobs found." -ForegroundColor Green
        return
    }

    $stuckJobs | Format-Table -Property @{Label = "Namespace"; Expression = { $_.metadata.namespace } }, @{Label = "Job"; Expression = { $_.metadata.name } }, @{Label = "Age (Hours)"; Expression = { ((New-TimeSpan -Start $_.status.startTime -End (Get-Date)).TotalHours) -as [int] } } -AutoSize
}

function Show-OrphanedConfigMapsSecrets {
    Write-Host "`n[Orphaned ConfigMaps & Secrets]" -ForegroundColor Cyan

    # Fetch all ConfigMaps and Secrets, excluding Helm-related ones
    $configMaps = kubectl get configmaps --all-namespaces -o json | ConvertFrom-Json |
    Select-Object -ExpandProperty items |
    Where-Object { $_.metadata.name -notmatch "^sh\.helm\.release\.v1\." }

    $secrets = kubectl get secrets --all-namespaces -o json | ConvertFrom-Json |
    Select-Object -ExpandProperty items |
    Where-Object { $_.metadata.name -notmatch "^sh\.helm\.release\.v1\." }

    # Fetch all Pods, Deployments, StatefulSets, DaemonSets
    $pods = kubectl get pods --all-namespaces -o json | ConvertFrom-Json | Select-Object -ExpandProperty items
    $deployments = kubectl get deployments --all-namespaces -o json | ConvertFrom-Json | Select-Object -ExpandProperty items
    $statefulSets = kubectl get statefulsets --all-namespaces -o json | ConvertFrom-Json | Select-Object -ExpandProperty items
    $daemonSets = kubectl get daemonsets --all-namespaces -o json | ConvertFrom-Json | Select-Object -ExpandProperty items

    # Extract used ConfigMaps and Secrets
    $usedConfigMaps = @()
    $usedSecrets = @()

    # Check usage in Pods
    $usedConfigMaps += $pods | ForEach-Object { $_.spec.volumes | Where-Object { $_.configMap } } | Select-Object -ExpandProperty configMap | Select-Object -ExpandProperty name
    $usedSecrets += $pods | ForEach-Object { $_.spec.volumes | Where-Object { $_.secret } } | Select-Object -ExpandProperty secret | Select-Object -ExpandProperty secretName

    # Check usage in Deployments, StatefulSets, and DaemonSets
    $workloads = $deployments + $statefulSets + $daemonSets

    foreach ($workload in $workloads) {
        if ($workload.spec.template.spec.volumes) {
            $usedConfigMaps += $workload.spec.template.spec.volumes | Where-Object { $_.configMap } | Select-Object -ExpandProperty configMap | Select-Object -ExpandProperty name
            $usedSecrets += $workload.spec.template.spec.volumes | Where-Object { $_.secret } | Select-Object -ExpandProperty secret | Select-Object -ExpandProperty secretName
        }

        if ($workload.spec.template.spec.containers) {
            foreach ($container in $workload.spec.template.spec.containers) {
                if ($container.envFrom) {
                    $usedConfigMaps += $container.envFrom | Where-Object { $_.configMapRef } | Select-Object -ExpandProperty configMapRef | Select-Object -ExpandProperty name
                    $usedSecrets += $container.envFrom | Where-Object { $_.secretRef } | Select-Object -ExpandProperty secretRef | Select-Object -ExpandProperty name
                }
            }
        }
    }

    # Remove duplicates
    $usedConfigMaps = $usedConfigMaps | Select-Object -Unique
    $usedSecrets = $usedSecrets | Select-Object -Unique

    # Find unused ConfigMaps and Secrets
    $orphanedConfigMaps = $configMaps | Where-Object { $_.metadata.name -notin $usedConfigMaps }
    $orphanedSecrets = $secrets | Where-Object { $_.metadata.name -notin $usedSecrets }

    if ($orphanedConfigMaps.Count -eq 0 -and $orphanedSecrets.Count -eq 0) {
        Write-Host "✅ No orphaned ConfigMaps or Secrets found." -ForegroundColor Green
        return
    }

    Write-Host "`nOrphaned ConfigMaps (excluding Helm releases):" -ForegroundColor Yellow
    $orphanedConfigMaps | Format-Table -Property @{Label = "Namespace"; Expression = { $_.metadata.namespace } }, @{Label = "ConfigMap"; Expression = { $_.metadata.name } } -AutoSize

    Write-Host "`nOrphaned Secrets (excluding Helm releases):" -ForegroundColor Yellow
    $orphanedSecrets | Format-Table -Property @{Label = "Namespace"; Expression = { $_.metadata.namespace } }, @{Label = "Secret"; Expression = { $_.metadata.name } } -AutoSize
}


function Check-RBACMisconfigurations {
    Write-Host "`n[RBAC Misconfigurations]" -ForegroundColor Cyan

    $roleBindings = kubectl get rolebindings --all-namespaces -o json | ConvertFrom-Json | Select-Object -ExpandProperty items
    $clusterRoleBindings = kubectl get clusterrolebindings -o json | ConvertFrom-Json | Select-Object -ExpandProperty items

    $invalidRBAC = @()

    foreach ($rb in $roleBindings + $clusterRoleBindings) {
        foreach ($subject in $rb.subjects) {
            if ($subject.kind -eq "User" -or $subject.kind -eq "Group") {
                continue  # Cannot verify users/groups easily
            }
            elseif ($subject.kind -eq "ServiceAccount") {
                $exists = kubectl get serviceaccount -n $subject.namespace $subject.name -o json 2>$null
                if (-not $exists) {
                    $invalidRBAC += [PSCustomObject]@{
                        Namespace   = $rb.metadata.namespace
                        RoleBinding = $rb.metadata.name
                        Subject     = "$($subject.kind)/$($subject.name)"
                    }
                }
            }
        }
    }

    if ($invalidRBAC.Count -eq 0) {
        Write-Host "✅ No RBAC misconfigurations found." -ForegroundColor Green
        return
    }

    $invalidRBAC | Format-Table -AutoSize
}


function Show-ClusterSummary {
    Write-Host "`n🔍 Fetching Cluster Summary..." -ForegroundColor Cyan
    Show-ClusterInfo
    Write-Host "`n📢 Checking Kubernetes Version Compatibility..." -ForegroundColor Cyan
    Write-Host -NoNewline "`r🤖 Checking..." -ForegroundColor Yellow
    $versionCheck = Check-KubernetesVersion
    Write-Host "`r$versionCheck"
    Write-Host "`n📊 Fetching Cluster Metrics..." -ForegroundColor Cyan
    Write-Host -NoNewline "`r🤖 Checking..." -ForegroundColor Yellow
    $summary = Show-HeroMetrics
    Write-Host "`r$summary"
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
            "1️⃣  Cluster Summary 📊"
            "2️⃣  Node Details 🖥️"
            "3️⃣  Pod Management 🚀"
            "4️⃣  Service & Networking 🌐"
            "5️⃣  Storage Management 📦"
            "6️⃣  RBAC & Security 🔐"
            "7️⃣  Kubernetes Jobs 🏗️"
            "❌  Exit (Q) ❌"
        )

        foreach ($option in $options) { Write-Host $option }

        # Get user choice
        $choice = Read-Host "`n🤖 Enter your choice"
        Clear-Host

        switch ($choice) {
            "1" { Show-ClusterSummary }
            "2" { Show-NodeMenu }
            "3" { Show-PodMenu }
            "4" { Show-ServiceMenu }
            "5" { Show-StorageMenu }
            "6" { Show-RBACMenu }
            "7" { Show-JobsMenu }
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
            "1️⃣  List all nodes and node conditions"
            "2️⃣  Get node resource usage"
            "🔙  Back (B) | ❌ Exit (Q)"
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

        Read-Host "`nPress Enter to return to the Node Menu"
        Clear-Host

    } while ($true)
}

# 🚀 Pod Management Menu
function Show-PodMenu {
    do {
        Write-Host "`n🚀 Pod Management Menu" -ForegroundColor Cyan
        Write-Host "--------------------------------"

        # Ask for namespace preference
        Write-Host "🤖 Would you like to check:" -ForegroundColor Yellow
        Write-Host "   1️⃣ All namespaces 🌍"
        Write-Host "   2️⃣ Choose a specific namespace"
        Write-Host "   🔙 Back (B)"

        $nsChoice = Read-Host "`nEnter choice"
        Clear-Host

        if ($nsChoice -match "^[Bb]$") { return }

        # Set Namespace: Use "--all-namespaces" or "--namespace <name>"
        $namespace = "--all-namespaces"
        if ($nsChoice -match "^[2]$") {
            do {
                $selectedNamespace = Read-Host "`nEnter the namespace (or type 'L' to list available ones)"
                
                if ($selectedNamespace -match "^[Ll]$") {
                    Write-Host "`n🔍 Fetching available namespaces..." -ForegroundColor Cyan
                    kubectl get namespaces --no-headers | ForEach-Object { $_.Split()[0] }
                    Write-Host ""
                    $selectedNamespace = ""  # Reset to prompt again
                }
            } until ($selectedNamespace -match "^[a-zA-Z0-9-]+$" -and $selectedNamespace -ne "")

            $namespace = "-n $selectedNamespace"
        }

        # Clear screen but keep the "Using namespace" message
        Clear-Host
        Write-Host "`n🤖 Using namespace: " -NoNewline -ForegroundColor Cyan
        Write-Host $(if ($namespace -eq "--all-namespaces") { "All Namespaces 🌍" } else { $namespace -replace '-n ', '' }) -ForegroundColor Yellow
        Write-Host ""

        do {
            Write-Host "`n📦 Choose a pod operation:" -ForegroundColor Cyan

            $podOptions = @(
                "1️⃣  Show pending pods"
                "2️⃣  Show failed pods"
                "3️⃣  Show pods with high restarts"
                "4️⃣  Show long-running pods"
                "5️⃣  Show CrashLoopBackOff pods"
                "🔙  Back (B) | ❌ Exit (Q)"
            )

            foreach ($option in $podOptions) { Write-Host $option }

            $podChoice = Read-Host "`n🤖 Enter your choice"
            Clear-Host

        switch ($podChoice) {
            "1" { 
                Write-Host -NoNewline "`r🤖 Checking pods with high restarts..." -ForegroundColor Yellow
                Show-PodsWithHighRestarts -Namespace $Namespace
            }
            "2" { 
                Write-Host -NoNewline "`r🤖 Checking long-running pods..." -ForegroundColor Yellow
                Show-LongRunningPods -Namespace $Namespace
            }
            "3" { 
                write-Host -NoNewline "`r🤖 Checking failed pods..." -ForegroundColor Yellow
                Show-FailedPods -Namespace $Namespace
            }
            "4" { 
                Write-Host -NoNewline "`r🤖 Checking pending pods..." -ForegroundColor Yellow
                Show-PendingPods -Namespace $Namespace
            }
            "5" {
                write-Host -NoNewline "`r🤖 Checking CrashLoopBackOff pods..." -ForegroundColor Yellow
                Show-CrashLoopBackOffPods -Namespace $Namespace
            }
            "B" { return }
            "Q" { Write-Host "👋 Exiting KubeBuddy. Have a great day! 🚀"; exit }
            default { Write-Host "⚠️ Invalid choice. Please try again!" -ForegroundColor Red }
        }

        Read-Host "`nPress Enter to return to the Pod Menu"
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
            "1️⃣  Show services without endpoints"
            "2️⃣  Show empty namespaces"
            "🔙  Back (B) | ❌ Exit (Q)"
        )

        foreach ($option in $serviceOptions) { Write-Host $option }

        $serviceChoice = Read-Host "`n🤖 Enter your choice"
        Clear-Host

        switch ($serviceChoice) {
            "1" { 
                Write-Host -NoNewline "`r🤖 Checking services without endpoints..." -ForegroundColor Yellow
                Show-ServicesWithoutEndpoints 
            }
            "2" { 
                write-Host -NoNewline "`r🤖 Checking empty namespaces..." -ForegroundColor Yellow
                Show-EmptyNamespaces 
            }
            "B" { return }
            "Q" { Write-Host "👋 Exiting KubeBuddy. Have a great day! 🚀"; exit }
            default { Write-Host "⚠️ Invalid choice. Please try again!" -ForegroundColor Red }
        }

        Read-Host "`nPress Enter to return to the Service Menu"
        Clear-Host

    } while ($true)
}

# 📦 Storage Management Menu
function Show-StorageMenu {
    do {
        Write-Host "`n📦 Storage Management Menu" -ForegroundColor Cyan
        Write-Host "------------------------------------"

        $storageOptions = @(
            "1️⃣  Show unused PVCs"
            "🔙  Back (B) | ❌ Exit (Q)"
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

        Read-Host "`nPress Enter to return to the Storage Menu"
        Clear-Host

    } while ($true)
}

# 🔐 RBAC & Security Menu
function Show-RBACMenu {
    do {
        Write-Host "`n🔐 RBAC & Security Menu" -ForegroundColor Cyan
        Write-Host "------------------------------------"

        $rbacOptions = @(
            "1️⃣  Check RBAC misconfigurations"
            "2️⃣  Show orphaned ConfigMaps & Secrets"
            "🔙  Back (B) | ❌ Exit (Q)"
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

        Read-Host "`nPress Enter to return to the RBAC Menu"
        Clear-Host

    } while ($true)
}

# 🏗️ Kubernetes Jobs Menu
function Show-JobsMenu {
    do {
        Write-Host "`n🏗️ Kubernetes Jobs Menu" -ForegroundColor Cyan
        Write-Host "------------------------------------"

        $jobOptions = @(
            "1️⃣  Show stuck Kubernetes jobs"
            "🔙  Back (B) | ❌ Exit (Q)"
        )

        foreach ($option in $jobOptions) { Write-Host $option }

        $jobChoice = Read-Host "`n🤖 Enter your choice"
        Clear-Host

        switch ($jobChoice) {
            "1" { 
                write-Host -NoNewline "`r🤖 Checking stuck Kubernetes jobs..." -ForegroundColor Yellow
                Show-StuckJobs 
            }
            "B" { return }
            "Q" { exit }
            default { Write-Host "⚠️ Invalid choice. Please try again!" -ForegroundColor Red }
        }

        Read-Host "`nPress Enter to return to the Jobs Menu"
        Clear-Host

    } while ($true)
}
