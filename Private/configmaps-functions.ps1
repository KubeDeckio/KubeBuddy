function Check-OrphanedConfigMaps {
    param(
        [int]$PageSize = 10,
        [switch]$Html,
        [switch]$ExcludeNamespaces,
        [switch]$Json,
        [object]$KubeData
    )

    if (-not $Text -and -not $Html -and -not $Json) { Clear-Host }
    Write-Host "`n[📜 Orphaned ConfigMaps]" -ForegroundColor Cyan
    Write-Host -NoNewline "`n🤖 Fetching ConfigMaps..." -ForegroundColor Yellow

    $excludedConfigMapPatterns = @(
        "^sh\.helm\.release\.v1\.",
        "^kube-root-ca\.crt$"
    )

    try {
        $configMaps = if ($KubeData -and $KubeData.ConfigMaps) {
            $KubeData.ConfigMaps
        } else {
            kubectl get configmaps --all-namespaces -o json | ConvertFrom-Json | Select-Object -ExpandProperty items
        }
    } catch {
        Write-Host "`r🤖 ❌ Failed to fetch ConfigMaps: $_" -ForegroundColor Red
        return
    }

    $configMaps = $configMaps | Where-Object { $_.metadata.name -notmatch ($excludedConfigMapPatterns -join "|") }

    if ($ExcludeNamespaces) {
        $configMaps = Exclude-Namespaces -items $configMaps
    }

    Write-Host "`r🤖 ✅ ConfigMaps fetched. ($($configMaps.Count) total)" -ForegroundColor Green
    Write-Host -NoNewline "`n🤖 Checking ConfigMap usage..." -ForegroundColor Yellow

    $usedConfigMaps = [System.Collections.Generic.HashSet[string]]::new()

    $pods = if ($KubeData -and $KubeData.Pods) { $KubeData.Pods.items } else {
        kubectl get pods --all-namespaces -o json | ConvertFrom-Json | Select-Object -ExpandProperty items
    }

    $workloadTypes = @("deployments", "statefulsets", "daemonsets", "cronjobs", "jobs", "replicasets")
    $workloads = $workloadTypes | ForEach-Object {
        if ($KubeData -and $KubeData[$_]) { $KubeData[$_].items } else {
            kubectl get $_ --all-namespaces -o json 2>$null | ConvertFrom-Json | Select-Object -ExpandProperty items
        }
    }

    foreach ($resource in $pods + $workloads) {
        $resource.spec.volumes | Where-Object { $_.configMap } | ForEach-Object {
            $null = $usedConfigMaps.Add($_.configMap.name)
        }

        $containers = @()
        $containers += $resource.spec.containers
        $containers += $resource.spec.initContainers
        $containers += $resource.spec.ephemeralContainers

        foreach ($container in $containers) {
            $container.env | Where-Object { $_.valueFrom.configMapKeyRef } | ForEach-Object {
                $null = $usedConfigMaps.Add($_.valueFrom.configMapKeyRef.name)
            }
            $container.envFrom | Where-Object { $_.configMapRef } | ForEach-Object {
                $null = $usedConfigMaps.Add($_.configMapRef.name)
            }
        }
    }

    # Add references from annotations (ingresses, services)
    foreach ($annotationSet in @($KubeData.Ingresses, $KubeData.Services)) {
        $annotationSet | ForEach-Object {
            $_.metadata.annotations.Values | Where-Object { $_ -match "configMap" } | ForEach-Object {
                $null = $usedConfigMaps.Add($_)
            }
        }
    }

    # Add references from CR annotations
    if ($KubeData -and $KubeData.CRDs -and $KubeData.CustomResourcesByKind) {
        foreach ($kind in $KubeData.CustomResourcesByKind.Keys) {
            $resources = $KubeData.CustomResourcesByKind[$kind]
            foreach ($res in $resources) {
                $res.metadata.annotations.Values | Where-Object { $_ -match "configMap" } | ForEach-Object {
                    $null = $usedConfigMaps.Add($_)
                }
            }
        }
    }

    Write-Host "`r✅ ConfigMap usage checked.   " -ForegroundColor Green

    $orphaned = $configMaps | Where-Object { -not $usedConfigMaps.Contains($_.metadata.name) }


    $items = foreach ($s in $orphaned) {
        $ns = if ($s.metadata.namespace) { $s.metadata.namespace } else { "N/A" }
        $name = if ($s.metadata.name) { $s.metadata.name } else { "N/A" }
    
        [PSCustomObject]@{
            Namespace = $ns
            Type      = "📜 ConfigMap"
            Name      = $name
        }
    }

    if ($items.Count -eq 0) {
        Write-Host "🤖 ✅ No orphaned ConfigMaps found." -ForegroundColor Green
        if ($Text -and -not $Html) {
            Write-ToReport "`n[📜 Orphaned ConfigMaps]`n"
            Write-ToReport "✅ No orphaned ConfigMaps found."
        }
        if ($Html) { return "<p><strong>✅ No orphaned ConfigMaps found.</strong></p>" }
        if ($Json) { return @{ Total = 0; Items = @() } }
        if (-not $Text -and -not $Html) { Read-Host "🤖 Press Enter to return to the menu" }
        return
    }

    if ($Json) {
        return @{ Total = $items.Count; Items = $items }
    }

    if ($Html) {
        $htmlOutput = $items |
            Sort-Object Namespace, Name |
            ConvertTo-Html -Fragment -Property Namespace, Type, Name -PreContent "<h2>Orphaned ConfigMaps</h2>" |
            Out-String
        return "<p><strong>⚠️ Total Orphaned ConfigMaps Found:</strong> $($items.Count)</p>$htmlOutput"
    }

    if ($Text) {
        Write-ToReport "`n[📜 Orphaned ConfigMaps]`n"
        Write-ToReport "⚠️ Total Orphaned ConfigMaps Found: $($items.Count)"
        $tableString = $items | Format-Table Namespace, Type, Name -AutoSize | Out-String 
        Write-ToReport $tableString
        return
    }

    $total = $items.Count
    $currentPage = 0
    $totalPages = [math]::Ceiling($total / $PageSize)

    do {
        Clear-Host
        Write-Host "`n[📜 Orphaned ConfigMaps - Page $($currentPage + 1) of $totalPages]" -ForegroundColor Cyan

        if ($currentPage -eq 0) {
            $msg = @(
                "🤖 ConfigMaps store configuration data for workloads.",
                "",
                "📌 This check identifies ConfigMaps that are not referenced by:",
                "   - Pods, Deployments, StatefulSets, DaemonSets.",
                "   - CronJobs, Jobs, ReplicaSets, Services, and Custom Resources.",
                "",
                "⚠️ Orphaned ConfigMaps may be outdated and can be reviewed for cleanup.",
                "",
                "⚠️ Total Orphaned ConfigMaps Found: $total"
            )
            Write-SpeechBubble -msg $msg -color "Cyan" -icon "🤖" -lastColor "Red" -delay 50
        }

        $paged = $items | Select-Object -Skip ($currentPage * $PageSize) -First $PageSize
        $paged | Format-Table Namespace, Type, Name -AutoSize | Out-Host

        $newPage = Show-Pagination -currentPage $currentPage -totalPages $totalPages
        if ($newPage -eq -1) { break }
        $currentPage = $newPage
    } while ($true)
}

