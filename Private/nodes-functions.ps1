function Show-NodeConditions {
    param(
        [int]$PageSize = 10,
        [switch]$Html,
        [object]$KubeData
    )

    if (-not $Global:MakeReport -and -not $Html) { Clear-Host }
    Write-Host "`n[🌍 Node Conditions]" -ForegroundColor Cyan
    Write-Host -NoNewline "`n🤖 Fetching Node Conditions..." -ForegroundColor Yellow

    try {
        $nodes = if ($KubeData -and $KubeData.Nodes) {
            $KubeData.Nodes
        } else {
            kubectl get nodes -o json | ConvertFrom-Json
        }
    } catch {
        Write-Host "`r🤖 ❌ Failed to retrieve node data." -ForegroundColor Red
        return
    }

    $totalNodes = $nodes.items.Count
    if ($totalNodes -eq 0) {
        Write-Host "`r🤖 ❌ No nodes found." -ForegroundColor Red
        if (-not $Global:MakeReport -and -not $Html) { Read-Host "🤖 Press Enter to return to the menu" }
        return
    }

    Write-Host "`r🤖 ✅ Nodes fetched. (Total: $totalNodes)" -ForegroundColor Green

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
        } else {
            $status = "❌ Not Ready"
            $totalNotReadyNodes++
            $issues = if ($issueConditions) {
                ($issueConditions | ForEach-Object { "$($_.type): $($_.message)" }) -join " | "
            } else {
                "Unknown Issue"
            }
        }

        $allNodesData += [PSCustomObject]@{
            Node   = $name
            Status = $status
            Issues = $issues
        }
    }

    if ($Html) {
        $sortedData = $allNodesData | Sort-Object {
            if ($_.Status -eq "❌ Not Ready") { 0 } else { 1 }
        }

        $htmlTable = $sortedData |
            ConvertTo-Html -Fragment -Property Node, Status, Issues |
            Out-String

        return "<p><strong>⚠️ Total Not Ready Nodes:</strong> $totalNotReadyNodes</p>$htmlTable"
    }

    if ($Global:MakeReport) {
        Write-ToReport "`n[🌍 Node Conditions]"
        Write-ToReport "`n⚠️ Total Not Ready Nodes in the Cluster: $totalNotReadyNodes"
        Write-ToReport "-----------------------------------------------------------"

        $sortedNodes = $allNodesData | Sort-Object {
            if ($_.Status -eq "❌ Not Ready") { 1 }
            elseif ($_.Status -eq "⚠️ Unknown") { 2 }
            else { 3 }
        }

        Write-ToReport ($sortedNodes | Format-Table Node, Status, Issues -AutoSize | Out-Host | Out-String)
        return
    }

    $currentPage = 0
    $totalPages = [math]::Ceiling($totalNodes / $PageSize)

    do {
        Clear-Host
        Write-Host "`n[🌍 Node Conditions - Page $($currentPage + 1) of $totalPages]" -ForegroundColor Cyan

        if ($currentPage -eq 0) {
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
        }

        $startIndex = $currentPage * $PageSize
        $endIndex = [math]::Min($startIndex + $PageSize, $totalNodes)

        $allNodesData[$startIndex..($endIndex - 1)] |
            Format-Table Node, Status, Issues -AutoSize | Out-Host

        $newPage = Show-Pagination -currentPage $currentPage -totalPages $totalPages
        if ($newPage -eq -1) { break }
        $currentPage = $newPage

    } while ($true)
}

