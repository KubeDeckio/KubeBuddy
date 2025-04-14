function Write-ToReport {
    param(
        [string]$Message
    )
    # if ($Global:Report) {
    Add-Content -Path $ReportFile -Value $Message
    # }
}

function Build-ChecksFromReport {
    param([string]$ReportFile)

    $reportLines = Get-Content $ReportFile
    $checks = @{}

    # Parse NodeConditions
    $notReadyLine = $reportLines | Where-Object { $_ -match 'Not Ready Nodes.*:\s*(\d+)' }
    if ($notReadyLine -match '(\d+)') {
        $checks["nodeConditions"] = @{ Total = 4; NotReady = [int]$matches[1] }
    }

    # Parse NodeResourceUsage
    $resourceWarningLine = $reportLines | Where-Object { $_ -match 'Total Resource Warnings.*:\s*(\d+)' }
    if ($resourceWarningLine -match '(\d+)') {
        $checks["nodeResources"] = @{ Total = 4; Warnings = [int]$matches[1] }
    }

    $sectionPatterns = @{
        "missingProbes"           = 'Missing Health Probes'
        "missingResourceLimits"   = 'Missing Resource Limits'
        "daemonSetIssues"         = 'DaemonSets Not Fully Running'
        "emptyNamespace"          = 'Empty Namespaces'
        "namespaceLimitRanges"    = 'Missing LimitRanges'
        "resourceQuotas"          = 'Missing or Weak ResourceQuotas'
        "HPA"                     = 'HorizontalPodAutoscalers'
        "PDB"                     = 'PodDisruptionBudget Coverage Check'
        "podsRestart"             = 'Pods With High Restarts'
        "podLongRunning"          = 'Long Running Pods'
        "podFail"                 = 'Failed Pods'
        "podPending"              = 'Pending Pods'
        "crashloop"               = 'CrashLoopBackOff Pods'
        "leftoverDebug"           = 'Leftover Debug Pods'
        "stuckJobs"               = 'Stuck Jobs'
        "jobFail"                 = 'Failed Jobs'
        "servicesWithoutEndpoints"= 'Services Without Endpoints'
        "publicServices"          = 'Publicly Accessible Services'
        "ingressHealth"           = 'Ingress Health'
        "unmountedPV"             = 'Unused PVCs'
        "rbacMisconfig"           = 'RBAC Misconfigurations'
        "rbacOverexposure"        = 'RBAC Overexposure'
        "orphanedRoles"           = 'Unused Roles & ClusterRoles'
        "orphanedServiceAccounts" = 'Orphaned ServiceAccounts'
        "orphanedConfigMaps"      = 'Orphaned ConfigMaps'
        "orphanedSecrets"         = 'Orphaned Secrets'
        "podsRoot"                = 'Pods Running as Root'
        "privilegedContainers"    = 'Privileged Containers'
        "hostPidNet"              = 'Pods with hostPID / hostNetwork'
        "deploymentIssues"        = 'Deployment Issues'
        "statefulSetIssues"       = 'StatefulSet Issues'
        "eventSummary"            = 'Kubernetes Warnings'
    }

    foreach ($key in $sectionPatterns.Keys) {
        $pattern = [regex]::Escape($sectionPatterns[$key])
        $sectionIndex = $reportLines | ForEach-Object { if ($_ -match "$pattern") { $reportLines.IndexOf($_) } } | Select-Object -First 1
        if ($null -ne $sectionIndex) {
            $nextSectionIndex = ($reportLines | ForEach-Object { if ($_.StartsWith('[') -and $reportLines.IndexOf($_) -gt $sectionIndex) { $reportLines.IndexOf($_) } } | Select-Object -First 1) ?? $reportLines.Count
            $sectionContent = $reportLines[$sectionIndex..($nextSectionIndex - 1)]
            $totalLine = $sectionContent | Where-Object { $_ -match '⚠️\s*Total.*:\s*(\d+)' } | Select-Object -Last 1
            if ($totalLine -match '(\d+)') {
                $checks[$key] = @{ Total = [int]$matches[1]; Items = @(1..$matches[1]) }
            }
            elseif ($sectionContent | Where-Object { $_ -match '✅' }) {
                $checks[$key] = @{ Total = 1; Items = @() }
            }
        }
    }

    return $checks
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

    # Checks with camelCase keys
    $checks = @{}

    $checks["nodeConditions"] = Show-NodeConditions -KubeData:$KubeData
    $checks["nodeResources"] = Show-NodeResourceUsage -KubeData:$KubeData
    Write-Host "`n🤖 Node Information fetched.   " -ForegroundColor Green

    $checks["emptyNamespace"] = Show-EmptyNamespaces -ExcludeNamespaces:$ExcludeNamespaces -KubeData:$KubeData
    $checks["resourceQuotas"] = Check-ResourceQuotas -ExcludeNamespaces:$ExcludeNamespaces -KubeData:$KubeData
    $checks["namespaceLimitRanges"] = Check-NamespaceLimitRanges -ExcludeNamespaces:$ExcludeNamespaces -KubeData:$KubeData
    Write-Host "`n🤖 Namespace Information fetched.   " -ForegroundColor Green

    $checks["daemonSetIssues"] = Show-DaemonSetIssues -ExcludeNamespaces:$ExcludeNamespaces -KubeData:$KubeData
    $checks["deploymentIssues"] = Check-DeploymentIssues -ExcludeNamespaces:$ExcludeNamespaces -KubeData:$KubeData
    $checks["statefulSetIssues"] = Check-StatefulSetIssues -ExcludeNamespaces:$ExcludeNamespaces -KubeData:$KubeData
    $checks["HPA"] = Check-HPAStatus -ExcludeNamespaces:$ExcludeNamespaces -KubeData:$KubeData
    $checks["missingResourceLimits"] = Check-MissingResourceLimits -ExcludeNamespaces:$ExcludeNamespaces -KubeData:$KubeData
    $checks["PDB"] = Check-PodDisruptionBudgets -ExcludeNamespaces:$ExcludeNamespaces -KubeData:$KubeData
    $checks["missingProbes"] = Check-MissingHealthProbes -ExcludeNamespaces:$ExcludeNamespaces -KubeData:$KubeData
    Write-Host "`n🤖 Workload Information fetched.   " -ForegroundColor Green

    $checks["podsRestart"] = Show-PodsWithHighRestarts -ExcludeNamespaces:$ExcludeNamespaces -KubeData:$KubeData
    $checks["podLongRunning"] = Show-LongRunningPods -ExcludeNamespaces:$ExcludeNamespaces -KubeData:$KubeData
    $checks["podFail"] = Show-FailedPods -ExcludeNamespaces:$ExcludeNamespaces -KubeData:$KubeData
    $checks["podPending"] = Show-PendingPods -ExcludeNamespaces:$ExcludeNamespaces -KubeData:$KubeData
    $checks["crashloop"] = Show-CrashLoopBackOffPods -ExcludeNamespaces:$ExcludeNamespaces -KubeData:$KubeData
    $checks["leftoverDebug"] = Show-LeftoverDebugPods -ExcludeNamespaces:$ExcludeNamespaces -KubeData:$KubeData
    Write-Host "`n🤖 Pod Information fetched.   " -ForegroundColor Green

    $checks["stuckJobs"] = Show-StuckJobs -ExcludeNamespaces:$ExcludeNamespaces -KubeData:$KubeData
    $checks["jobFail"] = Show-FailedJobs -ExcludeNamespaces:$ExcludeNamespaces -KubeData:$KubeData
    Write-Host "`n🤖 Job Information fetched.   " -ForegroundColor Green

    $checks["servicesWithoutEndpoints"] = Show-ServicesWithoutEndpoints -ExcludeNamespaces:$ExcludeNamespaces -KubeData:$KubeData
    $checks["publicServices"] = Check-PubliclyAccessibleServices -ExcludeNamespaces:$ExcludeNamespaces -KubeData:$KubeData
    $checks["ingressHealth"] = Check-IngressHealth -ExcludeNamespaces:$ExcludeNamespaces -KubeData:$KubeData
    Write-Host "`n🤖 Service Information fetched.   " -ForegroundColor Green

    $checks["unmountedPV"] = Show-UnusedPVCs -ExcludeNamespaces:$ExcludeNamespaces -KubeData:$KubeData
    Write-Host "`n🤖 Storage Information fetched.   " -ForegroundColor Green

    $checks["rbacMisconfig"] = Check-RBACMisconfigurations -ExcludeNamespaces:$ExcludeNamespaces -KubeData:$KubeData
    $checks["rbacOverexposure"] = Check-RBACOverexposure -ExcludeNamespaces:$ExcludeNamespaces -KubeData:$KubeData
    $checks["orphanedRoles"] = Check-OrphanedRoles -ExcludeNamespaces:$ExcludeNamespaces -KubeData:$KubeData
    $checks["orphanedServiceAccounts"] = Check-OrphanedServiceAccounts -ExcludeNamespaces:$ExcludeNamespaces -KubeData:$KubeData
    $checks["orphanedConfigMaps"] = Check-OrphanedConfigMaps -ExcludeNamespaces:$ExcludeNamespaces -KubeData:$KubeData
    $checks["orphanedSecrets"] = Check-OrphanedSecrets -ExcludeNamespaces:$ExcludeNamespaces -KubeData:$KubeData
    $checks["podsRoot"] = Check-PodsRunningAsRoot -ExcludeNamespaces:$ExcludeNamespaces -KubeData:$KubeData
    $checks["privilegedContainers"] = Check-PrivilegedContainers -ExcludeNamespaces:$ExcludeNamespaces -KubeData:$KubeData
    $checks["hostPidNet"] = Check-HostPidAndNetwork -ExcludeNamespaces:$ExcludeNamespaces -KubeData:$KubeData
    Write-Host "`n🤖 Security Information fetched.   " -ForegroundColor Green

    $checks["eventSummary"] = Show-KubeEvents -KubeData:$KubeData
    Write-Host "`n🤖 Kube Events fetched.   " -ForegroundColor Green

    if ($aks) {
        Invoke-AKSBestPractices -SubscriptionId $SubscriptionId -ResourceGroup $ResourceGroup -ClusterName $ClusterName -KubeData:$KubeData
        Write-Host "`n🤖 AKS Information fetched.   " -ForegroundColor Green
    }

    # Cluster score
    $parsedChecks = Build-ChecksFromReport -ReportFile $ReportFile
    $clusterScore = Get-ClusterHealthScore -Checks $parsedChecks
    Write-ToReport "`n🩺 Cluster Health Score: $clusterScore / 100"      

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
    } catch {}

    if ($env:container) { return $true }

    return $false
}