function Show-StuckJobs {
    param(
        [int]$PageSize = 10,
        [switch]$Html
    )

    if (-not $Global:MakeReport -and -not $Html) { Clear-Host }
    Write-Host "`n[⏳ Stuck Kubernetes Jobs]" -ForegroundColor Cyan
    Write-Host -NoNewline "`n🤖 Fetching Job Data..." -ForegroundColor Yellow

    # Fetch jobs
    $kubectlOutput = kubectl get jobs --all-namespaces -o json 2>&1 | Out-String

    if (-not $Global:MakeReport -and -not $Html) { $thresholds = Get-KubeBuddyThresholds }
    else {
        $thresholds = Get-KubeBuddyThresholds -Silent
    }

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
        $_.status.PSObject.Properties['active'] -and $_.status.active -gt 0 -and # Has active pods
        (-not $_.status.PSObject.Properties['ready'] -or $_.status.ready -eq 0) -and # No ready pods
        (-not $_.status.PSObject.Properties['succeeded'] -or $_.status.succeeded -eq 0) -and # Not succeeded
        (-not $_.status.PSObject.Properties['failed'] -or $_.status.failed -eq 0) -and # Not failed
        $_.status.PSObject.Properties['startTime'] -and # Has a startTime
        ((New-TimeSpan -Start $_.status.startTime -End (Get-Date)).TotalHours -gt $thresholds.stuck_job_hours)
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
            $ns = $job.metadata.namespace
            $jobName = $job.metadata.name
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

        $tableString = $tableData | Format-Table Namespace, Job, Age_Hours, Status -AutoSize | Out-String
        Write-ToReport $tableString
        return
    }

    # Otherwise, console pagination
    $totalJobs = $stuckJobs.Count
    $currentPage = 0
    $totalPages = [math]::Ceiling($totalJobs / $PageSize)

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
        $endIndex = [math]::Min($startIndex + $PageSize, $totalJobs)

        $tableData = @()
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
        [int]$PageSize = 10,
        [switch]$Html
    )

    if (-not $Global:MakeReport -and -not $Html) { Clear-Host }
    Write-Host "`n[🔴 Failed Kubernetes Jobs]" -ForegroundColor Cyan
    Write-Host -NoNewline "`n🤖 Fetching Job Data..." -ForegroundColor Yellow

    # Fetch jobs
    $kubectlOutput = kubectl get jobs --all-namespaces -o json 2>&1 | Out-String

    if (-not $Global:MakeReport -and -not $Html) { $thresholds = Get-KubeBuddyThresholds }
    else {
        $thresholds = Get-KubeBuddyThresholds -Silent
    }

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
        ((New-TimeSpan -Start $_.status.startTime -End (Get-Date)).TotalHours -gt $thresholds.failed_job_hours)
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

        $tableString = $tableData | Format-Table Namespace, Job, Age_Hours, Failures, Status -AutoSize | Out-String
        Write-ToReport $tableString
        return
    }

    # Otherwise, console pagination
    $totalJobs = $failedJobs.Count
    $currentPage = 0
    $totalPages = [math]::Ceiling($totalJobs / $PageSize)

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
        $endIndex = [math]::Min($startIndex + $PageSize, $totalJobs)

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