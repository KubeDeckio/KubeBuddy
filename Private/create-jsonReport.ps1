function Create-jsonReport {
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
            ClusterSummary           = Show-ClusterSummary -Json -KubeData $KubeData
            NodeConditions           = Show-NodeConditions -Json -KubeData $KubeData
            NodeResourceUsage        = Show-NodeResourceUsage -Json -KubeData $KubeData
            EmptyNamespaces          = Show-EmptyNamespaces -Json -KubeData $KubeData
            DaemonSetIssues          = Show-DaemonSetIssues -Json -KubeData $KubeData
            HighRestarts             = Show-PodsWithHighRestarts -Json -KubeData $KubeData
            LongRunningPods          = Show-LongRunningPods -Json -KubeData $KubeData
            FailedPods               = Show-FailedPods -Json -KubeData $KubeData
            CrashLoopBackOffPods     = Show-CrashLoopBackOffPods -Json -KubeData $KubeData
            PendingPods              = Show-PendingPods -Json -KubeData $KubeData
            DebugPods                = Show-LeftoverDebugPods -Json -KubeData $KubeData
            StuckJobs                = Show-StuckJobs -Json -KubeData $KubeData
            FailedJobs               = Show-FailedJobs -Json -KubeData $KubeData
            ServicesWithoutEndpoints = Show-ServicesWithoutEndpoints -Json -KubeData $KubeData
            PublicServices           = Check-PubliclyAccessibleServices -Json -KubeData $KubeData
            UnusedPVCs               = Show-UnusedPVCs -Json -KubeData $KubeData
            OrphanedConfigMaps       = Check-OrphanedConfigMaps -Json -KubeData $KubeData
            OrphanedSecrets          = Check-OrphanedSecrets -Json -KubeData $KubeData
            RBACMisconfig            = Check-RBACMisconfigurations -Json -KubeData $KubeData
            RBACOverexposure         = Check-RBACOverexposure -Json -KubeData $KubeData
            PodsRunningAsRoot        = Check-PodsRunningAsRoot -Json -KubeData $KubeData
            PrivilegedContainers     = Check-PrivilegedContainers -Json -KubeData $KubeData
            HostPidAndNet            = Check-HostPidAndNetwork -Json -KubeData $KubeData
            KubeEvents               = Show-KubeEvents -Json -KubeData $KubeData
        }
    }

    if ($aks -and $KubeData.AksCluster) {
        $results.metadata.aks = $KubeData.AksCluster
        $results.checks.AKSBestPractices = Invoke-AKSBestPractices -Json -KubeData $KubeData
    }

    $results | ConvertTo-Json -Depth 10 | Set-Content -Encoding UTF8 $OutputPath
}
