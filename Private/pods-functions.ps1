function Show-PodsWithHighRestarts {
    param(
        [string]$Namespace = "",
        [int]$PageSize = 10, # Number of pods per page
        [switch]$Html,       # If specified, return an HTML table rather than ASCII output
        [switch]$ExcludeNamespaces
    )

    if (-not $Global:MakeReport -and -not $Html) { Clear-Host }
    Write-Host "`n[🔁 Pods with High Restarts]" -ForegroundColor Cyan
    if (-not $Global:MakeReport -and -not $Html) {
        Write-Host -NoNewline "`n🤖 Fetching Pod Restart Data..." -ForegroundColor Yellow
    }

    if (-not $Global:MakeReport -and -not $Html) { $thresholds = Get-KubeBuddyThresholds }
    else {
        $thresholds = Get-KubeBuddyThresholds -Silent
    }

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

    if ($ExcludeNamespaces) {
        $restartPods = Exclude-Namespaces -items $restartPods
    }

    # Filter pods with high restart counts
    $filteredPods = @()

    foreach ($pod in $restartPods.items) {
        $ns = $pod.metadata.namespace
        $podName = $pod.metadata.name
        $deployment = if ($pod.metadata.ownerReferences) { 
            $pod.metadata.ownerReferences[0].name 
        }
        else { 
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
        $columns = "Namespace", "Pod", "Deployment", "Restarts", "Status"

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
        if ($currentPage -eq 0) {
            Write-SpeechBubble -msg $msg -color "Cyan" -icon "🤖" -lastColor "Red" -delay 50 # first page only
        }

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
        [int]$PageSize = 10, # Number of pods per page
        [switch]$Html,        # If specified, return an HTML table
        [switch]$ExcludeNamespaces
    )

    if (-not $Global:MakeReport -and -not $Html) { Clear-Host }
    Write-Host "`n[⏳ Long Running Pods]" -ForegroundColor Cyan
    if (-not $Global:MakeReport -and -not $Html) {
        Write-Host -NoNewline "`n🤖 Fetching Pod Data..." -ForegroundColor Yellow
    }

    if (-not $Global:MakeReport -and -not $Html) { $thresholds = Get-KubeBuddyThresholds }
    else {
        $thresholds = Get-KubeBuddyThresholds -Silent
    }
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

    if ($ExcludeNamespaces) {
        $stalePods = Exclude-Namespaces -items $stalePods
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
        ConvertTo-Html -Fragment -Property "Namespace", "Pod", "Age_Days", "Status" |
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
    $totalPages = [math]::Ceiling($totalPods / $PageSize)

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
        if ($currentPage -eq 0) {
            Write-SpeechBubble -msg $msg -color "Cyan" -icon "🤖" -lastColor "Red" -delay 50 # first page only
        }

        # Display current page
        $startIndex = $currentPage * $PageSize
        $endIndex = [math]::Min($startIndex + $PageSize, $totalPods)

        $tableData = $filteredPods[$startIndex..($endIndex - 1)]
        if ($tableData) {
            $tableData | Format-Table Namespace, Pod, Age_Days, Status -AutoSize
        }

        $newPage = Show-Pagination -currentPage $currentPage -totalPages $totalPages
        if ($newPage -eq -1) { break }
        
        $currentPage = $newPage
    } while ($true)
}

function Show-FailedPods {
    param(
        [string]$Namespace = "",
        [int]$PageSize = 10, # Number of pods per page
        [switch]$Html,       # If specified, return an HTML table
        [switch]$ExcludeNamespaces
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

    if ($ExcludeNamespaces) {
        $failedPods = Exclude-Namespaces -items $failedPods
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
    $totalPages = [math]::Ceiling($totalPods / $PageSize)

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
        if ($currentPage -eq 0) {
            Write-SpeechBubble -msg $msg -color "Cyan" -icon "🤖" -lastColor "Red" -delay 50 # first page only
        }

        # Pagination chunk
        $startIndex = $currentPage * $PageSize
        $endIndex = [math]::Min($startIndex + $PageSize, $totalPods)

        $tableData = @()
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

function Show-PendingPods {
    param(
        [string]$Namespace = "",
        [int]$PageSize = 10,
        [switch]$Html,   # If specified, return an HTML table
        [switch]$ExcludeNamespaces
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

    if ($ExcludeNamespaces) {
        $pendingPods = Exclude-Namespaces -items $pendingPods
    }

    # Filter Pending pods
    $pendingPods = $pendingPods | Where-Object { $_.status.phase -eq "Pending" }
    $totalPods = $pendingPods.Count

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
            $ns = $pod.metadata.namespace
            $podName = $pod.metadata.name
            $reason = if ($pod.status.conditions) { $pod.status.conditions[0].reason } else { "Unknown" }
            $message = if ($pod.status.conditions) {
                $pod.status.conditions[0].message -replace "`n", " "
            }
            else {
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
            $ns = $pod.metadata.namespace
            $podName = $pod.metadata.name
            $reason = if ($pod.status.conditions) { $pod.status.conditions[0].reason } else { "Unknown" }
            $message = if ($pod.status.conditions) {
                $pod.status.conditions[0].message -replace "`n", " "
            }
            else {
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
    $totalPages = [math]::Ceiling($totalPods / $PageSize)

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
        if ($currentPage -eq 0) {
            Write-SpeechBubble -msg $msg -color "Cyan" -icon "🤖" -lastColor "Red" -delay 50 # first page only
        }

        # Display current page
        $startIndex = $currentPage * $PageSize
        $endIndex = [math]::Min($startIndex + $PageSize, $totalPods)

        $tableData = @()
        for ($i = $startIndex; $i -lt $endIndex; $i++) {
            $pod = $pendingPods[$i]
            $ns = $pod.metadata.namespace
            $podName = $pod.metadata.name
            $reason = if ($pod.status.conditions) { $pod.status.conditions[0].reason } else { "Unknown" }
            $message = if ($pod.status.conditions) {
                $pod.status.conditions[0].message -replace "`n", " "
            }
            else {
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
        [switch]$Html,   # If specified, return an HTML table
        [switch]$ExcludeNamespaces
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

    if ($ExcludeNamespaces) {
        $crashPods = Exclude-Namespaces -items $crashPods
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

        $tableString = $tableData |
        Format-Table Namespace, Pod, Restarts, Status -AutoSize |
        Out-String

        Write-ToReport $tableString
        return
    }

    # Otherwise, do console pagination
    $currentPage = 0
    $totalPages = [math]::Ceiling($totalPods / $PageSize)

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
        
        if ($currentPage -eq 0) {
            Write-SpeechBubble -msg $msg -color "Cyan" -icon "🤖" -lastColor "Red" -delay 50 # first page only
        }

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

        $newPage = Show-Pagination -currentPage $currentPage -totalPages $totalPages
        if ($newPage -eq -1) { break }
        $currentPage = $newPage

    } while ($true)
}

function Show-LeftoverDebugPods {
    param(
        [string]$Namespace = "",
        [int]$PageSize = 10,
        [switch]$Html,
        [switch]$ExcludeNamespaces
    )

    if (-not $Global:MakeReport -and -not $Html) { Clear-Host }
    Write-Host "`n[🐞 Leftover Debug Pods]" -ForegroundColor Cyan
    Write-Host -NoNewline "`n🤖 Fetching Pod Data..." -ForegroundColor Yellow

    try {
        if ($Namespace -ne "") {
            $podItems = kubectl get pods -n $Namespace -o json 2>&1 | ConvertFrom-Json | Select-Object -ExpandProperty items
        } else {
            $podItems = kubectl get pods --all-namespaces -o json 2>&1 | ConvertFrom-Json | Select-Object -ExpandProperty items
        }
    } catch {
        Write-Host "`r🤖 ❌ Error retrieving pod data: $_" -ForegroundColor Red
        if ($Global:MakeReport -and -not $Html) {
            Write-ToReport "`n[🐞 Leftover Debug Pods]`n"
            Write-ToReport "❌ Error retrieving pod data: $_"
        }
        if (-not $Global:MakeReport -and -not $Html) {
            Read-Host "🤖 Press Enter to return to the menu"
        }
        return
    }

    if ($ExcludeNamespaces) {
        $podItems = Exclude-Namespaces -items $podItems
    }

    # Find debug pods (kubectl debug creates pods containing 'debugger')
    $debugPods = $podItems | Where-Object {
        $_.metadata.name -match "debugger"
    }

    $totalPods = $debugPods.Count

    if ($totalPods -eq 0) {
        Write-Host "`r🤖 ✅ No leftover debug pods detected." -ForegroundColor Green
        if ($Global:MakeReport -and -not $Html) {
            Write-ToReport "`n[🐞 Leftover Debug Pods]`n"
            Write-ToReport "✅ No leftover debug pods detected."
        }
        if (-not $Global:MakeReport -and -not $Html) {
            Read-Host "🤖 Press Enter to return to the menu"
        }
        if ($Html) {
            return "<p><strong>✅ No leftover debug pods detected.</strong></p>"
        }
        return
    }

    Write-Host "`r🤖 ✅ Pods fetched. ($totalPods leftover debug pods detected)" -ForegroundColor Green

    # HTML output
    if ($Html) {
        $tableData = foreach ($pod in $debugPods) {
            [PSCustomObject]@{
                Namespace  = $pod.metadata.namespace
                Pod        = $pod.metadata.name
                Node       = $pod.spec.nodeName
                Status     = $pod.status.phase
                AgeMinutes = [math]::Round(((Get-Date) - [DateTime]$pod.metadata.creationTimestamp).TotalMinutes, 1)
            }
        }

        $htmlTable = $tableData |
            ConvertTo-Html -Fragment -Property Namespace, Pod, Node, Status, AgeMinutes |
            Out-String

        $htmlTable = "<p><strong>⚠️ Total Leftover Debug Pods Found:</strong> $totalPods</p>" + $htmlTable
        return $htmlTable
    }

    # Report output
    if ($Global:MakeReport) {
        Write-ToReport "`n[🐞 Leftover Debug Pods]`n"
        Write-ToReport "⚠️ Total Leftover Debug Pods Found: $totalPods"
        Write-ToReport "----------------------------------------------------"

        $tableData = foreach ($pod in $debugPods) {
            [PSCustomObject]@{
                Namespace  = $pod.metadata.namespace
                Pod        = $pod.metadata.name
                Node       = $pod.spec.nodeName
                Status     = $pod.status.phase
                AgeMinutes = [math]::Round(((Get-Date) - [DateTime]$pod.metadata.creationTimestamp).TotalMinutes, 1)
            }
        }

        $tableString = $tableData |
            Format-Table Namespace, Pod, Node, Status, AgeMinutes -AutoSize |
            Out-String

        Write-ToReport $tableString
        return
    }

    # Console Pagination
    $currentPage = 0
    $totalPages = [math]::Ceiling($totalPods / $PageSize)

    do {
        Clear-Host
        Write-Host "`n[🐞 Leftover Debug Pods - Page $($currentPage + 1) of $totalPages]" -ForegroundColor Cyan

        $msg = @(
            "🤖 Leftover debug pods indicate incomplete cleanup after 'kubectl debug' sessions.",
            "",
            "📌 Why this matters:",
            "   - They may consume cluster resources unnecessarily.",
            "   - Potential security risk due to open debug access.",
            "",
            "🔍 Recommended Actions:",
            "   - Delete pods manually: kubectl delete pod <pod-name> -n <namespace>",
            "   - Review debugging procedures to prevent leftover pods.",
            "",
            "⚠️ Total Leftover Debug Pods Found: $totalPods"
        )

        if ($currentPage -eq 0) {
            Write-SpeechBubble -msg $msg -color "Cyan" -icon "🤖" -lastColor "Red" -delay 50
        }

        # Pagination logic
        $startIndex = $currentPage * $PageSize
        $endIndex = [math]::Min($startIndex + $PageSize, $totalPods)

        $tableData = @()
        for ($i = $startIndex; $i -lt $endIndex; $i++) {
            $pod = $debugPods[$i]
            $tableData += [PSCustomObject]@{
                Namespace  = $pod.metadata.namespace
                Pod        = $pod.metadata.name
                Node       = $pod.spec.nodeName
                Status     = $pod.status.phase
                AgeMinutes = [math]::Round(((Get-Date) - [DateTime]$pod.metadata.creationTimestamp).TotalMinutes, 1)
            }
        }

        if ($tableData) {
            $tableData | Format-Table Namespace, Pod, Node, Status, AgeMinutes -AutoSize
        }

        $newPage = Show-Pagination -currentPage $currentPage -totalPages $totalPages
        if ($newPage -eq -1) { break }
        $currentPage = $newPage

    } while ($true)
}
