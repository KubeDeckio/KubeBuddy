# Define report file location (global scope)
$ReportFile = "$pwd/kubebuddy-report.txt"

$localScripts = Get-ChildItem -Path "$pwd/Write-Box.ps1"

# Execute each .ps1 script found in the local Private directory
foreach ($script in $localScripts) {
    Write-Verbose "Executing script: $($script.FullName)"
    . $script.FullName  # Call the script
}

function Write-ToReport {
    param(
        [string]$Message
    )
    # if ($Global:Report) {
        Add-Content -Path $ReportFile -Value $Message
    # }
}

function Generate-FullReport {
    Write-Host "🤖 Generating full report..."
    $Global:Report = $true

    # Clear existing report content if the file exists
    if (Test-Path $ReportFile) {
        Clear-Content -Path $ReportFile -ErrorAction SilentlyContinue
    }

    # Write report header
    Write-ToReport "🤖 Kubebuddy Report - Generated on $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
    Write-ToReport "========================================"

    # Cluster summary
    Write-ToReport "`n📌 Cluster Summary:"
    Show-ClusterSummary

    # Deployments
    Write-ToReport "`n📌 Deployments List:"

    # Nodes
    Write-ToReport "`n📌 Nodes Information:"

    # Services
    Write-ToReport "`n📌 Services List:"

    $Global:Report = $false
    Write-Host "✅ Report generated: $ReportFile"
}


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
                    Write-Host "`n⚠️ Config found, but missing 'thresholds' section. Using defaults..." -ForegroundColor Yellow
                }
            }
        }
        catch {
            if (-not $Silent) {
                Write-Host "`n❌ Failed to parse config file. Using defaults..." -ForegroundColor Red
            }
        }
    }
    else {
        if (-not $Silent) {
            Write-Host "`n⚠️ No config found. Using default thresholds..." -ForegroundColor Yellow
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

function Show-Pagination {
    param(
        [int]$currentPage,
        [int]$totalPages
    )

    Write-Host "`nPage $($currentPage + 1) of $totalPages"

    $options = @()
    if ($currentPage -lt ($totalPages - 1)) { $options += "N = Next" }
    if ($currentPage -gt 0) { $options += "P = Previous" }
    $options += "C = Continue"

    # Ensure 'P' does not appear on the first page
    if ($currentPage -eq 0) { $options = $options -notmatch "P = Previous" }

    # Ensure 'N' does not appear on the last page
    if ($currentPage -eq ($totalPages - 1)) { $options = $options -notmatch "N = Next" }

    # Display available options
    Write-Host ($options -join ", ") -ForegroundColor Yellow

    do {
        $paginationInput = Read-Host "Enter your choice"
    } while ($paginationInput -notmatch "^[NnPpCc]$" -or 
             ($paginationInput -match "^[Nn]$" -and $currentPage -eq ($totalPages - 1)) -or 
             ($paginationInput -match "^[Pp]$" -and $currentPage -eq 0))

    if ($paginationInput -match "^[Nn]$") { return $currentPage + 1 }
    elseif ($paginationInput -match "^[Pp]$") { return $currentPage - 1 }
    elseif ($paginationInput -match "^[Cc]$") { return -1 }  # Exit pagination
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

    Write-Host "`n[🌍 Node Conditions]" -ForegroundColor Cyan
    Write-Host -NoNewline "`n🤖 Fetching Node Conditions..." -ForegroundColor Yellow

    # Fetch nodes
    $nodes = kubectl get nodes -o json | ConvertFrom-Json
    $totalNodes = $nodes.items.Count

    if ($totalNodes -eq 0) {
        Write-Host "`r🤖 ❌ No nodes found." -ForegroundColor Red
        Read-Host "🤖 Press Enter to return to the menu"
        return
    }

    Write-Host "`r🤖 ✅ Nodes fetched. ($totalNodes total)" -ForegroundColor Green

    # **Track total Not Ready nodes across the cluster**
    $totalNotReadyNodes = 0
    $allNodesData = @()

    foreach ($node in $nodes.items) {
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
            $totalNotReadyNodes++
            $issues = if ($issueConditions) {
                ($issueConditions | ForEach-Object { "$($_.type): $($_.message)" }) -join " | "
            }
            else {
                "Unknown Issue"
            }
        }

        $allNodesData += [PSCustomObject]@{
            Node   = $name
            Status = $status
            Issues = $issues
        }
    }

    # **Pagination Setup**
    $currentPage = 0
    $totalPages = [math]::Ceiling($totalNodes / $PageSize)

    do {
        Clear-Host
        Write-Host "`n[🌍 Node Conditions - Page $($currentPage + 1) of $totalPages]" -ForegroundColor Cyan

        # **Display total 'Not Ready' nodes in the speech bubble before pagination starts**
        $msg = @(
            "🤖 Nodes are assessed for readiness and issues.",
            "",
            "   If a node is 'Not Ready', it may impact workloads.",
            "",
            "📌 Common Causes of 'Not Ready':",
            "   - Network issues preventing API communication",
            "   - Insufficient CPU/Memory on the node",
            "   - Disk pressure or PID pressure detected",
            "   - Node failing to join due to missing CNI plugins",
            "",
            "🔍 Troubleshooting Tips:",
            "   - Run: kubectl describe node <NODE_NAME>",
            "   - Check kubelet logs: journalctl -u kubelet -f",
            "   - Verify networking: kubectl get pods -A -o wide",
            "",
            "⚠️ Total Not Ready Nodes in the Cluster: $totalNotReadyNodes"
        )

        Write-SpeechBubble -msg $msg -color "Cyan" -icon "🤖" -lastColor "Red" -delay 50

        # Display current page
        $startIndex = $currentPage * $PageSize
        $endIndex = [math]::Min($startIndex + $PageSize, $totalNodes)

        $tableData = $allNodesData[$startIndex..($endIndex - 1)]
        if ($tableData) {
            $tableData | Format-Table -AutoSize
        }

        # Call the pagination function
        $newPage = Show-Pagination -currentPage $currentPage -totalPages $totalPages

        # Exit pagination if 'C' (Continue) was selected
        if ($newPage -eq -1) { break }

        $currentPage = $newPage

    } while ($true)
}


function Show-NodeResourceUsage {
    param(
        [int]$PageSize = 10  # Number of nodes per page
    )

    Write-Host "`n[📊 Node Resource Usage]" -ForegroundColor Cyan
    Write-Host -NoNewline "`n🤖 Gathering Node Data & Resource Usage..." -ForegroundColor Yellow

    # Get thresholds and node data
    $thresholds = Get-KubeBuddyThresholds
    $allocatableRaw = kubectl get nodes -o json | ConvertFrom-Json
    $nodeUsageRaw = kubectl top nodes --no-headers

    $totalNodes = $allocatableRaw.items.Count

    if ($totalNodes -eq 0) {
        Write-Host "`r🤖 ❌ No nodes found in the cluster." -ForegroundColor Red
        Read-Host "Press Enter to return to the menu"
        return
    }

    Write-Host "`r🤖 ✅ Nodes fetched. (Total: $totalNodes)" -ForegroundColor Green

    # **Track total warnings across all nodes**
    $totalWarnings = 0
    $allNodesData = @()

    # **Preprocess all nodes to count warnings**
    foreach ($node in $allocatableRaw.items) {
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

            $cpuAlert = if ($cpuUsagePercent -gt $thresholds.cpu_critical) { "🔴 Critical"; $totalWarnings++ }
            elseif ($cpuUsagePercent -gt $thresholds.cpu_warning) { "🟡 Warning"; $totalWarnings++ }
            else { "✅ Normal" }

            $memAlert = if ($memUsagePercent -gt $thresholds.mem_critical) { "🔴 Critical"; $totalWarnings++ }
            elseif ($memUsagePercent -gt $thresholds.mem_warning) { "🟡 Warning"; $totalWarnings++ }
            else { "✅ Normal" }

            # Add disk usage check
            $diskUsagePercent = "<unknown>"
            $diskStatus = "⚠️ Unknown"

            if ($values.Length -ge 5 -and $values[4] -match "^\d+%$") {
                $diskUsagePercent = [int]($values[4] -replace "%", "")

                $diskStatus = if ($diskUsagePercent -gt 80) { "🔴 Critical"; $totalWarnings++ }
                elseif ($diskUsagePercent -gt 60) { "🟡 Warning"; $totalWarnings++ }
                else { "✅ Normal" }
            }

            # Store node data
            $allNodesData += [PSCustomObject]@{
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



    # **Pagination Setup**
    $currentPage = 0
    $totalPages = [math]::Ceiling($totalNodes / $PageSize)

    do {
        Clear-Host
        Write-Host "`n[📊 Node Resource Usage - Page $($currentPage + 1) of $totalPages]" -ForegroundColor Cyan

        # **Display total warnings in the speech bubble before pagination starts**
        $msg = @(
            "🤖 Nodes are assessed for CPU, memory, and disk usage. Alerts indicate high resource utilization.",
            "",
            "📌 If CPU or memory usage is high, check workloads consuming excessive resources and optimize them.",
            "📌 If disk usage is critical, consider adding storage capacity or cleaning up unused data.",
            "",
            "⚠️ Total Resource Warnings Across All Nodes: $totalWarnings"
        )

        Write-SpeechBubble -msg $msg -color "Cyan" -icon "🤖" -lastColor "Red" -delay 50

        # Display current page
        $startIndex = $currentPage * $PageSize
        $endIndex = [math]::Min($startIndex + $PageSize, $totalNodes)

        $tableData = $allNodesData[$startIndex..($endIndex - 1)]
        if ($tableData) {
            $tableData | Format-Table -Property Node, "CPU %", "CPU Used", "CPU Total", "CPU Status", "Mem %", "Mem Used", "Mem Total", "Mem Status", "Disk %", "Disk Status" -AutoSize
        }

        # Call the pagination function
        $newPage = Show-Pagination -currentPage $currentPage -totalPages $totalPages

        # Exit pagination if 'C' (Continue) was selected
        if ($newPage -eq -1) { break }

        $currentPage = $newPage

    } while ($true)
}


function Show-PodsWithHighRestarts {
    param(
        [string]$Namespace = "",
        [int]$PageSize = 10  # Number of pods per page
    )

    Write-Host "`n[🔁 Pods with High Restarts]" -ForegroundColor Cyan
    Write-Host -NoNewline "`n🤖 Fetching Pod Restart Data..." -ForegroundColor Yellow

    $thresholds = Get-KubeBuddyThresholds

    # Fetch pod data
    try {
        if ($Namespace -ne "") {
            $restartPods = kubectl get pods -n $Namespace -o json 2>&1 | ConvertFrom-Json
        }
        else {
            $restartPods = kubectl get pods --all-namespaces -o json 2>&1 | ConvertFrom-Json
        }
    }
    catch {
        Write-Host "`r🤖 ❌ Error retrieving pod data: $_" -ForegroundColor Red
        Read-Host "🤖 Press Enter to return to the menu"
        return
    }

    # Filter pods with high restart counts
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

        # Only include pods that exceed restart thresholds
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
        Write-Host "`r🤖 ✅ No pods with excessive restarts detected." -ForegroundColor Green
        Read-Host "🤖 Press Enter to return to the menu"
        return
    }

    Write-Host "`r🤖 ✅ High-restart pods fetched. ($totalPods detected)" -ForegroundColor Green

    # **Pagination Setup**
    $currentPage = 0
    $totalPages = [math]::Ceiling($totalPods / $PageSize)

    do {
        Clear-Host
        Write-Host "`n[🔁 Pods with High Restarts - Page $($currentPage + 1) of $totalPages]" -ForegroundColor Cyan

        # **Speech Bubble with Explanation**
        $msg = @(
            "🤖 Some pods are experiencing frequent restarts.",
            "",
            "📌 Why this matters:",
            "   - Frequent restarts may indicate a failing application.",
            "   - CrashLoopBackOff issues often result from config errors.",
            "   - High restarts can cause service degradation.",
            "",
            "🔍 Recommended Actions:",
            "   - Check logs with 'kubectl logs <pod> -n <namespace>'.",
            "   - Inspect events: 'kubectl describe pod <pod> -n <namespace>'.",
            "   - Verify resource limits and probes (liveness/readiness).",
            "",
            "⚠️ Total High-Restart Pods: $totalPods"
        )

        Write-SpeechBubble -msg $msg -color "Cyan" -icon "🤖" -lastColor "Red" -delay 50

        # Display current page
        $startIndex = $currentPage * $PageSize
        $endIndex = [math]::Min($startIndex + $PageSize, $totalPods)

        $tableData = $filteredPods[$startIndex..($endIndex - 1)]

        if ($tableData) {
            $tableData | Format-Table Namespace, Pod, Deployment, Restarts, Status -AutoSize
        }

        # Call the pagination function
        $newPage = Show-Pagination -currentPage $currentPage -totalPages $totalPages

        # Exit pagination if 'C' (Continue) was selected
        if ($newPage -eq -1) { break }
        
        $currentPage = $newPage

    } while ($true)
}

function Show-LongRunningPods {
    param(
        [string]$Namespace = "",
        [int]$PageSize = 10  # Number of pods per page
    )

    Write-Host "`n[⏳ Long Running Pods]" -ForegroundColor Cyan
    Write-Host -NoNewline "`n🤖 Fetching Pod Data..." -ForegroundColor Yellow

    $thresholds = Get-KubeBuddyThresholds

    # Fetch running pods
    try {
        if ($Namespace -ne "") {
            $stalePods = kubectl get pods -n $Namespace -o json 2>&1 | ConvertFrom-Json
        }
        else {
            $stalePods = kubectl get pods --all-namespaces -o json 2>&1 | ConvertFrom-Json
        }
    }
    catch {
        Write-Host "`r🤖 ❌ Error retrieving pod data: $_" -ForegroundColor Red
        Read-Host "🤖 Press Enter to return to the menu"
        return
    }

    # Filter only long-running pods exceeding warning/critical threshold
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
        Write-Host "`r🤖 ✅ No long-running pods detected." -ForegroundColor Green
        Read-Host "🤖 Press Enter to return to the menu"
        return
    }

    Write-Host "`r🤖 ✅ Long-running pods fetched. ($totalPods detected)" -ForegroundColor Green

    # **Pagination Setup**
    $currentPage = 0
    $totalPages = [math]::Ceiling($totalPods / $PageSize)

    do {
        Clear-Host
        Write-Host "`n[⏳ Long Running Pods - Page $($currentPage + 1) of $totalPages]" -ForegroundColor Cyan

        # **Speech Bubble with Explanation**
        $msg = @(
            "🤖 Pods that have been running for extended periods.",
            "",
            "📌 Why this matters:",
            "   - Long-running pods may indicate outdated workloads.",
            "   - Some applications expect restarts to refresh state.",
            "   - High uptime without rolling updates can cause drift issues.",
            "",
            "🔍 Recommended Actions:",
            "   - Check if these pods should be updated or restarted.",
            "   - Review deployments for stale workloads.",
            "",
            "⚠️ Total Long-Running Pods: $totalPods"
        )
        

        Write-SpeechBubble -msg $msg -color "Cyan" -icon "🤖" -lastColor "Red" -delay 50

        # Display current page
        $startIndex = $currentPage * $PageSize
        $endIndex = [math]::Min($startIndex + $PageSize, $totalPods)

        $tableData = $filteredPods[$startIndex..($endIndex - 1)]

        if ($tableData) {
            $tableData | Format-Table Namespace, Pod, Age_Days, Status -AutoSize
        }

        # Call the pagination function
        $newPage = Show-Pagination -currentPage $currentPage -totalPages $totalPages

        # Exit pagination if 'C' (Continue) was selected
        if ($newPage -eq -1) { break }
        
        $currentPage = $newPage

    } while ($true)
}


function Show-DaemonSetIssues {
    param(
        [int]$PageSize = 10  # Number of daemonsets per page
    )

    Write-Host "`n[🔄 DaemonSets Not Fully Running]" -ForegroundColor Cyan
    Write-Host -NoNewline "`n🤖 Fetching DaemonSet Data..." -ForegroundColor Yellow

    try {
        $daemonsets = kubectl get daemonsets --all-namespaces -o json 2>&1 | ConvertFrom-Json
    }
    catch {
        Write-Host "`r🤖 ❌ Error retrieving DaemonSet data: $_" -ForegroundColor Red
        Read-Host "🤖 Press Enter to return to the menu"
        return
    }

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
        Write-Host "`r🤖 ✅ All DaemonSets are fully running." -ForegroundColor Green
        Read-Host "🤖 Press Enter to return to the menu"
        return
    }

    Write-Host "`r🤖 ✅ DaemonSets fetched. ($totalDaemonSets DaemonSets with issues detected)" -ForegroundColor Green

    # **Pagination Setup**
    $currentPage = 0
    $totalPages = [math]::Ceiling($totalDaemonSets / $PageSize)

    do {
        Clear-Host
        Write-Host "`n[🔄 DaemonSets Not Fully Running - Page $($currentPage + 1) of $totalPages]" -ForegroundColor Cyan

        # **Speech Bubble with Explanation**
        $msg = @(
            "🤖 DaemonSets run on every node in your cluster.",
            "",
            "📌 This check identifies DaemonSets that are not fully running.",
            "   - Nodes may lack resources (CPU, Memory).",
            "   - Scheduling constraints (taints, affinity) could be blocking.",
            "   - DaemonSet pod images may be failing to pull.",
            "",
            "🔍 Investigate further using:",
            "   - 'kubectl describe ds <daemonset-name> -n <namespace>'",
            "   - 'kubectl get pods -n <namespace> -o wide'",
            "",
            "⚠️ Total DaemonSets with Issues: $totalDaemonSets"
        )

        Write-SpeechBubble -msg $msg -color "Cyan" -icon "🤖" -lastColor "Red" -delay 50

        # Display current page
        $startIndex = $currentPage * $PageSize
        $endIndex = [math]::Min($startIndex + $PageSize, $totalDaemonSets)

        $tableData = $filteredDaemonSets[$startIndex..($endIndex - 1)]
        if ($tableData) {
            $tableData | Format-Table Namespace, DaemonSet, Desired, Running, Scheduled, Status -AutoSize
        }

        # Call the pagination function
        $newPage = Show-Pagination -currentPage $currentPage -totalPages $totalPages

        # Exit pagination if 'C' (Continue) was selected
        if ($newPage -eq -1) { break }
        
        $currentPage = $newPage

    } while ($true)
}


