function Show-StuckJobs {
    param(
        [object]$KubeData,
        [int]$PageSize = 10,
        [switch]$Html,
        [switch]$Json,
        [switch]$ExcludeNamespaces
    )

    if (-not $Text -and -not $Html -and -not $Json) { Clear-Host }
    Write-Host "`n[⏳ Stuck Kubernetes Jobs]" -ForegroundColor Cyan
    Write-Host -NoNewline "`n🤖 Fetching Job Data..." -ForegroundColor Yellow

    if (-not $Text -and -not $Html -and -not $Json) {
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
        Write-Host "`r🤖 ✅ No jobs found." -ForegroundColor Green
        if ($Html) { return "<p><strong>✅ No jobs found.</strong></p>" }
        if (-not $Text -and -not $Html -and -not $Json) {
            Read-Host "🤖 Press Enter to return to the menu"
        }
        return
    }
    
    Write-Host "`r🤖 ✅ Jobs fetched. (Total: $($jobs.Count))" -ForegroundColor Green
    Write-Host -NoNewline "`n🤖 Analyzing Stuck Jobs..." -ForegroundColor Yellow

    $stuckJobs = $jobs | Where-Object {
        # Skip if status is null
        if ($null -eq $_.status) { return $false }

        # Check startTime and age
        $hasStartTime = $_.status.PSObject.Properties.Name -contains 'startTime'
        $isOldEnough = $hasStartTime -and ((New-TimeSpan -Start $_.status.startTime -End (Get-Date)).TotalHours -gt $thresholds.stuck_job_hours)

        # Check if job is not completed
        $conditions = $_.status.conditions
        $isNotComplete = -not $conditions -or (-not ($conditions | Where-Object { $_.type -eq "Complete" -and $_.status -eq "True" }))

        # Job is stuck if it’s old enough and not complete
        $isOldEnough -and $isNotComplete
    }    

    if (-not $stuckJobs -or $stuckJobs.Count -eq 0) {
        Write-Host "`r🤖 ✅ No stuck jobs found." -ForegroundColor Green
        if ($Html) { return "<p><strong>✅ No stuck jobs found.</strong></p>" }
        if (-not $Text -and -not $Html -and -not $Json) {
            Read-Host "🤖 Press Enter to return to the menu"
        }
        return
    }

    Write-Host "`r🤖 ✅ Job analysis complete. ($($stuckJobs.Count) stuck jobs detected)" -ForegroundColor Green

    $totalJobs = $stuckJobs.Count

    if ($Json) {
        $tableData = $stuckJobs | ForEach-Object {
            [PSCustomObject]@{
                Namespace = $_.metadata.namespace
                Job       = $_.metadata.name
                Age_Hours = [int](New-TimeSpan -Start $_.status.startTime -End (Get-Date)).TotalHours
                Status    = "🟡 Stuck"
            }
        }
        return @{ Total = $tableData.Count; Items = $tableData }
    }
    
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

    if ($Text) {
        Write-ToReport "`n[⏳ Stuck Kubernetes Jobs]`n⚠️ Total Stuck Jobs Found: $totalJobs"
        $tableData = $stuckJobs | ForEach-Object {
            [PSCustomObject]@{
                Namespace = $_.metadata.namespace
                Job       = $_.metadata.name
                Age_Hours = [int](New-TimeSpan -Start $_.status.startTime -End (Get-Date)).TotalHours
                Status    = "🟡 Stuck"
            }
        }
        $tableString = $tableData | Format-Table Namespace, Job, Age_Hours, Status -AutoSize | Out-String
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
        [switch]$Json,
        [switch]$ExcludeNamespaces
    )

    if (-not $Text -and -not $Html -and -not $Json) { Clear-Host }
    Write-Host "`n[🔴 Failed Kubernetes Jobs]" -ForegroundColor Cyan
    Write-Host -NoNewline "`n🤖 Fetching Job Data..." -ForegroundColor Yellow

    if (-not $Text -and -not $Html -and -not $Json) {
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
        Write-Host "`r🤖 ✅ No jobs found." -ForegroundColor Green
        if ($Html) { return "<p><strong>✅ No jobs found.</strong></p>" }
        if (-not $Text -and -not $Html -and -not $Json) {
            Read-Host "🤖 Press Enter to return to the menu"
        }
        return
    }

    Write-Host "`r🤖 ✅ Jobs fetched. (Total: $($jobs.Count))" -ForegroundColor Green
    Write-Host -NoNewline "`n🤖 Analyzing Failed Jobs..." -ForegroundColor Yellow

    $failedJobs = $jobs | Where-Object {
        # Ensure $_.status exists before checking properties
        if ($null -eq $_.status) { return $false }
        
        # Check for failed jobs safely
        $hasFailed = $_.status.PSObject.Properties.Name -contains 'failed' -and $_.status.failed -gt 0
        $noSuccess = -not ($_.status.PSObject.Properties.Name -contains 'succeeded') -or $_.status.succeeded -eq 0
        $hasStartTime = $_.status.PSObject.Properties.Name -contains 'startTime'
        $isOldEnough = $hasStartTime -and ((New-TimeSpan -Start $_.status.startTime -End (Get-Date)).TotalHours -gt $thresholds.failed_job_hours)

        $hasFailed -and $noSuccess -and $isOldEnough
    }

    if (-not $failedJobs -or $failedJobs.Count -eq 0) {
        Write-Host "`r🤖 ✅ No failed jobs found." -ForegroundColor Green
        if ($Html) { return "<p><strong>✅ No failed jobs found.</strong></p>" }
        if (-not $Text -and -not $Html -and -not $Json) {
            Read-Host "🤖 Press Enter to return to the menu"
        }
        return
    }

    Write-Host "`r🤖 ✅ Job analysis complete. ($($failedJobs.Count) failed jobs detected)" -ForegroundColor Green

    $totalJobs = $failedJobs.Count

    if ($Json) {
        if (-not $failedJobs -or $failedJobs.Count -eq 0) {
            return @{ Total = 0; Items = @() }
        }
    
        $tableData = $failedJobs | ForEach-Object {
            [PSCustomObject]@{
                Namespace = $_.metadata.namespace
                Job       = $_.metadata.name
                Age_Hours = [int](New-TimeSpan -Start $_.status.startTime -End (Get-Date)).TotalHours
                Failures  = $_.status.failed
                Status    = "🔴 Failed"
            }
        }
    
        return @{ Total = $tableData.Count; Items = $tableData }
    }
    
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

    if ($Text) {
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

        $tableString = $tableData | Format-Table Namespace, Job, Age_Hours, Failures, Status -AutoSize | Out-String
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