function Show-NodeResourceUsage {
    param(
        [int]$PageSize = 10,
        [switch]$Html,
        [object]$KubeData
    )

    if (-not $Global:MakeReport -and -not $Html) { Clear-Host }
    Write-Host "`n[📊 Node Resource Usage]" -ForegroundColor Cyan
    if (-not $Global:MakeReport -and -not $Html) {
        Write-Host -NoNewline "`n🤖 Fetching Node Data & Resource Usage..." -ForegroundColor Yellow
    }

    if (-not $Global:MakeReport -and -not $Html) { $thresholds = Get-KubeBuddyThresholds }
    else { $thresholds = Get-KubeBuddyThresholds -Silent }

    try {
        $allocatableRaw = if ($KubeData -and $KubeData.Nodes) {
            $KubeData.Nodes
        } else {
            kubectl get nodes -o json | ConvertFrom-Json
        }

        $nodeUsageRaw = if ($KubeData -and $KubeData.NodeTop) {
            $KubeData.NodeTop
        } else {
            kubectl top nodes --no-headers
        }
    }
    catch {
        Write-Host "`r🤖 ❌ Failed to fetch node data or metrics." -ForegroundColor Red
        return
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

    $totalWarnings = 0
    $allNodesData = @()

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

            $cpuAlert = if ($cpuUsagePercent -gt $thresholds.cpu_critical) {
                "🔴 Critical"; $totalWarnings++
            } elseif ($cpuUsagePercent -gt $thresholds.cpu_warning) {
                "🟡 Warning"; $totalWarnings++
            } else { "✅ Normal" }

            $memAlert = if ($memUsagePercent -gt $thresholds.mem_critical) {
                "🔴 Critical"; $totalWarnings++
            } elseif ($memUsagePercent -gt $thresholds.mem_warning) {
                "🟡 Warning"; $totalWarnings++
            } else { "✅ Normal" }

            $diskUsagePercent = "<unknown>"
            $diskStatus = "⚠️ Unknown"
            if ($values.Length -ge 5 -and $values[4] -match "^\d+%$") {
                $diskUsagePercent = [int]($values[4] -replace "%", "")
                $diskStatus = if ($diskUsagePercent -gt 80) {
                    "🔴 Critical"; $totalWarnings++
                } elseif ($diskUsagePercent -gt 60) {
                    "🟡 Warning"; $totalWarnings++
                } else { "✅ Normal" }
            }

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

    if ($Global:MakeReport -and -not $Html) {
        Write-ToReport "`n[📊 Node Resource Usage]"
        Write-ToReport "`n⚠️ Total Resource Warnings Across All Nodes: $totalWarnings"
        Write-ToReport "--------------------------------------------------------------------------"

        $sortedNodes = $allNodesData | Sort-Object {
            if ($_.‘CPU Status’ -eq "🔴 Critical" -or $_.‘Mem Status’ -eq "🔴 Critical" -or $_.‘Disk Status’ -eq "⚠️ Unknown") { 1 }
            elseif ($_.‘CPU Status’ -eq "🟡 Warning" -or $_.‘Mem Status’ -eq "🟡 Warning" -or $_.‘Disk Status’ -eq "🟡 Warning") { 2 }
            else { 3 }
        }

        $tableString = $sortedNodes |
        Format-Table -Property Node, "CPU Status", "CPU %", "CPU Used", "CPU Total", "Mem Status",
        "Mem %", "Mem Used", "Mem Total", "Disk %", "Disk Status" -AutoSize | Out-Host | Out-String

        Write-ToReport $tableString
        return
    }

    if ($Html) {
        $sortedHtmlData = $allNodesData | Sort-Object {
            if ($_.‘CPU Status’ -eq "🔴 Critical" -or $_.‘Mem Status’ -eq "🔴 Critical" -or $_.‘Disk Status’ -eq "⚠️ Unknown") { 1 }
            elseif ($_.‘CPU Status’ -eq "🟡 Warning" -or $_.‘Mem Status’ -eq "🟡 Warning" -or $_.‘Disk Status’ -eq "🟡 Warning") { 2 }
            else { 3 }
        }

        $columns = "Node", "CPU Status", "CPU %", "CPU Used", "CPU Total", "Mem Status", "Mem %", "Mem Used", "Mem Total", "Disk %", "Disk Status"

        $htmlTable = $sortedHtmlData |
        ConvertTo-Html -Fragment -Property $columns -PreContent "<h2>Node Resource Usage</h2>" |
        Out-String

        return "<p><strong>⚠️ Total Resource Warnings Across All Nodes:</strong> $totalWarnings</p>$htmlTable"
    }

    $currentPage = 0
    $totalPages = [math]::Ceiling($totalNodes / $PageSize)

    do {
        Clear-Host
        Write-Host "`n[📊 Node Resource Usage - Page $($currentPage + 1) of $totalPages]" -ForegroundColor Cyan

        if ($currentPage -eq 0) {
            $msg = @(
                "🤖 Nodes are assessed for CPU, memory, and disk usage. Alerts indicate high resource utilization.",
                "",
                "📌 If CPU or memory usage is high, check workloads consuming excessive resources and optimize them.",
                "📌 If disk usage is critical, consider adding storage capacity or cleaning up unused data.",
                "",
                "⚠️ Total Resource Warnings Across All Nodes: $totalWarnings"
            )
            Write-SpeechBubble -msg $msg -color "Cyan" -icon "🤖" -lastColor "Red" -delay 50
        }

        $startIndex = $currentPage * $PageSize
        $endIndex = [math]::Min($startIndex + $PageSize, $totalNodes)

        $tableData = $allNodesData[$startIndex..($endIndex - 1)]
        $tableData | Format-Table -Property Node, "CPU %", "CPU Used", "CPU Total",
            "CPU Status", "Mem %", "Mem Used", "Mem Total",
            "Mem Status", "Disk %", "Disk Status" -AutoSize | Out-Host

        $newPage = Show-Pagination -currentPage $currentPage -totalPages $totalPages
        if ($newPage -eq -1) { break }
        $currentPage = $newPage
    } while ($true)
}