function Check-ConfigMapDuplicates {
    param(
        [object]$KubeData,
        [string]$Namespace = "",
        [int]$PageSize = 10,
        [switch]$Html,
        [switch]$Json,
        [switch]$ExcludeNamespaces
    )

    if (-not $Text -and -not $Html -and -not $Json) { Clear-Host }
    Write-Host "`n[🧬 Duplicate ConfigMap Names]" -ForegroundColor Cyan
    if (-not $Text -and -not $Html -and -not $Json) {
        Write-Host -NoNewline "`n🤖 Fetching ConfigMaps..." -ForegroundColor Yellow
    }

    try {
        $configMaps = if ($KubeData -and $KubeData.ConfigMaps) {
            $KubeData.ConfigMaps
        } else {
            $raw = if ($Namespace) {
                kubectl get configmaps -n $Namespace -o json 2>&1
            } else {
                kubectl get configmaps --all-namespaces -o json 2>&1
            }
            if ($raw -match "No resources found") {
                if ($Html) { return "<p><strong>✅ No ConfigMaps found.</strong></p>" }
                if ($Json) { return @{ Total = 0; Items = @() } }
                Write-Host "`r🤖 ✅ No ConfigMaps found." -ForegroundColor Green
                return
            }
            ($raw | ConvertFrom-Json).items
        }
    } catch {
        Write-Host "`r🤖 ❌ Error retrieving ConfigMap data: $_" -ForegroundColor Red
        if ($Html) { return "<p><strong>❌ Error retrieving ConfigMaps.</strong></p>" }
        if ($Json) { return @{ Error = "$_" } }
        return
    }

    if ($ExcludeNamespaces) {
        $configMaps = Exclude-Namespaces -items $configMaps
    }

    $results = @()
    $nameGroups = $configMaps | Group-Object -Property { $_.metadata.name } | Where-Object { $_.Count -gt 1 }

    foreach ($group in $nameGroups) {
        $namespaces = $group.Group | ForEach-Object { $_.metadata.namespace }
        $results += [PSCustomObject]@{
            Name       = $group.Name
            Namespaces = ($namespaces -join ", ")
        }
    }

    $total = $results.Count
    if ($total -eq 0) {
        if ($Html) { return "<p><strong>✅ No duplicate ConfigMap names found.</strong></p>" }
        if ($Json) { return @{ Total = 0; Items = @() } }
        Write-Host "`r🤖 ✅ No duplicate ConfigMap names found." -ForegroundColor Green
        return
    }

    Write-Host "`r🤖 ✅ Duplicate ConfigMap names found. ($total detected)" -ForegroundColor Green

    if ($Json) { return @{ Total = $total; Items = $results } }

    if ($Html) {
        $htmlTable = $results | Sort-Object -Property Name |
            ConvertTo-Html -Fragment -Property Name, Namespaces | Out-String
        return "<p><strong>⚠️ Total Duplicate ConfigMap Names:</strong> $total</p>" + $htmlTable
    }

    if ($Text) {
        Write-ToReport "`n[🧬 Duplicate ConfigMap Names]`n"
        Write-ToReport "⚠️ Total Duplicate ConfigMap Names: $total"
        $tableString = $results | Format-Table Name, Namespaces -AutoSize | Out-String
        Write-ToReport $tableString
        return
    }

    $currentPage = 0
    $totalPages = [math]::Ceiling($total / $PageSize)
    do {
        Clear-Host
        Write-Host "`n[🧬 Duplicate ConfigMap Names - Page $($currentPage + 1) of $totalPages]" -ForegroundColor Cyan

        if ($currentPage -eq 0) {
            Write-SpeechBubble -msg @(
                "🤖 ConfigMap names reused in multiple namespaces.",
                "",
                "📌 Why this matters:",
                "   - Can lead to confusion or unexpected overrides.",
                "   - Often a result of copy/paste errors or lack of naming standards.",
                "",
                "⚠️ Total Duplicate Names: $total"
            ) -color "Cyan" -icon "🧬" -lastColor "Red" -delay 50
        }

        $paged = $results | Select-Object -Skip ($currentPage * $PageSize) -First $PageSize
        if ($paged) {
            $paged | Format-Table Name, Namespaces -AutoSize | Out-Host
        }

        $newPage = Show-Pagination -currentPage $currentPage -totalPages $totalPages
        if ($newPage -eq -1) { break }
        $currentPage = $newPage
    } while ($true)
}

