# Define report file location (global scope)
$ReportFile = "$pwd/kubebuddy-report.txt"
$Global:MakeReport = $false  # Global flag to control report mode

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

function Generate-Report {
    $Global:MakeReport = $true
    Write-Host "Generating report... Please wait."
    
    # Clear existing report if any
    if (Test-Path $ReportFile) {
        Remove-Item $ReportFile -Force
    }
    
    Write-ToReport "--- Kubernetes Cluster Report ---"
    Write-ToReport "Timestamp: $(Get-Date)"
    Write-ToReport "---------------------------------"

    $cursorPos = ""
    # Run each check in report mode
    $cursorPos = $Host.UI.RawUI.CursorPosition
    Write-Host -NoNewline "🤖 Retrieving Cluster Summary...                 ⏳ Fetching..." -ForegroundColor Yellow
    Write-ToReport "`n[🌐 Cluster Summary]`n"
    Show-ClusterSummary
    $cursorEndPos = $Host.UI.RawUI.CursorPosition
    $Host.UI.RawUI.CursorPosition = $cursorPos
    Write-Host "🤖 Retrieving Cluster Summary...                 ✅ Done!      " -ForegroundColor Green

    $Host.UI.RawUI.CursorPosition = $cursorEndPos
    Write-Host ""
    $cursorPos = $Host.UI.RawUI.CursorPosition
    Write-Host -NoNewline "🤖 Retrieving Node Information...                ⏳ Fetching..." -ForegroundColor Yellow
    Show-NodeConditions
    Show-NodeResourceUsage
    $cursorEndPos = $Host.UI.RawUI.CursorPosition
    $Host.UI.RawUI.CursorPosition = $cursorPos
    Write-Host "🤖 Retrieving Node Information...                ✅ Done!      " -ForegroundColor Green
    
    $Host.UI.RawUI.CursorPosition = $cursorEndPos
    Write-Host ""
    $cursorPos = $Host.UI.RawUI.CursorPosition
    Write-Host -NoNewline "🤖 Retrieving Namespace Information...           ⏳ Fetching..." -ForegroundColor Yellow
    Show-EmptyNamespaces
    $cursorEndPos = $Host.UI.RawUI.CursorPosition
    $Host.UI.RawUI.CursorPosition = $cursorPos
    Write-Host "🤖 Retrieving Namespace Information...           ✅ Done!      " -ForegroundColor Green

    $Host.UI.RawUI.CursorPosition = $cursorEndPos
    Write-Host ""
    $cursorPos = $Host.UI.RawUI.CursorPosition
    Write-Host -NoNewline "🤖 Retrieving Workload Information...            ⏳ Fetching..." -ForegroundColor Yellow
    Show-DaemonSetIssues
    $cursorEndPos = $Host.UI.RawUI.CursorPosition
    $Host.UI.RawUI.CursorPosition = $cursorPos
    Write-Host "🤖 Retrieving Workload Information...            ✅ Done!      " -ForegroundColor Green

    $Host.UI.RawUI.CursorPosition = $cursorEndPos
    Write-Host ""
    $cursorPos = $Host.UI.RawUI.CursorPosition
    Write-Host -NoNewline "🤖 Retrieving Pod Information...                 ⏳ Fetching..." -ForegroundColor Yellow
    Show-PodsWithHighRestarts
    Show-LongRunningPods
    Show-FailedPods
    Show-PendingPods
    Show-CrashLoopBackOffPods
    $cursorEndPos = $Host.UI.RawUI.CursorPosition
    $Host.UI.RawUI.CursorPosition = $cursorPos
    Write-Host "🤖 Retrieving Pod Information...                 ✅ Done!      " -ForegroundColor Green

    $Host.UI.RawUI.CursorPosition = $cursorEndPos
    Write-Host ""
    $cursorPos = $Host.UI.RawUI.CursorPosition
    Write-Host -NoNewline "🤖 Retrieving Job Information...                 ⏳ Fetching..." -ForegroundColor Yellow
    Show-StuckJobs
    Show-FailedJobs
    $cursorEndPos = $Host.UI.RawUI.CursorPosition
    $Host.UI.RawUI.CursorPosition = $cursorPos
    Write-Host "🤖 Retrieving Job Information...                 ✅ Done!      " -ForegroundColor Green

    $Host.UI.RawUI.CursorPosition = $cursorEndPos
    Write-Host ""
    $cursorPos = $Host.UI.RawUI.CursorPosition
    Write-Host -NoNewline "🤖 Retrieving Service Information...             ⏳ Fetching..." -ForegroundColor Yellow
    Show-ServicesWithoutEndpoints
    $cursorEndPos = $Host.UI.RawUI.CursorPosition
    $Host.UI.RawUI.CursorPosition = $cursorPos
    Write-Host "🤖 Retrieving Service Information...              ✅ Done!      " -ForegroundColor Green

    $Host.UI.RawUI.CursorPosition = $cursorEndPos
    Write-Host ""
    $cursorPos = $Host.UI.RawUI.CursorPosition
    Write-Host -NoNewline "🤖 Retrieving Storage Information...              ⏳ Fetching..." -ForegroundColor Yellow
    Show-UnusedPVCs
    $cursorEndPos = $Host.UI.RawUI.CursorPosition
    $Host.UI.RawUI.CursorPosition = $cursorPos
    Write-Host "🤖 Retrieving Storage Information...              ✅ Done!      " -ForegroundColor Green

    $Host.UI.RawUI.CursorPosition = $cursorEndPos
    Write-Host ""
    $cursorPos = $Host.UI.RawUI.CursorPosition
    Write-Host -NoNewline "🤖 Retrieving Security Information...             ⏳ Fetching..." -ForegroundColor Yellow
    Check-RBACMisconfigurations
    Check-OrphanedConfigMaps
    Check-OrphanedSecrets
    $cursorEndPos = $Host.UI.RawUI.CursorPosition
    $Host.UI.RawUI.CursorPosition = $cursorPos
    Write-Host "🤖 Retrieving Security Information...             ✅ Done!      " -ForegroundColor Green

    $Host.UI.RawUI.CursorPosition = $cursorEndPos
    $Global:MakeReport = $false
    Write-Host "✅ Report generated: $ReportFile" -ForegroundColor Green

    Read-Host "Press Enter to return to the menu"
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
        [int]$PageSize = 10, # Number of nodes per page
        [switch]$html
    )

    if (-not $Global:MakeReport -and -not $Html) { Clear-Host }
    Write-Host "`n[🌍 Node Conditions]" -ForegroundColor Cyan
    Write-Host -NoNewline "`n🤖 Fetching Node Conditions..." -ForegroundColor Yellow

    # Fetch nodes
    $nodes = kubectl get nodes -o json | ConvertFrom-Json
    $totalNodes = $nodes.items.Count

    if ($totalNodes -eq 0) {
        Write-Host "`r🤖 ❌ No nodes found." -ForegroundColor Red
        if (-not $Global:MakeReport -and -not $Html) { Read-Host "🤖 Press Enter to return to the menu" }
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
# If the -Html switch is used, return an HTML table
if ($Html) {
    # Sort so that "❌ Not Ready" is at the top
    $sortedData = $allNodesData | Sort-Object {
        if ($_.Status -eq "❌ Not Ready") { 0 } else { 1 }
    }

    # Convert the sorted data to an HTML table
    $htmlTable = $sortedData |
        ConvertTo-Html -Fragment -Property Node, Status, Issues |
        Out-String

    # Insert a note about total not ready
    $htmlTable = "<p><strong>⚠️ Total Not Ready Nodes:</strong> $totalNotReadyNodes</p>" + $htmlTable

    # Return the HTML snippet (no ASCII output)
    return $htmlTable
}

    if ($Global:MakeReport) {
        Write-ToReport "`n[🌍 Node Conditions]"
        Write-ToReport "`n⚠️ Total Not Ready Nodes in the Cluster: $totalNotReadyNodes"
        Write-ToReport "-----------------------------------------------------------"
        
        # Sort nodes: Critical first, then Warning, then Normal
        $sortedNodes = $allNodesData | Sort-Object {
            if ($_.Status -eq "❌ Not Ready") { 1 }
            elseif ($_.Status -eq "⚠️ Unknown") { 2 }
            else { 3 }
        }
    
        # Format as a table and write to report
        $tableString = $sortedNodes | Format-Table -Property Node, Status, Issues -AutoSize | Out-String
        Write-ToReport $tableString
    
        return
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
        [int]$PageSize = 10,  # Number of nodes per page
        [switch]$Html    # If specified, return an HTML table (no ASCII pagination)
    )

    if (-not $Global:MakeReport -and -not $Html) { Clear-Host }
    Write-Host "`n[📊 Node Resource Usage]" -ForegroundColor Cyan
    if (-not $Global:MakeReport -and -not $Html) {
        Write-Host -NoNewline "`n🤖 Gathering Node Data & Resource Usage..." -ForegroundColor Yellow
    }

    # Get thresholds and node data
    $thresholds = Get-KubeBuddyThresholds
    $allocatableRaw = kubectl get nodes -o json | ConvertFrom-Json
    $nodeUsageRaw   = kubectl top nodes --no-headers

    $totalNodes = $allocatableRaw.items.Count

    if ($totalNodes -eq 0) {
        Write-Host "`r🤖 ❌ No nodes found in the cluster." -ForegroundColor Red
        if (-not $Global:MakeReport -and -not $Html) {
            Read-Host "🤖 Press Enter to return to the menu"
        }
        return
    }

    Write-Host "`r🤖 ✅ Nodes fetched. (Total: $totalNodes)" -ForegroundColor Green

    # Track total warnings across all nodes
    $totalWarnings = 0
    $allNodesData  = @()

    # Preprocess all nodes to count warnings
    foreach ($node in $allocatableRaw.items) {
        $nodeName       = $node.metadata.name
        $allocatableCPU = [int]($node.status.allocatable.cpu -replace "m", "")
        $allocatableMem = [math]::Round(([int]($node.status.allocatable.memory -replace "Ki", "")) / 1024)

        $nodeStats = $nodeUsageRaw | Where-Object { $_ -match "^$nodeName\s" }
        if ($nodeStats) {
            $values  = $nodeStats -split "\s+"
            $usedCPU = if ($values[1] -match "^\d+m?$") { [int]($values[1] -replace "m", "") } else { 0 }
            $usedMem = if ($values[3] -match "^\d+Mi?$") { [math]::Round([int]($values[3] -replace "Mi", "")) } else { 0 }

            $cpuUsagePercent = [math]::Round(($usedCPU / $allocatableCPU) * 100, 2)
            $memUsagePercent = [math]::Round(($usedMem / $allocatableMem) * 100, 2)

            # CPU alert
            $cpuAlert = if ($cpuUsagePercent -gt $thresholds.cpu_critical) { 
                "🔴 Critical"; $totalWarnings++
            }
            elseif ($cpuUsagePercent -gt $thresholds.cpu_warning) { 
                "🟡 Warning"; $totalWarnings++
            }
            else { 
                "✅ Normal" 
            }

            # Memory alert
            $memAlert = if ($memUsagePercent -gt $thresholds.mem_critical) {
                "🔴 Critical"; $totalWarnings++
            }
            elseif ($memUsagePercent -gt $thresholds.mem_warning) {
                "🟡 Warning"; $totalWarnings++
            }
            else {
                "✅ Normal"
            }

            # Disk usage check
            $diskUsagePercent = "<unknown>"
            $diskStatus       = "⚠️ Unknown"

            if ($values.Length -ge 5 -and $values[4] -match "^\d+%$") {
                $diskUsagePercent = [int]($values[4] -replace "%", "")
                $diskStatus = if ($diskUsagePercent -gt 80)      { "🔴 Critical"; $totalWarnings++ }
                              elseif ($diskUsagePercent -gt 60) { "🟡 Warning";  $totalWarnings++ }
                              else                               { "✅ Normal" }
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

    # If in report mode (MakeReport) or no HTML switch, do normal ASCII printing
    if ($Global:MakeReport -and -not $Html) {
        Write-ToReport "`n[📊 Node Resource Usage]"
        Write-ToReport "`n⚠️ Total Resource Warnings Across All Nodes: $totalWarnings"
        Write-ToReport "--------------------------------------------------------------------------"

        # Sort nodes: Crit first, then Warning/Unknown, then Normal
        $sortedNodes = $allNodesData | Sort-Object {
            if ($_.‘CPU Status’ -eq "🔴 Critical" -or $_.‘Mem Status’ -eq "🔴 Critical" -or $_.‘Disk Status’ -eq "⚠️ Unknown") { 1 }
            elseif ($_.‘CPU Status’ -eq "🟡 Warning" -or $_.‘Mem Status’ -eq "🟡 Warning" -or $_.‘Disk Status’ -eq "🟡 Warning") { 2 }
            else { 3 }
        }

        # ASCII table
        $tableString = $sortedNodes |
            Format-Table -Property Node, "CPU Status", "CPU %", "CPU Used", "CPU Total", "Mem Status",
                                  "Mem %", "Mem Used", "Mem Total", "Disk %", "Disk Status" -AutoSize |
            Out-String

        Write-ToReport $tableString
        return
    }

    # If the -Html switch is specified, return an HTML table
    if ($Html) {
        # Sort the data the same way: critical -> warning -> normal
        $sortedHtmlData = $allNodesData | Sort-Object {
            if ($_.‘CPU Status’ -eq "🔴 Critical" -or $_.‘Mem Status’ -eq "🔴 Critical" -or $_.‘Disk Status’ -eq "⚠️ Unknown") { 1 }
            elseif ($_.‘CPU Status’ -eq "🟡 Warning" -or $_.‘Mem Status’ -eq "🟡 Warning" -or $_.‘Disk Status’ -eq "🟡 Warning") { 2 }
            else { 3 }
        }

        # Convert to a real HTML table
        # We'll show columns in a certain order, e.g.: Node, CPU Status, CPU %, CPU Used, CPU Total, ...
        $columns = "Node","CPU Status","CPU %","CPU Used","CPU Total","Mem Status","Mem %","Mem Used","Mem Total","Disk %","Disk Status"

        $htmlTable = $sortedHtmlData |
            ConvertTo-Html -Fragment -Property $columns -PreContent "<h2>Node Resource Usage</h2>" |
            Out-String

        # Insert a note about total warnings
        $htmlTable = "<p><strong>⚠️ Total Resource Warnings Across All Nodes:</strong> $totalWarnings</p>" + $htmlTable

        return $htmlTable
    }

    # Otherwise, do console pagination
    # (If not in MakeReport mode and no HTML switch)
    $currentPage = 0
    $totalPages  = [math]::Ceiling($totalNodes / $PageSize)

    do {
        Clear-Host
        Write-Host "`n[📊 Node Resource Usage - Page $($currentPage + 1) of $totalPages]" -ForegroundColor Cyan

        $msg = @(
            "🤖 Nodes are assessed for CPU, memory, and disk usage. Alerts indicate high resource utilization.",
            "",
            "📌 If CPU or memory usage is high, check workloads consuming excessive resources and optimize them.",
            "📌 If disk usage is critical, consider adding storage capacity or cleaning up unused data.",
            "",
            "⚠️ Total Resource Warnings Across All Nodes: $totalWarnings"
        )
        Write-SpeechBubble -msg $msg -color "Cyan" -icon "🤖" -lastColor "Red" -delay 50

        # Pagination
        $startIndex = $currentPage * $PageSize
        $endIndex   = [math]::Min($startIndex + $PageSize, $totalNodes)

        $tableData  = $allNodesData[$startIndex..($endIndex - 1)]
        if ($tableData) {
            $tableData | Format-Table -Property Node, "CPU %", "CPU Used", "CPU Total",
                                      "CPU Status", "Mem %", "Mem Used", "Mem Total",
                                      "Mem Status", "Disk %", "Disk Status" -AutoSize
        }

        $newPage = Show-Pagination -currentPage $currentPage -totalPages $totalPages
        if ($newPage -eq -1) { break }
        $currentPage = $newPage

    } while ($true)
}

function Show-PodsWithHighRestarts {
    param(
        [string]$Namespace = "",
        [int]$PageSize = 10,  # Number of pods per page
        [switch]$Html       # If specified, return an HTML table rather than ASCII output
    )

    if (-not $Global:MakeReport -and -not $Html) { Clear-Host }
    Write-Host "`n[🔁 Pods with High Restarts]" -ForegroundColor Cyan
    if (-not $Global:MakeReport -and -not $Html) {
        Write-Host -NoNewline "`n🤖 Fetching Pod Restart Data..." -ForegroundColor Yellow
    }

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
        if ($Global:MakeReport -and -not $Html) {
            Write-ToReport "`n[🔁 Pods with High Restarts]`n"
            Write-ToReport "❌ Error retrieving pod data: $_"
        }
        if (-not $Global:MakeReport -and -not $Html) {
            Read-Host "🤖 Press Enter to return to the menu"
        }
        return
    }

    # Filter pods with high restart counts
    $filteredPods = @()

    foreach ($pod in $restartPods.items) {
        $ns         = $pod.metadata.namespace
        $podName    = $pod.metadata.name
        $deployment = if ($pod.metadata.ownerReferences) { 
            $pod.metadata.ownerReferences[0].name 
        } else { 
            "N/A" 
        }

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
        if ($Global:MakeReport -and -not $Html) {
            Write-ToReport "`n[🔁 Pods with High Restarts]`n"
            Write-ToReport "✅ No pods with excessive restarts detected."
        }
        if (-not $Global:MakeReport -and -not $Html) {
            Read-Host "🤖 Press Enter to return to the menu"
        }
        if ($Html) { return "<p><strong>✅ No pods with excessive restarts detected.</strong></p>" }
        return
    }

    Write-Host "`r🤖 ✅ High-restart pods fetched. ($totalPods detected)" -ForegroundColor Green

    # If -Html is specified, return an HTML table
    if ($Html) {
        # You can sort if desired, e.g. by Restarts descending:
        $sortedData = $filteredPods | Sort-Object -Property Restarts -Descending

        # Convert to a real HTML table
        # We specify columns in the order we want them to appear
        $columns = "Namespace","Pod","Deployment","Restarts","Status"

        $htmlTable = $sortedData |
            ConvertTo-Html -Fragment -Property $columns |
            Out-String

        # Insert a note about total
        $htmlTable = "<p><strong>⚠️ Total High-Restart Pods:</strong> $totalPods</p>" + $htmlTable

        return $htmlTable
    }

    # If in report mode but NOT using -Html, do the original ASCII approach
    if ($Global:MakeReport) {
        Write-ToReport "`n[🔁 Pods with High Restarts]`n"
        Write-ToReport "⚠️ Total High-Restart Pods: $totalPods"
        Write-ToReport "----------------------------------------------"
        $tableString = $filteredPods |
            Format-Table Namespace, Pod, Deployment, Restarts, Status -AutoSize |
            Out-String
        Write-ToReport $tableString
        return
    }

    # Otherwise, console pagination
    $currentPage = 0
    $totalPages = [math]::Ceiling($totalPods / $PageSize)

    do {
        Clear-Host
        Write-Host "`n[🔁 Pods with High Restarts - Page $($currentPage + 1) of $totalPages]" -ForegroundColor Cyan

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

        # Pagination
        $newPage = Show-Pagination -currentPage $currentPage -totalPages $totalPages
        if ($newPage -eq -1) { break }
        
        $currentPage = $newPage
    } while ($true)
}

function Show-LongRunningPods {
    param(
        [string]$Namespace = "",
        [int]$PageSize = 10,  # Number of pods per page
        [switch]$Html        # If specified, return an HTML table
    )

    if (-not $Global:MakeReport -and -not $Html) { Clear-Host }
    Write-Host "`n[⏳ Long Running Pods]" -ForegroundColor Cyan
    if (-not $Global:MakeReport -and -not $Html) {
        Write-Host -NoNewline "`n🤖 Fetching Pod Data..." -ForegroundColor Yellow
    }

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
        if ($Global:MakeReport -and -not $Html) {
            Write-ToReport "`n[⏳ Long Running Pods]`n"
            Write-ToReport "❌ Error retrieving pod data: $_"
        }
        if (-not $Global:MakeReport -and -not $Html) {
            Read-Host "🤖 Press Enter to return to the menu"
        }
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
            $ageDays   = ((Get-Date) - $startTime).Days

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
        if ($Global:MakeReport -and -not $Html) {
            Write-ToReport "`n[⏳ Long Running Pods]`n"
            Write-ToReport "✅ No long-running pods detected."
        }
        if (-not $Global:MakeReport -and -not $Html) {
            Read-Host "🤖 Press Enter to return to the menu"
        }
        if ($Html) { return "<p><strong>✅ No long-running pods detected.</strong></p>" }
        return
    }

    Write-Host "`r🤖 ✅ Long-running pods fetched. ($totalPods detected)" -ForegroundColor Green

    # If -Html is specified, return an HTML table
    if ($Html) {
        # Sort by Age_Days descending if you prefer older pods first
        $sortedData = $filteredPods | Sort-Object -Property Age_Days -Descending

        # Convert to HTML table
        $htmlTable = $sortedData |
            ConvertTo-Html -Fragment -Property "Namespace","Pod","Age_Days","Status" |
            Out-String

        # Insert note about total
        $htmlTable = "<p><strong>⚠️ Total Long-Running Pods:</strong> $totalPods</p>" + $htmlTable

        return $htmlTable
    }

    # If in report mode (no -Html), do original ASCII
    if ($Global:MakeReport) {
        Write-ToReport "`n[⏳ Long Running Pods]`n"
        Write-ToReport "⚠️ Total Long-Running Pods: $totalPods"
        Write-ToReport "----------------------------------------------"

        $tableString = $filteredPods |
            Format-Table Namespace, Pod, Age_Days, Status -AutoSize |
            Out-String
        Write-ToReport $tableString
        return
    }

    # Otherwise, do console pagination
    $currentPage = 0
    $totalPages  = [math]::Ceiling($totalPods / $PageSize)

    do {
        Clear-Host
        Write-Host "`n[⏳ Long Running Pods - Page $($currentPage + 1) of $totalPages]" -ForegroundColor Cyan

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
        $endIndex   = [math]::Min($startIndex + $PageSize, $totalPods)

        $tableData  = $filteredPods[$startIndex..($endIndex - 1)]
        if ($tableData) {
            $tableData | Format-Table Namespace, Pod, Age_Days, Status -AutoSize
        }

        $newPage = Show-Pagination -currentPage $currentPage -totalPages $totalPages
        if ($newPage -eq -1) { break }
        
        $currentPage = $newPage
    } while ($true)
}


function Show-DaemonSetIssues {
    param(
        [int]$PageSize = 10,  # Number of daemonsets per page
        [switch]$Html   # If specified, return an HTML table instead of ASCII/pagination
    )

    if (-not $Global:MakeReport -and -not $Html) { Clear-Host }
    Write-Host "`n[🔄 DaemonSets Not Fully Running]" -ForegroundColor Cyan
    Write-Host -NoNewline "`n🤖 Fetching DaemonSet Data..." -ForegroundColor Yellow

    try {
        $daemonsets = kubectl get daemonsets --all-namespaces -o json 2>&1 | ConvertFrom-Json
    }
    catch {
        Write-Host "`r🤖 ❌ Error retrieving DaemonSet data: $_" -ForegroundColor Red
        if ($Global:MakeReport -and -not $Html) {
            Write-ToReport "`n[🔄 DaemonSets Not Fully Running]`n"
            Write-ToReport "❌ Error retrieving DaemonSet data: $_"
        }
        if (-not $Global:MakeReport -and -not $Html) {
            Read-Host "🤖 Press Enter to return to the menu"
        }
        return
    }

    # Filter only DaemonSets with issues
    $filteredDaemonSets = @()
    foreach ($ds in $daemonsets.items) {
        $ns      = $ds.metadata.namespace
        $name    = $ds.metadata.name
        $desired = $ds.status.desiredNumberScheduled
        $current = $ds.status.currentNumberScheduled
        $running = $ds.status.numberReady

        # Only include DaemonSets that are NOT fully running
        if ($desired -ne $running) {
            $filteredDaemonSets += [PSCustomObject]@{
                Namespace   = $ns
                DaemonSet   = $name
                Desired     = $desired
                Running     = $running
                Scheduled   = $current
                Status      = "⚠️ Incomplete"
            }
        }
    }

    $totalDaemonSets = $filteredDaemonSets.Count

    if ($totalDaemonSets -eq 0) {
        Write-Host "`r🤖 ✅ All DaemonSets are fully running." -ForegroundColor Green
        if ($Global:MakeReport -and -not $Html) {
            Write-ToReport "`n[🔄 DaemonSets Not Fully Running]`n"
            Write-ToReport "✅ All DaemonSets are fully running."
        }
        if (-not $Global:MakeReport -and -not $Html) {
            Read-Host "🤖 Press Enter to return to the menu"
        }
        if ($Html) { return "<p><strong>✅ All DaemonSets are fully running.</strong></p>" }
        return
    }

    Write-Host "`r🤖 ✅ DaemonSets fetched. ($totalDaemonSets DaemonSets with issues detected)" -ForegroundColor Green

    # If -Html is specified, return a real HTML table
    if ($Html) {
        # Convert to sorted data if desired. For example,
        # you might want to sort by namespace, or keep as-is:
        $sortedData = $filteredDaemonSets | Sort-Object Namespace

        # Build HTML table
        $htmlTable = $sortedData |
            ConvertTo-Html -Fragment -Property "Namespace","DaemonSet","Desired","Running","Scheduled","Status" |
            Out-String

        # Insert note about total DS with issues
        $htmlTable = "<p><strong>⚠️ Total DaemonSets with Issues:</strong> $totalDaemonSets</p>" + $htmlTable

        return $htmlTable
    }

    # If in report mode (but NOT using -Html), do the original ASCII approach
    if ($Global:MakeReport) {
        Write-ToReport "`n[🔄 DaemonSets Not Fully Running]`n"
        Write-ToReport "⚠️ Total DaemonSets with Issues: $totalDaemonSets"
        Write-ToReport "----------------------------------------------------"
        $tableString = $filteredDaemonSets |
            Format-Table Namespace, DaemonSet, Desired, Running, Scheduled, Status -AutoSize |
            Out-String
        Write-ToReport $tableString
        return
    }

    # Otherwise, do console pagination (no -Html, no MakeReport)
    $currentPage = 0
    $totalPages  = [math]::Ceiling($totalDaemonSets / $PageSize)

    do {
        Clear-Host
        Write-Host "`n[🔄 DaemonSets Not Fully Running - Page $($currentPage + 1) of $totalPages]" -ForegroundColor Cyan

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
        $endIndex   = [math]::Min($startIndex + $PageSize, $totalDaemonSets)

        $tableData  = $filteredDaemonSets[$startIndex..($endIndex - 1)]
        if ($tableData) {
            $tableData | Format-Table Namespace, DaemonSet, Desired, Running, Scheduled, Status -AutoSize
        }

        $newPage = Show-Pagination -currentPage $currentPage -totalPages $totalPages
        if ($newPage -eq -1) { break }
        
        $currentPage = $newPage
    } while ($true)
}

function Show-FailedPods {
    param(
        [string]$Namespace = "",
        [int]$PageSize = 10,  # Number of pods per page
        [switch]$Html       # If specified, return an HTML table
    )

    if (-not $Global:MakeReport -and -not $Html) { Clear-Host }
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
        if ($Global:MakeReport -and -not $Html) {
            Write-ToReport "`n[🔴 Failed Pods]`n"
            Write-ToReport "❌ Error retrieving pod data: $_"
        }
        if (-not $Global:MakeReport -and -not $Html) {
            Read-Host "🤖 Press Enter to return to the menu"
        }
        return
    }

    $totalPods = $failedPods.Count

    if ($totalPods -eq 0) {
        Write-Host "`r🤖 ✅ No failed pods found." -ForegroundColor Green
        if ($Global:MakeReport -and -not $Html) {
            Write-ToReport "`n[🔴 Failed Pods]`n"
            Write-ToReport "✅ No failed pods found."
        }
        if (-not $Global:MakeReport -and -not $Html) {
            Read-Host "🤖 Press Enter to return to the menu"
        }
        if ($Html) {
            return "<p><strong>✅ No failed pods found.</strong></p>"
        }
        return
    }

    Write-Host "`r🤖 ✅ Failed Pods fetched. ($totalPods detected)" -ForegroundColor Green

    # If -Html is specified, build and return an HTML table
    if ($Html) {
        # Convert the array of failedPods into a PSCustomObject array
        $tableData = foreach ($pod in $failedPods) {
            [PSCustomObject]@{
                Namespace = $pod.metadata.namespace
                Pod       = $pod.metadata.name
                Reason    = $pod.status.reason
                Message   = ($pod.status.message -replace "`n", " ") # remove newlines
            }
        }

        # Convert to an HTML table
        $htmlTable = $tableData |
            ConvertTo-Html -Fragment -Property Namespace, Pod, Reason, Message -PreContent "<h2>Failed Pods</h2>" |
            Out-String

        # Insert note about total
        $htmlTable = "<p><strong>⚠️ Total Failed Pods:</strong> $totalPods</p>" + $htmlTable
        return $htmlTable
    }

    # If in report mode (but NOT using -Html), do original ASCII approach
    if ($Global:MakeReport) {
        Write-ToReport "`n[🔴 Failed Pods]`n"
        Write-ToReport "⚠️ Total Failed Pods: $totalPods"
        Write-ToReport "----------------------------------------------------"

        # Prepare table data
        $tableData = @()
        foreach ($pod in $failedPods) {
            $ns = $pod.metadata.namespace
            $podName = $pod.metadata.name
            $reason = $pod.status.reason
            $message = $pod.status.message -replace "`n", " "

            $tableData += [PSCustomObject]@{
                Namespace = $ns
                Pod       = $podName
                Reason    = $reason
                Message   = $message
            }
        }

        # Format and write to report
        $tableString = $tableData |
            Format-Table Namespace, Pod, Reason, Message -AutoSize |
            Out-String

        Write-ToReport $tableString
        return
    }

    # Otherwise, console pagination
    $currentPage = 0
    $totalPages  = [math]::Ceiling($totalPods / $PageSize)

    do {
        Clear-Host
        Write-Host "`n[🔴 Failed Pods - Page $($currentPage + 1) of $totalPages]" -ForegroundColor Cyan

        # Explanation bubble
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

        # Pagination chunk
        $startIndex = $currentPage * $PageSize
        $endIndex   = [math]::Min($startIndex + $PageSize, $totalPods)

        $tableData  = @()
        for ($i = $startIndex; $i -lt $endIndex; $i++) {
            $pod = $failedPods[$i]
            $ns = $pod.metadata.namespace
            $podName = $pod.metadata.name
            $reason = $pod.status.reason
            $message = $pod.status.message -replace "`n", " "

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

        $newPage = Show-Pagination -currentPage $currentPage -totalPages $totalPages
        if ($newPage -eq -1) { break }
        $currentPage = $newPage

    } while ($true)
}


function Show-EmptyNamespaces {
    param(
        [int]$PageSize = 10,  # Number of namespaces per page
        [switch]$Html        # If specified, return an HTML table
    )

    if (-not $Global:MakeReport -and -not $Html) { Clear-Host }
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

        if ($Global:MakeReport -and -not $Html) {
            Write-ToReport "`n[📂 Empty Namespaces]`n"
            Write-ToReport "✅ No empty namespaces found."
        }

        # If not in report mode or HTML mode, prompt to continue
        if (-not $Global:MakeReport -and -not $Html) {
            Read-Host "🤖 Press Enter to return to the menu"
        }
        if ($Html) {
            return "<p><strong>✅ No empty namespaces found.</strong></p>"
        }
        return
    }

    Write-Host "`r🤖 ✅ Namespaces fetched. ($totalNamespaces empty namespaces detected)" -ForegroundColor Green

    # ----- HTML SWITCH -----
    if ($Html) {
        # Build an HTML table. Each row => one namespace
        # Convert the array into PSCustomObjects first
        $namespacesData = $emptyNamespaces | ForEach-Object {
            [PSCustomObject]@{
                "Namespace" = $_
            }
        }

        # Convert to HTML
        $htmlTable = $namespacesData |
            ConvertTo-Html -Fragment -Property "Namespace" |
            Out-String

        # Insert a note about total empty
        $htmlTable = "<p><strong>⚠️ Total Empty Namespaces:</strong> $totalNamespaces</p>" + $htmlTable

        return $htmlTable
    }
    # ----- END HTML SWITCH -----

    # ----- If in report mode, but no -Html switch, do original ascii printing -----
    if ($Global:MakeReport) {
        Write-ToReport "`n[📂 Empty Namespaces]`n"
        Write-ToReport "⚠️ Total Empty Namespaces: $totalNamespaces"
        Write-ToReport "---------------------------------"
        foreach ($namespace in $emptyNamespaces) {
            Write-ToReport "$namespace"
        }
        return
    }

    # ----- Otherwise, do console pagination as before -----
    $currentPage = 0
    $totalPages = [math]::Ceiling($totalNamespaces / $PageSize)

    do {
        Clear-Host
        Write-Host "`n[📂 Empty Namespaces - Page $($currentPage + 1) of $totalPages]" -ForegroundColor Cyan

        # Speech bubble
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
        $endIndex   = [math]::Min($startIndex + $PageSize, $totalNamespaces)

        $tableData  = @()
        for ($i = $startIndex; $i -lt $endIndex; $i++) {
            $namespace = $emptyNamespaces[$i]
            $tableData += [PSCustomObject]@{ "Namespace" = $namespace }
        }

        if ($tableData) {
            $tableData | Format-Table Namespace -AutoSize
        }

        # Pagination
        $newPage = Show-Pagination -currentPage $currentPage -totalPages $totalPages
        if ($newPage -eq -1) { break }
        
        $currentPage = $newPage
    } while ($true)
}

