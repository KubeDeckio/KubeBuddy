function Show-KubeEvents {
    param(
        [int]$PageSize = 10,
        [switch]$Html,
        [switch]$Json,
        [object]$KubeData
    )

    if (-not $Global:MakeReport -and -not $Html -and -not $Json) { Clear-Host }
    Write-Host "`n[📢 Kubernetes Warnings]" -ForegroundColor Cyan
    Write-Host -NoNewline "`n🤖 Fetching Kubernetes Warnings..." -ForegroundColor Yellow

    try {
        $events = if ($KubeData -and $KubeData.Events) {
            $KubeData.Events
        } else {
            (kubectl get events -A --sort-by=.metadata.creationTimestamp -o json | ConvertFrom-Json).items
        }
    } catch {
        Write-Host "`r🤖 ❌ Failed to fetch Kubernetes events." -ForegroundColor Red
        if ($Json) { return [pscustomobject]@{ TotalWarnings = 0; Summary = @(); Events = @(); Error = $_.ToString() } }
        if ($Html) { return "<p><strong>❌ Failed to fetch Kubernetes events: $($_.ToString())</strong></p>" }
        if ($Global:MakeReport) { Write-ToReport "`n[📢 Kubernetes Warnings]`n❌ Failed to fetch Kubernetes events: $($_.ToString())" }
        return
    }

    $warningEvents = $events | Where-Object { $_.type -eq "Warning" }
    $warningCount = $warningEvents.Count
    if ($warningCount -eq 0) {
        Write-Host "`r🤖 ✅ No warnings found.          " -ForegroundColor Green
        if ($Json) {
            return [pscustomobject]@{
                TotalWarnings = 0
                Summary       = @()
                Events        = @()
            }
        }
        if ($Html) {
            return @{
                SummaryHtml = "<p><strong>✅ No Kubernetes warnings found.</strong></p>"
                EventsHtml  = "<p><strong>✅ No Kubernetes warnings found.</strong></p>"
            }
        }
        if ($Global:MakeReport) { Write-ToReport "`n[📢 Kubernetes Warnings]`n✅ No warnings found." }
        if (-not $Global:MakeReport -and -not $Html -and -not $Json) {
            Read-Host "🤖 Press Enter to return to the menu"
        }
        return
    }

    Write-Host "`r🤖 ✅ Warnings fetched. (Total: $warningCount)" -ForegroundColor Green

    # 🔹 Build full event table
    $detailedEvents = $warningEvents | ForEach-Object {
        [PSCustomObject]@{
            Timestamp = $_.metadata.creationTimestamp
            Type      = "⚠️ Warning"
            Namespace = $_.metadata.namespace
            Source    = $_.source.component
            Object    = "$($_.involvedObject.kind)/$($_.involvedObject.name)"
            Reason    = $_.reason
            Message   = $_.message
        }
    }

    $sortedEvents = $detailedEvents | Sort-Object Timestamp -Descending

    # 🔹 Build summary table grouped by Reason + Message
    $summaryGrouped = $detailedEvents | Group-Object Reason, Message | Sort-Object Count -Descending
    $summaryTable = $summaryGrouped | ForEach-Object {
        [PSCustomObject]@{
            Count   = $_.Count
            Reason  = $_.Group[0].Reason
            Message = $_.Group[0].Message
            Source  = $_.Group[0].Source
        }
    }

    $summaryCount = $summaryGrouped.count

    if ($Json) {
        return [pscustomobject]@{
            TotalWarnings = $warningCount
            Summary       = $summaryTable
            Events        = $sortedEvents
        }
    }

    if ($Html) {
        $summaryHtml = $summaryTable |
            ConvertTo-Html -Fragment -Property Count, Reason, Message, Source |
            Out-String

        $detailHtml = $sortedEvents |
            ConvertTo-Html -Fragment -Property Timestamp, Type, Namespace, Source, Object, Reason, Message |
            Out-String

        return @{
            SummaryHtml = "<p><strong>⚠️ Total Grouped Warnings:</strong> $summaryCount</p><h3>Warning Summary (Grouped)</h3><div class='table-container'>$summaryHtml</div>"
            EventsHtml  = "<p><strong>⚠️ Total Warnings:</strong> $warningCount</p><h3>Full Warning Event Log</h3><div class='table-container'>$detailHtml</div>"
        }
    }

    if ($Global:MakeReport) {
        Write-ToReport "`n[📢 Kubernetes Warnings]"
        Write-ToReport "`n⚠️ Warnings: $warningCount"
        Write-ToReport "Top Issues:"
        $summaryTable | Format-Table Count, Reason, Message, Source -AutoSize | Out-String -Width 200 | Write-ToReport
        return
    }

    # Console interactive view
    $currentPage = 0
    $totalPages = [math]::Ceiling($sortedEvents.Count / $PageSize)

    do {
        Clear-Host
        Write-Host "`n[📢 Kubernetes Warnings - Page $($currentPage + 1) of $totalPages]" -ForegroundColor Cyan

        if ($currentPage -eq 0) {
            $msg = @(
                "🤖 Kubernetes Warnings track potential issues in the cluster.",
                "",
                "📌 What to look for:",
                "   - ⚠️ Warnings indicate possible failures",
                "",
                "🔍 Troubleshooting Tips:",
                "   - Run: kubectl describe node <NODE_NAME>",
                "   - Check pod logs: kubectl logs <POD_NAME> -n <NAMESPACE>",
                "   - Look for patterns in warnings",
                "",
                "📢 Total Warnings: $warningCount"
            )

            Write-SpeechBubble -msg $msg -color "Cyan" -icon "🤖" -lastColor "Red" -delay 50
        }

        $startIndex = $currentPage * $PageSize
        $pageData = $sortedEvents | Select-Object -Skip $startIndex -First $PageSize

        if ($pageData) {
            $pageData | Format-Table Timestamp, Type, Namespace, Source, Object, Reason, Message -AutoSize | Out-Host
        }

        $newPage = Show-Pagination -currentPage $currentPage -totalPages $totalPages
        if ($newPage -eq -1) { break }
        $currentPage = $newPage
    } while ($true)
}