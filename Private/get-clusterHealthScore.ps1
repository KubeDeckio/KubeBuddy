function Get-ClusterHealthScore {
    param (
        [array]$Checks
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

    $totalWeight = 0
    $failedWeight = 0

    foreach ($check in $Checks) {
        $id = $check.Id
        if ($weights.ContainsKey($id)) {
            $weight = $weights[$id]
            $totalWeight += $weight
            if ($check.Status -ne 'Passed') {
                $failedWeight += $weight
            }
        }
    }

    if ($totalWeight -eq 0) { return 0 }

    $score = 100 - (($failedWeight / $totalWeight) * 100)
    return [math]::Round($score, 1)
}