function Show-FailedPods {
    param(
        [string]$Namespace = "",
        [int]$PageSize = 10  # Number of pods per page
    )

    Write-Host "`n[🔴 Failed Pods]" -ForegroundColor Cyan
    Write-Host -NoNewline "`n🤖 Fetching Failed Pod Data..." -ForegroundColor Yellow

    # Fetch failed pods
    try {
        if ($Namespace -ne "") {
            $failedPods = kubectl get pods -n $Namespace -o json 2>&1 | ConvertFrom-Json |
            Select-Object -ExpandProperty items |
            Where-Object { $_.status.phase -eq "Failed" }
        }
        else {
            $failedPods = kubectl get pods --all-namespaces -o json 2>&1 | ConvertFrom-Json |
            Select-Object -ExpandProperty items |
            Where-Object { $_.status.phase -eq "Failed" }
        }
    }
    catch {
        Write-Host "`r🤖 ❌ Error retrieving pod data: $_" -ForegroundColor Red
        Read-Host "🤖 Press Enter to return to the menu"
        return
    }

    $totalPods = $failedPods.Count

    if ($totalPods -eq 0) {
        Write-Host "`r🤖 ✅ No failed pods found." -ForegroundColor Green
        Read-Host "🤖 Press Enter to return to the menu"
        return
    }

    Write-Host "`r🤖 ✅ Failed Pods fetched. ($totalPods detected)" -ForegroundColor Green

    # **Pagination Setup**
    $currentPage = 0
    $totalPages = [math]::Ceiling($totalPods / $PageSize)

    do {
        Clear-Host
        Write-Host "`n[🔴 Failed Pods - Page $($currentPage + 1) of $totalPages]" -ForegroundColor Cyan

        # **Speech Bubble with Explanation**
        $msg = @(
            "🤖 Pods that failed to start or complete successfully.",
            "",
            "📌 A pod can fail due to:",
            "   - Image pull issues (wrong image, no registry access).",
            "   - Insufficient CPU/memory resources.",
            "   - CrashLoopBackOff due to misconfigured applications.",
            "",
            "🔍 Debugging Commands:",
            "   - 'kubectl describe pod <pod-name> -n <namespace>'",
            "   - 'kubectl logs <pod-name> -n <namespace>'",
            "",
            "⚠️ Total Failed Pods: $totalPods"
        )

        Write-SpeechBubble -msg $msg -color "Cyan" -icon "🤖" -lastColor "Red" -delay 50

        # Display current page
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

        if ($tableData) {
            $tableData | Format-Table Namespace, Pod, Reason, Message -AutoSize
        }

        # Call the pagination function
        $newPage = Show-Pagination -currentPage $currentPage -totalPages $totalPages

        # Exit pagination if 'C' (Continue) was selected
        if ($newPage -eq -1) { break }
        
        $currentPage = $newPage

    } while ($true)
}


