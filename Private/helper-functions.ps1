function Write-ToReport {
    param(
        [string]$Message
    )
    Add-Content -Path $ReportFile -Value $Message
}

function Generate-K8sTextReport {
    param (
        [string]$ReportFile = "$pwd/kubebuddy-report.txt",
        [switch]$ExcludeNamespaces,
        [object]$KubeData,
        [switch]$Aks,
        [string]$SubscriptionId,
        [string]$ResourceGroup,
        [string]$ClusterName
    )

    if (Test-Path $ReportFile) {
        Remove-Item $ReportFile -Force
    }

    Write-ToReport "--- Kubernetes Cluster Report ---"
    Write-ToReport "Timestamp: $(Get-Date)"
    Write-ToReport "---------------------------------"

    Write-ToReport "`n[🌐 Cluster Summary]`n"
    $summaryOutput = Show-ClusterSummary -Text
    Write-ToReport $summaryOutput
    Write-Host "`n🤖 Cluster Summary fetched." -ForegroundColor Green

    $yamlCheckResults = Invoke-yamlChecks -Text -KubeData $KubeData -ExcludeNamespaces:$ExcludeNamespaces

    foreach ($check in $yamlCheckResults.Items) {
        Write-ToReport "`n[$($check.ID) - $($check.Name)]"
        Write-ToReport "Section: $($check.Section)"
        Write-ToReport "Category: $($check.Category)"
        Write-ToReport "Severity: $($check.Severity)"
        Write-ToReport "Recommendation: $($check.Recommendation)"
        if ($check.URL) {
            Write-ToReport "URL: $($check.URL)"
        }

        if ($check.Total -eq 0) {
            Write-ToReport "✅ No issues detected for $($check.Name)."
        }
        else {
            Write-ToReport "⚠️ Total Issues: $($check.Total)"
            if ($check.Items) {
                $columns = $check.Items |
                ForEach-Object { $_.PSObject.Properties.Name } |
                Group-Object |
                Sort-Object Count -Descending |
                Select-Object -ExpandProperty Name -Unique

                foreach ($item in $check.Items) {
                    $lineParts = @()
                    foreach ($col in $columns) {
                        if ($item.PSObject.Properties.Name -contains $col) {
                            $lineParts += "${col}: $($item.$col)"
                        }
                    }
                    Write-ToReport ("- " + ($lineParts -join " | "))
                }
            }
        }
    }

    if ($Aks) {
        Write-ToReport -Message "`n[✅ AKS Best Practices Check]`n"
        $aksResults = Invoke-AKSBestPractices -Text -SubscriptionId $SubscriptionId -ResourceGroup $ResourceGroup -ClusterName $ClusterName -KubeData:$KubeData
        Write-Host "`n🤖 AKS Information fetched." -ForegroundColor Green

        # Write individual AKS check results
        foreach ($check in $aksResults.Items) {
            Write-ToReport -Message "`n[$($check.ID) - $($check.Name)]"
            Write-ToReport -Message "Category: $($check.Category)"
            Write-ToReport -Message "Severity: $($check.Severity)"
            Write-ToReport -Message "Recommendation: $($check.Recommendation)"
            if ($check.URL) {
                Write-ToReport -Message "URL: $($check.URL)"
            }

            if ($check.Total -eq 0) {
                Write-ToReport -Message "✅ No issues detected for $($check.Name)."
            }
            else {
                Write-ToReport -Message "⚠️ Total Issues: $($check.Total)"
                if ($check.Items) {
                    foreach ($item in $check.Items) {
                        $lineParts = @()
                        foreach ($prop in $item.PSObject.Properties.Name) {
                            $lineParts += "${prop}: $($item.$prop)"
                        }
                        Write-ToReport -Message ("- " + ($lineParts -join " | "))
                    }
                }
            }
        }

        # Write the AKS summary
        Write-ToReport -Message ($aksResults.TextOutput -join "`n")
    }

    # ----- Prometheus Metrics (Last 24h) -----
    if ($KubeData.PrometheusMetrics) {
        # Cluster-level metrics
        $cpuVals = $KubeData.PrometheusMetrics.NodeCpuUsagePercent | ForEach-Object { $_.values | ForEach-Object { [double]$_[1] } }
        $memVals = $KubeData.PrometheusMetrics.NodeMemoryUsagePercent | ForEach-Object { $_.values | ForEach-Object { [double]$_[1] } }
        $avgCpu = [math]::Round(($cpuVals | Measure-Object -Average).Average, 2)
        $avgMem = [math]::Round(($memVals | Measure-Object -Average).Average, 2)
        # Determine status (adjust thresholds as needed)
        $cpuStatus = if ($avgCpu -ge $thresholds.cpu_critical) { 'Critical' } elseif ($avgCpu -ge $thresholds.cpu_warning) { 'Warning' } else { 'Normal' }
        $memStatus = if ($avgMem -ge $thresholds.mem_critical) { 'Critical' } elseif ($avgMem -ge $thresholds.mem_warning) { 'Warning' } else { 'Normal' }
    
        Write-ToReport "`n[📊 Cluster Metrics]"
        Write-ToReport "Avg CPU Usage: $avgCpu% ($cpuStatus)"
        Write-ToReport "Avg Memory Usage: $avgMem% ($memStatus)"
    
        # Build series
        $cpuSeries = $KubeData.PrometheusMetrics.NodeCpuUsagePercent |
        ForEach-Object { $_.values | ForEach-Object { [PSCustomObject]@{ ts = [int64]($_[0] * 1000); val = [double]$_[1] } } } |
        Group-Object ts |
        ForEach-Object { [PSCustomObject]@{ ts = $_.Name; val = [math]::Round(($_.Group | Measure-Object val -Average).Average, 2) } } |
        Sort-Object ts
        $memSeries = $KubeData.PrometheusMetrics.NodeMemoryUsagePercent |
        ForEach-Object { $_.values | ForEach-Object { [PSCustomObject]@{ ts = [int64]($_[0] * 1000); val = [double]$_[1] } } } |
        Group-Object ts |
        ForEach-Object { [PSCustomObject]@{ ts = $_.Name; val = [math]::Round(($_.Group | Measure-Object val -Average).Average, 2) } } |
        Sort-Object ts
    
        Write-ToReport "`nCPU Time Series (timestamp : value%)"
        foreach ($pt in $cpuSeries) { Write-ToReport "  $($pt.ts) : $($pt.val)" }
        Write-ToReport "`nMemory Time Series (timestamp : value%)"
        foreach ($pt in $memSeries) { Write-ToReport "  $($pt.ts) : $($pt.val)" }
    
        # Node-level metrics
        Write-ToReport "`n[📊 Node Metrics]"
        foreach ($node in $KubeData.Nodes.items) {
            $n = $node.metadata.name
            $c = ($KubeData.PrometheusMetrics.NodeCpuUsagePercent | Where-Object { $_.metric.instance -match $n }).values | ForEach-Object { [double]$_[1] }
            $m = ($KubeData.PrometheusMetrics.NodeMemoryUsagePercent | Where-Object { $_.metric.instance -match $n }).values | ForEach-Object { [double]$_[1] }
            $d = ($KubeData.PrometheusMetrics.NodeDiskUsagePercent | Where-Object { $_.metric.instance -match $n }).values | ForEach-Object { [double]$_[1] }
            $avgC = if ($c) { [math]::Round(($c | Measure-Object -Average).Average, 2) } else { 'N/A' }
            $avgM = if ($m) { [math]::Round(($m | Measure-Object -Average).Average, 2) } else { 'N/A' }
            $avgD = if ($d) { [math]::Round(($d | Measure-Object -Average).Average, 2) } else { 'N/A' }
            Write-ToReport "Node: $n - CPU: $avgC% | Mem: $avgM% | Disk: $avgD%"
        }
    }

    $score = Get-ClusterHealthScore -Checks $yamlCheckResults.Items
    Write-ToReport "`n🩺 Cluster Health Score: $score / 100"
}

