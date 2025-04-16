function Show-PodsWithHighRestarts {
    param(
        [object]$KubeData,
        [string]$Namespace = "",
        [int]$PageSize = 10,
        [switch]$Html,
        [switch]$Json,
        [switch]$ExcludeNamespaces
    )

    if (-not $Text -and -not $Html -and -not $Json) { Clear-Host }
    Write-Host "`n[🔁 Pods with High Restarts]" -ForegroundColor Cyan
    if (-not $Text -and -not $Html -and -not $Json) {
        Write-Host -NoNewline "`n🤖 Fetching Pod Restart Data..." -ForegroundColor Yellow
    }

    $thresholds = if ($Text -or $Html -or $Json) {
        Get-KubeBuddyThresholds -Silent
    } else {
        Get-KubeBuddyThresholds
    }

    try {
        $restartPods = if ($KubeData) {
            if ($Namespace) {
                $KubeData.Pods.items | Where-Object { $_.metadata.namespace -eq $Namespace }
            } else {
                $KubeData.Pods.items
            }
        } else {
            $restartPods = if ($Namespace) {
                kubectl get pods -n $Namespace -o json 2>&1
            } else {
                kubectl get pods --all-namespaces -o json 2>&1
            }
            if ($restartPods -match "No resources found") {
                if ($Html) { return "<p><strong>✅ No pods found.</strong></p>" }
                if ($Json) { return @{ Total = 0; Items = @() } }
                Write-Host "`r🤖 ✅ No pods found." -ForegroundColor Green
                if (-not $Text -and -not $Html -and -not $Json) {
                    Read-Host "🤖 Press Enter to return to the menu"
                }
                return
            }
            ($restartPods | ConvertFrom-Json).items
        }
    }
    catch {
        Write-Host "`r🤖 ❌ Error retrieving pod data: $_" -ForegroundColor Red
        if ($Html) { return "<p><strong>❌ Error retrieving pod data.</strong></p>" }
        if ($Json) { return @{ Error = "$_" } }
        return
    }

    if ($ExcludeNamespaces) {
        $restartPods = Exclude-Namespaces -items $restartPods
    }

    if (-not $restartPods -or $restartPods.Count -eq 0) {
        if ($Html) { return "<p><strong>✅ No pods found.</strong></p>" }
        if ($Json) { return @{ Total = 0; Items = @() } }
        Write-Host "`r🤖 ✅ No pods found." -ForegroundColor Green
        if (-not $Text -and -not $Html -and -not $Json) {
            Read-Host "🤖 Press Enter to return to the menu"
        }
        return
    }

    $filteredPods = @()
    foreach ($pod in $restartPods) {
        $ns = $pod.metadata.namespace
        $podName = $pod.metadata.name
        $deployment = if ($pod.metadata.ownerReferences) {
            $pod.metadata.ownerReferences[0].name
        } else {
            "N/A"
        }

        $restarts = if ($pod.status.containerStatuses) {
            [int]($pod.status.containerStatuses | Measure-Object -Property restartCount -Sum | Select-Object -ExpandProperty Sum)
        } else {
            0
        }

        $restartStatus = $null
        if ($restarts -gt $thresholds.restarts_critical) {
            $restartStatus = "🔴 Critical"
        } elseif ($restarts -gt $thresholds.restarts_warning) {
            $restartStatus = "🟡 Warning"
        }

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
        if ($Html) { return "<p><strong>✅ No pods with excessive restarts detected.</strong></p>" }
        if ($Json) { return @{ Total = 0; Items = @() } }
        Write-Host "`r🤖 ✅ No pods with excessive restarts detected." -ForegroundColor Green
        if (-not $Text -and -not $Html -and -not $Json) {
            Read-Host "🤖 Press Enter to return to the menu"
        }
        return
    }

    if ($Json) {
        return @{ Total = $totalPods; Items = $filteredPods }
    }

    Write-Host "`r🤖 ✅ High-restart pods fetched. ($totalPods detected)" -ForegroundColor Green

    if ($Html) {
        $sortedData = $filteredPods | Sort-Object -Property Restarts -Descending
        $columns = "Namespace", "Pod", "Deployment", "Restarts", "Status"
        $htmlTable = $sortedData | ConvertTo-Html -Fragment -Property $columns | Out-String
        return "<p><strong>⚠️ Total High-Restart Pods:</strong> $totalPods</p>" + $htmlTable
    }

    if ($Text) {
        Write-ToReport "`n[🔁 Pods with High Restarts]`n"
        Write-ToReport "⚠️ Total High-Restart Pods: $totalPods"
        $tableString = $filteredPods | Format-Table Namespace, Pod, Deployment, Restarts, Status -AutoSize | Out-String
        Write-ToReport $tableString
        return
    }

    # Console output with pagination
    $currentPage = 0
    $totalPages = [math]::Ceiling($totalPods / $PageSize)

    do {
        Clear-Host
        Write-Host "`n[🔁 Pods with High Restarts - Page $($currentPage + 1) of $totalPages]" -ForegroundColor Cyan

        if ($currentPage -eq 0) {
            Write-SpeechBubble -msg @(
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
            ) -color "Cyan" -icon "🤖" -lastColor "Red" -delay 50
        }

        $paged = $filteredPods | Select-Object -Skip ($currentPage * $PageSize) -First $PageSize
        if ($paged) {
            $paged | Format-Table Namespace, Pod, Deployment, Restarts, Status -AutoSize | Out-Host
        }

        $newPage = Show-Pagination -currentPage $currentPage -totalPages $totalPages
        if ($newPage -eq -1) { break }
        $currentPage = $newPage
    } while ($true)
}