function Show-EmptyNamespaces {
    param(
        [int]$PageSize = 10  # Number of namespaces per page
    )

    Write-Host "`n[📂 Empty Namespaces]" -ForegroundColor Cyan
    Write-Host -NoNewline "`n🤖 Fetching Namespace Data..." -ForegroundColor Yellow

    # Fetch all namespaces
    $namespaces = kubectl get namespaces -o json | ConvertFrom-Json |
    Select-Object -ExpandProperty items |
    Select-Object -ExpandProperty metadata |
    Select-Object -ExpandProperty name

    # Fetch all pods and their namespaces
    $pods = kubectl get pods --all-namespaces -o json | ConvertFrom-Json |
    Select-Object -ExpandProperty items |
    Group-Object { $_.metadata.namespace }

    # Extract namespaces that have at least one pod
    $namespacesWithPods = $pods.Name

    # Get only namespaces that are completely empty
    $emptyNamespaces = $namespaces | Where-Object { $_ -notin $namespacesWithPods }

    $totalNamespaces = $emptyNamespaces.Count

    if ($totalNamespaces -eq 0) {
        Write-Host "`r🤖 ✅ No empty namespaces found." -ForegroundColor Green
        Read-Host "🤖 Press Enter to return to the menu"
        return
    }

    Write-Host "`r🤖 ✅ Namespaces fetched. ($totalNamespaces empty namespaces detected)" -ForegroundColor Green


    # **Pagination Setup**
    $currentPage = 0
    $totalPages = [math]::Ceiling($totalNamespaces / $PageSize)

    do {
        Clear-Host
        Write-Host "`n[📂 Empty Namespaces - Page $($currentPage + 1) of $totalPages]" -ForegroundColor Cyan

        # **Speech Bubble with Explanation**
        $msg = @(
            "🤖 Empty namespaces exist but contain no running pods.",
            "",
            "📌 These may be unused namespaces that can be cleaned up.",
            "📌 If needed, verify if they contain other resources (Secrets, PVCs).",
            "📌 Deleting an empty namespace will remove all associated resources.",
            "",
            "⚠️ Total Empty Namespaces: $totalNamespaces"
        )

        Write-SpeechBubble -msg $msg -color "Cyan" -icon "🤖" -lastColor "Red" -delay 50

        # Display current page
        $startIndex = $currentPage * $PageSize
        $endIndex = [math]::Min($startIndex + $PageSize, $totalNamespaces)

        $tableData = @()
        for ($i = $startIndex; $i -lt $endIndex; $i++) {
            $namespace = $emptyNamespaces[$i]
            $tableData += [PSCustomObject]@{ "Namespace" = $namespace }
        }

        if ($tableData) {
            $tableData | Format-Table Namespace -AutoSize
        }

        # Call the pagination function
        $newPage = Show-Pagination -currentPage $currentPage -totalPages $totalPages

        # Exit pagination if 'C' (Continue) was selected
        if ($newPage -eq -1) { break }
        
        $currentPage = $newPage

    } while ($true)
}

