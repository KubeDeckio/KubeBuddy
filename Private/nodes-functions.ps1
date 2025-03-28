function Show-NodeConditions {
    param(
        [object]$KubeData,
        [int]$PageSize = 10, # Number of nodes per page
        [switch]$html
    )

    if (-not $Global:MakeReport -and -not $Html) { Clear-Host }
    Write-Host "`n[🌍 Node Conditions]" -ForegroundColor Cyan
    Write-Host -NoNewline "`n🤖 Fetching Node Conditions..." -ForegroundColor Yellow

    # Fetch nodes
    if ($kubeData) {
        $nodes = $kubeData.Nodes
    } else {
    $nodes = kubectl get nodes -o json | ConvertFrom-Json
    }

    $totalNodes = $nodes.items.Count

    if ($totalNodes -eq 0) {
        Write-Host "`r🤖 ❌ No nodes found." -ForegroundColor Red
        if (-not $Global:MakeReport -and -not $Html) { Read-Host "🤖 Press Enter to return to the menu" }
        return
    }

    Write-Host "`r🤖 ✅ Nodes fetched. (Total: $totalNodes)" -ForegroundColor Green

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

        # Show speech bubble only on the first page
        if ($currentPage -eq 0) {
            Write-SpeechBubble -msg $msg -color "Cyan" -icon "🤖" -lastColor "Red" -delay 50 # first page only
        }

        # Display current page
        $startIndex = $currentPage * $PageSize
        $endIndex = [math]::Min($startIndex + $PageSize, $totalNodes)

        $tableData = $allNodesData[$startIndex..($endIndex - 1)]
        if ($tableData) {
            $tableData | Format-Table -AutoSize | Out-Host
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
        [int]$PageSize = 10, # Number of nodes per page
        [switch]$Html    # If specified, return an HTML table (no ASCII pagination)
    )

    if (-not $Global:MakeReport -and -not $Html) { Clear-Host }
    Write-Host "`n[📊 Node Resource Usage]" -ForegroundColor Cyan
    if (-not $Global:MakeReport -and -not $Html) {
        Write-Host -NoNewline "`n🤖 Fetching Node Data & Resource Usage..." -ForegroundColor Yellow
    }

    # Get thresholds and node data
    if (-not $Global:MakeReport -and -not $Html) { $thresholds = Get-KubeBuddyThresholds }
    else {
        $thresholds = Get-KubeBuddyThresholds -Silent
    }
    
    if ($kubeData) {
        $allocatableRaw = $kubeData.Nodes
        $nodeUsageRaw = $kubeData.TopNodes
    } else {
    $allocatableRaw = kubectl get nodes -o json | ConvertFrom-Json
    $nodeUsageRaw = kubectl top nodes --no-headers
    }

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
    $allNodesData = @()

    # Preprocess all nodes to count warnings
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
        $columns = "Node", "CPU Status", "CPU %", "CPU Used", "CPU Total", "Mem Status", "Mem %", "Mem Used", "Mem Total", "Disk %", "Disk Status"

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
    $totalPages = [math]::Ceiling($totalNodes / $PageSize)

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
        
        if ($currentPage -eq 0) {
            Write-SpeechBubble -msg $msg -color "Cyan" -icon "🤖" -lastColor "Red" -delay 50 # first page only
        }

        # Pagination
        $startIndex = $currentPage * $PageSize
        $endIndex = [math]::Min($startIndex + $PageSize, $totalNodes)

        $tableData = $allNodesData[$startIndex..($endIndex - 1)]
        if ($tableData) {
            $tableData | Format-Table -Property Node, "CPU %", "CPU Used", "CPU Total",
            "CPU Status", "Mem %", "Mem Used", "Mem Total",
            "Mem Status", "Disk %", "Disk Status" -AutoSize | Out-Host
        }

        $newPage = Show-Pagination -currentPage $currentPage -totalPages $totalPages
        if ($newPage -eq -1) { break }
        $currentPage = $newPage

    } while ($true)
}