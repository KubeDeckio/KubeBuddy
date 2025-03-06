function Show-KubeEvents {
    param(
        [int]$PageSize = 10, # Number of events per page
        [switch]$Html
    )

    if (-not $Global:MakeReport -and -not $Html) { Clear-Host }
    Write-Host "`n[📢 Kubernetes Warnings]" -ForegroundColor Cyan
    Write-Host -NoNewline "`n🤖 Fetching Kubernetes Warnings..." -ForegroundColor Yellow

    # Fetch events
    $events = kubectl get events -A --sort-by=.metadata.creationTimestamp -o json | ConvertFrom-Json
    $totalEvents = $events.items.Count

    if ($totalEvents -eq 0) {
        Write-Host "`r🤖 ❌ No warnings found." -ForegroundColor Red
        if (-not $Global:MakeReport -and -not $Html) { Read-Host "🤖 Press Enter to return to the menu" }
        return
    }

    Write-Host "`r🤖 ✅ Warnings fetched. (Total: $totalEvents)" -ForegroundColor Green

    # **Process events (only warnings)**
    $eventData = @()
    $warningCount = 0

    foreach ($event in $events.items) {
        # Only include Warnings
        if ($event.type -eq "Warning") {
            
            # Count the warning
            $severity = "⚠️ Warning"; $warningCount++
    
            # Add to event list
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

    # **Return HTML Output if -Html is used**
    if ($Html) {
        # Sort warnings by timestamp
        $sortedData = $eventData | Sort-Object Timestamp -Descending

        # Convert the sorted data to an HTML table
        $htmlTable = $sortedData |
        ConvertTo-Html -Fragment -Property Timestamp, Type, Namespace, Source, Object, Reason, Message |
        Out-String

        # Insert hero metrics at the top
        $htmlTable = "<p><strong>⚠️ Warnings:</strong> $warningCount</p>" + $htmlTable

        return $htmlTable
    }

    # **Write to Report**
    if ($Global:MakeReport) {
        Write-ToReport "`n[📢 Kubernetes Warnings]"
        Write-ToReport "`n⚠️ Warnings: $warningCount"
        Write-ToReport "-----------------------------------------------------------"
    
        # Sort warnings by timestamp
        $sortedData = $eventData | Sort-Object Timestamp -Descending
        
        # Format as a table and write to report
        $tableString = $sortedData | Format-Table -Property Timestamp, Type, Namespace, Source, Object, Reason, Message -AutoSize | Out-String -Width 500
        $tableString -split "`n" | ForEach-Object { Write-ToReport $_ }
    
        return
    }
   

    # **Pagination Setup**
    $currentPage = 0
    $totalPages = [math]::Ceiling($eventData.Count / $PageSize)

    do {
        Clear-Host
        Write-Host "`n[📢 Kubernetes Warnings - Page $($currentPage + 1) of $totalPages]" -ForegroundColor Cyan

        # **Kubebuddy Message (First Page Only)**
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

        # Display current page of sorted warnings (newest first)
        $sortedData = $eventData | Sort-Object Timestamp -Descending
        $startIndex = $currentPage * $PageSize
        $endIndex = [math]::Min($startIndex + $PageSize, $sortedData.Count)

        $tableData = $sortedData[$startIndex..($endIndex - 1)]

        if ($tableData) {
            $tableData | Format-Table -Property Timestamp, Type, Namespace, Source, Object, Reason, Message -AutoSize
        }

        # Call the pagination function
        $newPage = Show-Pagination -currentPage $currentPage -totalPages $totalPages

        # Exit pagination if 'C' (Continue) was selected
        if ($newPage -eq -1) { break }

        $currentPage = $newPage

    } while ($true)
}