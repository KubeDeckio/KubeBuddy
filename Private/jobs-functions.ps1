function Show-StuckJobs {
    param(
        [object]$KubeData,
        [int]$PageSize = 10,
        [switch]$Html,
        [switch]$ExcludeNamespaces
    )

    if (-not $Global:MakeReport -and -not $Html) { Clear-Host }
    Write-Host "`n[⏳ Stuck Kubernetes Jobs]" -ForegroundColor Cyan
    Write-Host -NoNewline "`n🤖 Fetching Job Data..." -ForegroundColor Yellow

    if (-not $Global:MakeReport -and -not $Html) {
        $thresholds = Get-KubeBuddyThresholds
    } else {
        $thresholds = Get-KubeBuddyThresholds -Silent
    }

    try {
        $jobs = if ($null -ne $KubeData) {
            $KubeData.Jobs.items
        } else {
            $raw = kubectl get jobs --all-namespaces -o json 2>&1 | Out-String
            if ($raw -match "^{") {
                ($raw | ConvertFrom-Json).items
            } else {
                throw "Unexpected response from kubectl. No valid JSON received."
            }
        }
    }
    catch {
        Write-Host "`r🤖 ❌ Failed to fetch jobs: $_" -ForegroundColor Red
        if ($Html) { return "<p><strong>❌ Failed to fetch job data.</strong></p>" }
        return
    }

    if ($ExcludeNamespaces) {
        $jobs = Exclude-Namespaces -items $jobs
    }

    if (-not $jobs -or $jobs.Count -eq 0) {
        Write-Host "`r🤖 ✅ No jobs found in the cluster." -ForegroundColor Green
        if ($Html) { return "<p><strong>✅ No jobs found in the cluster.</strong></p>" }
        return
    }

    Write-Host "`r🤖 ✅ Jobs fetched. (Total: $($jobs.Count))" -ForegroundColor Green
    Write-Host -NoNewline "`n🤖 Analyzing Stuck Jobs..." -ForegroundColor Yellow

    $stuckJobs = $jobs | Where-Object {
        (-not $_.status.conditions -or $_.status.conditions.type -notcontains "Complete") -and
        $_.status.PSObject.Properties['active'] -and $_.status.active -gt 0 -and
        (-not $_.status.PSObject.Properties['ready'] -or $_.status.ready -eq 0) -and
        (-not $_.status.PSObject.Properties['succeeded'] -or $_.status.succeeded -eq 0) -and
        (-not $_.status.PSObject.Properties['failed'] -or $_.status.failed -eq 0) -and
        $_.status.PSObject.Properties['startTime'] -and
        ((New-TimeSpan -Start $_.status.startTime -End (Get-Date)).TotalHours -gt $thresholds.stuck_job_hours)
    }

    if (-not $stuckJobs -or $stuckJobs.Count -eq 0) {
        Write-Host "`r🤖 ✅ No stuck jobs found." -ForegroundColor Green
        if ($Html) { return "<p><strong>✅ No stuck jobs found.</strong></p>" }
        return
    }

    Write-Host "`r🤖 ✅ Job analysis complete. ($($stuckJobs.Count) stuck jobs detected)" -ForegroundColor Green

    $totalJobs = $stuckJobs.Count

    if ($Html) {
        $tableData = $stuckJobs | ForEach-Object {
            [PSCustomObject]@{
                Namespace = $_.metadata.namespace
                Job       = $_.metadata.name
                Age_Hours = [int](New-TimeSpan -Start $_.status.startTime -End (Get-Date)).TotalHours
                Status    = "🟡 Stuck"
            }
        }

        $htmlTable = $tableData |
            ConvertTo-Html -Fragment -Property Namespace, Job, Age_Hours, Status |
            Out-String

        return "<p><strong>⚠️ Total Stuck Jobs Found:</strong> $totalJobs</p>" + $htmlTable
    }

    if ($Global:MakeReport) {
        Write-ToReport "`n[⏳ Stuck Kubernetes Jobs]`n⚠️ Total Stuck Jobs Found: $totalJobs"

        $tableData = $stuckJobs | ForEach-Object {
            [PSCustomObject]@{
                Namespace = $_.metadata.namespace
                Job       = $_.metadata.name
                Age_Hours = [int](New-TimeSpan -Start $_.status.startTime -End (Get-Date)).TotalHours
                Status    = "🟡 Stuck"
            }
        }

        $tableString = $tableData | Format-Table Namespace, Job, Age_Hours, Status -AutoSize | Out-Host | Out-String
        Write-ToReport $tableString
        return
    }

    $currentPage = 0
    $totalPages = [math]::Ceiling($totalJobs / $PageSize)

    do {
        Clear-Host
        Write-Host "`n[⏳ Stuck Kubernetes Jobs - Page $($currentPage + 1) of $totalPages]" -ForegroundColor Cyan

        if ($currentPage -eq 0) {
            Write-SpeechBubble -msg @(
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
                "⚠️ Total Stuck Jobs Found: $totalJobs"
            ) -color "Cyan" -icon "🤖" -lastColor "Red" -delay 50
        }

        $startIndex = $currentPage * $PageSize
        $endIndex = [math]::Min($startIndex + $PageSize, $totalJobs)

        $tableData = $stuckJobs[$startIndex..($endIndex - 1)] | ForEach-Object {
            [PSCustomObject]@{
                Namespace = $_.metadata.namespace
                Job       = $_.metadata.name
                Age_Hours = [int](New-TimeSpan -Start $_.status.startTime -End (Get-Date)).TotalHours
                Status    = "🟡 Stuck"
            }
        }

        if ($tableData) {
            $tableData | Format-Table Namespace, Job, Age_Hours, Status -AutoSize | Out-Host
        }

        $newPage = Show-Pagination -currentPage $currentPage -totalPages $totalPages
        if ($newPage -eq -1) { break }
        $currentPage = $newPage

    } while ($true)
}