function Show-PendingPods {
    param(
        [string]$Namespace = "",
        [int]$PageSize = 10,
        [switch]$Html   # If specified, return an HTML table
    )

    if (-not $Global:MakeReport -and -not $Html) { Clear-Host }
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
        if ($Global:MakeReport -and -not $Html) {
            Write-ToReport "`n[⏳ Pending Pods]`n"
            Write-ToReport "❌ Error retrieving pod data: $_"
        }
        if (-not $Global:MakeReport -and -not $Html) {
            Read-Host "🤖 Press Enter to return to the menu"
        }
        return
    }

    # Filter Pending pods
    $pendingPods = $pendingPods | Where-Object { $_.status.phase -eq "Pending" }
    $totalPods   = $pendingPods.Count

    if ($totalPods -eq 0) {
        Write-Host "`r🤖 ✅ No pending pods found." -ForegroundColor Green
        if ($Global:MakeReport -and -not $Html) {
            Write-ToReport "`n[⏳ Pending Pods]`n"
            Write-ToReport "✅ No pending pods found."
        }
        if (-not $Global:MakeReport -and -not $Html) {
            Read-Host "🤖 Press Enter to return to the menu"
        }
        if ($Html) {
            return "<p><strong>✅ No pending pods found.</strong></p>"
        }
        return
    }

    Write-Host "`r🤖 ✅ Pods fetched. ($totalPods Pending pods detected)" -ForegroundColor Green

    # If -Html is specified, return an HTML table
    if ($Html) {
        # Build an array of PSCustomObjects for the table
        $tableData = foreach ($pod in $pendingPods) {
            $ns      = $pod.metadata.namespace
            $podName = $pod.metadata.name
            $reason  = if ($pod.status.conditions) { $pod.status.conditions[0].reason } else { "Unknown" }
            $message = if ($pod.status.conditions) {
                $pod.status.conditions[0].message -replace "`n", " "
            } else {
                "No details available"
            }

            [PSCustomObject]@{
                Namespace = $ns
                Pod       = $podName
                Reason    = $reason
                Message   = $message
            }
        }

        # Convert to HTML
        $htmlTable = $tableData |
            ConvertTo-Html -Fragment -Property Namespace, Pod, Reason, Message -PreContent "<h2>Pending Pods</h2>" |
            Out-String

        # Insert note about total
        $htmlTable = "<p><strong>⚠️ Total Pending Pods Found:</strong> $totalPods</p>" + $htmlTable
        return $htmlTable
    }

    # If in report mode (no -Html), do original ASCII approach
    if ($Global:MakeReport) {
        Write-ToReport "`n[⏳ Pending Pods]`n"
        Write-ToReport "⚠️ Total Pending Pods Found: $totalPods"
        Write-ToReport "----------------------------------------------------"

        # Prepare table data
        $tableData = @()
        foreach ($pod in $pendingPods) {
            $ns      = $pod.metadata.namespace
            $podName = $pod.metadata.name
            $reason  = if ($pod.status.conditions) { $pod.status.conditions[0].reason } else { "Unknown" }
            $message = if ($pod.status.conditions) {
                $pod.status.conditions[0].message -replace "`n", " "
            } else {
                "No details available"
            }

            $tableData += [PSCustomObject]@{
                Namespace = $ns
                Pod       = $podName
                Reason    = $reason
                Message   = $message
            }
        }

        # Format and write to report
        $tableString = $tableData |
            Format-Table Namespace, Pod, Reason, Message -AutoSize |
            Out-String

        Write-ToReport $tableString
        return
    }

    # Otherwise, console pagination
    $currentPage = 0
    $totalPages  = [math]::Ceiling($totalPods / $PageSize)

    do {
        Clear-Host
        Write-Host "`n[⏳ Pending Pods - Page $($currentPage + 1) of $totalPages]" -ForegroundColor Cyan

        # Speech Bubble
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
        Write-SpeechBubble -msg $msg -color "Cyan" -icon "🤖" -lastColor "Red" -delay 50

        # Display current page
        $startIndex = $currentPage * $PageSize
        $endIndex   = [math]::Min($startIndex + $PageSize, $totalPods)

        $tableData  = @()
        for ($i = $startIndex; $i -lt $endIndex; $i++) {
            $pod = $pendingPods[$i]
            $ns      = $pod.metadata.namespace
            $podName = $pod.metadata.name
            $reason  = if ($pod.status.conditions) { $pod.status.conditions[0].reason } else { "Unknown" }
            $message = if ($pod.status.conditions) {
                $pod.status.conditions[0].message -replace "`n", " "
            } else {
                "No details available"
            }

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

        $newPage = Show-Pagination -currentPage $currentPage -totalPages $totalPages
        if ($newPage -eq -1) { break }
        
        $currentPage = $newPage
    } while ($true)
}


