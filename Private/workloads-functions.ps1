function Show-DaemonSetIssues {
    param(
        [object]$DaemonSetsData,
        [int]$PageSize = 10,
        [switch]$Html,
        [switch]$ExcludeNamespaces,
        [switch]$Json
    )

    if (-not $Global:MakeReport -and -not $Html -and -not $Json) { Clear-Host }
    Write-Host "`n[🔄 DaemonSets Not Fully Running]" -ForegroundColor Cyan
    Write-Host -NoNewline "`n🤖 Checking DaemonSet status..." -ForegroundColor Yellow

    try {
        $daemonsets = if ($DaemonSetsData -and $DaemonSetsData.items) {
            $DaemonSetsData
        } else {
            kubectl get daemonsets --all-namespaces -o json 2>&1 | ConvertFrom-Json
        }
    }
    catch {
        Write-Host "`r🤖 ❌ Failed to retrieve DaemonSet data: $_" -ForegroundColor Red
        if ($Global:MakeReport -and -not $Html) {
            Write-ToReport "`n[🔄 DaemonSets Not Fully Running]`n❌ Error: $_"
        }
        if (-not $Global:MakeReport -and -not $Html) {
            Read-Host "🤖 Press Enter to return to the menu"
        }
        return
    }

    if ($ExcludeNamespaces) {
        $daemonsets.items = Exclude-Namespaces -items $daemonsets.items
    }

    $filtered = $daemonsets.items | Where-Object {
        $_.status.desiredNumberScheduled -ne $_.status.numberReady
    } | ForEach-Object {
        [PSCustomObject]@{
            Namespace = $_.metadata.namespace
            DaemonSet = $_.metadata.name
            Desired   = $_.status.desiredNumberScheduled
            Running   = $_.status.numberReady
            Scheduled = $_.status.currentNumberScheduled
            Status    = "⚠️ Incomplete"
        }
    }

    $total = $filtered.Count

    if ($total -eq 0) {
        Write-Host "`r🤖 ✅ All DaemonSets are fully running." -ForegroundColor Green
        if ($Global:MakeReport -and -not $Html) {
            Write-ToReport "`n[🔄 DaemonSets Not Fully Running]`n✅ All DaemonSets are fully running."
        }
        if ($Html) { return "<p><strong>✅ All DaemonSets are fully running.</strong></p>" }
        if ($Json) { return @{ Total = 0; Items = @() } }
        if (-not $Global:MakeReport -and -not $Html) {
            Read-Host "🤖 Press Enter to return to the menu"
        }
        return
    }

    Write-Host "`r🤖 ✅ DaemonSets checked. ($total with issues)" -ForegroundColor Green

    if ($Html) {
        $htmlTable = ($filtered | Sort-Object Namespace) |
            ConvertTo-Html -Fragment -Property Namespace, DaemonSet, Desired, Running, Scheduled, Status |
            Out-String
        return "<p><strong>⚠️ Total DaemonSets with Issues:</strong> $total</p>" + $htmlTable
    }

    if ($Json) {
        return @{ Total = $total; Items = $filtered }
    }

    if ($Global:MakeReport) {
        Write-ToReport "`n[🔄 DaemonSets Not Fully Running]`n⚠️ Total Issues: $total"
        $filtered | Format-Table Namespace, DaemonSet, Desired, Running, Scheduled, Status -AutoSize |
            Out-String | Write-ToReport
        return
    }

    $currentPage = 0
    $totalPages = [math]::Ceiling($total / $PageSize)

    do {
        Clear-Host
        Write-Host "`n[🔄 DaemonSets Not Fully Running - Page $($currentPage + 1) of $totalPages]" -ForegroundColor Cyan

        if ($currentPage -eq 0) {
            Write-SpeechBubble -msg @(
                "🤖 DaemonSets run pods on every node.",
                "",
                "📌 These are not fully running:",
                "   - Check taints, node status, or resource limits.",
                "   - Use: kubectl describe ds <name> -n <ns>",
                "",
                "⚠️ Total DaemonSets with Issues: $total"
            ) -color "Cyan" -icon "🤖" -lastColor "Red" -delay 50
        }

        $start = $currentPage * $PageSize
        $slice = $filtered | Select-Object -Skip $start -First $PageSize

        if ($slice.Count -gt 0) {
            $slice | Format-Table Namespace, DaemonSet, Desired, Running, Scheduled, Status -AutoSize | Out-Host
        }

        $newPage = Show-Pagination -currentPage $currentPage -totalPages $totalPages
        if ($newPage -eq -1) { break }
        $currentPage = $newPage
    } while ($true)
}