function Get-KubeBuddyThresholds {
    param([switch]$Silent)

    $configPath = "$HOME/.kube/kubebuddy-config.yaml"

    if (Test-Path $configPath) {
        try {
            $config = Get-Content -Raw $configPath | ConvertFrom-Yaml
            return @{
                cpu_warning             = $config.thresholds.cpu_warning ?? 50
                cpu_critical            = $config.thresholds.cpu_critical ?? 75
                mem_warning             = $config.thresholds.mem_warning ?? 50
                mem_critical            = $config.thresholds.mem_critical ?? 75
                restarts_warning        = $config.thresholds.restarts_warning ?? 3
                restarts_critical       = $config.thresholds.restarts_critical ?? 5
                pod_age_warning         = $config.thresholds.pod_age_warning ?? 15
                pod_age_critical        = $config.thresholds.pod_age_critical ?? 40
                stuck_job_hours         = $config.thresholds.stuck_job_hours ?? 2
                failed_job_hours        = $config.thresholds.failed_job_hours ?? 2
                event_errors_warning    = $config.thresholds.event_errors_warning ?? 10
                event_errors_critical   = $config.thresholds.event_errors_critical ?? 20
                event_warnings_warning  = $config.thresholds.event_warnings_warning ?? 50
                event_warnings_critical = $config.thresholds.event_warnings_critical ?? 100
                excluded_checks         = $config.excluded_checks ?? @()
                trusted_registries      = $config.trusted_registries ?? @("mcr.microsoft.com/")
            }
        }
        catch {
            if (-not $Silent) {
                Write-Host "`n❌ Failed to parse config. Using defaults..." -ForegroundColor Red
            }
        }
    }

    return @{
        cpu_warning             = 50
        cpu_critical            = 75
        mem_warning             = 50
        mem_critical            = 75
        disk_warning            = 60
        disk_critical           = 80
        restarts_warning        = 3
        restarts_critical       = 5
        pod_age_warning         = 15
        pod_age_critical        = 40
        stuck_job_hours         = 2
        failed_job_hours        = 2
        event_errors_warning    = 10
        event_errors_critical   = 20
        event_warnings_warning  = 50
        event_warnings_critical = 100
        excluded_checks         = @()
        trusted_registries      = @("mcr.microsoft.com/")
    }
}