function Show-LongRunningPods {
    param(
        [object]$KubeData,
        [string]$Namespace = "",
        [int]$PageSize = 10,
        [switch]$Html,
        [switch]$Json,
        [switch]$ExcludeNamespaces
    )

    if (-not $Text -and -not $Html -and -not $Json) { Clear-Host }
    Write-Host "`n[⏳ Long Running Pods]" -ForegroundColor Cyan
    if (-not $Text -and -not $Html -and -not $Json) {
        Write-Host -NoNewline "`n🤖 Fetching Pod Data..." -ForegroundColor Yellow
    }

    $thresholds = if ($Text -or $Html -or $Json) {
        Get-KubeBuddyThresholds -Silent
    } else {
        Get-KubeBuddyThresholds
    }

    try {
        $pods = if ($KubeData) {
            if ($Namespace) {
                $KubeData.Pods.items | Where-Object { $_.metadata.namespace -eq $Namespace }
            } else {
                $KubeData.Pods.items
            }
        } else {
            $pods = if ($Namespace) {
                kubectl get pods -n $Namespace -o json 2>&1
            } else {
                kubectl get pods --all-namespaces -o json 2>&1
            }
            if ($pods -match "No resources found") {
                if ($Html) { return "<p><strong>✅ No pods found.</strong></p>" }
                if ($Json) { return @{ Total = 0; Items = @() } }
                Write-Host "`r🤖 ✅ No pods found." -ForegroundColor Green
                if (-not $Text -and -not $Html -and -not $Json) {
                    Read-Host "🤖 Press Enter to return to the menu"
                }
                return
            }
            ($pods | ConvertFrom-Json).items
        }
    }
    catch {
        Write-Host "`r🤖 ❌ Error retrieving pod data: $_" -ForegroundColor Red
        if ($Html) { return "<p><strong>❌ Error retrieving pod data.</strong></p>" }
        if ($Json) { return @{ Error = "$_" } }
        return
    }

    if ($ExcludeNamespaces) {
        $pods = Exclude-Namespaces -items $pods
    }

    $filteredPods = @()
    foreach ($pod in $pods) {
        $ns = $pod.metadata.namespace
        $podName = $pod.metadata.name
        $status = $pod.status.phase

        if ($status -eq "Running" -and $pod.status.PSObject.Properties['startTime'] -and $pod.status.startTime) {
            $startTime = [datetime]$pod.status.startTime
            $ageDays = ((Get-Date) - $startTime).Days

            $podStatus = $null
            if ($ageDays -gt $thresholds.pod_age_critical) {
                $podStatus = "🔴 Critical"
            } elseif ($ageDays -gt $thresholds.pod_age_warning) {
                $podStatus = "🟡 Warning"
            }

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
        if ($Html) { return "<p><strong>✅ No long-running pods detected.</strong></p>" }
        if ($Json) { return @{ Total = 0; Items = @() } }
        Write-Host "`r🤖 ✅ No long-running pods detected." -ForegroundColor Green
        if (-not $Text -and -not $Html -and -not $Json) {
            Read-Host "🤖 Press Enter to return to the menu"
        }
        return
    }

    Write-Host "`r🤖 ✅ Long-running pods fetched. ($totalPods detected)" -ForegroundColor Green

    if ($Json) {
        return @{ Total = $totalPods; Items = $filteredPods }
    }

    if ($Html) {
        $htmlTable = $filteredPods |
            Sort-Object -Property Age_Days -Descending |
            ConvertTo-Html -Fragment -Property Namespace, Pod, Age_Days, Status |
            Out-String
        return "<p><strong>⚠️ Total Long-Running Pods:</strong> $totalPods</p>" + $htmlTable
    }

    if ($Text) {
        Write-ToReport "`n[⏳ Long Running Pods]`n"
        Write-ToReport "⚠️ Total Long-Running Pods: $totalPods"
        $tableString = $filteredPods |
            Format-Table Namespace, Pod, Age_Days, Status -AutoSize | Out-String
        Write-ToReport $tableString
        return
    }

    $currentPage = 0
    $totalPages = [math]::Ceiling($totalPods / $PageSize)

    do {
        Clear-Host
        Write-Host "`n[⏳ Long Running Pods - Page $($currentPage + 1) of $totalPages]" -ForegroundColor Cyan

        if ($currentPage -eq 0) {
            Write-SpeechBubble -msg @(
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
            ) -color "Cyan" -icon "🤖" -lastColor "Red" -delay 50
        }

        $paged = $filteredPods | Select-Object -Skip ($currentPage * $PageSize) -First $PageSize
        if ($paged) {
            $paged | Format-Table Namespace, Pod, Age_Days, Status -AutoSize | Out-Host
        }

        $newPage = Show-Pagination -currentPage $currentPage -totalPages $totalPages
        if ($newPage -eq -1) { break }
        $currentPage = $newPage
    } while ($true)
}

function Show-FailedPods {
    param(
        [object]$KubeData,
        [string]$Namespace = "",
        [int]$PageSize = 10,
        [switch]$Html,
        [switch]$Json,
        [switch]$ExcludeNamespaces
    )

    if (-not $Text -and -not $Html -and -not $Json) { Clear-Host }
    Write-Host "`n[🔴 Failed Pods]" -ForegroundColor Cyan
    Write-Host -NoNewline "`n🤖 Fetching Failed Pod Data..." -ForegroundColor Yellow

    try {
        $failedPods = if ($KubeData) {
            $allPods = if ($Namespace) {
                $KubeData.Pods.items | Where-Object { $_.metadata.namespace -eq $Namespace }
            } else {
                $KubeData.Pods.items
            }
            $allPods | Where-Object { $_.status.phase -eq "Failed" }
        } else {
            $failedPods = if ($Namespace) {
                kubectl get pods -n $Namespace -o json 2>&1
            } else {
                kubectl get pods --all-namespaces -o json 2>&1
            }
            if ($failedPods -match "No resources found") {
                if ($Html) { return "<p><strong>✅ No failed pods found.</strong></p>" }
                if ($Json) { return @{ Total = 0; Items = @() } }
                Write-Host "`r🤖 ✅ No failed pods found." -ForegroundColor Green
                if (-not $Text -and -not $Html -and -not $Json) {
                    Read-Host "🤖 Press Enter to return to the menu"
                }
                return
            }
            $parsed = $failedPods | ConvertFrom-Json
            $parsed.items | Where-Object { $_.status.phase -eq "Failed" }
        }
    } catch {
        Write-Host "`r🤖 ❌ Error retrieving pod data: $_" -ForegroundColor Red
        if ($Html) { return "<p><strong>❌ Error retrieving pod data.</strong></p>" }
        if ($Json) { return @{ Error = "$_" } }
        return
    }

    if ($ExcludeNamespaces) {
        $failedPods = Exclude-Namespaces -items $failedPods
    }

    $totalPods = $failedPods.Count

    if ($totalPods -eq 0) {
        if ($Html) { return "<p><strong>✅ No failed pods found.</strong></p>" }
        if ($Json) { return @{ Total = 0; Items = @() } }
        Write-Host "`r🤖 ✅ No failed pods found." -ForegroundColor Green
        if (-not $Text -and -not $Html -and -not $Json) {
            Read-Host "🤖 Press Enter to return to the menu"
        }
        return
    }

    Write-Host "`r🤖 ✅ Failed Pods fetched. ($totalPods detected)" -ForegroundColor Green

    $tableData = foreach ($pod in $failedPods) {
        [PSCustomObject]@{
            Namespace = $pod.metadata.namespace
            Pod       = $pod.metadata.name
            Reason    = if ($pod.status.reason) { $pod.status.reason } else { "Unknown" }
            Message   = if ($pod.status.message) { $pod.status.message -replace "`n", " " } else { "No details" }
        }
    }

    if ($Json) {
        return @{ Total = $tableData.Count; Items = $tableData }
    }

    if ($Html) {
        $htmlTable = $tableData |
            ConvertTo-Html -Fragment -Property Namespace, Pod, Reason, Message -PreContent "<h2>Failed Pods</h2>" |
            Out-String
        return "<p><strong>⚠️ Total Failed Pods:</strong> $totalPods</p>" + $htmlTable
    }

    if ($Text) {
        Write-ToReport "`n[🔴 Failed Pods]`n"
        Write-ToReport "⚠️ Total Failed Pods: $totalPods"
        $tableString = $tableData |
            Format-Table Namespace, Pod, Reason, Message -AutoSize | Out-String
        Write-ToReport $tableString
        return
    }

    $currentPage = 0
    $totalPages = [math]::Ceiling($totalPods / $PageSize)

    do {
        Clear-Host
        Write-Host "`n[🔴 Failed Pods - Page $($currentPage + 1) of $totalPages]" -ForegroundColor Cyan

        if ($currentPage -eq 0) {
            Write-SpeechBubble -msg @(
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
            ) -color "Cyan" -icon "🤖" -lastColor "Red" -delay 50
        }

        $paged = $tableData | Select-Object -Skip ($currentPage * $PageSize) -First $PageSize
        if ($paged) {
            $paged | Format-Table Namespace, Pod, Reason, Message -AutoSize | Out-Host
        }

        $newPage = Show-Pagination -currentPage $currentPage -totalPages $totalPages
        if ($newPage -eq -1) { break }
        $currentPage = $newPage
    } while ($true)
}

function Show-PendingPods {
    param(
        [object]$KubeData,
        [string]$Namespace = "",
        [int]$PageSize = 10,
        [switch]$Html,
        [switch]$Json,
        [switch]$ExcludeNamespaces
    )

    if (-not $Text -and -not $Html -and -not $Json) { Clear-Host }
    Write-Host "`n[⏳ Pending Pods]" -ForegroundColor Cyan
    Write-Host -NoNewline "`n🤖 Fetching Pod Data..." -ForegroundColor Yellow

    try {
        $pendingPods = if ($KubeData) {
            $allPods = if ($Namespace) {
                $KubeData.Pods.items | Where-Object { $_.metadata.namespace -eq $Namespace }
            } else {
                $KubeData.Pods.items
            }
            $allPods | Where-Object { $_.status.phase -eq "Pending" }
        } else {
            $pendingPods = if ($Namespace) {
                kubectl get pods -n $Namespace -o json 2>&1
            } else {
                kubectl get pods --all-namespaces -o json 2>&1
            }
            if ($pendingPods -match "No resources found") {
                if ($Html) { return "<p><strong>✅ No pending pods found.</strong></p>" }
                if ($Json) { return @{ Total = 0; Items = @() } }
                Write-Host "`r🤖 ✅ No pending pods found." -ForegroundColor Green
                if (-not $Text -and -not $Html -and -not $Json) {
                    Read-Host "🤖 Press Enter to return to the menu"
                }
                return
            }
            $parsed = $pendingPods | ConvertFrom-Json
            $parsed.items | Where-Object { $_.status.phase -eq "Pending" }
        }
    } catch {
        Write-Host "`r🤖 ❌ Error retrieving pod data: $_" -ForegroundColor Red
        if ($Html) { return "<p><strong>❌ Error retrieving pod data.</strong></p>" }
        if ($Json) { return @{ Error = "$_" } }
        return
    }

    if ($ExcludeNamespaces) {
        $pendingPods = Exclude-Namespaces -items $pendingPods
    }

    $totalPods = $pendingPods.Count

    if ($totalPods -eq 0) {
        if ($Html) { return "<p><strong>✅ No pending pods found.</strong></p>" }
        if ($Json) { return @{ Total = 0; Items = @() } }
        Write-Host "`r🤖 ✅ No pending pods found." -ForegroundColor Green
        if (-not $Text -and -not $Html -and -not $Json) {
            Read-Host "🤖 Press Enter to return to the menu"
        }
        return
    }

    Write-Host "`r🤖 ✅ Pods fetched. ($totalPods Pending pods detected)" -ForegroundColor Green

    $tableData = foreach ($pod in $pendingPods) {
        [PSCustomObject]@{
            Namespace = $pod.metadata.namespace
            Pod       = $pod.metadata.name
            Reason    = if ($pod.status.conditions) { $pod.status.conditions[0].reason } else { "Unknown" }
            Message   = if ($pod.status.conditions) {
                $pod.status.conditions[0].message -replace "`n", " "
            } else {
                "No details available"
            }
        }
    }

    if ($Json) {
        return @{ Total = $tableData.Count; Items = $tableData }
    }

    if ($Html) {
        $htmlTable = $tableData |
            ConvertTo-Html -Fragment -Property Namespace, Pod, Reason, Message -PreContent "<h2>Pending Pods</h2>" |
            Out-String
        return "<p><strong>⚠️ Total Pending Pods Found:</strong> $totalPods</p>" + $htmlTable
    }

    if ($Text) {
        Write-ToReport "`n[⏳ Pending Pods]`n"
        Write-ToReport "⚠️ Total Pending Pods Found: $totalPods"
        $tableString = $tableData |
            Format-Table Namespace, Pod, Reason, Message -AutoSize | Out-String
        Write-ToReport $tableString
        return
    }

    $currentPage = 0
    $totalPages = [math]::Ceiling($totalPods / $PageSize)

    do {
        Clear-Host
        Write-Host "`n[⏳ Pending Pods - Page $($currentPage + 1) of $totalPages]" -ForegroundColor Cyan

        if ($currentPage -eq 0) {
            Write-SpeechBubble -msg @(
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
            ) -color "Cyan" -icon "🤖" -lastColor "Red" -delay 50
        }

        $paged = $tableData | Select-Object -Skip ($currentPage * $PageSize) -First $PageSize
        if ($paged) {
            $paged | Format-Table Namespace, Pod, Reason, Message -AutoSize | Out-Host
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
        [switch]$Html,
        [switch]$Json,
        [switch]$ExcludeNamespaces,
        [object]$KubeData
    )

    if (-not $Text -and -not $Html -and -not $Json) { Clear-Host }
    Write-Host "`n[🔴 CrashLoopBackOff Pods]" -ForegroundColor Cyan
    Write-Host -NoNewline "`n🤖 Checking for CrashLoopBackOff pods..." -ForegroundColor Yellow

    try {
        $allPods = if ($KubeData -and $KubeData.Pods) {
            $KubeData.Pods.items
        } elseif ($Namespace -ne "") {
            kubectl get pods -n $Namespace -o json | ConvertFrom-Json | Select-Object -ExpandProperty items
        } else {
            kubectl get pods --all-namespaces -o json | ConvertFrom-Json | Select-Object -ExpandProperty items
        }
    } catch {
        Write-Host "`r🤖 ❌ Error retrieving pod data: $_" -ForegroundColor Red
        if ($Text -and -not $Html) {
            Write-ToReport "`n[🔴 CrashLoopBackOff Pods]`n❌ Error retrieving pod data: $_"
        }
        if ($Html) { return "<p><strong>❌ Error retrieving pod data.</strong></p>" }
        if ($Json) { return @{ Error = "$_" } }
        return
    }

    if ($Namespace) {
        $allPods = $allPods | Where-Object { $_.metadata.namespace -eq $Namespace }
    }

    if ($ExcludeNamespaces) {
        $allPods = Exclude-Namespaces -items $allPods
    }

    $crashPods = @()
    foreach ($pod in $allPods) {
        if ($pod.status.containerStatuses) {
            $crashed = $pod.status.containerStatuses | Where-Object {
                $_.state -and $_.state.waiting -and $_.state.waiting.reason -eq "CrashLoopBackOff"
            }

            if ($crashed) {
                $restartTotal = ($crashed | Measure-Object -Property restartCount -Sum).Sum
                $crashPods += [PSCustomObject]@{
                    Namespace = $pod.metadata.namespace
                    Pod       = $pod.metadata.name
                    Restarts  = $restartTotal
                    Status    = "🔴 CrashLoopBackOff"
                }
            }
        }
    }

    $totalPods = $crashPods.Count

    if ($totalPods -eq 0) {
        Write-Host "`r🤖 ✅ No CrashLoopBackOff pods found." -ForegroundColor Green
        if ($Html) { return "<p><strong>✅ No CrashLoopBackOff pods found.</strong></p>" }
        if ($Json) { return @{ Total = 0; Items = @() } }
        if ($Text -and -not $Html) {
            Write-ToReport "`n[🔴 CrashLoopBackOff Pods]`n✅ No CrashLoopBackOff pods found."
        }
        if (-not $Text -and -not $Html -and -not $Json) {
            Read-Host "🤖 Press Enter to return to the menu"
        }
        return
    }

    Write-Host "`r🤖 ✅ Pods fetched. ($totalPods CrashLoopBackOff pods detected)" -ForegroundColor Green

    if ($Json) {
        return @{ Total = $crashPods.Count; Items = $crashPods }
    }

    if ($Html) {
        $htmlTable = $crashPods |
            ConvertTo-Html -Fragment -Property Namespace, Pod, Restarts, Status |
            Out-String
        return "<p><strong>⚠️ Total CrashLoopBackOff Pods Found:</strong> $totalPods</p>$htmlTable"
    }

    if ($Text) {
        Write-ToReport "`n[🔴 CrashLoopBackOff Pods]`n⚠️ Total CrashLoopBackOff Pods Found: $totalPods"
        $tableString = $crashPods | Format-Table Namespace, Pod, Restarts, Status -AutoSize | Out-String
        Write-ToReport $tableString
        return
    }

    $currentPage = 0
    $totalPages = [math]::Ceiling($totalPods / $PageSize)

    do {
        Clear-Host
        Write-Host "`n[🔴 CrashLoopBackOff Pods - Page $($currentPage + 1) of $totalPages]" -ForegroundColor Cyan

        if ($currentPage -eq 0) {
            $msg = @(
                "🤖 CrashLoopBackOff occurs when a pod continuously crashes.",
                "",
                "📌 This check identifies pods that keep restarting due to failures.",
                "   - Common causes: misconfigurations, missing dependencies, or insufficient resources.",
                "   - Investigate pod logs: 'kubectl logs <pod-name> -n <namespace>'",
                "   - Describe the pod: 'kubectl describe pod <pod-name>'",
                "",
                "⚠️ Total CrashLoopBackOff Pods Found: $totalPods"
            )
            Write-SpeechBubble -msg $msg -color "Cyan" -icon "🤖" -lastColor "Red" -delay 50
        }

        $paged = $crashPods | Select-Object -Skip ($currentPage * $PageSize) -First $PageSize
        if ($paged) {
            $paged | Format-Table Namespace, Pod, Restarts, Status -AutoSize | Out-Host
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
        [switch]$Json,
        [switch]$ExcludeNamespaces,
        [object]$KubeData
    )

    if (-not $Text -and -not $Html -and -not $Json) { Clear-Host }
    Write-Host "`n[🐞 Leftover Debug Pods]" -ForegroundColor Cyan
    Write-Host -NoNewline "`n🤖 Fetching Pod Data..." -ForegroundColor Yellow

    try {
        $podItems = if ($KubeData -and $KubeData.Pods) {
            $KubeData.Pods.items
        } elseif ($Namespace) {
            kubectl get pods -n $Namespace -o json | ConvertFrom-Json | Select-Object -ExpandProperty items
        } else {
            kubectl get pods --all-namespaces -o json | ConvertFrom-Json | Select-Object -ExpandProperty items
        }
    } catch {
        Write-Host "`r🤖 ❌ Error retrieving pod data: $_" -ForegroundColor Red
        if ($Text -and -not $Html) {
            Write-ToReport "`n[🐞 Leftover Debug Pods]`n❌ Error retrieving pod data: $_"
        }
        if ($Html) { return "<p><strong>❌ Error retrieving pod data.</strong></p>" }
        if ($Json) { return @{ Error = "$_" } }
        return
    }

    if ($Namespace) {
        $podItems = $podItems | Where-Object { $_.metadata.namespace -eq $Namespace }
    }

    if ($ExcludeNamespaces) {
        $podItems = Exclude-Namespaces -items $podItems
    }

    $debugPods = $podItems | Where-Object { $_.metadata.name -match "debugger" }
    $totalPods = $debugPods.Count

    if ($totalPods -eq 0) {
        Write-Host "`r🤖 ✅ No leftover debug pods detected." -ForegroundColor Green
        if ($Html) { return "<p><strong>✅ No leftover debug pods detected.</strong></p>" }
        if ($Json) { return @{ Total = 0; Items = @() } }
        if ($Text -and -not $Html) {
            Write-ToReport "`n[🐞 Leftover Debug Pods]`n✅ No leftover debug pods detected."
        }
        if (-not $Text -and -not $Html -and -not $Json) {
            Read-Host "🤖 Press Enter to return to the menu"
        }
        return
    }

    Write-Host "`r🤖 ✅ Pods fetched. ($totalPods leftover debug pods detected)" -ForegroundColor Green

    $buildRow = {
        param($pod)
        [PSCustomObject]@{
            Namespace  = $pod.metadata.namespace
            Pod        = $pod.metadata.name
            Node       = $pod.spec.nodeName
            Status     = $pod.status.phase
            AgeMinutes = [math]::Round(((Get-Date) - [datetime]$pod.metadata.creationTimestamp).TotalMinutes, 1)
        }
    }

    $tableData = $debugPods | ForEach-Object { & $buildRow $_ }

    if ($Json) {
        return @{ Total = $totalPods; Items = $tableData }
    }

    if ($Html) {
        $htmlTable = $tableData |
            ConvertTo-Html -Fragment -Property Namespace, Pod, Node, Status, AgeMinutes |
            Out-String
        return "<p><strong>⚠️ Total Leftover Debug Pods Found:</strong> $totalPods</p>$htmlTable"
    }

    if ($Text) {
        Write-ToReport "`n[🐞 Leftover Debug Pods]`n⚠️ Total Leftover Debug Pods Found: $totalPods"
        $tableString = $tableData | Format-Table Namespace, Pod, Node, Status, AgeMinutes -AutoSize | Out-String
        Write-ToReport $tableString
        return
    }

    $currentPage = 0
    $totalPages = [math]::Ceiling($totalPods / $PageSize)

    do {
        Clear-Host
        Write-Host "`n[🐞 Leftover Debug Pods - Page $($currentPage + 1) of $totalPages]" -ForegroundColor Cyan

        if ($currentPage -eq 0) {
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
            Write-SpeechBubble -msg $msg -color "Cyan" -icon "🤖" -lastColor "Red" -delay 50
        }

        $paged = $tableData | Select-Object -Skip ($currentPage * $PageSize) -First $PageSize
        if ($paged) {
            $paged | Format-Table Namespace, Pod, Node, Status, AgeMinutes -AutoSize | Out-Host
        } else {
            Write-Host "DEBUG: No data for page $currentPage (totalPods: $totalPods)" -ForegroundColor Yellow
        }

        $newPage = Show-Pagination -currentPage $currentPage -totalPages $totalPages
        if ($newPage -eq -1) { break }
        $currentPage = $newPage
    } while ($true)
}