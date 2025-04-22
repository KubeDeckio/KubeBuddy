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

    $score = Get-ClusterHealthScore -Checks $yamlCheckResults.Items
    Write-ToReport "`n🩺 Cluster Health Score: $score / 100"
}

function Get-KubeBuddyThresholds {
    param(
        [switch]$Silent  # Suppress output when set
    )

    $configPath = "$HOME/.kube/kubebuddy-config.yaml"

    $defaults = @{
        thresholds = @{
            cpu_warning             = 50
            cpu_critical            = 75
            mem_warning             = 50
            mem_critical            = 75
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
        }
        trusted_registries = @(
            "mcr.microsoft.com/"
        )
    }

    if (Test-Path $configPath) {
        try {
            $configContent = Get-Content -Raw $configPath | ConvertFrom-Yaml
            if (-not $configContent) {
                if (-not $Silent) {
                    Write-Host "`n⚠️ Config file is empty or invalid. Using defaults..." -ForegroundColor Yellow
                }
                return $defaults
            }

            $thresholds = $configContent.thresholds
            $registries = $configContent.trusted_registries

            return @{
                thresholds        = if ($thresholds) { $thresholds } else { $defaults.thresholds }
                trusted_registries = if ($registries) { $registries } else { $defaults.trusted_registries }
            }
        }
        catch {
            if (-not $Silent) {
                Write-Host "`n❌ Failed to parse config file. Using defaults..." -ForegroundColor Red
            }
            return $defaults
        }
    }
    else {
        if (-not $Silent) {
            Write-Host "`n⚠️ No config found. Using default thresholds and registries..." -ForegroundColor Yellow
        }
        return $defaults
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
        "tigera-operator", "calico-system", "coredns", "aks-istio-system"
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