function Show-PendingPods {
    param(
        [string]$Namespace = "",
        [int]$PageSize = 10
    )

    Write-Host "`n[⏳ Pending Pods]" -ForegroundColor Cyan
    Write-Host -NoNewline "`n🤖 Fetching Pod Data..." -ForegroundColor Yellow

    try {
        if ($Namespace -ne "") {
            $pendingPods = kubectl get pods -n $Namespace -o json 2>&1 | ConvertFrom-Json | Select-Object -ExpandProperty items
        } 
        else {
            $pendingPods = kubectl get pods --all-namespaces -o json 2>&1 | ConvertFrom-Json | Select-Object -ExpandProperty items
        }
    }
    catch {
        Write-Host "`r🤖 ❌ Error retrieving pod data: $_" -ForegroundColor Red
        Read-Host "🤖 Press Enter to return to the menu"
        return
    }

    # Filter Pending pods
    $pendingPods = $pendingPods | Where-Object { $_.status.phase -eq "Pending" }

    $totalPods = $pendingPods.Count

    if ($totalPods -eq 0) {
        Write-Host "`r🤖 ✅ No pending pods found." -ForegroundColor Green
        Read-Host "🤖 Press Enter to return to the menu"
        return
    }

    Write-Host "`r🤖 ✅ Pods fetched. ($totalPods Pending pods detected)" -ForegroundColor Green

    # **Pagination Setup**
    $currentPage = 0
    $totalPages = [math]::Ceiling($totalPods / $PageSize)

    do {
        Clear-Host
        Write-Host "`n[⏳ Pending Pods - Page $($currentPage + 1) of $totalPages]" -ForegroundColor Cyan

        # **Speech Bubble with Explanation**
        $msg = @(
            "🤖 Pending pods are stuck in a non-running state.",
            "",
            "📌 This check identifies pods that are unable to start due to:",
            "   - Insufficient cluster resources (CPU, Memory)",
            "   - Scheduling issues (e.g., node taints, affinity rules)",
            "   - Missing dependencies (PVCs, ConfigMaps, Secrets)",
            "",
            "🔍 Investigate further using:",
            "   - 'kubectl describe pod <pod-name> -n <namespace>'",
            "   - 'kubectl get events -n <namespace>'",
            "",
            "⚠️ Total Pending Pods Found: $totalPods"
        )

        write-SpeechBubble -msg $msg -color "Cyan" -icon "🤖" -lastColor "Red" -delay 50

        # Display current page
        $startIndex = $currentPage * $PageSize
        $endIndex = [math]::Min($startIndex + $PageSize, $totalPods)

        $tableData = @()
        for ($i = $startIndex; $i -lt $endIndex; $i++) {
            $pod = $pendingPods[$i]
            $ns = $pod.metadata.namespace
            $podName = $pod.metadata.name
            $reason = if ($pod.status.conditions) { $pod.status.conditions[0].reason } else { "Unknown" }
            $message = if ($pod.status.conditions) { $pod.status.conditions[0].message -replace "`n", " " } else { "No details available" }

            $tableData += [PSCustomObject]@{
                Namespace = $ns
                Pod       = $podName
                Reason    = $reason
                Message   = $message
            }
        }

        if ($tableData) {
            $tableData | Format-Table Namespace, Pod, Reason, Message -AutoSize
        }

        # Call the pagination function
        $newPage = Show-Pagination -currentPage $currentPage -totalPages $totalPages

        # Exit pagination if 'C' (Continue) was selected
        if ($newPage -eq -1) { break }
        
        $currentPage = $newPage

    } while ($true)
}


function Show-CrashLoopBackOffPods {
    param(
        [string]$Namespace = "",
        [int]$PageSize = 10
    )

    Write-Host "`n[🔴 CrashLoopBackOff Pods]" -ForegroundColor Cyan
    Write-Host -NoNewline "`n🤖 Fetching Pod Data..." -ForegroundColor Yellow

    try {
        if ($Namespace -ne "") {
            $crashPods = kubectl get pods -n $Namespace -o json 2>&1 | ConvertFrom-Json | Select-Object -ExpandProperty items
        } 
        else {
            $crashPods = kubectl get pods --all-namespaces -o json 2>&1 | ConvertFrom-Json | Select-Object -ExpandProperty items
        }
    }
    catch {
        Write-Host "`r🤖 ❌ Error retrieving pod data: $_" -ForegroundColor Red
        Read-Host "🤖 Press Enter to return to the menu"
        return
    }

    # Filter CrashLoopBackOff pods
    $crashPods = $crashPods | Where-Object { 
        $_.status.containerStatuses -and 
        $_.status.containerStatuses.restartCount -gt 5 -and 
        $_.status.containerStatuses.state.waiting.reason -eq "CrashLoopBackOff"
    }

    $totalPods = $crashPods.Count

    if ($totalPods -eq 0) {
        Write-Host "`r🤖 ✅ No CrashLoopBackOff pods found." -ForegroundColor Green
        Read-Host "🤖 Press Enter to return to the menu"
        return
    }

    Write-Host "`r🤖 ✅ Pods fetched. ($totalPods CrashLoopBackOff pods detected)" -ForegroundColor Green

    # **Pagination Setup**
    $currentPage = 0
    $totalPages = [math]::Ceiling($totalPods / $PageSize)

    do {
        Clear-Host
        Write-Host "`n[🔴 CrashLoopBackOff Pods - Page $($currentPage + 1) of $totalPages]" -ForegroundColor Cyan

        # **Speech Bubble with Explanation**
        $msg = @(
            "🤖 CrashLoopBackOff occurs when a pod continuously crashes.",
            "",
            "📌 This check identifies pods that keep restarting due to failures.",
            "   - Common causes: misconfigurations, missing dependencies, or insufficient resources.",
            "   - Investigate pod logs: 'kubectl logs <pod-name> -n <namespace>'",
            "   - Describe the pod: 'kubectl describe pod <pod-name>'",
            "",
            "⚠️ Review and fix these issues to restore pod stability.",
            "",
            "⚠️ Total CrashLoopBackOff Pods Found: $totalPods"
        )

        Write-SpeechBubble -msg $msg -color "Cyan" -icon "🤖" -lastColor "Red" -delay 50

        # Display current page
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

        if ($tableData) {
            $tableData | Format-Table Namespace, Pod, Restarts, Status -AutoSize
        }

        # Call the pagination function
        $newPage = Show-Pagination -currentPage $currentPage -totalPages $totalPages

        # Exit pagination if 'C' (Continue) was selected
        if ($newPage -eq -1) { break }
        
        $currentPage = $newPage

    } while ($true)
}


function Show-ServicesWithoutEndpoints {
    param(
        [int]$PageSize = 10  # Number of services per page
    )

    Write-Host "`n[🔍 Services Without Endpoints]" -ForegroundColor Cyan
    Write-Host -NoNewline "`n🤖 Fetching Service Data..." -ForegroundColor Yellow

    # Fetch all services
    $services = kubectl get services --all-namespaces -o json | ConvertFrom-Json | Select-Object -ExpandProperty items |
        Where-Object { $_.spec.type -ne "ExternalName" }  # Exclude ExternalName services

    if (-not $services) {
        Write-Host "`r🤖 ❌ Failed to fetch service data." -ForegroundColor Red
        Read-Host "🤖 Press Enter to return to the menu"
        return
    }

    Write-Host "`r🤖 ✅ Services fetched. (Total: $($services.Count))" -ForegroundColor Green

    Write-Host -NoNewline "`n🤖 Fetching Endpoint Data..." -ForegroundColor Yellow

    # Fetch endpoints
    $endpoints = kubectl get endpoints --all-namespaces -o json | ConvertFrom-Json | Select-Object -ExpandProperty items |
        Group-Object { $_.metadata.namespace + "/" + $_.metadata.name }

    if (-not $endpoints) {
        Write-Host "`r🤖 ❌ Failed to fetch endpoint data." -ForegroundColor Red
        Read-Host "🤖 Press Enter to return to the menu"
        return
    }

    Write-Host "`r🤖 ✅ Endpoints fetched. (Total: $($endpoints.Count))" -ForegroundColor Green
    Write-Host "`n🤖 Analyzing Services..." -ForegroundColor Yellow

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
        Write-Host "`r🤖 ✅ All services have endpoints." -ForegroundColor Green
        Read-Host "🤖 Press Enter to return to the menu"
        return
    }

    Write-Host "`r🤖 ✅ Service analysis complete. ($totalServices services without endpoints detected)" -ForegroundColor Green

    # **Pagination Setup**
    $currentPage = 0
    $totalPages = [math]::Ceiling($totalServices / $PageSize)

    do {
        Clear-Host
        Write-Host "`n[🔍 Services Without Endpoints - Page $($currentPage + 1) of $totalPages]" -ForegroundColor Cyan

        # **Speech Bubble with Explanation**
        $msg = @(
            "🤖 Kubernetes services route traffic, but require endpoints to work.",
            "",
            "📌 This check identifies services that have no associated endpoints.",
            "   - No endpoints could mean no running pods match service selectors.",
            "   - It may also indicate misconfigurations or orphaned services.",
            "",
            "⚠️ Investigate these services to confirm if they are required.",
            "",
            "⚠️ Total Services Without Endpoints: $totalServices"
        )

        write-SpeechBubble -msg $msg -color "Cyan" -icon "🤖" -lastColor "Red" -delay 50

        # Display current page
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

        if ($tableData) {
            $tableData | Format-Table Namespace, Service, Type, Status -AutoSize
        }

        # Call the pagination function
        $newPage = Show-Pagination -currentPage $currentPage -totalPages $totalPages

        # Exit pagination if 'C' (Continue) was selected
        if ($newPage -eq -1) { break }
        
        $currentPage = $newPage

    } while ($true)
}


