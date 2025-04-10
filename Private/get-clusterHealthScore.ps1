function Get-ClusterHealthScore {
    param (
        [object]$Checks
    )

    $weights = @{
        "nodeConditions"           = 8
        "nodeResources"            = 8
        "emptyNamespace"           = 1
        "resourceQuotas"           = 2
        "namespaceLimitRanges"     = 2
        "daemonSetIssues"          = 2
        "HPA"                      = 1
        "missingResourceLimits"    = 3
        "PDB"                      = 2
        "missingProbes"            = 4
        "podsRestart"              = 3
        "podLongRunning"           = 2
        "podFail"                  = 3
        "podPending"               = 3
        "crashloop"                = 3
        "leftoverDebug"            = 1
        "stuckJobs"                = 2
        "jobFail"                  = 3
        "servicesWithoutEndpoints" = 2
        "publicServices"           = 4
        "unmountedPV"              = 1
        "rbacMisconfig"            = 3
        "rbacOverexposure"         = 4
        "orphanedRoles"            = 1
        "orphanedServiceAccounts"  = 1
        "orphanedConfigMaps"       = 1
        "orphanedSecrets"          = 2
        "podsRoot"                 = 3
        "privilegedContainers"     = 4
        "hostPidNet"               = 3
        "eventSummary"             = 2
        "deploymentIssues"         = 3
        "statefulSetIssues"        = 2
        "ingressHealth"            = 2
    }

    $score = 100

    foreach ($checkName in $Checks.Keys) {
        if (-not $weights.ContainsKey($checkName)) { 
            Write-Host "Skipping $checkName (no weight defined)" -ForegroundColor Yellow
            continue 
        }
        $weight = $weights[$checkName]
        $check = $Checks[$checkName]
        $deduction = 0

        if ($check -is [string]) {
            $rows = $check | Select-String -Pattern "<tr>.*?<td>.*?</td>.*?</tr>" -AllMatches
            $headerRow = if ($rows) { $rows.Matches | Where-Object { $_.Value -match "<th>" } } else { $null }
            $dataRows = if ($rows) { $rows.Matches | Where-Object { $_.Value -notmatch "<th>" } } else { @() }
            $total = if ($dataRows) { $dataRows.Count } else { 1 }

            if ($checkName -eq "nodeConditions" -and $check -match '<p(?:>|.*?>.*?)<strong>[✅⚠️].*?Not Ready Nodes.*?</strong>\s*(\d+)</p>') {
                $issues = [int]$matches[1]
                $total = if ($rows) { $rows.Matches.Count } else { 1 }
                $deduction = ($issues / $total) * $weight
                if ($deduction -gt $weight) { $deduction = $weight }
            }
            elseif ($checkName -eq "nodeResources" -and $check -match '<p(?:>|.*?>.*?)<strong>[✅⚠️].*?Resource Warnings.*?</strong>\s*(\d+)</p>') {
                $issues = [int]$matches[1]
                $total = if ($rows) { $rows.Matches.Count * 3 } else { 1 }  # 3 resources per node
                $deduction = ($issues / $total) * $weight
                if ($deduction -gt $weight) { $deduction = $weight }
            }
            else {
                $issues = $dataRows.Count
                $deduction = ($issues / $total) * $weight
                if ($deduction -gt $weight) { $deduction = $weight }
            }
        }
        else {
            if ($checkName -eq "nodeConditions" -and $check.NotReady -is [int]) {
                $total = if ($check.Total -gt 0) { $check.Total } else { 1 }
                $deduction = ($check.NotReady / $total) * $weight
                if ($deduction -gt $weight) { $deduction = $weight }
            }
            elseif ($checkName -eq "nodeResources" -and $check.Warnings -is [int]) {
                $total = if ($check.Total -gt 0) { $check.Total * 3 } else { 1 }
                $deduction = ($check.Warnings / $total) * $weight
                if ($deduction -gt $weight) { $deduction = $weight }
            }
            elseif ($checkName -eq "emptyNamespace" -and $check.TotalEmptyNamespaces -is [int]) {
                $issues = $check.TotalEmptyNamespaces
                $total = if ($issues -gt 0) { $issues } else { 1 }
                $deduction = ($issues / $total) * $weight
                if ($deduction -gt $weight) { $deduction = $weight }
            }
            elseif ($checkName -eq "eventSummary" -and $check.Events) {
                $warnings = ($check.Events | Where-Object { $_.Type -eq "Warning" }).Count
                $errors = ($check.Events | Where-Object { $_.Type -eq "Error" }).Count
                $totalIssues = $warnings + $errors
                $total = if ($totalIssues -gt 0) { $totalIssues } else { 1 }
                $deduction = ($totalIssues / $total) * $weight
                if ($deduction -gt $weight) { $deduction = $weight }
            }
            else {
                $total = if ($check.Total -is [int] -and $check.Total -gt 0) { $check.Total } else { 1 }
                $issues = if ($check.Items -is [array]) { $check.Items.Count } 
                         elseif ($check.Items -and $check.Items.PSObject.Properties) { 1 }
                         else { 0 }
                $deduction = ($issues / $total) * $weight
                if ($deduction -gt $weight) { $deduction = $weight }
            }
        }

        $score -= $deduction
    }

    if ($score -lt 0) { $score = 0 }
    if ($score -gt 100) { $score = 100 }

    return [math]::Round($score, 1)
}