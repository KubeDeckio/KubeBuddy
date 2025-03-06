function Show-DaemonSetIssues {
    param(
        [int]$PageSize = 10, # Number of daemonsets per page
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
        $ns = $ds.metadata.namespace
        $name = $ds.metadata.name
        $desired = $ds.status.desiredNumberScheduled
        $current = $ds.status.currentNumberScheduled
        $running = $ds.status.numberReady

        # Only include DaemonSets that are NOT fully running
        if ($desired -ne $running) {
            $filteredDaemonSets += [PSCustomObject]@{
                Namespace = $ns
                DaemonSet = $name
                Desired   = $desired
                Running   = $running
                Scheduled = $current
                Status    = "⚠️ Incomplete"
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
        ConvertTo-Html -Fragment -Property "Namespace", "DaemonSet", "Desired", "Running", "Scheduled", "Status" |
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
    $totalPages = [math]::Ceiling($totalDaemonSets / $PageSize)

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
        if ($currentPage -eq 0) {
            Write-SpeechBubble -msg $msg -color "Cyan" -icon "🤖" -lastColor "Red" -delay 50 # first page only
        }

        # Display current page
        $startIndex = $currentPage * $PageSize
        $endIndex = [math]::Min($startIndex + $PageSize, $totalDaemonSets)

        $tableData = $filteredDaemonSets[$startIndex..($endIndex - 1)]
        if ($tableData) {
            $tableData | Format-Table Namespace, DaemonSet, Desired, Running, Scheduled, Status -AutoSize
        }

        $newPage = Show-Pagination -currentPage $currentPage -totalPages $totalPages
        if ($newPage -eq -1) { break }
        
        $currentPage = $newPage
    } while ($true)
}