function Show-CrashLoopBackOffPods {
    param(
        [string]$Namespace = "",
        [int]$PageSize = 10,
        [switch]$Html   # If specified, return an HTML table
    )

    if (-not $Global:MakeReport -and -not $Html) { Clear-Host }
    Write-Host "`n[🔴 CrashLoopBackOff Pods]" -ForegroundColor Cyan
    Write-Host -NoNewline "`n🤖 Fetching Pod Data..." -ForegroundColor Yellow

    try {
        if ($Namespace -ne "") {
            $crashPods = kubectl get pods -n $Namespace -o json 2>&1 | ConvertFrom-Json |
                Select-Object -ExpandProperty items
        } 
        else {
            $crashPods = kubectl get pods --all-namespaces -o json 2>&1 | ConvertFrom-Json |
                Select-Object -ExpandProperty items
        }
    }
    catch {
        Write-Host "`r🤖 ❌ Error retrieving pod data: $_" -ForegroundColor Red
        if ($Global:MakeReport -and -not $Html) {
            Write-ToReport "`n[🔴 CrashLoopBackOff Pods]`n"
            Write-ToReport "❌ Error retrieving pod data: $_"
        }
        if (-not $Global:MakeReport -and -not $Html) {
            Read-Host "🤖 Press Enter to return to the menu"
        }
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
        if ($Global:MakeReport -and -not $Html) {
            Write-ToReport "`n[🔴 CrashLoopBackOff Pods]`n"
            Write-ToReport "✅ No CrashLoopBackOff pods found."
        }
        if (-not $Global:MakeReport -and -not $Html) {
            Read-Host "🤖 Press Enter to return to the menu"
        }
        if ($Html) { 
            return "<p><strong>✅ No CrashLoopBackOff pods found.</strong></p>"
        }
        return
    }

    Write-Host "`r🤖 ✅ Pods fetched. ($totalPods CrashLoopBackOff pods detected)" -ForegroundColor Green

    # If -Html is specified, build and return an HTML table
    if ($Html) {
        # Create a PSCustomObject array for the final table
        $tableData = foreach ($pod in $crashPods) {
            [PSCustomObject]@{
                Namespace = $pod.metadata.namespace
                Pod       = $pod.metadata.name
                Restarts  = $pod.status.containerStatuses.restartCount
                Status    = "🔴 CrashLoopBackOff"
            }
        }

        # Convert to HTML
        $htmlTable = $tableData |
            ConvertTo-Html -Fragment -Property Namespace, Pod, Restarts, Status |
            Out-String

        # Insert a note about total
        $htmlTable = "<p><strong>⚠️ Total CrashLoopBackOff Pods Found:</strong> $totalPods</p>" + $htmlTable
        return $htmlTable
    }

    # If in report mode (no -Html), do original ASCII approach
    if ($Global:MakeReport) {
        Write-ToReport "`n[🔴 CrashLoopBackOff Pods]`n"
        Write-ToReport "⚠️ Total CrashLoopBackOff Pods Found: $totalPods"
        Write-ToReport "----------------------------------------------------"

        $tableData = @()
        foreach ($pod in $crashPods) {
            $ns       = $pod.metadata.namespace
            $podName  = $pod.metadata.name
            $restarts = $pod.status.containerStatuses.restartCount

            $tableData += [PSCustomObject]@{
                Namespace = $ns
                Pod       = $podName
                Restarts  = $restarts
                Status    = "🔴 CrashLoopBackOff"
            }
        }

        $tableString = $tableData |
            Format-Table Namespace, Pod, Restarts, Status -AutoSize |
            Out-String

        Write-ToReport $tableString
        return
    }

    # Otherwise, do console pagination
    $currentPage = 0
    $totalPages  = [math]::Ceiling($totalPods / $PageSize)

    do {
        Clear-Host
        Write-Host "`n[🔴 CrashLoopBackOff Pods - Page $($currentPage + 1) of $totalPages]" -ForegroundColor Cyan

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
        $endIndex   = [math]::Min($startIndex + $PageSize, $totalPods)

        $tableData  = @()
        for ($i = $startIndex; $i -lt $endIndex; $i++) {
            $pod       = $crashPods[$i]
            $ns        = $pod.metadata.namespace
            $podName   = $pod.metadata.name
            $restarts  = $pod.status.containerStatuses.restartCount

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

        $newPage = Show-Pagination -currentPage $currentPage -totalPages $totalPages
        if ($newPage -eq -1) { break }
        $currentPage = $newPage

    } while ($true)
}

function Show-ServicesWithoutEndpoints {
    param(
        [int]$PageSize = 10,  # Number of services per page
        [switch]$Html         # If specified, return an HTML table
    )

    if (-not $Global:MakeReport -and -not $Html) { Clear-Host }
    Write-Host "`n[🔍 Services Without Endpoints]" -ForegroundColor Cyan
    Write-Host -NoNewline "`n🤖 Fetching Service Data..." -ForegroundColor Yellow

    # Fetch all services
    $services = kubectl get services --all-namespaces -o json | ConvertFrom-Json | Select-Object -ExpandProperty items |
        Where-Object { $_.spec.type -ne "ExternalName" }  # Exclude ExternalName services

    if (-not $services) {
        Write-Host "`r🤖 ❌ Failed to fetch service data." -ForegroundColor Red
        if ($Global:MakeReport -and -not $Html) {
            Write-ToReport "`n[🔍 Services Without Endpoints]`n"
            Write-ToReport "❌ Failed to fetch service data."
        }
        if (-not $Global:MakeReport -and -not $Html) {
            Read-Host "🤖 Press Enter to return to the menu"
        }
        return
    }

    Write-Host "`r🤖 ✅ Services fetched. (Total: $($services.Count))" -ForegroundColor Green
    Write-Host -NoNewline "`n🤖 Fetching Endpoint Data..." -ForegroundColor Yellow

    # Fetch endpoints
    $endpoints = kubectl get endpoints --all-namespaces -o json | ConvertFrom-Json | Select-Object -ExpandProperty items |
        Group-Object { $_.metadata.namespace + "/" + $_.metadata.name }

    if (-not $endpoints) {
        Write-Host "`r🤖 ❌ Failed to fetch endpoint data." -ForegroundColor Red
        if ($Global:MakeReport -and -not $Html) {
            Write-ToReport "`n[🔍 Services Without Endpoints]`n"
            Write-ToReport "❌ Failed to fetch endpoint data."
        }
        if (-not $Global:MakeReport -and -not $Html) {
            Read-Host "🤖 Press Enter to return to the menu"
        }
        return
    }

    Write-Host "`r🤖 ✅ Endpoints fetched. (Total: $($endpoints.Count))" -ForegroundColor Green
    Write-Host "`n🤖 Analyzing Services..." -ForegroundColor Yellow

    # Convert endpoints to a lookup table
    $endpointsLookup = @{}
    foreach ($ep in $endpoints) {
        $endpointsLookup[$ep.Name] = $true
    }

    # Filter services without endpoints
    $servicesWithoutEndpoints = $services | Where-Object {
        -not $endpointsLookup.ContainsKey($_.metadata.namespace + "/" + $_.metadata.name)
    }

    $totalServices = $servicesWithoutEndpoints.Count

    if ($totalServices -eq 0) {
        Write-Host "`r🤖 ✅ All services have endpoints." -ForegroundColor Green
        if ($Global:MakeReport -and -not $Html) {
            Write-ToReport "`n[🔍 Services Without Endpoints]`n"
            Write-ToReport "✅ All services have endpoints."
        }
        if (-not $Global:MakeReport -and -not $Html) {
            Read-Host "🤖 Press Enter to return to the menu"
        }
        if ($Html) { return "<p>✅ All services have endpoints.</p>" }
        return
    }

    Write-Host "`r🤖 ✅ Service analysis complete. ($totalServices services without endpoints detected)" -ForegroundColor Green

    # If -Html, return an HTML table
    if ($Html) {
        $tableData = foreach ($svc in $servicesWithoutEndpoints) {
            [PSCustomObject]@{
                Namespace = $svc.metadata.namespace
                Service   = $svc.metadata.name
                Type      = $svc.spec.type
                Status    = "⚠️ No Endpoints"
            }
        }

        $htmlTable = $tableData |
            ConvertTo-Html -Fragment -Property Namespace, Service, Type, Status -PreContent "<h2>Services Without Endpoints</h2>" |
            Out-String

        # Insert note about total
        $htmlTable = "<p><strong>⚠️ Total Services Without Endpoints:</strong> $totalServices</p>" + $htmlTable
        return $htmlTable
    }

    # If in report mode but not HTML
    if ($Global:MakeReport) {
        Write-ToReport "`n[🔍 Services Without Endpoints]`n"
        Write-ToReport "⚠️ Total Services Without Endpoints: $totalServices" 
        $tableData = @()
        foreach ($svc in $servicesWithoutEndpoints) {
            $tableData += [PSCustomObject]@{
                Namespace = $svc.metadata.namespace
                Service   = $svc.metadata.name
                Type      = $svc.spec.type
                Status    = "⚠️ No Endpoints"
            }
        }
        $tableString = $tableData | Format-Table Namespace, Service, Type, Status -AutoSize | Out-String
        Write-ToReport $tableString
        return
    }

    # Pagination approach
    $currentPage = 0
    $totalPages  = [math]::Ceiling($totalServices / $PageSize)

    do {
        Clear-Host
        Write-Host "`n[🔍 Services Without Endpoints - Page $($currentPage + 1) of $totalPages]" -ForegroundColor Cyan

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

        Write-SpeechBubble -msg $msg -color "Cyan" -icon "🤖" -lastColor "Red" -delay 50

        $startIndex = $currentPage * $PageSize
        $endIndex   = [math]::Min($startIndex + $PageSize, $totalServices)

        $tableData  = @()
        for ($i = $startIndex; $i -lt $endIndex; $i++) {
            $svc = $servicesWithoutEndpoints[$i]
            [PSCustomObject]@{
                Namespace = $svc.metadata.namespace
                Service   = $svc.metadata.name
                Type      = $svc.spec.type
                Status    = "⚠️"
            } | ForEach-Object { $tableData += $_ }
        }

        if ($tableData) {
            $tableData | Format-Table Namespace, Service, Type, Status -AutoSize
        }

        $newPage = Show-Pagination -currentPage $currentPage -totalPages $totalPages
        if ($newPage -eq -1) { break }
        $currentPage = $newPage
    } while ($true)
}

function Show-UnusedPVCs {
    param(
        [int]$PageSize = 10,
        [switch]$Html  # If specified, return an HTML table
    )

    if (-not $Global:MakeReport -and -not $Html) { Clear-Host }
    Write-Host "`n[💾 Unused Persistent Volume Claims]" -ForegroundColor Cyan
    Write-Host -NoNewline "`n🤖 Fetching PVC Data..." -ForegroundColor Yellow

    # Capture raw kubectl output
    $pvcsRaw = kubectl get pvc --all-namespaces -o json 2>&1 | Out-String

    # "No resources found" before JSON parse
    if ($pvcsRaw -match "No resources found") {
        Write-Host "`r🤖 ✅ No PVCs found in the cluster." -ForegroundColor Green
        if ($Global:MakeReport -and -not $Html) {
            Write-ToReport "`n[💾 Unused Persistent Volume Claims]`n"
            Write-ToReport "✅ No PVCs found in the cluster."
        }
        if (-not $Global:MakeReport -and -not $Html) {
            Read-Host "🤖 Press Enter to return to the menu"
        }
        if ($Html) { return "<p><strong>✅ No PVCs found in the cluster.</strong></p>" }
        return
    }

    # Convert JSON
    try {
        $pvcsJson = $pvcsRaw | ConvertFrom-Json
        $pvcs = if ($pvcsJson.PSObject.Properties['items']) { $pvcsJson.items } else { @() }
    }
    catch {
        Write-Host "`r🤖 ❌ Failed to parse JSON from kubectl output." -ForegroundColor Red
        if ($Global:MakeReport -and -not $Html) {
            Write-ToReport "`n[💾 Unused Persistent Volume Claims]`n"
            Write-ToReport "❌ Failed to parse JSON from kubectl output."
        }
        if (-not $Global:MakeReport -and -not $Html) {
            Read-Host "🤖 Press Enter to return to the menu"
        }
        if ($Html) { return "<p><strong>❌ Failed to parse JSON from kubectl output.</strong></p>" }
        return
    }

    # Ensure array
    if ($pvcs -isnot [System.Array]) { $pvcs = @($pvcs) }

    # Check if PVCs exist
    if ($pvcs.Count -eq 0) {
        Write-Host "`r🤖 ✅ No unused PVCs found." -ForegroundColor Green
        if ($Global:MakeReport -and -not $Html) {
            Write-ToReport "`n[💾 Unused Persistent Volume Claims]`n"
            Write-ToReport "✅ No unused PVCs found."
        }
        if (-not $Global:MakeReport -and -not $Html) {
            Read-Host "🤖 Press Enter to return to the menu"
        }
        if ($Html) { return "<p><strong>✅ No unused PVCs found.</strong></p>" }
        return
    }

    Write-Host "`r🤖 ✅ PVCs fetched. (Total: $($pvcs.Count))" -ForegroundColor Green
    Write-Host -NoNewline "`n🤖 Fetching Pod Data..." -ForegroundColor Yellow

    # Fetch all Pods
    $pods = kubectl get pods --all-namespaces -o json | ConvertFrom-Json | Select-Object -ExpandProperty items
    if (-not $pods) {
        Write-Host "`r🤖 ❌ Failed to fetch Pod data." -ForegroundColor Red
        if ($Global:MakeReport -and -not $Html) {
            Write-ToReport "`n[💾 Unused Persistent Volume Claims]`n"
            Write-ToReport "❌ Failed to fetch Pod data."
        }
        if (-not $Global:MakeReport -and -not $Html) {
            Read-Host "🤖 Press Enter to return to the menu"
        }
        if ($Html) { return "<p><strong>❌ Failed to fetch Pod data.</strong></p>" }
        return
    }

    Write-Host "`r🤖 ✅ Pods fetched. (Total: $($pods.Count))" -ForegroundColor Green

    Write-Host "`n🤖 Analyzing PVC usage..." -ForegroundColor Yellow

    # Gather attached PVCs from pod volumes
    $attachedPVCs = $pods |
        ForEach-Object { $_.spec.volumes | Where-Object { $_.persistentVolumeClaim } } |
        Select-Object -ExpandProperty persistentVolumeClaim

    # Filter out any that appear in attachedPVCs
    $unusedPVCs = $pvcs | Where-Object { $_.metadata.name -notin $attachedPVCs.name }
    $totalPVCs  = $unusedPVCs.Count

    if ($totalPVCs -eq 0) {
        Write-Host "`r🤖 ✅ No unused PVCs found." -ForegroundColor Green
        if ($Global:MakeReport -and -not $Html) {
            Write-ToReport "`n[💾 Unused Persistent Volume Claims]`n"
            Write-ToReport "✅ No unused PVCs found."
        }
        if (-not $Global:MakeReport -and -not $Html) {
            Read-Host "🤖 Press Enter to return to the menu"
        }
        if ($Html) { return "<p><strong>✅ No unused PVCs found.</strong></p>" }
        return
    }

    Write-Host "`r🤖 ✅ PVC usage analyzed. ($totalPVCs unused PVCs detected)" -ForegroundColor Green

    # If -Html, return an HTML table
    if ($Html) {
        $tableData = foreach ($pvc in $unusedPVCs) {
            [PSCustomObject]@{
                Namespace = $pvc.metadata.namespace
                PVC       = $pvc.metadata.name
                Storage   = $pvc.spec.resources.requests.storage
            }
        }

        $htmlTable = $tableData |
            ConvertTo-Html -Fragment -Property Namespace, PVC, Storage -PreContent "<h2>Unused Persistent Volume Claims</h2>" |
            Out-String

        # Insert note about total
        $htmlTable = "<p><strong>⚠️ Total Unused PVCs Found:</strong> $totalPVCs</p>" + $htmlTable
        return $htmlTable
    }

    # If in report mode (no -Html)
    if ($Global:MakeReport) {
        Write-ToReport "`n[💾 Unused Persistent Volume Claims]`n"
        Write-ToReport "⚠️ Total Unused PVCs Found: $totalPVCs"
        Write-ToReport "-------------------------------------------------"

        $tableData = @()
        foreach ($pvc in $unusedPVCs) {
            $tableData += [PSCustomObject]@{
                Namespace = $pvc.metadata.namespace
                PVC       = $pvc.metadata.name
                Storage   = $pvc.spec.resources.requests.storage
            }
        }

        $tableString = $tableData | Format-Table Namespace, PVC, Storage -AutoSize | Out-String
        Write-ToReport $tableString
        return
    }

    # Otherwise, pagination
    $currentPage = 0
    $totalPages  = [math]::Ceiling($totalPVCs / $PageSize)

    do {
        Clear-Host
        Write-Host "`n[💾 Unused Persistent Volume Claims - Page $($currentPage + 1) of $totalPages]" -ForegroundColor Cyan

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
        Write-SpeechBubble -msg $msg -color "Cyan" -icon "🤖" -lastColor "Red" -delay 50

        $startIndex = $currentPage * $PageSize
        $endIndex   = [math]::Min($startIndex + $PageSize, $totalPVCs)

        $tableData  = @()
        for ($i = $startIndex; $i -lt $endIndex; $i++) {
            $pvc = $unusedPVCs[$i]
            $tableData += [PSCustomObject]@{
                Namespace = $pvc.metadata.namespace
                PVC       = $pvc.metadata.name
                Storage   = $pvc.spec.resources.requests.storage
            }
        }

        if ($tableData) {
            $tableData | Format-Table Namespace, PVC, Storage -AutoSize
        }

        $newPage = Show-Pagination -currentPage $currentPage -totalPages $totalPages
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
        [int]$PageSize = 10,
        [switch]$Html
    )

    if (-not $Global:MakeReport -and -not $Html) { Clear-Host }
    Write-Host "`n[⏳ Stuck Kubernetes Jobs]" -ForegroundColor Cyan
    Write-Host -NoNewline "`n🤖 Fetching Job Data..." -ForegroundColor Yellow

    # Fetch jobs
    $kubectlOutput = kubectl get jobs --all-namespaces -o json 2>&1 | Out-String

    # Check for errors
    if ($kubectlOutput -match "error|not found|forbidden") {
        Write-Host "`r🤖 ❌ Error retrieving job data: $kubectlOutput" -ForegroundColor Red
        if ($Global:MakeReport -and -not $Html) {
            Write-ToReport "`n[⏳ Stuck Kubernetes Jobs]`n"
            Write-ToReport "❌ Error retrieving job data: $kubectlOutput"
        }
        if (-not $Global:MakeReport -and -not $Html) {
            Read-Host "🤖 Press Enter to return to the menu"
        }
        if ($Html) { return "<p><strong>❌ Error retrieving job data: $kubectlOutput</strong></p>" }
        return
    }

    if ($kubectlOutput -match "^{") {
        $jobs = $kubectlOutput | ConvertFrom-Json | Select-Object -ExpandProperty items
    }
    else {
        Write-Host "`r🤖 ❌ Unexpected response from kubectl. No valid JSON received." -ForegroundColor Red
        if ($Global:MakeReport -and -not $Html) {
            Write-ToReport "`n[⏳ Stuck Kubernetes Jobs]`n"
            Write-ToReport "❌ Unexpected response from kubectl. No valid JSON received."
        }
        if (-not $Global:MakeReport -and -not $Html) {
            Read-Host "🤖 Press Enter to return to the menu"
        }
        if ($Html) { return "<p><strong>❌ Unexpected response from kubectl. No valid JSON received.</strong></p>" }
        return
    }

    if (-not $jobs -or $jobs.Count -eq 0) {
        Write-Host "`r🤖 ✅ No jobs found in the cluster." -ForegroundColor Green
        if ($Global:MakeReport -and -not $Html) {
            Write-ToReport "`n[⏳ Stuck Kubernetes Jobs]`n"
            Write-ToReport "✅ No jobs found in the cluster."
        }
        if (-not $Global:MakeReport -and -not $Html) {
            Read-Host "🤖 Press Enter to return to the menu"
        }
        if ($Html) { return "<p><strong>✅ No jobs found in the cluster.</strong></p>" }
        return
    }

    Write-Host "`r🤖 ✅ Jobs fetched. (Total: $($jobs.Count))" -ForegroundColor Green
    Write-Host -NoNewline "`n🤖 Analyzing Stuck Jobs..." -ForegroundColor Yellow

    # Filter stuck jobs
    $stuckJobs = $jobs | Where-Object { 
        (-not $_.status.conditions -or $_.status.conditions.type -notcontains "Complete") -and # Not marked complete
        $_.status.PSObject.Properties['active'] -and $_.status.active -gt 0 -and               # Has active pods
        (-not $_.status.PSObject.Properties['ready'] -or $_.status.ready -eq 0) -and          # No ready pods
        (-not $_.status.PSObject.Properties['succeeded'] -or $_.status.succeeded -eq 0) -and  # Not succeeded
        (-not $_.status.PSObject.Properties['failed'] -or $_.status.failed -eq 0) -and        # Not failed
        $_.status.PSObject.Properties['startTime'] -and                                       # Has a startTime
        ((New-TimeSpan -Start $_.status.startTime -End (Get-Date)).TotalHours -gt $StuckThresholdHours)
    }

    if (-not $stuckJobs -or $stuckJobs.Count -eq 0) {
        Write-Host "`r🤖 ✅ No stuck jobs found." -ForegroundColor Green
        if ($Global:MakeReport -and -not $Html) {
            Write-ToReport "`n[⏳ Stuck Kubernetes Jobs]`n"
            Write-ToReport "✅ No stuck jobs found."
        }
        if (-not $Global:MakeReport -and -not $Html) {
            Read-Host "🤖 Press Enter to return to the menu"
        }
        if ($Html) { return "<p><strong>✅ No stuck jobs found.</strong></p>" }
        return
    }

    Write-Host "`r🤖 ✅ Job analysis complete. ($($stuckJobs.Count) stuck jobs detected)" -ForegroundColor Green

    # If -Html is specified, return an HTML table
    if ($Html) {
        # Build PSCustomObject array
        $tableData = foreach ($job in $stuckJobs) {
            $ns       = $job.metadata.namespace
            $jobName  = $job.metadata.name
            $ageHours = ((New-TimeSpan -Start $job.status.startTime -End (Get-Date)).TotalHours) -as [int]

            [PSCustomObject]@{
                Namespace = $ns
                Job       = $jobName
                Age_Hours = $ageHours
                Status    = "🟡 Stuck"
            }
        }

        # Convert to HTML
        $htmlTable = $tableData |
            ConvertTo-Html -Fragment -Property Namespace, Job, Age_Hours, Status |
            Out-String

        # Insert note about total
        $htmlTable = "<p><strong>⚠️ Total Stuck Jobs Found:</strong> $($stuckJobs.Count)</p>" + $htmlTable
        return $htmlTable
    }

    # If in report mode (no -Html), do original ASCII approach
    if ($Global:MakeReport) {
        Write-ToReport "`n[⏳ Stuck Kubernetes Jobs]`n"
        Write-ToReport "⚠️ Total Stuck Jobs Found: $($stuckJobs.Count)"
        Write-ToReport "---------------------------------------------"

        $tableData = @()
        foreach ($job in $stuckJobs) {
            $ns       = $job.metadata.namespace
            $jobName  = $job.metadata.name
            $ageHours = ((New-TimeSpan -Start $job.status.startTime -End (Get-Date)).TotalHours) -as [int]
            
            $tableData += [PSCustomObject]@{
                Namespace = $ns
                Job       = $jobName
                Age_Hours = $ageHours
                Status    = "🟡 Stuck"
            }
        }

        $tableString = $tableData | Format-Table Namespace, Job, Age_Hours, Status -AutoSize | Out-String
        Write-ToReport $tableString
        return
    }

    # Otherwise, console pagination
    $totalJobs   = $stuckJobs.Count
    $currentPage = 0
    $totalPages  = [math]::Ceiling($totalJobs / $PageSize)

    do {
        Clear-Host
        Write-Host "`n[⏳ Stuck Kubernetes Jobs - Page $($currentPage + 1) of $totalPages]" -ForegroundColor Cyan

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

        $startIndex = $currentPage * $PageSize
        $endIndex   = [math]::Min($startIndex + $PageSize, $totalJobs)

        $tableData  = @()
        for ($i = $startIndex; $i -lt $endIndex; $i++) {
            $job = $stuckJobs[$i]
            $tableData += [PSCustomObject]@{
                Namespace = $job.metadata.namespace
                Job       = $job.metadata.name
                Age_Hours = ((New-TimeSpan -Start $job.status.startTime -End (Get-Date)).TotalHours) -as [int]
                Status    = "🟡 Stuck"
            }
        }

        if ($tableData) {
            $tableData | Format-Table Namespace, Job, Age_Hours, Status -AutoSize
        }

        $newPage = Show-Pagination -currentPage $currentPage -totalPages $totalPages
        if ($newPage -eq -1) { break }
        $currentPage = $newPage

    } while ($true)
}


function Show-FailedJobs {
    param(
        [int]$StuckThresholdHours = 2,
        [int]$PageSize = 10,
        [switch]$Html
    )

    if (-not $Global:MakeReport -and -not $Html) { Clear-Host }
    Write-Host "`n[🔴 Failed Kubernetes Jobs]" -ForegroundColor Cyan
    Write-Host -NoNewline "`n🤖 Fetching Job Data..." -ForegroundColor Yellow

    # Fetch jobs
    $kubectlOutput = kubectl get jobs --all-namespaces -o json 2>&1 | Out-String

    # Check for errors
    if ($kubectlOutput -match "error|not found|forbidden") {
        Write-Host "`r🤖 ❌ Error retrieving job data: $kubectlOutput" -ForegroundColor Red
        if ($Global:MakeReport -and -not $Html) {
            Write-ToReport "`n[🔴 Failed Kubernetes Jobs]`n"
            Write-ToReport "❌ Error retrieving job data: $kubectlOutput"
        }
        if (-not $Global:MakeReport -and -not $Html) {
            Read-Host "🤖 Press Enter to return to the menu"
        }
        if ($Html) { return "<p><strong>❌ Error retrieving job data: $kubectlOutput</strong></p>" }
        return
    }

    if ($kubectlOutput -match "^{") {
        $jobs = $kubectlOutput | ConvertFrom-Json | Select-Object -ExpandProperty items
    }
    else {
        Write-Host "`r🤖 ❌ Unexpected response from kubectl. No valid JSON received." -ForegroundColor Red
        if ($Global:MakeReport -and -not $Html) {
            Write-ToReport "`n[🔴 Failed Kubernetes Jobs]`n"
            Write-ToReport "❌ Unexpected response from kubectl. No valid JSON received."
        }
        if (-not $Global:MakeReport -and -not $Html) {
            Read-Host "🤖 Press Enter to return to the menu"
        }
        if ($Html) { return "<p><strong>❌ Unexpected response from kubectl. No valid JSON received.</strong></p>" }
        return
    }

    if (-not $jobs -or $jobs.Count -eq 0) {
        Write-Host "`r🤖 ✅ No jobs found in the cluster." -ForegroundColor Green
        if ($Global:MakeReport -and -not $Html) {
            Write-ToReport "`n[🔴 Failed Kubernetes Jobs]`n"
            Write-ToReport "✅ No jobs found in the cluster."
        }
        if (-not $Global:MakeReport -and -not $Html) {
            Read-Host "🤖 Press Enter to return to the menu"
        }
        if ($Html) { return "<p><strong>✅ No failed jobs found.</strong></p>" }
        return
    }

    Write-Host "`r🤖 ✅ Jobs fetched. (Total: $($jobs.Count))" -ForegroundColor Green
    Write-Host -NoNewline "`n🤖 Analyzing Failed Jobs..." -ForegroundColor Yellow

    # Filter failed jobs
    $failedJobs = $jobs | Where-Object { 
        $_.status.PSObject.Properties['failed'] -and $_.status.failed -gt 0 -and # Job has failed
        (-not $_.status.PSObject.Properties['succeeded'] -or $_.status.succeeded -eq 0) -and # Not succeeded
        $_.status.PSObject.Properties['startTime'] -and
        ((New-TimeSpan -Start $_.status.startTime -End (Get-Date)).TotalHours -gt $StuckThresholdHours)
    }

    if (-not $failedJobs -or $failedJobs.Count -eq 0) {
        Write-Host "`r🤖 ✅ No failed jobs found." -ForegroundColor Green
        if ($Global:MakeReport -and -not $Html) {
            Write-ToReport "`n[🔴 Failed Kubernetes Jobs]`n"
            Write-ToReport "✅ No failed jobs found."
        }
        if (-not $Global:MakeReport -and -not $Html) {
            Read-Host "🤖 Press Enter to return to the menu"
        }
        if ($Html) { return "<p><strong>✅ No failed jobs found.</strong></p>" }
        return
    }

    Write-Host "`r🤖 ✅ Job analysis complete. ($($failedJobs.Count) failed jobs detected)" -ForegroundColor Green

    # If -Html is specified, return an HTML table
    if ($Html) {
        $tableData = foreach ($job in $failedJobs) {
            [PSCustomObject]@{
                Namespace = $job.metadata.namespace
                Job       = $job.metadata.name
                Age_Hours = ((New-TimeSpan -Start $job.status.startTime -End (Get-Date)).TotalHours) -as [int]
                Failures  = if ($job.status.PSObject.Properties['failed']) { $job.status.failed } else { "Unknown" }
                Status    = "🔴 Failed"
            }
        }

        # Convert to HTML
        $htmlTable = $tableData |
            ConvertTo-Html -Fragment -Property Namespace, Job, Age_Hours, Failures, Status -PreContent "<h2>Failed Kubernetes Jobs</h2>" |
            Out-String

        # Insert note about total
        $htmlTable = "<p><strong>⚠️ Total Failed Jobs Found:</strong> $($failedJobs.Count)</p>" + $htmlTable
        return $htmlTable
    }

    # If in report mode (no -Html), do original ASCII approach
    if ($Global:MakeReport) {
        Write-ToReport "`n[🔴 Failed Kubernetes Jobs]`n"
        Write-ToReport "⚠️ Total Failed Jobs Found: $($failedJobs.Count)"
        Write-ToReport "---------------------------------------------"

        $tableData = @()
        foreach ($job in $failedJobs) {
            $ns       = $job.metadata.namespace
            $jobName  = $job.metadata.name
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

        $tableString = $tableData | Format-Table Namespace, Job, Age_Hours, Failures, Status -AutoSize | Out-String
        Write-ToReport $tableString
        return
    }

    # Otherwise, console pagination
    $totalJobs   = $failedJobs.Count
    $currentPage = 0
    $totalPages  = [math]::Ceiling($totalJobs / $PageSize)

    do {
        Clear-Host
        Write-Host "`n[🔴 Failed Kubernetes Jobs - Page $($currentPage + 1) of $totalPages]" -ForegroundColor Cyan

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

        $startIndex = $currentPage * $totalJobs / $PageSize
        $startIndex = $currentPage * $PageSize
        $endIndex   = [math]::Min($startIndex + $PageSize, $totalJobs)

        $tableData = @()
        for ($i = $startIndex; $i -lt $endIndex; $i++) {
            $job = $failedJobs[$i]
            $tableData += [PSCustomObject]@{
                Namespace = $job.metadata.namespace
                Job       = $job.metadata.name
                Age_Hours = ((New-TimeSpan -Start $job.status.startTime -End (Get-Date)).TotalHours) -as [int]
                Failures  = if ($job.status.PSObject.Properties['failed']) { $job.status.failed } else { "Unknown" }
                Status    = "🔴 Failed"
            }
        }

        if ($tableData) {
            $tableData | Format-Table Namespace, Job, Age_Hours, Failures, Status -AutoSize
        }

        $newPage = Show-Pagination -currentPage $currentPage -totalPages $totalPages
        if ($newPage -eq -1) { break }
        $currentPage = $newPage

    } while ($true)
}

function Check-OrphanedConfigMaps {
    param(
        [int]$PageSize = 10,
        [switch]$Html
    )

    if (-not $Global:MakeReport -and -not $Html) { Clear-Host }
    Write-Host "`n[📜 Orphaned ConfigMaps]" -ForegroundColor Cyan
    Write-Host -NoNewline "`n🤖 Fetching ConfigMaps..." -ForegroundColor Yellow

    # Exclude Helm-managed ConfigMaps
    $excludedConfigMapPatterns = @("^sh\.helm\.release\.v1\.")

    $configMaps = kubectl get configmaps --all-namespaces -o json | ConvertFrom-Json | Select-Object -ExpandProperty items |
        Where-Object { $_.metadata.name -notmatch ($excludedConfigMapPatterns -join "|") }

    Write-Host "`r🤖 ✅ ConfigMaps fetched. ($($configMaps.Count) total)" -ForegroundColor Green

    # Fetch workloads & used ConfigMaps
    Write-Host -NoNewline "`n🤖 Checking ConfigMap usage..." -ForegroundColor Yellow
    $usedConfigMaps = @()

    # Pods
    $pods = kubectl get pods --all-namespaces -o json | ConvertFrom-Json | Select-Object -ExpandProperty items

    # Various workloads
    $workloads = @(kubectl get deployments --all-namespaces -o json | ConvertFrom-Json | Select-Object -ExpandProperty items) +
                 @(kubectl get statefulsets --all-namespaces -o json | ConvertFrom-Json | Select-Object -ExpandProperty items) +
                 @(kubectl get daemonsets --all-namespaces -o json | ConvertFrom-Json | Select-Object -ExpandProperty items) +
                 @(kubectl get cronjobs --all-namespaces -o json | ConvertFrom-Json | Select-Object -ExpandProperty items) +
                 @(kubectl get jobs --all-namespaces -o json | ConvertFrom-Json | Select-Object -ExpandProperty items) +
                 @(kubectl get replicasets --all-namespaces -o json | ConvertFrom-Json | Select-Object -ExpandProperty items)

    $ingresses = kubectl get ingress --all-namespaces -o json | ConvertFrom-Json | Select-Object -ExpandProperty items
    $services  = kubectl get services --all-namespaces -o json | ConvertFrom-Json | Select-Object -ExpandProperty items

    # Scan Pods + workloads for configmap references
    foreach ($resource in $pods + $workloads) {
        $usedConfigMaps += $resource.spec.volumes | Where-Object { $_.configMap } | Select-Object -ExpandProperty configMap | Select-Object -ExpandProperty name

        foreach ($container in $resource.spec.containers) {
            if ($container.env) {
                $usedConfigMaps += $container.env | Where-Object { $_.valueFrom.configMapKeyRef } |
                                   Select-Object -ExpandProperty valueFrom |
                                   Select-Object -ExpandProperty configMapKeyRef |
                                   Select-Object -ExpandProperty name
            }
            if ($container.envFrom) {
                $usedConfigMaps += $container.envFrom | Where-Object { $_.configMapRef } |
                                   Select-Object -ExpandProperty configMapRef |
                                   Select-Object -ExpandProperty name
            }
        }
    }

    # Ingress & Service annotations
    $usedConfigMaps += $ingresses | ForEach-Object { $_.metadata.annotations.Values -match "configMap" }
    $usedConfigMaps += $services  | ForEach-Object { $_.metadata.annotations.Values -match "configMap" }

    # Custom Resources
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

    # Clean up references
    $usedConfigMaps = $usedConfigMaps | Where-Object { $_ } | Sort-Object -Unique
    Write-Host "`r✅ ConfigMap usage checked." -ForegroundColor Green

    # Orphaned = not in usedConfigMaps
    $orphanedConfigMaps = $configMaps | Where-Object { $_.metadata.name -notin $usedConfigMaps }

    # Build an array for pagination / output
    $orphanedItems = @()
    foreach ($ocm in $orphanedConfigMaps) {
        $orphanedItems += [PSCustomObject]@{
            Namespace = $ocm.metadata.namespace
            Type      = "📜 ConfigMap"
            Name      = $ocm.metadata.name
        }
    }

    if ($orphanedItems.Count -eq 0) {
        Write-Host "🤖 ✅ No orphaned ConfigMaps found." -ForegroundColor Green
        if ($Global:MakeReport -and -not $Html) {
            Write-ToReport "`n[📜 Orphaned ConfigMaps]`n"
            Write-ToReport "✅ No orphaned ConfigMaps found."
        }
        if (-not $Global:MakeReport -and -not $Html) {
            Read-Host "🤖 Press Enter to return to the menu"
        }
        return
    }

    # If -Html is specified, create & return an HTML table
    if ($Html) {
        $htmlTable = $orphanedItems |
            ConvertTo-Html -Fragment -Property Namespace,Type,Name -PreContent "<h2>Orphaned ConfigMaps</h2>" |
            Out-String

        $htmlTable = "<p><strong>⚠️ Total Orphaned ConfigMaps Found:</strong> $($orphanedItems.Count)</p>" + $htmlTable
        return $htmlTable
    }

    # If in report mode, ASCII
    if ($Global:MakeReport) {
        Write-ToReport "`n[📜 Orphaned ConfigMaps]`n"
        Write-ToReport "⚠️ Total Orphaned ConfigMaps Found: $($orphanedItems.Count)"

        $tableString = $orphanedItems | Format-Table Namespace, Type, Name -AutoSize | Out-String
        Write-ToReport $tableString
        return
    }

    # Pagination
    $totalItems   = $orphanedItems.Count
    $currentPage  = 0
    $totalPages   = [math]::Ceiling($totalItems / $PageSize)

    do {
        Clear-Host
        Write-Host "`n[📜 Orphaned ConfigMaps - Page $($currentPage + 1) of $totalPages]" -ForegroundColor Cyan

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

        $startIndex = $currentPage * $PageSize
        $endIndex   = [math]::Min($startIndex + $PageSize, $totalItems)

        $tableData  = $orphanedItems[$startIndex..($endIndex - 1)]
        if ($tableData) {
            $tableData | Format-Table Namespace,Type,Name -AutoSize
        }

        $newPage = Show-Pagination -currentPage $currentPage -totalPages $totalPages
        if ($newPage -eq -1) { break }
        $currentPage = $newPage
    } while ($true)
}

function Check-OrphanedSecrets {
    param(
        [int]$PageSize = 10,
        [switch]$Html
    )

    if (-not $Global:MakeReport -and -not $Html) { Clear-Host }
    Write-Host "`n[🔑 Orphaned Secrets]" -ForegroundColor Cyan
    Write-Host -NoNewline "`n🤖 Fetching Secrets..." -ForegroundColor Yellow

    # Exclude system-managed secrets
    $excludedSecretPatterns = @("^sh\.helm\.release\.v1\.", "^bootstrap-token-", "^default-token-", "^kube-root-ca.crt$", "^kubernetes.io/service-account-token")

    $secrets = kubectl get secrets --all-namespaces -o json | ConvertFrom-Json | Select-Object -ExpandProperty items |
        Where-Object { $_.metadata.name -notmatch ($excludedSecretPatterns -join "|") }

    Write-Host "`r🤖 ✅ Secrets fetched. ($($secrets.Count) total)" -ForegroundColor Green

    Write-Host -NoNewline "`n🤖 Checking Secret usage..." -ForegroundColor Yellow
    $usedSecrets = @()

    # Pods and various workloads
    $pods      = kubectl get pods --all-namespaces -o json | ConvertFrom-Json | Select-Object -ExpandProperty items
    $workloads = @(kubectl get deployments --all-namespaces -o json | ConvertFrom-Json | Select-Object -ExpandProperty items) +
                 @(kubectl get statefulsets --all-namespaces -o json | ConvertFrom-Json | Select-Object -ExpandProperty items) +
                 @(kubectl get daemonsets --all-namespaces -o json | ConvertFrom-Json | Select-Object -ExpandProperty items)

    $ingresses        = kubectl get ingress --all-namespaces -o json | ConvertFrom-Json | Select-Object -ExpandProperty items
    $serviceAccounts  = kubectl get serviceaccounts --all-namespaces -o json | ConvertFrom-Json | Select-Object -ExpandProperty items

    foreach ($resource in $pods + $workloads) {
        $usedSecrets += $resource.spec.volumes | Where-Object { $_.secret } |
                        Select-Object -ExpandProperty secret |
                        Select-Object -ExpandProperty secretName

        foreach ($container in $resource.spec.containers) {
            if ($container.env) {
                $usedSecrets += $container.env | Where-Object { $_.valueFrom.secretKeyRef } |
                                Select-Object -ExpandProperty valueFrom |
                                Select-Object -ExpandProperty secretKeyRef |
                                Select-Object -ExpandProperty name
            }
        }
    }

    # Ingress TLS
    $usedSecrets += $ingresses | ForEach-Object { $_.spec.tls | Select-Object -ExpandProperty secretName }
    # ServiceAccounts
    $usedSecrets += $serviceAccounts | ForEach-Object { $_.secrets | Select-Object -ExpandProperty name }

    Write-Host "`r🤖 ✅ Secret usage checked." -ForegroundColor Green

    # Check custom resources
    Write-Host "`n🤖 Checking Custom Resources for Secret usage..." -ForegroundColor Yellow
    $customResources = kubectl api-resources --verbs=list --namespaced -o name | Where-Object { $_ }
    foreach ($cr in $customResources) {
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

    # Orphaned Secrets
    $orphanedSecrets = $secrets | Where-Object { $_.metadata.name -notin $usedSecrets }

    $orphanedItems = @()
    foreach ($sec in $orphanedSecrets) {
        $orphanedItems += [PSCustomObject]@{
            Namespace = $sec.metadata.namespace
            Type      = "🔑 Secret"
            Name      = $sec.metadata.name
        }
    }

    if ($orphanedItems.Count -eq 0) {
        Write-Host "🤖 ✅ No orphaned Secrets found." -ForegroundColor Green
        if ($Global:MakeReport -and -not $Html) {
            Write-ToReport "`n[🔑 Orphaned Secrets]`n"
            Write-ToReport "✅ No orphaned Secrets found."
        }
        if (-not $Global:MakeReport -and -not $Html) {
            Read-Host "🤖 Press Enter to return to the menu"
        }
        return
    }

    # If -Html
    if ($Html) {
        $htmlTable = $orphanedItems |
            ConvertTo-Html -Fragment -Property Namespace, Type, Name -PreContent "<h2>Orphaned Secrets</h2>" |
            Out-String

        $htmlTable = "<p><strong>⚠️ Total Orphaned Secrets Found:</strong> $($orphanedItems.Count)</p>" + $htmlTable
        return $htmlTable
    }

    # If in report mode
    if ($Global:MakeReport) {
        Write-ToReport "`n[🔑 Orphaned Secrets]`n"
        Write-ToReport "⚠️ Total Orphaned Secrets Found: $($orphanedItems.Count)"

        $tableString = $orphanedItems | Format-Table Namespace, Type, Name -AutoSize | Out-String
        Write-ToReport $tableString
        return
    }

    # Pagination
    $totalItems   = $orphanedItems.Count
    $currentPage  = 0
    $totalPages   = [math]::Ceiling($totalItems / $PageSize)

    do {
        Clear-Host
        Write-Host "`n[🔑 Orphaned Secrets - Page $($currentPage + 1) of $totalPages]" -ForegroundColor Cyan

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

        $startIndex = $currentPage * $PageSize
        $endIndex   = [math]::Min($startIndex + $PageSize, $totalItems)

        $tableData  = $orphanedItems[$startIndex..($endIndex - 1)]
        if ($tableData) {
            $tableData | Format-Table Namespace, Type, Name -AutoSize
        }

        $newPage = Show-Pagination -currentPage $currentPage -totalPages $totalPages
        if ($newPage -eq -1) { break }
        $currentPage = $newPage
    } while ($true)
}
function Check-RBACMisconfigurations {
    param(
        [int]$PageSize = 10,
        [switch]$Html
    )

    if (-not $Global:MakeReport -and -not $Html) { Clear-Host }
    Write-Host "`n[RBAC Misconfigurations]" -ForegroundColor Cyan

    # Fetch RoleBindings & ClusterRoleBindings
    Write-Host -NoNewline "`n🤖 Fetching RoleBindings & ClusterRoleBindings..." -ForegroundColor Yellow
    $roleBindings         = kubectl get rolebindings --all-namespaces -o json | ConvertFrom-Json | Select-Object -ExpandProperty items
    $clusterRoleBindings  = kubectl get clusterrolebindings -o json | ConvertFrom-Json | Select-Object -ExpandProperty items
    $roles                = kubectl get roles --all-namespaces -o json | ConvertFrom-Json | Select-Object -ExpandProperty items
    $clusterRoles         = kubectl get clusterroles -o json | ConvertFrom-Json | Select-Object -ExpandProperty items

    $existingNamespaces   = kubectl get namespaces -o json | ConvertFrom-Json | Select-Object -ExpandProperty items | Select-Object -ExpandProperty metadata | Select-Object -ExpandProperty name

    Write-Host "`r🤖 ✅ Fetched $($roleBindings.Count) RoleBindings, $($clusterRoleBindings.Count) ClusterRoleBindings.`n" -ForegroundColor Green

    $invalidRBAC = @()

    Write-Host "🤖 Analyzing RBAC configurations..." -ForegroundColor Yellow

    # Evaluate RoleBindings
    foreach ($rb in $roleBindings) {
        $rbNamespace     = $rb.metadata.namespace
        $namespaceExists = $rbNamespace -in $existingNamespaces

        # Check if the role exists in that namespace
        $roleExists = $roles | Where-Object { $_.metadata.name -eq $rb.roleRef.name -and $_.metadata.namespace -eq $rbNamespace }
        if (-not $roleExists -and $rb.roleRef.kind -eq "Role") {
            $invalidRBAC += [PSCustomObject]@{
                Namespace   = if ($namespaceExists) { $rbNamespace } else { "🛑 Namespace Missing" }
                Type        = "🔹 Namespace Role"
                RoleBinding = $rb.metadata.name
                Subject     = "N/A"
                Issue       = "❌ Missing Role: $($rb.roleRef.name)"
            }
        }
        # For RoleRef kind = "ClusterRole", you could check $clusterRoles if needed

        # Check each subject
        foreach ($subject in $rb.subjects) {
            if ($subject.kind -eq "ServiceAccount") {
                if (-not $namespaceExists) {
                    $invalidRBAC += [PSCustomObject]@{
                        Namespace   = "🛑 Namespace Missing"
                        Type        = "🔹 Namespace Role"
                        RoleBinding = $rb.metadata.name
                        Subject     = "$($subject.kind)/$($subject.name)"
                        Issue       = "🛑 Namespace does not exist"
                    }
                }
                else {
                    $exists = kubectl get serviceaccount -n $subject.namespace $subject.name -o json 2>$null
                    if (-not $exists) {
                        $invalidRBAC += [PSCustomObject]@{
                            Namespace   = $rbNamespace
                            Type        = "🔹 Namespace Role"
                            RoleBinding = $rb.metadata.name
                            Subject     = "$($subject.kind)/$($subject.name)"
                            Issue       = "❌ ServiceAccount does not exist"
                        }
                    }
                }
            }
        }
    }

    # Evaluate ClusterRoleBindings
    foreach ($crb in $clusterRoleBindings) {
        foreach ($subject in $crb.subjects) {
            if ($subject.kind -eq "ServiceAccount") {
                if ($subject.namespace -notin $existingNamespaces) {
                    $invalidRBAC += [PSCustomObject]@{
                        Namespace   = "🛑 Namespace Missing"
                        Type        = "🔸 Cluster Role"
                        RoleBinding = $crb.metadata.name
                        Subject     = "$($subject.kind)/$($subject.name)"
                        Issue       = "🛑 Namespace does not exist"
                    }
                }
                else {
                    $exists = kubectl get serviceaccount -n $subject.namespace $subject.name -o json 2>$null
                    if (-not $exists) {
                        $invalidRBAC += [PSCustomObject]@{
                            Namespace   = "🌍 Cluster-Wide"
                            Type        = "🔸 Cluster Role"
                            RoleBinding = $crb.metadata.name
                            Subject     = "$($subject.kind)/$($subject.name)"
                            Issue       = "❌ ServiceAccount does not exist"
                        }
                    }
                }
            }
        }
    }

    if ($invalidRBAC.Count -eq 0) {
        Write-Host "✅ No RBAC misconfigurations found." -ForegroundColor Green
        if ($Global:MakeReport -and -not $Html) {
            Write-ToReport "`n[RBAC Misconfigurations]`n"
            Write-ToReport "✅ No RBAC misconfigurations found."
        }
        if (-not $Global:MakeReport -and -not $Html) {
            Read-Host "🤖 Press Enter to return to the menu"
        }
        return
    }

    # If -Html, build an HTML table
    if ($Html) {
        if ($invalidRBAC.Count -eq 0) {
            return "<p><strong>✅ No RBAC misconfigurations found.</strong></p>"
        }
        $htmlTable = $invalidRBAC |
            ConvertTo-Html -Fragment -Property Namespace,Type,RoleBinding,Subject,Issue -PreContent "<h2>RBAC Misconfigurations</h2>" |
            Out-String

        $htmlTable = "<p><strong>⚠️ Total RBAC Misconfigurations Detected:</strong> $($invalidRBAC.Count)</p>" + $htmlTable
        return $htmlTable
    }

    # If in report mode
    if ($Global:MakeReport) {
        Write-ToReport "`n[RBAC Misconfigurations]`n"
        Write-ToReport "⚠️ Total RBAC Misconfigurations Detected: $($invalidRBAC.Count)"

        $tableString = $invalidRBAC | Format-Table Namespace,Type,RoleBinding,Subject,Issue -AutoSize | Out-String
        Write-ToReport $tableString
        return
    }

    # Otherwise, do pagination
    $totalBindings = $invalidRBAC.Count
    $currentPage   = 0
    $totalPages    = [math]::Ceiling($totalBindings / $PageSize)

    do {
        Clear-Host
        Write-Host "`n[RBAC Misconfigurations - Page $($currentPage + 1) of $totalPages]" -ForegroundColor Cyan

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
        $endIndex   = [math]::Min($startIndex + $PageSize, $totalBindings)

        $tableData = $invalidRBAC[$startIndex..($endIndex - 1)]
        if ($tableData) {
            $tableData | Format-Table Namespace,Type,RoleBinding,Subject,Issue -AutoSize
        }

        $newPage = Show-Pagination -currentPage $currentPage -totalPages $totalPages
        if ($newPage -eq -1) { break }
        $currentPage = $newPage
    } while ($true)
}


function Show-ClusterSummary {
    param(
        [switch]$Html
    )

    if (-not $Global:MakeReport ) { Clear-Host }
    Write-Host "`n[🌐 Cluster Summary]" -ForegroundColor Cyan

    # Retrieve Kubernetes Version
    Write-Host -NoNewline "`n🤖 Retrieving Cluster Information...             ⏳ Fetching..." -ForegroundColor Yellow
    $versionInfo = kubectl version -o json | ConvertFrom-Json
    $k8sVersion = if ($versionInfo.serverVersion.gitVersion) { $versionInfo.serverVersion.gitVersion } else { "Unknown" }
    $clusterName = (kubectl config current-context)
    Write-Host "`r🤖 Retrieving Cluster Information...             ✅ Done!      " -ForegroundColor Green

    if (-not $Global:MakeReport ) {
        Write-Host "`nCluster Name " -NoNewline -ForegroundColor Green
        Write-Host "is " -NoNewline
        Write-Host "$clusterName" -ForegroundColor Yellow
        Write-Host "Kubernetes Version " -NoNewline -ForegroundColor Green
        Write-Host "is " -NoNewline
        Write-Host "$k8sVersion" -ForegroundColor Yellow
        kubectl cluster-info
    }

    # Kubernetes Version Check
    Write-Host -NoNewline "`n🤖 Checking Kubernetes Version Compatibility...  ⏳ Fetching..." -ForegroundColor Yellow
    $versionCheck = Check-KubernetesVersion
    Write-Host "`r🤖 Checking Kubernetes Version Compatibility...  ✅ Done!       " -ForegroundColor Green
    if (-not $Global:MakeReport ) { Write-Host "`n$versionCheck" }

    # Cluster Metrics
    Write-Host -NoNewline "`n🤖 Fetching Cluster Metrics...                   ⏳ Fetching..." -ForegroundColor Yellow
    $summary = Show-HeroMetrics
    Write-Host "`r🤖 Fetching Cluster Metrics...                   ✅ Done!       " -ForegroundColor Green
    if (-not $Global:MakeReport ) { Write-Host "`n$summary" }

    # Log to report if in report mode
    Write-ToReport "Cluster Name: $clusterName"
    Write-ToReport "Kubernetes Version: $k8sVersion"
    if ($Global:MakeReport) {
        $info = kubectl cluster-info | Out-String
        Write-ToReport $info
    }
    Write-ToReport "Compatibility Check: $versionCheck"
    Write-ToReport "`nMetrics: $summary"

    if (-not $Global:MakeReport -and -not $Html) {
        Read-Host "`nPress Enter to return to the main menu"
    }
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
            "10" { Generate-Report }
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