function Get-ExcludedNamespaces {
    $config = Get-KubeBuddyThresholds -Silent
    if ($config -and $config.ContainsKey("excluded_namespaces")) {
        return $config["excluded_namespaces"]
    }

    return @(
        "kube-system", "kube-public", "kube-node-lease",
        "local-path-storage", "kube-flannel",
        "tigera-operator", "calico-system", "coredns", "aks-istio-system", "gatekeeper-system"
    )
}

function Exclude-Namespaces {
    param([array]$items)

    $excludedNamespaces = Get-ExcludedNamespaces
    $excludedSet = $excludedNamespaces | ForEach-Object { $_.ToLowerInvariant() }

    return $items | Where-Object {
        if ($_ -is [string]) {
            $_.ToLowerInvariant() -notin $excludedSet
        }
        elseif ($_.metadata) {
            $ns = if ($_.metadata.namespace) {
                $_.metadata.namespace
            }
            elseif ($_.metadata.name) {
                $_.metadata.name
            }
            else {
                $null
            }

            $ns -and $ns.ToLowerInvariant() -notin $excludedSet
        }
        else {
            $true
        }
    }
}

function Show-Pagination {
    param(
        [int]$currentPage,
        [int]$totalPages
    )

    Write-Host "`nPage $($currentPage + 1) of $totalPages"

    $options = @()
    if ($currentPage -lt ($totalPages - 1)) { $options += "N = Next" }
    if ($currentPage -gt 0) { $options += "P = Previous" }
    $options += "C = Continue"

    # Ensure 'P' does not appear on the first page
    if ($currentPage -eq 0) { $options = $options -notmatch "P = Previous" }

    # Ensure 'N' does not appear on the last page
    if ($currentPage -eq ($totalPages - 1)) { $options = $options -notmatch "N = Next" }

    # Display available options
    Write-Host ($options -join ", ") -ForegroundColor Yellow

    do {
        $paginationInput = Read-Host "Enter your choice"
    } while ($paginationInput -notmatch "^[NnPpCc]$" -or 
             ($paginationInput -match "^[Nn]$" -and $currentPage -eq ($totalPages - 1)) -or 
             ($paginationInput -match "^[Pp]$" -and $currentPage -eq 0))

    if ($paginationInput -match "^[Nn]$") { return $currentPage + 1 }
    elseif ($paginationInput -match "^[Pp]$") { return $currentPage - 1 }
    elseif ($paginationInput -match "^[Cc]$") { return -1 }  # Exit pagination
}

# Function to detect if running in any container
function Test-IsContainer {
    if ((Test-Path "/.dockerenv") -or (Test-Path "/run/.containerenv")) {
        return $true
    }

    try {
        $cgroup = Get-Content "/proc/1/cgroup" -ErrorAction SilentlyContinue
        if ($cgroup -match "docker|kubepods|crio|containerd") {
            return $true
        }
    }
    catch {}

    if ($env:container) { return $true }

    return $false
}

function Resolve-NodeMetrics {
    param (
        [string]$NodeName,
        [array]$Metrics
    )
    # Write-Host "Debug: NodeName = $NodeName"
    # Write-Host "Debug: Metrics instances = $($Metrics | ForEach-Object { $_.metric.instance } | Sort-Object -Unique)"
    $filtered = $Metrics | Where-Object {
        $instanceHost = ($_.metric.instance -split ":")[0]
        $instanceHostShort = $instanceHost -replace '\.internal\.cloudapp\.net$', ''
        # Write-Host "Debug: Comparing instanceHostShort=$instanceHostShort to NodeName=$NodeName"
        $instanceHostShort -eq $NodeName
    }
    # Write-Host "Debug: Filtered metrics count = $($filtered.Count)"
    # # Write-Host "Debug: Raw disk values for $NodeName :"
    # $diskMetrics.values | ForEach-Object { Write-Host "  $_" }

    return $filtered
}