function Show-UnusedPVCs {
    param(
        [int]$PageSize = 10  # Number of PVCs per page
    )

    Write-Host "`n[💾 Unused Persistent Volume Claims]" -ForegroundColor Cyan
    Write-Host -NoNewline "`n🤖 Fetching PVC Data..." -ForegroundColor Yellow

    # Fetch all PVCs
    $pvcs = kubectl get pvc --all-namespaces -o json | ConvertFrom-Json | Select-Object -ExpandProperty items
    if (-not $pvcs) {
        Write-Host "`r🤖 ❌ Failed to fetch PVC data." -ForegroundColor Red
        Read-Host "🤖 Press Enter to return to the menu"
        return
    }
    
    Write-Host "`r🤖 ✅ PVCs fetched. (Total: $($pvcs.Count))" -ForegroundColor Green

    Write-Host -NoNewline "`n🤖 Fetching Pod Data..." -ForegroundColor Yellow

    # Fetch all Pods
    $pods = kubectl get pods --all-namespaces -o json | ConvertFrom-Json | Select-Object -ExpandProperty items
    if (-not $pods) {
        Write-Host "`r🤖 ❌ Failed to fetch Pod data." -ForegroundColor Red
        Read-Host "🤖 Press Enter to return to the menu"
        return
    }
    
    Write-Host "`r🤖 ✅ Pods fetched. (Total: $($pods.Count))" -ForegroundColor Green

    # Get all PVCs that are not attached to any pod
    Write-Host "`n🤖 Analyzing PVC usage..." -ForegroundColor Yellow

    $attachedPVCs = $pods | ForEach-Object { $_.spec.volumes | Where-Object { $_.persistentVolumeClaim } } | Select-Object -ExpandProperty persistentVolumeClaim
    $unusedPVCs = $pvcs | Where-Object { $_.metadata.name -notin $attachedPVCs.name }

    $totalPVCs = $unusedPVCs.Count

    if ($totalPVCs -eq 0) {
        Write-Host "`r🤖 ✅ No unused PVCs found." -ForegroundColor Green
        Read-Host "🤖 Press Enter to return to the menu"
        return
    }

    Write-Host "`r🤖 ✅ PVC usage analyzed. ($totalPVCs unused PVCs detected)" -ForegroundColor Green

    # **Pagination Setup**
    $currentPage = 0
    $totalPages = [math]::Ceiling($totalPVCs / $PageSize)

    do {
        Clear-Host
        Write-Host "`n[💾 Unused Persistent Volume Claims - Page $($currentPage + 1) of $totalPages]" -ForegroundColor Cyan

        # **Speech Bubble with Explanation**
        $msg = @(
            "🤖 Persistent Volume Claims (PVCs) reserve storage in your cluster.",
            "",
            "📌 This check identifies PVCs that are NOT attached to any Pod.",
            "   - Unused PVCs may indicate abandoned or uncleaned storage.",
            "   - Storage resources remain allocated until PVCs are deleted.",
            "",
            "⚠️ Review unused PVCs before deletion to avoid accidental data loss.",
            "",
            "⚠️ Total Unused PVCs Found: $totalPVCs"
        )

        write-SpeechBubble -msg $msg -color "Cyan" -icon "🤖" -lastColor "Red" -delay 50

        $startIndex = $currentPage * $PageSize
        $endIndex = [math]::Min($startIndex + $PageSize, $totalPVCs)

        $tableData = $unusedPVCs[$startIndex..($endIndex - 1)]

        if ($tableData) {
            $tableData | Format-Table -Property @{Label = "Namespace"; Expression = { $_.metadata.namespace } }, 
            @{Label = "PVC"; Expression = { $_.metadata.name } }, 
            @{Label = "Storage"; Expression = { $_.spec.resources.requests.storage } } -AutoSize
        }

        # Call the pagination function
        $newPage = Show-Pagination -currentPage $currentPage -totalPages $totalPages

        # Exit pagination if 'C' (Continue) was selected
        if ($newPage -eq -1) { break }
                
        $currentPage = $newPage

    } while ($true)
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

    Write-Host "`n[⏳ Stuck Kubernetes Jobs]" -ForegroundColor Cyan
    Write-Host -NoNewline "`n🤖 Fetching Job Data..." -ForegroundColor Yellow

    # Fetch jobs, capturing both stdout and stderr
    $kubectlOutput = kubectl get jobs --all-namespaces -o json 2>&1 | Out-String

    # Check for actual errors in kubectl output
    if ($kubectlOutput -match "error|not found|forbidden") {
        Write-Host "`r🤖 ❌ Error retrieving job data: $kubectlOutput" -ForegroundColor Red
        Read-Host "🤖 Press Enter to return to the menu"
        return
    }

    # Ensure valid JSON before parsing
    if ($kubectlOutput -match "^{") {
        $jobs = $kubectlOutput | ConvertFrom-Json | Select-Object -ExpandProperty items
    }
    else {
        Write-Host "`r🤖 ❌ Unexpected response from kubectl. No valid JSON received." -ForegroundColor Red
        Read-Host "🤖 Press Enter to return to the menu"
        return
    }

    # Ensure $jobs is an array before processing
    if (-not $jobs -or $jobs.Count -eq 0) {
        Write-Host "`r🤖 ✅ No jobs found in the cluster." -ForegroundColor Green
        Read-Host "🤖 Press Enter to return to the menu"
        return
    }

    Write-Host "`r🤖 ✅ Jobs fetched. (Total: $($jobs.Count))" -ForegroundColor Green
    Write-Host -NoNewline "`n🤖 Analyzing Stuck Jobs..." -ForegroundColor Yellow

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
        Write-Host "`r🤖 ✅ No stuck jobs found." -ForegroundColor Green
        Read-Host "🤖 Press Enter to return to the menu"
        return
    }

    Write-Host "`r🤖 ✅ Job analysis complete. ($($stuckJobs.Count) stuck jobs detected)" -ForegroundColor Green

    # **Pagination Setup**
    $totalJobs = $stuckJobs.Count
    $currentPage = 0
    $totalPages = [math]::Ceiling($totalJobs / $PageSize)

    do {
        Clear-Host
        Write-Host "`n[⏳ Stuck Kubernetes Jobs - Page $($currentPage + 1) of $totalPages]" -ForegroundColor Cyan

        # **Speech Bubble with Explanation**
        $msg = @(
            "🤖 Kubernetes Jobs should complete within a reasonable time.",
            "",
            "📌 This check identifies jobs that have been running too long and have not completed, failed, or succeeded.",
            "📌 Possible causes:",
            "   - Stuck pods or unresponsive workloads",
            "   - Misconfigured restart policies",
            "   - Insufficient resources (CPU/Memory)",
            "",
            "⚠️ Investigate these jobs to determine the cause and resolve issues.",
            "",
            "⚠️ Total Stuck Jobs Found: $($stuckJobs.Count)"
        )

        Write-SpeechBubble -msg $msg -color "Cyan" -icon "🤖" -lastColor "Red" -delay 50

        # Display current page
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

        if ($tableData) {
            $tableData | Format-Table Namespace, Job, Age_Hours, Status -AutoSize
        }

        # Call the pagination function
        $newPage = Show-Pagination -currentPage $currentPage -totalPages $totalPages

        # Exit pagination if 'C' (Continue) was selected
        if ($newPage -eq -1) { break }
        
        $currentPage = $newPage

    } while ($true)
}


