function Show-KubeEvents {
    param(
        [int]$PageSize = 10, # Number of events per page
        [switch]$Html
    )

    if (-not $Global:MakeReport -and -not $Html) { Clear-Host }
    Write-Host "`n[📢 Kubernetes Warnings]" -ForegroundColor Cyan
    Write-Host -NoNewline "`n🤖 Fetching Kubernetes Warnings..." -ForegroundColor Yellow

    $events = kubectl get events -A --sort-by=.metadata.creationTimestamp -o json | ConvertFrom-Json
    $totalEvents = $events.items.Count

    $eventData = @()
    $warningCount = 0

    foreach ($event in $events.items) {
        if ($event.type -eq "Warning") {
            $severity = "⚠️ Warning"; $warningCount++
            $eventData += [PSCustomObject]@{
                Timestamp = $event.metadata.creationTimestamp
                Type      = $severity
                Namespace = $event.metadata.namespace
                Source    = $event.source.component
                Object    = "$($event.involvedObject.kind)/$($event.involvedObject.name)"
                Reason    = $event.reason
                Message   = $event.message
            }
        }
    }

    if ($warningCount -eq 0) {
        Write-Host "`r🤖 ✅ No warnings found.          " -ForegroundColor Green
        if ($Html) {
            return "<p><strong>✅ No Kubernetes warnings found.</strong></p>"
        }
        if (-not $Global:MakeReport -and -not $Html) {
            Read-Host "🤖 Press Enter to return to the menu"
        }
        return
    }

    Write-Host "`r🤖 ✅ Warnings fetched. (Total: $warningCount)" -ForegroundColor Green

    if ($Html) {
        $sortedData = $eventData | Sort-Object Timestamp -Descending
        $htmlTable = $sortedData |
        ConvertTo-Html -Fragment -Property Timestamp, Type, Namespace, Source, Object, Reason, Message |
        Out-String

        $htmlTable = "<p><strong>⚠️ Warnings:</strong> $warningCount</p>" + $htmlTable
        return $htmlTable
    }

    if ($Global:MakeReport) {
        Write-ToReport "`n[📢 Kubernetes Warnings]"
        Write-ToReport "`n⚠️ Warnings: $warningCount"
        Write-ToReport "-----------------------------------------------------------"

        $sortedData = $eventData | Sort-Object Timestamp -Descending
        $tableString = $sortedData | Format-Table -Property Timestamp, Type, Namespace, Source, Object, Reason, Message -AutoSize | Out-String -Width 500
        $tableString -split "`n" | ForEach-Object { Write-ToReport $_ }

        return
    }

    # Pagination
    $currentPage = 0
    $totalPages = [math]::Ceiling($eventData.Count / $PageSize)

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

        $sortedData = $eventData | Sort-Object Timestamp -Descending
        $startIndex = $currentPage * $PageSize
        $endIndex = [math]::Min($startIndex + $PageSize, $sortedData.Count)

        $tableData = $sortedData[$startIndex..($endIndex - 1)]
        if ($tableData) {
            $tableData | Format-Table -Property Timestamp, Type, Namespace, Source, Object, Reason, Message -AutoSize
        }

        $newPage = Show-Pagination -currentPage $currentPage -totalPages $totalPages
        if ($newPage -eq -1) { break }
        $currentPage = $newPage

    } while ($true)
}
