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
        }
        else {
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

function Check-DeploymentIssues {
    param(
        [object]$KubeData,
        [int]$PageSize = 10,
        [switch]$Html,
        [switch]$Json,
        [switch]$ExcludeNamespaces
    )

    if (-not $Html -and -not $Json -and -not $Global:MakeReport) { Clear-Host }
    Write-Host "`n[🚀 Deployment Issues]" -ForegroundColor Cyan
    Write-Host -NoNewline "`n🤖 Checking deployments..." -ForegroundColor Yellow

    $deployments = if ($KubeData -and $KubeData.Deployments) {
        $KubeData.Deployments
    } else {
        kubectl get deployments --all-namespaces -o json | ConvertFrom-Json | Select-Object -ExpandProperty items
    }

    if ($ExcludeNamespaces) {
        $deployments = Exclude-Namespaces -items $deployments
    }

    $issues = @()

    foreach ($d in $deployments) {
        $ns = $d.metadata.namespace
        $name = $d.metadata.name
        $available = $d.status.availableReplicas
        $desired = $d.spec.replicas

        if (-not $available -or $available -lt $desired) {
            $issues += [pscustomobject]@{
                Namespace  = $ns
                Deployment = $name
                Available  = $available
                Desired    = $desired
                Issue      = "⚠️ Insufficient replicas"
            }
        }
    }

    $total = $issues.Count

    if ($total -eq 0) {
        Write-Host "`r🤖 ✅ All deployments are healthy." -ForegroundColor Green
        if (-not $Global:MakeReport -and -not $Html -and -not $Json) {
            Read-Host "🤖 Press Enter to return to the menu"
        }
        if ($Json) { return @{ Total = 0; Items = @() } }
        if ($Html) { return "<p><strong>✅ All deployments are healthy.</strong></p>" }
        if ($Global:MakeReport) {
            Write-ToReport "`n[🚀 Deployment Issues]`n✅ All deployments are healthy."
        }
        return
    }    

    Write-Host "`r🤖 ✅ Deployment scan complete. ($total with issues)" -ForegroundColor Green

    if ($Json) { return @{ Total = $total; Items = $issues } }

    if ($Html) {
        return "<p><strong>⚠️ Deployment Issues: $total</strong></p>" +
            ($issues | Sort-Object Namespace |
            ConvertTo-Html -Fragment -Property Namespace, Deployment, Available, Desired, Issue | Out-String)
    }

    if ($Global:MakeReport) {
        Write-ToReport "`n[🚀 Deployment Issues]`n⚠️ Total: $total"
        $issues | Format-Table Namespace, Deployment, Available, Desired, Issue -AutoSize |
            Out-String | Write-ToReport
        return
    }

    # CLI paginated view
    $currentPage = 0
    $totalPages = [math]::Ceiling($total / $PageSize)

    do {
        Clear-Host
        Write-Host "`n[🚀 Deployment Issues - Page $($currentPage + 1) of $totalPages]" -ForegroundColor Cyan

        if ($currentPage -eq 0) {
            Write-SpeechBubble -msg @(
                "🤖 Deployments manage stateless apps.",
                "",
                "📌 These are missing available replicas:",
                "   - Check rollout progress or pod failures.",
                "   - Use: kubectl describe deploy <name> -n <ns>",
                "",
                "⚠️ Total Deployment Issues: $total"
            ) -color "Cyan" -icon "🤖" -lastColor "Red" -delay 50
        }

        $start = $currentPage * $PageSize
        $slice = $issues | Select-Object -Skip $start -First $PageSize

        if ($slice.Count -gt 0) {
            $slice | Format-Table Namespace, Deployment, Available, Desired, Issue -AutoSize | Out-Host
        }

        $newPage = Show-Pagination -currentPage $currentPage -totalPages $totalPages
        if ($newPage -eq -1) { break }
        $currentPage = $newPage
    } while ($true)
}

function Check-StatefulSetIssues {
    param(
        [object]$KubeData,
        [int]$PageSize = 10,
        [switch]$Html,
        [switch]$Json,
        [switch]$ExcludeNamespaces
    )

    if (-not $Html -and -not $Json -and -not $Global:MakeReport) { Clear-Host }
    Write-Host "`n[🏗️ StatefulSet Issues]" -ForegroundColor Cyan
    Write-Host -NoNewline "`n🤖 Checking StatefulSets..." -ForegroundColor Yellow

    $statefulsets = if ($KubeData -and $KubeData.StatefulSets) {
        $KubeData.StatefulSets
    } else {
        kubectl get statefulsets --all-namespaces -o json | ConvertFrom-Json | Select-Object -ExpandProperty items
    }

    if ($ExcludeNamespaces) {
        $statefulsets = Exclude-Namespaces -items $statefulsets
    }

    $results = @()

    foreach ($s in $statefulsets) {
        $name = $s.metadata.name
        $ns = $s.metadata.namespace
        $ready = $s.status.readyReplicas
        $desired = $s.spec.replicas

        if (-not $ready -or $ready -lt $desired) {
            $results += [pscustomobject]@{
                Namespace   = $ns
                StatefulSet = $name
                Ready       = $ready
                Desired     = $desired
                Issue       = "⚠️ Incomplete rollout"
            }
        }
    }

    $total = $results.Count

    if ($total -eq 0) {
        Write-Host "`r🤖 ✅ All StatefulSets are healthy." -ForegroundColor Green
        if (-not $Global:MakeReport -and -not $Html -and -not $Json) {
            Read-Host "🤖 Press Enter to return to the menu"
        }
        if ($Json) { return @{ Total = 0; Items = @() } }
        if ($Html) { return "<p><strong>✅ All StatefulSets are healthy.</strong></p>" }
        if ($Global:MakeReport) {
            Write-ToReport "`n[🏗️ StatefulSet Issues]`n✅ All StatefulSets are healthy."
        }
        return
    }    

    Write-Host "`r🤖 ✅ StatefulSets checked. ($total with issues)" -ForegroundColor Green

    if ($Json) { return @{ Total = $total; Items = $results } }

    if ($Html) {
        return "<p><strong>⚠️ StatefulSet Issues: $total</strong></p>" +
            ($results | Sort-Object Namespace |
            ConvertTo-Html -Fragment -Property Namespace, StatefulSet, Ready, Desired, Issue | Out-String)
    }

    if ($Global:MakeReport) {
        Write-ToReport "`n[🏗️ StatefulSet Issues]`n⚠️ Total: $total"
        $results | Format-Table Namespace, StatefulSet, Ready, Desired, Issue -AutoSize |
            Out-String | Write-ToReport
        return
    }

    $currentPage = 0
    $totalPages = [math]::Ceiling($total / $PageSize)

    do {
        Clear-Host
        Write-Host "`n[🏗️ StatefulSet Issues - Page $($currentPage + 1) of $totalPages]" -ForegroundColor Cyan

        if ($currentPage -eq 0) {
            Write-SpeechBubble -msg @(
                "🤖 StatefulSets manage ordered, persistent workloads.",
                "",
                "📌 These sets have missing ready pods:",
                "   - Check pod logs and PVC binding.",
                "   - Use: kubectl describe sts <name> -n <ns>",
                "",
                "⚠️ Total StatefulSet Issues: $total"
            ) -color "Cyan" -icon "🤖" -lastColor "Red" -delay 50
        }

        $start = $currentPage * $PageSize
        $slice = $results | Select-Object -Skip $start -First $PageSize

        if ($slice.Count -gt 0) {
            $slice | Format-Table Namespace, StatefulSet, Ready, Desired, Issue -AutoSize | Out-Host
        }

        $newPage = Show-Pagination -currentPage $currentPage -totalPages $totalPages
        if ($newPage -eq -1) { break }
        $currentPage = $newPage
    } while ($true)
}

function Check-HPAStatus {
    param(
        [object]$KubeData,
        [string]$Namespace = "",
        [int]$PageSize = 10,
        [switch]$Html,
        [switch]$Json,
        [switch]$ExcludeNamespaces
    )

    if (-not $Global:MakeReport -and -not $Html -and -not $Json) { Clear-Host }
    Write-Host "`n[📉 HorizontalPodAutoscaler Status Check]" -ForegroundColor Cyan
    if (-not $Global:MakeReport -and -not $Html -and -not $Json) {
        Write-Host -NoNewline "`n🤖 Checking HPA status..." -ForegroundColor Yellow
    }

    try {
        $hpas = if ($KubeData -and $KubeData.HorizontalPodAutoscalers) {
            $KubeData.HorizontalPodAutoscalers
        }        
        else {
            $raw = kubectl get hpa --all-namespaces -o json 2>&1
            if ($raw -match "No resources found") { @() } else { ($raw | ConvertFrom-Json).items }
        }

        $deployments = if ($KubeData -and $KubeData.Deployments) {
            $KubeData.Deployments
        }
        else {
            (kubectl get deployments --all-namespaces -o json | ConvertFrom-Json).items
        }

        $statefulsets = if ($KubeData -and $KubeData.StatefulSets) {
            $KubeData.StatefulSets
        }
        else {
            (kubectl get statefulsets --all-namespaces -o json | ConvertFrom-Json).items
        }
    }
    catch {
        Write-Host "`r🤖 ❌ Error fetching HPA or workload data: $_" -ForegroundColor Red
        if ($Html) { return "<p><strong>❌ Error fetching HPA data.</strong></p>" }
        if ($Json) { return @{ Error = "$_" } }
        return
    }

    if ($ExcludeNamespaces) {
        $hpas = Exclude-Namespaces -items $hpas
        $deployments = Exclude-Namespaces -items $deployments
        $statefulsets = Exclude-Namespaces -items $statefulsets
    }

    $results = @()

    foreach ($hpa in $hpas) {
        $ns = $hpa.metadata.namespace
        $name = $hpa.metadata.name
        $targetKind = $hpa.spec.scaleTargetRef.kind
        $targetName = $hpa.spec.scaleTargetRef.name
        $targetRef = "$targetKind/$targetName"

        $status = $hpa.status
        $current = $status.currentReplicas
        $desired = $status.desiredReplicas

        $conditions = @{}
        if ($status.conditions) {
            foreach ($c in $status.conditions) {
                $conditions[$c.type] = $c
            }
        }

        $targetFound = $false

        if ($targetKind -eq "Deployment") {
            $targetFound = ($deployments | Where-Object {
                    $_.metadata.namespace -eq $ns -and $_.metadata.name -eq $targetName
                }).Count -gt 0
        }
        elseif ($targetKind -eq "StatefulSet") {
            $targetFound = ($statefulsets | Where-Object {
                    $_.metadata.namespace -eq $ns -and $_.metadata.name -eq $targetName
                }).Count -gt 0
        }
       

        if (-not $targetFound) {
            $results += [PSCustomObject]@{
                Namespace = $ns
                HPA       = $name
                Target    = $targetRef
                Issue     = "❌ Target not found"
            }
            continue
        }

        if (-not $status.currentMetrics -or $status.currentMetrics.Count -eq 0) {
            $results += [PSCustomObject]@{
                Namespace = $ns
                HPA       = $name
                Target    = $targetRef
                Issue     = "❌ No metrics available"
            }
        }

        if ($conditions["AbleToScale"] -and $conditions["AbleToScale"].status -eq "False") {
            $msg = $conditions["AbleToScale"].reason
            $results += [PSCustomObject]@{
                Namespace = $ns
                HPA       = $name
                Target    = $targetRef
                Issue     = "⚠️ Scaling disabled: $msg"
            }
        }

        if ($conditions["ScalingActive"] -and $conditions["ScalingActive"].status -eq "False") {
            $msg = $conditions["ScalingActive"].reason
            $results += [PSCustomObject]@{
                Namespace = $ns
                HPA       = $name
                Target    = $targetRef
                Issue     = "⚠️ Scaling not active: $msg"
            }
        }

        if ($desired -eq 0 -and $current -eq 0) {
            $results += [PSCustomObject]@{
                Namespace = $ns
                HPA       = $name
                Target    = $targetRef
                Issue     = "⚠️ HPA inactive (0 replicas)"
            }
        }

        if ($desired -ne $current) {
            $results += [PSCustomObject]@{
                Namespace = $ns
                HPA       = $name
                Target    = $targetRef
                Issue     = "⚠️ Scaling mismatch: $current → $desired"
            }
        }
    }

    $total = $results.Count
    if ($total -eq 0) {
        if ($Html) { return "<p><strong>✅ All HPAs are valid, scaled, and reporting metrics.</strong></p>" }
        if ($Json) { return @{ Total = 0; Items = @() } }
        Write-Host "`r🤖 ✅ All HPAs are valid, scaled, and reporting metrics." -ForegroundColor Green
        if (-not $Global:MakeReport -and -not $Html -and -not $json) {
            Read-Host "🤖 Press Enter to return to the menu"
        }
        return
    }

    Write-Host "`r🤖 ✅ HPA issues found. ($total total)" -ForegroundColor Green

    if ($Json) { return @{ Total = $total; Items = $results } }

    if ($Html) {
        $htmlTable = $results | Sort-Object Namespace |
        ConvertTo-Html -Fragment -Property Namespace, HPA, Target, Issue | Out-String
        return "<p><strong>⚠️ HPA Issues:</strong> $total</p>" + $htmlTable
    }

    if ($Global:MakeReport) {
        Write-ToReport "`n[📉 HorizontalPodAutoscaler Status Check]`n"
        Write-ToReport "⚠️ Total Issues: $total"
        $tableString = $results | Format-Table Namespace, HPA, Target, Issue -AutoSize | Out-String
        Write-ToReport $tableString
        return
    }

    $currentPage = 0
    $totalPages = [math]::Ceiling($total / $PageSize)
    do {
        Clear-Host
        Write-Host "`n[📉 HPA Issues - Page $($currentPage + 1) of $totalPages]" -ForegroundColor Cyan

        if ($currentPage -eq 0) {
            Write-SpeechBubble -msg @(
                "🤖 HorizontalPodAutoscalers are responsible for dynamic workload scaling.",
                "",
                "📌 This check reports:",
                "   - HPAs with broken or missing targets",
                "   - HPAs with no metrics or stuck replicas",
                "   - HPAs disabled due to scaling errors",
                "",
                "⚠️ Total Issues: $total"
            ) -color "Cyan" -icon "📉" -lastColor "Red" -delay 50
        }

        $paged = $results | Select-Object -Skip ($currentPage * $PageSize) -First $PageSize
        if ($paged) {
            $paged | Format-Table Namespace, HPA, Target, Issue -AutoSize | Out-Host
        }

        $newPage = Show-Pagination -currentPage $currentPage -totalPages $totalPages
        if ($newPage -eq -1) { break }
        $currentPage = $newPage
    } while ($true)
}

function Check-MissingResourceLimits {
    param(
        [object]$KubeData,
        [int]$PageSize = 10,
        [switch]$Html,
        [switch]$Json,
        [switch]$ExcludeNamespaces
    )

    if (-not $Global:MakeReport -and -not $Html -and -not $Json) { Clear-Host }
    Write-Host "`n[📦 Missing Resource Limits]" -ForegroundColor Cyan
    Write-Host -NoNewline "`n🤖 Scanning workloads..." -ForegroundColor Yellow

    $workloadTypes = @("deployments", "statefulsets", "daemonsets")
    $results = @()

    try {
        $items = @()
        foreach ($type in $workloadTypes) {
            $raw = if ($KubeData -and $KubeData[$type]) {
                $KubeData[$type]
            }
            else {
                kubectl get $type --all-namespaces -o json | ConvertFrom-Json | Select-Object -ExpandProperty items
            }
            $kind = ($type -replace "s$") 
            $kind = $kind.Substring(0, 1).ToUpper() + $kind.Substring(1)
            $items += $raw | ForEach-Object {
                if (-not $_.PSObject.Properties['kind']) {
                    $_ | Add-Member -NotePropertyName kind -NotePropertyValue $kind -PassThru
                }
                else {
                    $_
                }
            }                    
        }
    }
    catch {
        Write-Host "`r🤖 ❌ Failed to fetch workloads: $_" -ForegroundColor Red
        if (-not $Global:MakeReport -and -not $Html -and -not $json) {
            Read-Host "🤖 Press Enter to return to the menu"
        }
        return
    }

    if ($ExcludeNamespaces) {
        $items = Exclude-Namespaces -items $items
    }

    foreach ($w in $items) {
        $ns = $w.metadata.namespace
        $name = $w.metadata.name
        $kind = $w.kind
        $containers = @()

        if ($w.spec.template.spec.containers) {
            $containers += $w.spec.template.spec.containers
        }
        if ($w.spec.template.spec.initContainers) {
            $containers += $w.spec.template.spec.initContainers
        }

        foreach ($c in $containers) {
            $limits = $c.resources.limits
            $requests = $c.resources.requests

            $missingCpuLimit = -not $limits -or -not $limits.PSObject.Properties.Name -contains "cpu"
            $missingMemLimit = -not $limits -or -not $limits.PSObject.Properties.Name -contains "memory"
            $missingCpuReq = -not $requests -or -not $requests.PSObject.Properties.Name -contains "cpu"
            $missingMemReq = -not $requests -or -not $requests.PSObject.Properties.Name -contains "memory"
      

            $missingRequests = @()
            $missingLimits = @()

            if ($missingCpuReq) { $missingRequests += "CPU" }
            if ($missingMemReq) { $missingRequests += "Memory" }
            if ($missingCpuLimit) { $missingLimits += "CPU" }
            if ($missingMemLimit) { $missingLimits += "Memory" }

            if ($missingRequests.Count -gt 0 -or $missingLimits.Count -gt 0) {
                $results += [PSCustomObject]@{
                    Namespace       = $ns
                    Workload        = $name
                    Kind            = $kind
                    Container       = $c.name
                    MissingRequests = $missingRequests -join ", "
                    MissingLimits   = $missingLimits -join ", "
                }
            }


        }
    }

    $total = $results.Count
    Write-Host "`r🤖 ✅ Analysis complete. ($total containers without resource limits)" -ForegroundColor Green

    if ($total -eq 0) {
        if ($Html) { return "<p><strong>✅ All workloads have resource limits.</strong></p>" }
        if ($Json) { return @{ Total = 0; Items = @() } }
        if ($Global:MakeReport -and -not $Html) {
            Write-ToReport "`n[📦 Missing Resource Limits]`n✅ All workloads have limits."
        }
        if (-not $Global:MakeReport -and -not $Html) {
            Read-Host "🤖 Press Enter to return to the menu"
        }
        return
    }

    if ($Json) {
        return @{ Total = $total; Items = $results }
    }

    if ($Html) {
        $htmlOutput = $results |
        ConvertTo-Html -Fragment -Property Namespace, Kind, Workload, Container, MissingRequests, MissingLimits |
        Out-String
        return "<p><strong>⚠️ Total Containers Missing Requests and/or Limits:</strong> $total</p>$htmlOutput"
    }

    if ($Global:MakeReport) {
        Write-ToReport "`n[📦 Missing Resource Limits]`n⚠️ Total: $total"
        $tableString = $results | Format-Table Namespace, Kind, Workload, Container, Missing -AutoSize | Out-String
        Write-ToReport $tableString
        return
    }

    $currentPage = 0
    $totalPages = [math]::Ceiling($total / $PageSize)

    do {
        Clear-Host
        Write-Host "`n[📦 Missing Resource Limits - Page $($currentPage + 1) of $totalPages]" -ForegroundColor Cyan

        if ($currentPage -eq 0) {
            Write-SpeechBubble -msg @(
                "🤖 Containers without resource limits may impact cluster stability.",
                "",
                "📌 This check finds workloads missing CPU or memory limits.",
                "   - Applies to Deployments, StatefulSets, and DaemonSets.",
                "",
                "⚠️ Total affected containers: $total"
            ) -color "Cyan" -icon "📦" -lastColor "Red" -delay 50
        }

        $paged = $results | Select-Object -Skip ($currentPage * $PageSize) -First $PageSize
        $paged | Format-Table Namespace, Kind, Workload, Container, Missing -AutoSize | Out-Host

        $newPage = Show-Pagination -currentPage $currentPage -totalPages $totalPages
        if ($newPage -eq -1) { break }
        $currentPage = $newPage
    } while ($true)
}

function Check-PodDisruptionBudgets {
    param(
        [object]$KubeData,
        [string]$Namespace = "",
        [int]$PageSize = 10,
        [switch]$Html,
        [switch]$Json,
        [switch]$ExcludeNamespaces
    )

    if (-not $Global:MakeReport -and -not $Html -and -not $Json) { Clear-Host }
    Write-Host "`n[🛡️ PodDisruptionBudget Coverage Check]" -ForegroundColor Cyan
    if (-not $Global:MakeReport -and -not $Html -and -not $Json) {
        Write-Host -NoNewline "`n🤖 Checking PDB coverage of workloads..." -ForegroundColor Yellow
    }

    try {
        $pdbs = if ($KubeData -and $KubeData.PodDisruptionBudgets) {
            $KubeData.PodDisruptionBudgets
        }
        else {
            $raw = kubectl get pdb --all-namespaces -o json 2>&1
            if ($raw -match "No resources found") { @() } else { ($raw | ConvertFrom-Json).items }
        }

        $pods = if ($KubeData -and $KubeData.Pods) {
            $KubeData.Pods.items
        }
        else {
            ($Namespace) ? (kubectl get pods -n $Namespace -o json | ConvertFrom-Json).items :
                           (kubectl get pods --all-namespaces -o json | ConvertFrom-Json).items
        }

        $deployments = if ($KubeData -and $KubeData.Deployments) {
            $KubeData.Deployments
        }
        else {
            (kubectl get deployments --all-namespaces -o json | ConvertFrom-Json).items
        }

        $statefulsets = if ($KubeData -and $KubeData.StatefulSets) {
            $KubeData.StatefulSets
        }
        else {
            (kubectl get statefulsets --all-namespaces -o json | ConvertFrom-Json).items
        }


    }
    catch {
        Write-Host "`r🤖 ❌ Error fetching data: $_" -ForegroundColor Red
        if ($Html) { return "<p><strong>❌ Error fetching data.</strong></p>" }
        if ($Json) { return @{ Error = "$_" } }
        if (-not $Global:MakeReport -and -not $Html -and -not $json) {
            Read-Host "🤖 Press Enter to return to the menu"
        }
        return
    }

    if ($ExcludeNamespaces) {
        $pdbs = Exclude-Namespaces -items $pdbs
        $pods = Exclude-Namespaces -items $pods
        $deployments = Exclude-Namespaces -items $deployments
        $statefulsets = Exclude-Namespaces -items $statefulsets
    }

    $results = @()

    function IsWeakPDB($pdb) {
        if ($pdb.spec.minAvailable -eq 0) { return "⚠️ minAvailable = 0" }
        if ($pdb.spec.maxUnavailable -eq 1 -or $pdb.spec.maxUnavailable -eq "100%" -or $pdb.spec.maxUnavailable -eq "1") {
            return "⚠️ maxUnavailable = 100%"
        }
        return $null
    }

    foreach ($pdb in $pdbs) {
        $weak = IsWeakPDB $pdb
        if ($weak) {
            $results += [PSCustomObject]@{
                Namespace = $pdb.metadata.namespace
                Name      = $pdb.metadata.name
                Kind      = "PDB"
                Issue     = $weak
            }
        }

        if ($pdb.status.expectedPods -eq 0) {
            $results += [PSCustomObject]@{
                Namespace = $pdb.metadata.namespace
                Name      = $pdb.metadata.name
                Kind      = "PDB"
                Issue     = "⚠️ Matches 0 pods"
            }
        }
    }

    function MatchesSelector($labels, $selector) {
        foreach ($key in $selector.matchLabels.Keys) {
            if (-not $labels.ContainsKey($key) -or $labels[$key] -ne $selector.matchLabels[$key]) {
                return $false
            }
        }
        return $true
    }

    $allWorkloads = @()
    $allWorkloads += $deployments | Where-Object { $_ -ne $null } | ForEach-Object {
        $_ | Add-Member -NotePropertyName kind -NotePropertyValue "Deployment" -Force -PassThru
    }
    $allWorkloads += $statefulsets | Where-Object { $_ -ne $null } | ForEach-Object {
        $_ | Add-Member -NotePropertyName kind -NotePropertyValue "StatefulSet" -Force -PassThru
    }

    foreach ($workload in $allWorkloads) {
        $ns = $workload.metadata.namespace
        $name = $workload.metadata.name
        $kind = $workload.kind
        $labels = $workload.spec.template.metadata.labels

        $matched = $false
        foreach ($pdb in $pdbs | Where-Object { $_.metadata.namespace -eq $ns }) {
            if ($pdb.spec.selector -and $pdb.spec.selector.matchLabels) {
                if (MatchesSelector $labels $pdb.spec.selector) {
                    $matched = $true
                    break
                }
            }
        }

        if (-not $matched) {
            $results += [PSCustomObject]@{
                Namespace = $ns
                Name      = $name
                Kind      = $kind
                Issue     = "❌ No matching PDB"
            }
        }
    }

    $total = $results.Count
    if ($total -eq 0) {
        if ($Html) { return "<p><strong>✅ All workloads are protected by PDBs.</strong></p>" }
        if ($Json) { return @{ Total = 0; Items = @() } }
        Write-Host "`r🤖 ✅ All workloads are protected by PDBs." -ForegroundColor Green
        if (-not $Global:MakeReport -and -not $Html -and -not $json) {
            Read-Host "🤖 Press Enter to return to the menu"
        }
        return
    }

    Write-Host "`r🤖 ✅ PDB issues found. ($total uncovered workloads or weak PDBs)" -ForegroundColor Green

    if ($Json) { return @{ Total = $total; Items = $results } }

    if ($Html) {
        $htmlTable = $results | Sort-Object Namespace |
        ConvertTo-Html -Fragment -Property Namespace, Name, Kind, Issue | Out-String
        return "<p><strong>⚠️ PDB Issues Detected:</strong> $total</p>" + $htmlTable
    }

    if ($Global:MakeReport) {
        Write-ToReport "`n[🛡️ PodDisruptionBudget Coverage Check]`n"
        Write-ToReport "⚠️ Total Issues: $total"
        $tableString = $results | Format-Table Namespace, Name, Kind, Issue -AutoSize | Out-String
        Write-ToReport $tableString
        return
    }

    $currentPage = 0
    $totalPages = [math]::Ceiling($total / $PageSize)
    do {
        Clear-Host
        Write-Host "`n[🛡️ PDB Coverage Issues - Page $($currentPage + 1) of $totalPages]" -ForegroundColor Cyan

        if ($currentPage -eq 0) {
            Write-SpeechBubble -msg @(
                "🤖 These workloads aren't protected by a valid PDB.",
                "",
                "📌 This check reports:",
                "   - Workloads without a matching PDB",
                "   - PDBs that match no pods",
                "   - PDBs with ineffective settings (0 minAvailable, 100% maxUnavailable)",
                "",
                "⚠️ Total Issues: $total"
            ) -color "Cyan" -icon "🛡️" -lastColor "Red" -delay 50
        }

        $paged = $results | Select-Object -Skip ($currentPage * $PageSize) -First $PageSize
        if ($paged) {
            $paged | Format-Table Namespace, Name, Kind, Issue -AutoSize | Out-Host
        }

        $newPage = Show-Pagination -currentPage $currentPage -totalPages $totalPages
        if ($newPage -eq -1) { break }
        $currentPage = $newPage
    } while ($true)
}

function Check-MissingHealthProbes {
    param(
        [object]$KubeData,
        [int]$PageSize = 10,
        [switch]$Html,
        [switch]$Json,
        [switch]$ExcludeNamespaces
    )

    if (-not $Global:MakeReport -and -not $Html -and -not $Json) { Clear-Host }
    Write-Host "`n[🔎 Missing Health Probes]" -ForegroundColor Cyan
    Write-Host -NoNewline "`n🤖 Scanning workloads for missing readiness and liveness probes..." -ForegroundColor Yellow

    $results = @()
    $workloadTypes = @("deployments", "statefulsets", "daemonsets")

    try {
        $items = @()
        foreach ($type in $workloadTypes) {
            $raw = if ($KubeData -and $KubeData[$type]) {
                $KubeData[$type]
            }
            else {
                kubectl get $type --all-namespaces -o json | ConvertFrom-Json | Select-Object -ExpandProperty items
            }

            $kind = ($type -replace "s$") 
            $kind = $kind.Substring(0, 1).ToUpper() + $kind.Substring(1)
            $items += $raw | ForEach-Object {
                if (-not $_.PSObject.Properties['kind']) {
                    $_ | Add-Member -NotePropertyName kind -NotePropertyValue $kind -PassThru
                }
                else {
                    $_
                }
            }                     
        }
    }
    catch {
        Write-Host "`r🤖 ❌ Failed to fetch workload data: $_" -ForegroundColor Red
        if (-not $Global:MakeReport -and -not $Html -and -not $json) {
            Read-Host "🤖 Press Enter to return to the menu"
        }
        return
    }

    if ($ExcludeNamespaces) {
        $items = Exclude-Namespaces -items $items
    }

    foreach ($w in $items) {
        $ns = $w.metadata.namespace
        $name = $w.metadata.name
        $kind = $w.kind
        $containers = $w.spec.template.spec.containers

        foreach ($c in $containers) {
            $missing = @()
            if (-not $c.readinessProbe) { $missing += "readiness" }
            if (-not $c.livenessProbe) { $missing += "liveness" }

            if ($missing.Count -gt 0) {
                $results += [PSCustomObject]@{
                    Namespace = $ns
                    Workload  = $name
                    Kind      = $kind
                    Container = $c.name
                    Missing   = $missing -join ", "
                }
            }
        }
    }

    $total = $results.Count
    Write-Host "`r🤖 ✅ Probe analysis complete. ($total issues found)" -ForegroundColor Green

    if ($total -eq 0) {
        if ($Html) { return "<p><strong>✅ All containers have health probes defined.</strong></p>" }
        if ($Json) { return @{ Total = 0; Items = @() } }
        if ($Global:MakeReport -and -not $Html) {
            Write-ToReport "`n[🔎 Missing Health Probes]`n✅ All containers have health probes."
        }
        if (-not $Global:MakeReport -and -not $Html) {
            Read-Host "🤖 Press Enter to return to the menu"
        }
        return
    }

    if ($Json) {
        return @{ Total = $total; Items = $results }
    }

    if ($Html) {
        $htmlOutput = $results |
        ConvertTo-Html -Fragment -Property Namespace, Kind, Workload, Container, Missing |
        Out-String
        return "<p><strong>⚠️ Containers Missing Probes:</strong> $total</p>" + $htmlOutput
    }

    if ($Global:MakeReport) {
        Write-ToReport "`n[🔎 Missing Health Probes]`n⚠️ Total: $total"
        $tableString = $results | Format-Table Namespace, Kind, Workload, Container, Missing -AutoSize | Out-String
        Write-ToReport $tableString
        return
    }

    $currentPage = 0
    $totalPages = [math]::Ceiling($total / $PageSize)

    do {
        Clear-Host
        Write-Host "`n[🔎 Missing Probes - Page $($currentPage + 1) of $totalPages]" -ForegroundColor Cyan

        if ($currentPage -eq 0) {
            Write-SpeechBubble -msg @(
                "🤖 These containers are missing health probes.",
                "",
                "📌 Probes help Kubernetes detect unresponsive or unhealthy apps.",
                "   - Readiness: pod is ready to serve traffic",
                "   - Liveness: pod is still alive",
                "",
                "⚠️ Total affected containers: $total"
            ) -color "Cyan" -icon "🔎" -lastColor "Red" -delay 50
        }

        $paged = $results | Select-Object -Skip ($currentPage * $PageSize) -First $PageSize
        $paged | Format-Table Namespace, Kind, Workload, Container, Missing -AutoSize | Out-Host

        $newPage = Show-Pagination -currentPage $currentPage -totalPages $totalPages
        if ($newPage -eq -1) { break }
        $currentPage = $newPage
    } while ($true)
}