function Show-FailedJobs {
    param(
        [int]$StuckThresholdHours = 2,
        [int]$PageSize = 10
    )

    Write-Host "`n[🔴 Failed Kubernetes Jobs]" -ForegroundColor Cyan
    Write-Host -NoNewline "`n🤖 Fetching Job Data..." -ForegroundColor Yellow

    # Fetch jobs, capturing both stdout and stderr
    $kubectlOutput = kubectl get jobs --all-namespaces -o json 2>&1 | Out-String

    # Check for actual errors in kubectl output
    if ($kubectlOutput -match "error|not found|forbidden") {
        Write-Host "`r🤖 ❌ Error retrieving job data: $kubectlOutput" -ForegroundColor Red
        Read-Host "🤖 Press Enter to return to the menu"
        return
    }

    # Ensure valid JSON before parsing
    if ($kubectlOutput -match "^{") {
        $jobs = $kubectlOutput | ConvertFrom-Json | Select-Object -ExpandProperty items
    }
    else {
        Write-Host "`r🤖 ❌ Unexpected response from kubectl. No valid JSON received." -ForegroundColor Red
        Read-Host "🤖 Press Enter to return to the menu"
        return
    }

    # Ensure $jobs is an array before processing
    if (-not $jobs -or $jobs.Count -eq 0) {
        Write-Host "`r🤖 ✅ No jobs found in the cluster." -ForegroundColor Green
        Read-Host "🤖 Press Enter to return to the menu"
        return
    }

    Write-Host "`r🤖 ✅ Jobs fetched. (Total: $($jobs.Count))" -ForegroundColor Green
    Write-Host -NoNewline "`n🤖 Analyzing Failed Jobs..." -ForegroundColor Yellow

    # Filter failed jobs
    $failedJobs = $jobs | Where-Object { 
        $_.status.PSObject.Properties['failed'] -and $_.status.failed -gt 0 -and # Job has failed
        (-not $_.status.PSObject.Properties['succeeded'] -or $_.status.succeeded -eq 0) -and # Not succeeded
        $_.status.PSObject.Properties['startTime'] -and # Has a startTime
        ((New-TimeSpan -Start $_.status.startTime -End (Get-Date)).TotalHours -gt $StuckThresholdHours)
    }

    # No failed jobs found
    if (-not $failedJobs -or $failedJobs.Count -eq 0) {
        Write-Host "`r🤖 ✅ No failed jobs found." -ForegroundColor Green
        Read-Host "🤖 Press Enter to return to the menu"
        return
    }

    Write-Host "`r🤖 ✅ Job analysis complete. ($($failedJobs.Count) failed jobs detected)" -ForegroundColor Green

    # **Pagination Setup**
    $totalJobs = $failedJobs.Count
    $currentPage = 0
    $totalPages = [math]::Ceiling($totalJobs / $PageSize)

    do {
        Clear-Host
        Write-Host "`n[🔴 Failed Kubernetes Jobs - Page $($currentPage + 1) of $totalPages]" -ForegroundColor Cyan

        # **Speech Bubble with Explanation**
        $msg = @(
            "🤖 Kubernetes Jobs should complete successfully.",
            "",
            "📌 This check identifies jobs that have encountered failures.",
            "   - Jobs may fail due to insufficient resources, timeouts, or misconfigurations.",
            "   - Review logs with 'kubectl logs job/<job-name>'",
            "   - Investigate pod failures with 'kubectl describe job/<job-name>'",
            "",
            "⚠️ Consider re-running or debugging these jobs for resolution.",
            "",
            "⚠️ Total Failed Jobs Found: $($failedJobs.Count)"
        )

        Write-SpeechBubble -msg $msg -color "Cyan" -icon "🤖" -lastColor "Red" -delay 50

        # Display current page
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

        if ($tableData) {
            $tableData | Format-Table Namespace, Job, Age_Hours, Failures, Status -AutoSize
        }

        # Call the pagination function
        $newPage = Show-Pagination -currentPage $currentPage -totalPages $totalPages

        # Exit pagination if 'C' (Continue) was selected
        if ($newPage -eq -1) { break }
        
        $currentPage = $newPage

    } while ($true)
}

function Check-OrphanedConfigMaps {
    param(
        [int]$PageSize = 10
    )

    Write-Host "`n[🔍 Orphaned ConfigMaps]" -ForegroundColor Cyan
    Write-Host -NoNewline "`n🤖 Fetching ConfigMaps..." -ForegroundColor Yellow

    # Exclude Helm-managed ConfigMaps
    $excludedConfigMapPatterns = @("^sh\.helm\.release\.v1\.")

    $configMaps = kubectl get configmaps --all-namespaces -o json | ConvertFrom-Json | Select-Object -ExpandProperty items |
    Where-Object { $_.metadata.name -notmatch ($excludedConfigMapPatterns -join "|") }

    Write-Host "`r🤖 ✅ ConfigMaps fetched. ($($configMaps.Count) total)" -ForegroundColor Green

    # Fetch workloads & used ConfigMaps
    Write-Host -NoNewline "`n🤖 Checking ConfigMap usage..." -ForegroundColor Yellow
    $usedConfigMaps = @()

    # Fetch Kubernetes resources that can reference ConfigMaps
    $pods = kubectl get pods --all-namespaces -o json | ConvertFrom-Json | Select-Object -ExpandProperty items

    $workloads = @(kubectl get deployments --all-namespaces -o json | ConvertFrom-Json | Select-Object -ExpandProperty items) +
    @(kubectl get statefulsets --all-namespaces -o json | ConvertFrom-Json | Select-Object -ExpandProperty items) +
    @(kubectl get daemonsets --all-namespaces -o json | ConvertFrom-Json | Select-Object -ExpandProperty items) +
    @(kubectl get cronjobs --all-namespaces -o json | ConvertFrom-Json | Select-Object -ExpandProperty items) +
    @(kubectl get jobs --all-namespaces -o json | ConvertFrom-Json | Select-Object -ExpandProperty items) +
    @(kubectl get replicasets --all-namespaces -o json | ConvertFrom-Json | Select-Object -ExpandProperty items)

    $ingresses = kubectl get ingress --all-namespaces -o json | ConvertFrom-Json | Select-Object -ExpandProperty items
    $services = kubectl get services --all-namespaces -o json | ConvertFrom-Json | Select-Object -ExpandProperty items

    # Scan Pods, Deployments, StatefulSets, DaemonSets, CronJobs, Jobs, ReplicaSets
    foreach ($resource in $pods + $workloads) {
        $usedConfigMaps += $resource.spec.volumes | Where-Object { $_.configMap } | Select-Object -ExpandProperty configMap | Select-Object -ExpandProperty name
        foreach ($container in $resource.spec.containers) {
            if ($container.env) {
                $usedConfigMaps += $container.env | Where-Object { $_.valueFrom.configMapKeyRef } | Select-Object -ExpandProperty valueFrom | Select-Object -ExpandProperty configMapKeyRef | Select-Object -ExpandProperty name
            }
            if ($container.envFrom) {
                $usedConfigMaps += $container.envFrom | Where-Object { $_.configMapRef } | Select-Object -ExpandProperty configMapRef | Select-Object -ExpandProperty name
            }
            # **NEW: Check ConfigMap references in container args**
            if ($container.args) {
                foreach ($arg in $container.args) {
                    if ($arg -match "--configmap=\$\(POD_NAMESPACE\)/([\w-]+)") {
                        $usedConfigMaps += $matches[1]  # Capture the ConfigMap name
                    }
                }
            }
        }
    }

    # Check Ingress Annotations
    $usedConfigMaps += $ingresses | ForEach-Object { $_.metadata.annotations.Values -match "configMap" }

    # Check Service Annotations (if they reference ConfigMaps)
    $usedConfigMaps += $services | ForEach-Object { $_.metadata.annotations.Values -match "configMap" }

    # **Scan Custom Resources for ConfigMap References**
    $crds = kubectl get crds -o json | ConvertFrom-Json | Select-Object -ExpandProperty items
    foreach ($crd in $crds) {
        $crdKind = $crd.spec.names.kind
        if ($crdKind -match "^[a-z0-9-]+$") { 
            $customResources = kubectl get $crdKind --all-namespaces -o json 2>$null | ConvertFrom-Json | Select-Object -ExpandProperty items
            foreach ($cr in $customResources) {
                if ($cr.metadata.annotations.Values -match "configMap") {
                    $usedConfigMaps += $cr.metadata.annotations.Values
                }
            }
        }
    }

    # Remove duplicates & nulls
    $usedConfigMaps = $usedConfigMaps | Where-Object { $_ } | Sort-Object -Unique
    Write-Host "`r✅ ConfigMap usage checked." -ForegroundColor Green

    # **Find orphaned ConfigMaps**
    $orphanedConfigMaps = $configMaps | Where-Object { $_.metadata.name -notin $usedConfigMaps }

    # Store orphaned items for pagination
    $orphanedItems = @()
    $orphanedConfigMaps | ForEach-Object {
        $orphanedItems += [PSCustomObject]@{
            Namespace = $_.metadata.namespace
            Type      = "📜 ConfigMap"
            Name      = $_.metadata.name
        }
    }

    # If nothing found, return early
    if ($orphanedItems.Count -eq 0) {
        Write-Host "🤖 ✅ No orphaned ConfigMaps found." -ForegroundColor Green
        Read-Host "🤖 Press Enter to return to the menu"
        return
    }

    # Pagination Setup
    $totalItems = $orphanedItems.Count
    $currentPage = 0
    $totalPages = [math]::Ceiling($totalItems / $PageSize)

    do {
        Clear-Host
        # **Speech Bubble with Explanation**
        $msg = @(
            "🤖 ConfigMaps store configuration data for workloads.",
            "",
            "📌 This check identifies ConfigMaps that are not referenced by:",
            "   - Pods, Deployments, StatefulSets, DaemonSets.",
            "   - CronJobs, Jobs, ReplicaSets, Services, and Custom Resources.",
            "",
            "⚠️ Orphaned ConfigMaps may be outdated and can be reviewed for cleanup.",
            "",
            "⚠️ Total Orphaned ConfigMaps Found: $($orphanedItems.Count)"
        )

        Write-SpeechBubble -msg $msg -color "Cyan" -icon "🤖" -lastColor "Red" -delay 50

        # Display current page
        $startIndex = $currentPage * $PageSize
        $endIndex = [math]::Min($startIndex + $PageSize, $totalItems)

        $tableData = $orphanedItems[$startIndex..($endIndex - 1)]
        if ($tableData) {
            $tableData | Format-Table Namespace, Type, Name -AutoSize
        }

        # Call the pagination function
        $newPage = Show-Pagination -currentPage $currentPage -totalPages $totalPages

        # Exit pagination if 'C' (Continue) was selected
        if ($newPage -eq -1) { break }
        
        $currentPage = $newPage

    } while ($true)
}