function Show-FailedJobs {
    param(
        [object]$KubeData,
        [int]$PageSize = 10,
        [switch]$Html,
        [switch]$ExcludeNamespaces
    )

    if (-not $Global:MakeReport -and -not $Html) { Clear-Host }
    Write-Host "`n[🔴 Failed Kubernetes Jobs]" -ForegroundColor Cyan
    Write-Host -NoNewline "`n🤖 Fetching Job Data..." -ForegroundColor Yellow

    if (-not $Global:MakeReport -and -not $Html) {
        $thresholds = Get-KubeBuddyThresholds
    } else {
        $thresholds = Get-KubeBuddyThresholds -Silent
    }

    try {
        $jobs = if ($null -ne $KubeData) {
            $KubeData.Jobs.items
        } else {
            $raw = kubectl get jobs --all-namespaces -o json 2>&1 | Out-String
            if ($raw -match "^{") {
                ($raw | ConvertFrom-Json).items
            } else {
                throw "Unexpected response from kubectl. No valid JSON received."
            }
        }
    } catch {
        Write-Host "`r🤖 ❌ Failed to fetch jobs: $_" -ForegroundColor Red
        if ($Html) { return "<p><strong>❌ Failed to fetch job data.</strong></p>" }
        return
    }

    if ($ExcludeNamespaces) {
        $jobs = Exclude-Namespaces -items $jobs
    }

    if (-not $jobs -or $jobs.Count -eq 0) {
        Write-Host "`r🤖 ✅ No jobs found in the cluster." -ForegroundColor Green
        if ($Html) { return "<p><strong>✅ No failed jobs found.</strong></p>" }
        return
    }

    Write-Host "`r🤖 ✅ Jobs fetched. (Total: $($jobs.Count))" -ForegroundColor Green
    Write-Host -NoNewline "`n🤖 Analyzing Failed Jobs..." -ForegroundColor Yellow

    $failedJobs = $jobs | Where-Object {
        $_.status.PSObject.Properties['failed'] -and $_.status.failed -gt 0 -and
        (-not $_.status.PSObject.Properties['succeeded'] -or $_.status.succeeded -eq 0) -and
        $_.status.PSObject.Properties['startTime'] -and
        ((New-TimeSpan -Start $_.status.startTime -End (Get-Date)).TotalHours -gt $thresholds.failed_job_hours)
    }

    if (-not $failedJobs -or $failedJobs.Count -eq 0) {
        Write-Host "`r🤖 ✅ No failed jobs found." -ForegroundColor Green
        if ($Html) { return "<p><strong>✅ No failed jobs found.</strong></p>" }
        return
    }

    Write-Host "`r🤖 ✅ Job analysis complete. ($($failedJobs.Count) failed jobs detected)" -ForegroundColor Green

    $totalJobs = $failedJobs.Count

    if ($Html) {
        $tableData = $failedJobs | ForEach-Object {
            [PSCustomObject]@{
                Namespace = $_.metadata.namespace
                Job       = $_.metadata.name
                Age_Hours = [int](New-TimeSpan -Start $_.status.startTime -End (Get-Date)).TotalHours
                Failures  = $_.status.failed
                Status    = "🔴 Failed"
            }
        }

        $htmlTable = $tableData |
            ConvertTo-Html -Fragment -Property Namespace, Job, Age_Hours, Failures, Status -PreContent "<h2>Failed Kubernetes Jobs</h2>" |
            Out-String

        return "<p><strong>⚠️ Total Failed Jobs Found:</strong> $totalJobs</p>" + $htmlTable
    }

    if ($Global:MakeReport) {
        Write-ToReport "`n[🔴 Failed Kubernetes Jobs]`n⚠️ Total Failed Jobs Found: $totalJobs"
        $tableData = $failedJobs | ForEach-Object {
            [PSCustomObject]@{
                Namespace = $_.metadata.namespace
                Job       = $_.metadata.name
                Age_Hours = [int](New-TimeSpan -Start $_.status.startTime -End (Get-Date)).TotalHours
                Failures  = $_.status.failed
                Status    = "🔴 Failed"
            }
        }

        $tableString = $tableData | Format-Table Namespace, Job, Age_Hours, Failures, Status -AutoSize | Out-Host | Out-String
        Write-ToReport $tableString
        return
    }

    # Pagination output
    $currentPage = 0
    $totalPages = [math]::Ceiling($totalJobs / $PageSize)

    do {
        Clear-Host
        Write-Host "`n[🔴 Failed Kubernetes Jobs - Page $($currentPage + 1) of $totalPages]" -ForegroundColor Cyan

        if ($currentPage -eq 0) {
            Write-SpeechBubble -msg @(
                "🤖 Kubernetes Jobs should complete successfully.",
                "",
                "📌 This check identifies jobs that have encountered failures.",
                "   - Jobs may fail due to insufficient resources, timeouts, or misconfigurations.",
                "   - Review logs with 'kubectl logs job/<job-name>'",
                "   - Investigate pod failures with 'kubectl describe job/<job-name>'",
                "",
                "⚠️ Consider re-running or debugging these jobs for resolution.",
                "",
                "⚠️ Total Failed Jobs Found: $totalJobs"
            ) -color "Cyan" -icon "🤖" -lastColor "Red" -delay 50
        }

        $startIndex = $currentPage * $PageSize
        $endIndex = [math]::Min($startIndex + $PageSize, $totalJobs)

        $tableData = $failedJobs[$startIndex..($endIndex - 1)] | ForEach-Object {
            [PSCustomObject]@{
                Namespace = $_.metadata.namespace
                Job       = $_.metadata.name
                Age_Hours = [int](New-TimeSpan -Start $_.status.startTime -End (Get-Date)).TotalHours
                Failures  = $_.status.failed
                Status    = "🔴 Failed"
            }
        }

        if ($tableData) {
            $tableData | Format-Table Namespace, Job, Age_Hours, Failures, Status -AutoSize | Out-Host
        }

        $newPage = Show-Pagination -currentPage $currentPage -totalPages $totalPages
        if ($newPage -eq -1) { break }
        $currentPage = $newPage

    } while ($true)
}