function Check-ConfigMapSize {
    param(
        [object]$KubeData,
        [string]$Namespace = "",
        [int]$PageSize = 10,
        [switch]$Html,
        [switch]$Json,
        [switch]$ExcludeNamespaces
    )

    if (-not $Text -and -not $Html -and -not $Json) { Clear-Host }
    Write-Host "`n[📦 Large ConfigMaps]" -ForegroundColor Cyan
    if (-not $Text -and -not $Html -and -not $Json) {
        Write-Host -NoNewline "`n🤖 Fetching ConfigMaps..." -ForegroundColor Yellow
    }

    try {
        $configMaps = if ($KubeData -and $KubeData.ConfigMaps) {
            $KubeData.ConfigMaps
        } else {
            $raw = if ($Namespace) {
                kubectl get configmaps -n $Namespace -o json 2>&1
            } else {
                kubectl get configmaps --all-namespaces -o json 2>&1
            }
            if ($raw -match "No resources found") {
                if ($Html) { return "<p><strong>✅ No ConfigMaps found.</strong></p>" }
                if ($Json) { return @{ Total = 0; Items = @() } }
                Write-Host "`r🤖 ✅ No ConfigMaps found." -ForegroundColor Green
                return
            }
            ($raw | ConvertFrom-Json).items
        }
    } catch {
        Write-Host "`r🤖 ❌ Error retrieving ConfigMap data: $_" -ForegroundColor Red
        if ($Html) { return "<p><strong>❌ Error retrieving ConfigMaps.</strong></p>" }
        if ($Json) { return @{ Error = "$_" } }
        return
    }

    if ($ExcludeNamespaces) {
        $configMaps = Exclude-Namespaces -items $configMaps
    }

    $thresholdBytes = 1048576
    $results = @()
    foreach ($cm in $configMaps) {
        $size = ($cm.data.PSObject.Properties | Measure-Object -Property Value -Sum).Sum.Length
        if ($size -gt $thresholdBytes) {
            $results += [PSCustomObject]@{
                Namespace = $cm.metadata.namespace
                Name      = $cm.metadata.name
                SizeBytes = $size
            }
        }
    }

    $total = $results.Count
    if ($total -eq 0) {
        if ($Html) { return "<p><strong>✅ No large ConfigMaps detected.</strong></p>" }
        if ($Json) { return @{ Total = 0; Items = @() } }
        Write-Host "`r🤖 ✅ No large ConfigMaps detected." -ForegroundColor Green
        return
    }

    Write-Host "`r🤖 ✅ Large ConfigMaps fetched. ($total detected)" -ForegroundColor Green

    if ($Json) { return @{ Total = $total; Items = $results } }

    if ($Html) {
        $htmlTable = $results | Sort-Object -Property SizeBytes -Descending |
            ConvertTo-Html -Fragment -Property Namespace, Name, SizeBytes | Out-String
        return "<p><strong>⚠️ Total Large ConfigMaps:</strong> $total</p>" + $htmlTable
    }

    if ($Text) {
        Write-ToReport "`n[📦 Large ConfigMaps]`n"
        Write-ToReport "⚠️ Total Large ConfigMaps: $total"
        $tableString = $results | Format-Table Namespace, Name, SizeBytes -AutoSize | Out-String
        Write-ToReport $tableString
        return
    }

    $currentPage = 0
    $totalPages = [math]::Ceiling($total / $PageSize)
    do {
        Clear-Host
        Write-Host "`n[📦 Large ConfigMaps - Page $($currentPage + 1) of $totalPages]" -ForegroundColor Cyan

        if ($currentPage -eq 0) {
            Write-SpeechBubble -msg @(
                "🤖 ConfigMaps that exceed 1 MiB in size.",
                "",
                "📌 Why this matters:",
                "   - Large ConfigMaps may contain sensitive or bloated data.",
                "   - Kubernetes has size limits for ConfigMaps.",
                "",
                "⚠️ Total Large ConfigMaps: $total"
            ) -color "Cyan" -icon "📦" -lastColor "Red" -delay 50
        }

        $paged = $results | Select-Object -Skip ($currentPage * $PageSize) -First $PageSize
        if ($paged) {
            $paged | Format-Table Namespace, Name, SizeBytes -AutoSize | Out-Host
        }

        $newPage = Show-Pagination -currentPage $currentPage -totalPages $totalPages
        if ($newPage -eq -1) { break }
        $currentPage = $newPage
    } while ($true)
}
