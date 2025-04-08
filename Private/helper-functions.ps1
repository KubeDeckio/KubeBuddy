function Write-ToReport {
    param(
        [string]$Message
    )
    # if ($Global:Report) {
    Add-Content -Path $ReportFile -Value $Message
    # }
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
    $Global:MakeReport = $true
    
    if (Test-Path $ReportFile) {
        Remove-Item $ReportFile -Force
    }
    
    Write-ToReport "--- Kubernetes Cluster Report ---"
    Write-ToReport "Timestamp: $(Get-Date)"
    Write-ToReport "---------------------------------"

    Write-ToReport "`n[🌐 Cluster Summary]`n"
    Show-ClusterSummary
    Write-Host "`n🤖 Cluster Summary fetched.   " -ForegroundColor Green

    Show-NodeConditions -KubeData:$KubeData
    Show-NodeResourceUsage -KubeData:$KubeData
    Write-Host "`n🤖 Node Information fetched.   " -ForegroundColor Green

    Show-EmptyNamespaces -ExcludeNamespaces:$ExcludeNamespaces -KubeData:$KubeData
    Check-ResourceQuotas -ExcludeNamespaces:$ExcludeNamespaces -KubeData:$KubeData
    Check-NamespaceLimitRanges -ExcludeNamespaces:$ExcludeNamespaces -KubeData:$KubeData
    Write-Host "`n🤖 Namespace Information fetched.   " -ForegroundColor Green

    Show-DaemonSetIssues -ExcludeNamespaces:$ExcludeNamespaces -KubeData:$KubeData
    Check-DeploymentIssues -ExcludeNamespaces:$ExcludeNamespaces -KubeData:$KubeData
    Check-StatefulSetIssues -ExcludeNamespaces:$ExcludeNamespaces -KubeData:$KubeData
    Check-HPAStatus -ExcludeNamespaces:$ExcludeNamespaces -KubeData:$KubeData
    Check-MissingResourceLimits -ExcludeNamespaces:$ExcludeNamespaces -KubeData:$KubeData
    Check-PodDisruptionBudgets -ExcludeNamespaces:$ExcludeNamespaces -KubeData:$KubeData
    Check-MissingHealthProbes -ExcludeNamespaces:$ExcludeNamespaces -KubeData:$KubeData
    Write-Host "`n🤖 Workload Information fetched.   " -ForegroundColor Green 

    Show-PodsWithHighRestarts -ExcludeNamespaces:$ExcludeNamespaces -KubeData:$KubeData
    Show-LongRunningPods -ExcludeNamespaces:$ExcludeNamespaces -KubeData:$KubeData
    Show-FailedPods -ExcludeNamespaces:$ExcludeNamespaces -KubeData:$KubeData
    Show-PendingPods -ExcludeNamespaces:$ExcludeNamespaces -KubeData:$KubeData
    Show-CrashLoopBackOffPods -ExcludeNamespaces:$ExcludeNamespaces -KubeData:$KubeData
    Show-LeftoverDebugPods -ExcludeNamespaces:$ExcludeNamespaces -KubeData:$KubeData
    Write-Host "`n🤖 Pod Information fetched.   " -ForegroundColor Green

    Show-StuckJobs -ExcludeNamespaces:$ExcludeNamespaces -KubeData:$KubeData
    Show-FailedJobs -ExcludeNamespaces:$ExcludeNamespaces -KubeData:$KubeData
    Write-Host "`n🤖 Job Information fetched.   " -ForegroundColor Green

    Show-ServicesWithoutEndpoints -ExcludeNamespaces:$ExcludeNamespaces -KubeData:$KubeData
    Check-PubliclyAccessibleServices -ExcludeNamespaces:$ExcludeNamespaces -KubeData:$KubeData
    Check-IngressHealth -ExcludeNamespaces:$ExcludeNamespaces -KubeData:$KubeData
    Write-Host "`n🤖 Service Information fetched.   " -ForegroundColor Green

    Show-UnusedPVCs -ExcludeNamespaces:$ExcludeNamespaces -KubeData:$KubeData
    Write-Host "`n🤖 Storage Information fetched.   " -ForegroundColor Green

    # Security Checks
    Check-RBACMisconfigurations -ExcludeNamespaces:$ExcludeNamespaces -KubeData:$KubeData
    Check-RBACOverexposure -ExcludeNamespaces:$ExcludeNamespaces -KubeData:$KubeData
    Check-OrphanedRoles -ExcludeNamespaces:$ExcludeNamespaces -KubeData:$KubeData
    Check-OrphanedServiceAccounts -ExcludeNamespaces:$ExcludeNamespaces -KubeData:$KubeData
    Check-OrphanedConfigMaps -ExcludeNamespaces:$ExcludeNamespaces -KubeData:$KubeData
    Check-OrphanedSecrets -ExcludeNamespaces:$ExcludeNamespaces -KubeData:$KubeData
    Check-PodsRunningAsRoot -ExcludeNamespaces:$ExcludeNamespaces -KubeData:$KubeData
    Check-PrivilegedContainers -ExcludeNamespaces:$ExcludeNamespaces -KubeData:$KubeData
    Check-HostPidAndNetwork -ExcludeNamespaces:$ExcludeNamespaces -KubeData:$KubeData
    Write-Host "`n🤖 Security Information fetched.   " -ForegroundColor Green

    Show-KubeEvents -KubeData:$KubeData
    Write-Host "`n🤖 Kube Events fetched.   " -ForegroundColor Green

    if ($aks) {
        Invoke-AKSBestPractices -SubscriptionId $SubscriptionId -ResourceGroup $ResourceGroup -ClusterName $ClusterName -KubeData:$KubeData
        Write-Host "`n🤖 AKS Information fetched.   " -ForegroundColor Green
    }

    $Global:MakeReport = $false
}


function Get-KubeBuddyThresholds {
    param(
        [switch]$Silent  # Suppress output when set
    )

    $configPath = "$HOME/.kube/kubebuddy-config.yaml"

    if (Test-Path $configPath) {
        try {
            # Read the YAML file and convert it to a PowerShell object
            $configContent = Get-Content -Raw $configPath | ConvertFrom-Yaml
            
            if ($configContent -and $configContent.thresholds) {
                return $configContent.thresholds
            }
            else {
                if (-not $Silent) {
                    Write-Host "`n⚠️ Config found, but missing 'thresholds' section. Using defaults..." -ForegroundColor Yellow
                }
            }
        }
        catch {
            if (-not $Silent) {
                Write-Host "`n❌ Failed to parse config file. Using defaults..." -ForegroundColor Red
            }
        }
    }
    else {
        if (-not $Silent) {
            Write-Host "`n⚠️ No config found. Using default thresholds..." -ForegroundColor Yellow
        }
    }

    # Return default thresholds if no valid config is found
    return @{
        cpu_warning       = 50
        cpu_critical      = 75
        mem_warning       = 50
        mem_critical      = 75
        restarts_warning  = 3
        restarts_critical = 5
        pod_age_warning   = 15
        pod_age_critical  = 40
        stuck_job_hours   = 2
        failed_job_hours  = 2
        event_errors_warning    = 10
        event_errors_critical   = 20
        event_warnings_warning  = 50
        event_warnings_critical = 100
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
        } elseif ($_.metadata) {
            $ns = if ($_.metadata.namespace) {
                $_.metadata.namespace
            } elseif ($_.metadata.name) {
                $_.metadata.name
            } else {
                $null
            }

            $ns -and $ns.ToLowerInvariant() -notin $excludedSet
        } else {
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