function Check-OrphanedSecrets {
    param(
        [int]$PageSize = 10
    )

    Write-Host "`n[🔑 Orphaned Secrets]" -ForegroundColor Cyan
    Write-Host -NoNewline "`n🤖 Fetching Secrets..." -ForegroundColor Yellow

    # Exclude system-managed secrets
    $excludedSecretPatterns = @("^sh\.helm\.release\.v1\.", "^bootstrap-token-", "^default-token-", "^kube-root-ca.crt$", "^kubernetes.io/service-account-token")

    $secrets = kubectl get secrets --all-namespaces -o json | ConvertFrom-Json | Select-Object -ExpandProperty items |
    Where-Object { $_.metadata.name -notmatch ($excludedSecretPatterns -join "|") }

    Write-Host "`r🤖 ✅ Secrets fetched. ($($secrets.Count) total)" -ForegroundColor Green

    # Fetch workloads & used Secrets
    Write-Host -NoNewline "`n🤖 Checking Secret usage..." -ForegroundColor Yellow
    $usedSecrets = @()

    $pods = kubectl get pods --all-namespaces -o json | ConvertFrom-Json | Select-Object -ExpandProperty items
    $workloads = @(kubectl get deployments --all-namespaces -o json | ConvertFrom-Json | Select-Object -ExpandProperty items) +
    @(kubectl get statefulsets --all-namespaces -o json | ConvertFrom-Json | Select-Object -ExpandProperty items) +
    @(kubectl get daemonsets --all-namespaces -o json | ConvertFrom-Json | Select-Object -ExpandProperty items)

    $ingresses = kubectl get ingress --all-namespaces -o json | ConvertFrom-Json | Select-Object -ExpandProperty items
    $serviceAccounts = kubectl get serviceaccounts --all-namespaces -o json | ConvertFrom-Json | Select-Object -ExpandProperty items

    foreach ($resource in $pods + $workloads) {
        $usedSecrets += $resource.spec.volumes | Where-Object { $_.secret } | Select-Object -ExpandProperty secret | Select-Object -ExpandProperty secretName
        foreach ($container in $resource.spec.containers) {
            if ($container.env) {
                $usedSecrets += $container.env | Where-Object { $_.valueFrom.secretKeyRef } | Select-Object -ExpandProperty valueFrom | Select-Object -ExpandProperty secretKeyRef | Select-Object -ExpandProperty name
            }
        }
    }

    $usedSecrets += $ingresses | ForEach-Object { $_.spec.tls | Select-Object -ExpandProperty secretName }
    $usedSecrets += $serviceAccounts | ForEach-Object { $_.secrets | Select-Object -ExpandProperty name }

    Write-Host "`r🤖 ✅ Secret usage checked." -ForegroundColor Green

    # **Check Custom Resources for secret usage**
    Write-Host "`n🤖 Checking Custom Resources for Secret usage..." -ForegroundColor Yellow
    $customResources = kubectl api-resources --verbs=list --namespaced -o name | Where-Object { $_ }
    foreach ($cr in $customResources) {
        # Validate before fetching resources
        $crInstances = kubectl get $cr --all-namespaces -o json 2>$null | ConvertFrom-Json | Select-Object -ExpandProperty items
        if ($crInstances) {
            foreach ($instance in $crInstances) {
                if ($instance.spec -and $instance.spec.PSObject.Properties.name -contains "secretName") {
                    $usedSecrets += $instance.spec.secretName
                }
            }
        }
    }

    $usedSecrets = $usedSecrets | Where-Object { $_ } | Sort-Object -Unique
    Write-Host "`r🤖 ✅ Secret usage checked. ($($usedSecrets.Count) in use)" -ForegroundColor Green

    # **Find orphaned Secrets**
    $orphanedSecrets = $secrets | Where-Object { $_.metadata.name -notin $usedSecrets }

    # Store orphaned items for pagination
    $orphanedItems = @()
    $orphanedSecrets | ForEach-Object {
        $orphanedItems += [PSCustomObject]@{
            Namespace = $_.metadata.namespace
            Type      = "🔑 Secret"
            Name      = $_.metadata.name
        }
    }

    # If nothing found, return early
    if ($orphanedItems.Count -eq 0) {
        Write-Host "🤖 ✅ No orphaned Secrets found." -ForegroundColor Green
        Read-Host "🤖 Press Enter to return to the menu"
        return
    }

    # Pagination Setup
    $totalItems = $orphanedItems.Count
    $currentPage = 0
    $totalPages = [math]::Ceiling($totalItems / $PageSize)

    do {
        Clear-Host
        # **Speech Bubble with Explanation**
        $msg = @(
            "🤖 Secrets store sensitive data such as API keys and credentials.",
            "",
            "📌 This check identifies Secrets that are NOT used by:",
            "   - Pods, Deployments, StatefulSets, DaemonSets.",
            "   - Ingress TLS, ServiceAccounts, and Custom Resources.",
            "",
            "⚠️ Unused Secrets may indicate outdated credentials or misconfigurations.",
            "",
            "⚠️ Total Orphaned Secrets Found: $($orphanedItems.Count)"
        )

        Write-SpeechBubble -msg $msg -color "Cyan" -icon "🤖" -lastColor "Red" -delay 50

        # Display current page
        $startIndex = $currentPage * $PageSize
        $endIndex = [math]::Min($startIndex + $PageSize, $totalItems)

        $tableData = $orphanedItems[$startIndex..($endIndex - 1)]
        if ($tableData) {
            $tableData | Format-Table Namespace, Type, Name -AutoSize
        }

        # Call the pagination function
        $newPage = Show-Pagination -currentPage $currentPage -totalPages $totalPages

        # Exit pagination if 'C' (Continue) was selected
        if ($newPage -eq -1) { break }
        
        $currentPage = $newPage

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

    Write-Host "`r🤖 ✅ Fetched $($roleBindings.Count) RoleBindings, $($clusterRoleBindings.Count) ClusterRoleBindings.`n" -ForegroundColor Green

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
        # **Speech Bubble with Explanation**
        $msg = @(
            "🤖 RBAC (Role-Based Access Control) defines who can do what in your cluster.",
            "",
            "📌 This check identifies:",
            "   - 🔍 Misconfigurations in RoleBindings & ClusterRoleBindings.",
            "   - ❌ Missing references to ServiceAccounts & Namespaces.",
            "   - 🔓 Overly permissive roles that may pose security risks.",
            "",
            "⚠️ Total RBAC Misconfigurations Detected: $totalBindings"
        )

        Write-SpeechBubble -msg $msg -color "Cyan" -icon "🤖" -lastColor "Red" -delay 50

        $startIndex = $currentPage * $PageSize
        $endIndex = [math]::Min($startIndex + $PageSize, $totalBindings)

        $tableData = $invalidRBAC[$startIndex..($endIndex - 1)]
        if ($tableData) {
            $tableData | Format-Table -AutoSize
        }

        # Call the pagination function
        $newPage = Show-Pagination -currentPage $currentPage -totalPages $totalPages

        # Exit pagination if 'C' (Continue) was selected
        if ($newPage -eq -1) { break }
        
        $currentPage = $newPage

    } while ($true)
}


function Show-ClusterSummary {
    Clear-Host
    Write-Host "`n[Cluster Summary]" -ForegroundColor Cyan

    # Retrieve Kubernetes Version
    Write-Host -NoNewline "`n🤖 Retrieving Cluster Information...             ⏳ Fetching..." -ForegroundColor Yellow
    $versionInfo = kubectl version -o json | ConvertFrom-Json
    $k8sVersion = if ($versionInfo.serverVersion.gitVersion) { $versionInfo.serverVersion.gitVersion } else { "Unknown" }
    $clusterName = (kubectl config current-context)
    Write-Host "`r🤖 Retrieving Cluster Information...             ✅ Done!      " -ForegroundColor Green

    # Print Cluster Information
    Write-Host "`nCluster Name " -NoNewline -ForegroundColor Green
    Write-Host "is " -NoNewline
    Write-Host "$clusterName" -ForegroundColor Yellow
    Write-Host "Kubernetes Version " -NoNewline -ForegroundColor Green
    Write-Host "is " -NoNewline
    Write-Host "$k8sVersion" -ForegroundColor Yellow
    kubectl cluster-info

    # Kubernetes Version Check
    Write-Host -NoNewline "`n🤖 Checking Kubernetes Version Compatibility...  ⏳ Fetching..." -ForegroundColor Yellow
    $versionCheck = Check-KubernetesVersion
    Write-Host "`r🤖 Checking Kubernetes Version Compatibility...  ✅ Done!       " -ForegroundColor Green
    Write-Host "`n$versionCheck"

    # Cluster Metrics
    Write-Host -NoNewline "`n🤖 Fetching Cluster Metrics...                    ⏳ Fetching..." -ForegroundColor Yellow
    $summary = Show-HeroMetrics
    Write-Host "`r🤖 Fetching Cluster Metrics...                   ✅ Done!       " -ForegroundColor Green
    Write-Host "`n$summary"

    # Log to report
    Write-ToReport "Cluster Name: $clusterName"
    Write-ToReport "Kubernetes Version: $k8sVersion"
    $info = kubectl cluster-info | Out-String
            Write-ToReport $info
    Write-ToReport "Compatibility Check: $versionCheck"
    Write-ToReport "`nMetrics: $summary"

    # Wait for user input and exit function
    Read-Host "`nPress Enter to return to the main menu"
}

