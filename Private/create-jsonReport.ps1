function Create-JsonReport {
    param (
        [string]$OutputPath,
        [object]$KubeData,
        [switch]$aks
    )

    $clusterName = (kubectl config current-context)
    $versionInfo = kubectl version -o json | ConvertFrom-Json
    $k8sVersion = $versionInfo.serverVersion.gitVersion
    $generatedAt = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")

    $results = @{
        metadata = @{
            clusterName       = $clusterName
            kubernetesVersion = $k8sVersion
            generatedAt       = $generatedAt
        }
        checks = @{
            "nodeConditions"           = Show-NodeConditions -Json -KubeData $KubeData
            "nodeResources"            = Show-NodeResourceUsage -Json -KubeData $KubeData
            "emptyNamespace"           = Show-EmptyNamespaces -Json -KubeData $KubeData
            "resourceQuotas"           = Check-ResourceQuotas -Json -KubeData $KubeData
            "namespaceLimitRanges"     = Check-NamespaceLimitRanges -Json -KubeData $KubeData
            "daemonSetIssues"          = Show-DaemonSetIssues -Json -KubeData $KubeData
            "HPA"                      = Check-HPAStatus -Json -KubeData $KubeData
            "missingResourceLimits"    = Check-MissingResourceLimits -Json -KubeData $KubeData
            "PDB"                      = Check-PodDisruptionBudgets -Json -KubeData $KubeData
            "missingProbes"            = Check-MissingHealthProbes -Json -KubeData $KubeData
            "podsRestart"              = Show-PodsWithHighRestarts -Json -KubeData $KubeData
            "podLongRunning"           = Show-LongRunningPods -Json -KubeData $KubeData
            "podFail"                  = Show-FailedPods -Json -KubeData $KubeData
            "podPending"               = Show-PendingPods -Json -KubeData $KubeData
            "crashloop"                = Show-CrashLoopBackOffPods -Json -KubeData $KubeData
            "leftoverDebug"            = Show-LeftoverDebugPods -Json -KubeData $KubeData
            "stuckJobs"                = Show-StuckJobs -Json -KubeData $KubeData
            "jobFail"                  = Show-FailedJobs -Json -KubeData $KubeData
            "servicesWithoutEndpoints" = Show-ServicesWithoutEndpoints -Json -KubeData $KubeData
            "publicServices"           = Check-PubliclyAccessibleServices -Json -KubeData $KubeData
            "unmountedPV"              = Show-UnusedPVCs -Json -KubeData $KubeData
            "rbacMisconfig"            = Check-RBACMisconfigurations -Json -KubeData $KubeData
            "rbacOverexposure"         = Check-RBACOverexposure -Json -KubeData $KubeData
            "orphanedRoles"            = Check-OrphanedRoles -Json -KubeData $KubeData
            "orphanedServiceAccounts"  = Check-OrphanedServiceAccounts -Json -KubeData $KubeData
            "orphanedConfigMaps"       = Check-OrphanedConfigMaps -Json -KubeData $KubeData
            "orphanedSecrets"          = Check-OrphanedSecrets -Json -KubeData $KubeData
            "podsRoot"                 = Check-PodsRunningAsRoot -Json -KubeData $KubeData
            "privilegedContainers"     = Check-PrivilegedContainers -Json -KubeData $KubeData
            "hostPidNet"               = Check-HostPidAndNetwork -Json -KubeData $KubeData
            "eventSummary"             = Show-KubeEvents -Json -KubeData $KubeData
            "deploymentIssues"         = Check-DeploymentIssues -Json -KubeData $KubeData
            "statefulSetIssues"        = Check-StatefulSetIssues -Json -KubeData $KubeData
            "ingressHealth"            = Check-IngressHealth -Json -KubeData $KubeData
        }
    }

    if ($aks -and $KubeData.AksCluster) {
        $results.metadata.aks = $KubeData.AksCluster
        $results.checks.AKSBestPractices = Invoke-AKSBestPractices -Json -KubeData $KubeData
    }

    $results.metadata.score = Get-ClusterHealthScore -Checks $results.checks

    $results | ConvertTo-Json -Depth 10 | Set-Content -Encoding UTF8 $OutputPath
}