$version = "v0.0.1"

function Invoke-KubeBuddy {
    Clear-Host
    $banner = @"
██╗  ██╗██╗   ██╗██████╗ ███████╗██████╗ ██╗   ██╗██████╗ ██████╗ ██╗   ██╗
██║ ██╔╝██║   ██║██╔══██╗██╔════╝██╔══██╗██║   ██║██╔══██╗██╔══██╗╚██╗ ██╔╝
█████╔╝ ██║   ██║██████╔╝█████╗  ██████╔╝██║   ██║██║  ██║██║  ██║ ╚████╔╝ 
██╔═██╗ ██║   ██║██╔══██╗██╔══╝  ██╔══██╗██║   ██║██║  ██║██║  ██║  ╚██╔╝  
██║  ██╗╚██████╔╝██████╔╝███████╗██████╔╝╚██████╔╝██████╔╝██████╔╝   ██║   
╚═╝  ╚═╝ ╚═════╝ ╚═════╝ ╚══════╝╚═════╝  ╚═════╝ ╚═════╝ ╚═════╝    ╚═╝   
"@

    # KubeBuddy ASCII Art
    Write-Host ""
    Write-Host -NoNewline $banner -ForegroundColor Cyan
    write-host "$version" -ForegroundColor Magenta
    Write-Host "-------------------------------------------------------------" -ForegroundColor DarkGray
    Write-Host "Your Kubernetes Assistant" -ForegroundColor Cyan
    Write-Host "-------------------------------------------------------------" -ForegroundColor DarkGray

    # Thinking animation
    Write-Host -NoNewline "`r🤖 Initializing KubeBuddy..." -ForegroundColor Yellow
    Start-Sleep -Seconds 2  
    Write-Host "`r✅ KubeBuddy is ready to assist you!  " -ForegroundColor Green


        $msg = @(
            "🤖 Hello, I'm KubeBuddy! Your friendly Kubernetes assistant.",
            "",
            "   - I can help you check node health, workload status, networking, storage, RBAC security, and more.",
            "  - Select an option from the menu below to begin!"
        )

        Write-SpeechBubble -msg $msg -color "Cyan" -icon "🤖" -lastColor "Green" -delay 50

        $firstRun = $true  # Flag to track first execution
        show-mainMenu
}

function show-mainMenu {
    do {
        if ($firstRun) {
            $firstRun = $false
        }
        else {
            Clear-Host
        }
        Write-Host "`n[🏠  Main Menu]" -ForegroundColor Cyan
        Write-Host "------------------------------------------" -ForegroundColor DarkGray

            # Main menu options
            $options = @(
                "[1]  Cluster Summary 📊"
                "[2]  Node Details 🖥️"
                "[3]  Namespace Management 📂"
                "[4]  Workload Management ⚙️"
                "[5]  Pod Management 🚀"
                "[6]  Kubernetes Jobs 🏢"
                "[7]  Service & Networking 🌐"
                "[8]  Storage Management 📦"
                "[9]  RBAC & Security 🔐"
                "[10] Generate Report"
                "[Q]  Exit ❌"
            )
    
            foreach ($option in $options) { Write-Host $option }
    
            # Get user choice
            $choice = Read-Host "`n🤖 Enter your choice"
            Clear-Host
    
            switch ($choice) {
                "1" { Show-ClusterSummary }
                "2" { Show-NodeMenu }
                "3" { Show-NamespaceMenu }
                "4" { Show-WorkloadMenu }
                "5" { Show-PodMenu }
                "6" { Show-JobsMenu }
                "7" { Show-ServiceMenu }
                "8" { Show-StorageMenu }
                "9" { Show-RBACMenu }
                "10" { Generate-FullReport }
                "Q" { Write-Host "👋 Goodbye! Have a great day! 🚀"; return }
                default { Write-Host "⚠️ Invalid choice. Please try again!" -ForegroundColor Red }
            }
    
        } while ($true)
}

function Show-WorkloadMenu {
    do {
        Clear-Host
        Write-Host "`n[⚙️  Workload Management]" -ForegroundColor Cyan
        Write-Host "------------------------------------------" -ForegroundColor DarkGray

        $options = @(
            "[1] Check DaemonSet Health 🛠️"
            "[2] Check Deployment Issues 🚀"
            "[3] Check StatefulSet Issues 🏗️"
            "[4] Check ReplicaSet Health 📈"
            "🔙  Back [B] | ❌ Exit [Q]"
        )

        foreach ($option in $options) { Write-Host $option }

        $choice = Read-Host "`n🤖 Enter your choice"
        Clear-Host

        switch ($choice) {
            "1" { Show-DaemonSetIssues }

            "2" {
                $msg = @(
                    "🤖 Deployment Issues Check is coming soon!",
                    "",
                    "   - This feature will identify failing or unhealthy Deployments, rollout failures, and unavailable pods.",
                    "   - Stay tuned! 🚀"
                )

                Write-SpeechBubble -msg $msg -color "Cyan" -icon "🤖" -lastColor "Cyan" -delay 50
                
                Read-Host "🤖 Press Enter to return to the menu"
            }

            "3" {
                $msg = @(
                    "🤖 StatefulSet Health Check is coming soon!",
                    "",
                    "   - This feature will analyze StatefulSets for failures, stuck rollouts, and missing pods.",
                    "   - Stay tuned for updates! 🏗️"
                )

                Write-SpeechBubble -msg $msg -color "Cyan" -icon "🤖" -lastColor "Cyan" -delay 50

                Read-Host "🤖 Press Enter to return to the menu"
            }

            "4" {
                $msg = @(
                    "🤖 ReplicaSet Health Check is coming soon!",
                    "",
                    "   - This feature will monitor ReplicaSets for pod mismatches, scaling issues, and failures.",
                    "   - Coming soon! 📈"
                )
                Write-SpeechBubble -msg $msg -color "Cyan" -icon "🤖" -lastColor "Cyan" -delay 50

                Read-Host "🤖 Press Enter to return to the menu"
            }

            "B" { return }
            "Q" { Write-Host "👋 Exiting KubeBuddy. Have a great day! 🚀"; exit }
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
                Show-NodeConditions
            }
            "2" { 
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
                    Write-Host -NoNewline "`r🤖 Fetching available namespaces...       ⏳ Fetching..." -ForegroundColor Yellow
                    Start-Sleep -Seconds 1  # Optional small delay for UX
                    
                    # Capture namespaces first
                    $namespaces = kubectl get namespaces --no-headers | ForEach-Object { $_.Split()[0] }
                    
                    # Clear previous line and print the list properly
                    Write-Host "`r🤖 Fetching available namespaces...       ✅ Done!" -ForegroundColor Green
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
                    Show-PodsWithHighRestarts -Namespace $Namespace
                }
                "2" { 
                    Show-LongRunningPods -Namespace $Namespace
                }
                "3" { 
                    Show-FailedPods -Namespace $Namespace
                }
                "4" { 
                    Show-PendingPods -Namespace $Namespace
                }
                "5" {
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
            "[2]  Show orphaned ConfigMaps"
            "[3]  Show orphaned Secrets"
            "🔙  Back [B] | ❌ Exit [Q]"
        )

        foreach ($option in $rbacOptions) { Write-Host $option }

        $rbacChoice = Read-Host "`n🤖 Enter your choice"
        Clear-Host

        switch ($rbacChoice) {
            "1" { 
                Check-RBACMisconfigurations 
            }
            "2" { 
                Check-OrphanedConfigMaps
            }
            "3" { 
                Check-OrphanedSecrets 
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
                Show-StuckJobs 
            }
            "2" { 
                Show-FailedJobs 
            }
            "B" { return }
            "Q" { Write-Host "👋 Exiting KubeBuddy. Have a great day! 🚀"; exit }
            default { Write-Host "⚠️ Invalid choice. Please try again!" -ForegroundColor Red }
        }

        Clear-Host

    } while ($true)
}
