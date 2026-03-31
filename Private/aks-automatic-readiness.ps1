function Get-KubeBuddyAutomaticReadiness {
    param(
        [object[]]$YamlChecks = @(),
        [object[]]$AksChecks = @(),
        [string]$ClusterName = '',
        [string]$ActionPlanPath = '',
        [object]$AksClusterInfo = $null,
        [object]$KubeData = $null
    )

    function Get-CheckValue {
        param(
            [object]$Check,
            [string]$Name
        )

        if ($null -eq $Check) { return $null }
        if ($Check -is [hashtable] -and $Check.ContainsKey($Name)) { return $Check[$Name] }
        $prop = $Check.PSObject.Properties[$Name]
        if ($prop) { return $prop.Value }
        return $null
    }

    function Get-AutomaticReasonTitle {
        param([string]$Reason)

        switch ($Reason) {
            'host_namespace' { return 'Remove host namespace sharing' }
            'privileged' { return 'Remove privileged container usage' }
            'host_path' { return 'Replace hostPath volumes' }
            'host_ports' { return 'Remove host port bindings' }
            'capabilities' { return 'Remove unsupported Linux capabilities' }
            'seccomp' { return 'Set seccomp to RuntimeDefault or Localhost' }
            'proc_mount' { return 'Reset proc mount type to Default' }
            'sysctls' { return 'Remove disallowed sysctls' }
            'apparmor' { return 'Use supported AppArmor values' }
            'storage_csi' { return 'Migrate Azure storage classes to CSI drivers' }
            'image_tag' { return 'Use explicit image tags' }
            'resource_requests' { return 'Define container resource requests' }
            'pod_spread' { return 'Add workload spreading rules' }
            'service_selector' { return 'Use unique Service selectors' }
            'gateway_api' { return 'Plan ingress migration to Gateway API' }
            'health_probes' { return 'Add readiness and liveness probes' }
            'aks_networking' { return 'Align target cluster networking with AKS Automatic defaults' }
            'aks_platform' { return 'Review AKS Automatic platform defaults' }
            'aks_security' { return 'Align target cluster security defaults' }
            'aks_autoscaling' { return 'Adopt AKS Automatic autoscaling defaults' }
            default { return 'Review compatibility finding' }
        }
    }

    function Get-AutomaticReasonSteps {
        param([string]$Reason)

        switch ($Reason) {
            'host_namespace' { return @('Inspect Pod specs for hostNetwork, hostPID, and hostIPC usage.', 'Remove those fields or set them to false unless the workload is a trusted platform component.', 'Replace direct host access with Services or supported platform integrations where possible.') }
            'privileged' { return @('Remove securityContext.privileged: true from the affected containers.', 'Replace privileged access with narrower capabilities or a supported platform integration.', 'Redeploy and verify the workload still starts and functions correctly.') }
            'host_path' { return @('Identify why each hostPath mount is used.', 'Replace hostPath with a PVC, ConfigMap, Secret, or EmptyDir as appropriate.', 'Redeploy and confirm the workload works without direct node filesystem access.') }
            'host_ports' { return @('Remove hostPort from container port definitions.', 'Expose the workload through a Service and, if needed, an Ingress or Gateway.', 'Validate traffic reaches the workload through cluster networking instead of node-bound ports.') }
            'capabilities' { return @('Review each added Linux capability in container securityContext.capabilities.add.', 'Remove broad capabilities such as SYS_ADMIN unless a documented platform exception exists.', 'If a capability is truly required, confirm the chart or manifest can be changed at the source before migration.') }
            'seccomp' { return @('Find every seccompProfile.type set to Unconfined.', 'Change the profile to RuntimeDefault or Localhost.', 'Retest the workload under the tighter seccomp policy.') }
            'proc_mount' { return @('Locate non-default procMount usage in container securityContext.', 'Remove the override or set procMount to Default.', 'Retest any debugging or observability behavior that depended on the custom mount.') }
            'sysctls' { return @('List the sysctls defined in pod securityContext.sysctls.', 'Remove any sysctl outside the baseline allowlist.', 'Move required kernel tuning to node configuration instead of the pod spec.') }
            'apparmor' { return @('Inspect AppArmor annotations and structured appArmorProfile values.', 'Use only runtime/default or localhost/* annotations, or RuntimeDefault/Localhost structured profile types.', 'Remove unsupported AppArmor values and redeploy the workload.') }
            'storage_csi' { return @('Create replacement StorageClasses that use disk.csi.azure.com or file.csi.azure.com.', 'Migrate workloads and PVCs off the in-tree Azure Disk or Azure File classes.', 'Retire the old StorageClasses only after the replacement PVCs are bound and healthy.') }
            'image_tag' { return @('Replace latest or blank image tags with explicit, versioned tags for every affected container and init container.', 'Update the source workload manifest, Helm values, or image automation so the version is pinned at the source.', 'Redeploy and verify the workload uses the intended immutable image reference.') }
            'resource_requests' { return @('Add CPU and memory requests to every affected container.', 'Add memory limits where required by your platform standards and ensure requests are not below platform minimums.', 'Redeploy and validate scheduling and performance with the new resource values.') }
            'pod_spread' { return @('Add topologySpreadConstraints or podAntiAffinity to each replicated workload before migrating it.', 'Prefer changing the owning Deployment, StatefulSet, or Helm values instead of patching running Pods.', 'Retest scheduling with at least two replicas to confirm the new spread policy is accepted.') }
            'service_selector' { return @('Identify Services in the same namespace that select the same pod labels.', 'Consolidate duplicate Services or change selectors so each Service has a distinct ownership boundary.', 'Update the source manifest or Helm values and verify traffic still reaches the intended backend.') }
            'gateway_api' { return @('Inventory all current Ingress resources and controller-specific annotations before migration.', 'Design the target north-south path around Gateway, HTTPRoute, and supported AKS application routing options instead of assuming an NGINX Ingress controller on the destination cluster.', 'Test Gateway API routing and cutover behavior before moving production traffic.') }
            'health_probes' { return @('Add readinessProbe and livenessProbe to each affected container.', 'Use probes that reflect real application health rather than only process startup.', 'Confirm the rollout completes and the probes stay healthy under normal load.') }
            'aks_networking' { return @('Plan the target cluster with AKS Automatic-compatible networking defaults such as Azure CNI Overlay with Cilium.', 'Review dependencies on the current network plugin and policy engine.', 'Validate ingress, egress, and policy behavior in a migration environment before cutover.') }
            'aks_platform' { return @('Review the target cluster build against AKS Automatic defaults such as Azure Linux, Standard tier, and deployment safeguards.', 'Update the migration runbook so the new cluster is created with those defaults from the start.', 'Verify region, quota, and prerequisite support before creating the target cluster.') }
            'aks_security' { return @('Enable the AKS security capabilities expected on the target cluster, such as OIDC issuer, workload identity, and image cleaner where applicable.', 'Update workloads to use federated identity instead of stored credentials.', 'Validate the security features are active before moving production workloads.') }
            'aks_autoscaling' { return @('Plan the target cluster around AKS Automatic scaling defaults such as node autoprovisioning, VPA, and KEDA where relevant.', 'Review workload requests and autoscaler assumptions before migration.', 'Run a controlled workload test on the target cluster to confirm expected scaling behavior.') }
            default { return @('Review the failing shared check and identify the manifest or platform setting causing it.', 'Apply the recommended change in a non-production environment first.', 'Rerun KubeBuddy to confirm the issue no longer appears.') }
        }
    }

    function Get-AutomaticAdmissionNote {
        param(
            [string]$Behavior,
            [string]$MutationOutcome
        )

        switch ($Behavior) {
            'mutates_on_enforce' {
                if ($MutationOutcome) {
                    return "AKS Automatic may mutate this on admission: $MutationOutcome"
                }
                return 'AKS Automatic may mutate this on admission.'
            }
            'denies_on_enforce' {
                if ($MutationOutcome) {
                    return "AKS Automatic may deny this resource in enforce mode. $MutationOutcome"
                }
                return 'AKS Automatic may deny this resource in enforce mode.'
            }
            'warns_only' {
                return 'AKS Automatic surfaces this as a warning and does not auto-mutate it.'
            }
            default {
                return ''
            }
        }
    }

    function Get-ActionPhase {
        param(
            [string]$Relevance,
            [string]$Scope
        )

        if ($Scope -in @('cluster', 'platform') -or $Relevance -eq 'alignment') {
            return 'target_cluster_build'
        }
        return 'fix_before_migration'
    }

    function Get-CheckSamples {
        param(
            [object]$Check,
            [hashtable]$ResourceIndex
        )

        $items = @(Get-CheckValue -Check $Check -Name 'Items')
        if (-not $items) { return @() }

        $samples = @()
        foreach ($item in ($items | Select-Object -First 5)) {
            $resolved = Resolve-AutomaticAffectedResource -Item $item -ResourceIndex $ResourceIndex
            if ($resolved.display) {
                $samples += $resolved.display
            }
        }

        return @($samples | Where-Object { $_ } | Select-Object -Unique)
    }

    function Get-CheckAffectedResources {
        param(
            [object]$Check,
            [hashtable]$ResourceIndex
        )

        $items = @(Get-CheckValue -Check $Check -Name 'Items')
        if (-not $items) { return @() }

        $results = @()
        foreach ($item in ($items | Select-Object -First 10)) {
            $resolved = Resolve-AutomaticAffectedResource -Item $item -ResourceIndex $ResourceIndex
            if (-not $resolved.display) { continue }

            $results += [pscustomobject]@{
                namespace = [string]$resolved.namespace
                workload = [string]$resolved.topDisplay
                observedResource = [string]$resolved.sourceDisplay
                helmSource = [string]$resolved.helmDisplay
                display = [string]$resolved.display
            }
        }

        return @($results | Sort-Object namespace, workload, observedResource -Unique)
    }

    function Get-ObjectArray {
        param([object]$Value)

        if ($null -eq $Value) { return @() }
        if ($Value -is [System.Array]) { return @($Value) }
        if ($Value.PSObject.Properties['items']) { return @($Value.items) }
        return @($Value)
    }

    function Get-OwnerRef {
        param([object]$Metadata)

        if (-not $Metadata -or -not $Metadata.ownerReferences) { return $null }
        return @($Metadata.ownerReferences | Where-Object { $_.controller -eq $true } | Select-Object -First 1)[0] ?? @($Metadata.ownerReferences | Select-Object -First 1)[0]
    }

    function Get-ResourceKey {
        param(
            [string]$Kind,
            [string]$Namespace,
            [string]$Name
        )

        return ("{0}|{1}|{2}" -f $Kind.ToLowerInvariant(), $Namespace.ToLowerInvariant(), $Name.ToLowerInvariant())
    }

    function Get-MetadataValue {
        param(
            [hashtable]$MetadataMap,
            [string]$Type,
            [string[]]$Keys
        )

        if (-not $MetadataMap -or -not $MetadataMap.ContainsKey($Type)) { return '' }
        return Get-KubeBuddyArtifactLabelValue -Labels $MetadataMap[$Type] -Keys $Keys
    }

    function Get-HelmDescriptor {
        param([hashtable]$Entry)

        if (-not $Entry) { return '' }
        if (-not $Entry.helmManaged) { return '' }

        $parts = @()
        if ($Entry.helmReleaseName) {
            $parts += "release $($Entry.helmReleaseName)"
        }
        if ($Entry.helmChartName) {
            $chartText = if ($Entry.helmChartVersion) { "$($Entry.helmChartName)@$($Entry.helmChartVersion)" } else { $Entry.helmChartName }
            $parts += "chart $chartText"
        }

        if ($parts.Count -eq 0) {
            return 'Helm managed'
        }

        return "Helm: $($parts -join ', ')"
    }

    function New-AutomaticResourceIndex {
        param([object]$KubeData)

        $index = @{
            workloads = @{}
            podByName = @{}
            rsToDeployment = @{}
        }

        if (-not $KubeData) { return $index }

        foreach ($kind in @('Deployments', 'StatefulSets', 'DaemonSets', 'Jobs', 'CronJobs')) {
            foreach ($item in (Get-ObjectArray -Value $KubeData.$kind)) {
                if (-not $item -or -not $item.metadata) { continue }

                $workloadKind = switch ($kind) {
                    'Deployments' { 'Deployment' }
                    'StatefulSets' { 'StatefulSet' }
                    'DaemonSets' { 'DaemonSet' }
                    'Jobs' { 'Job' }
                    'CronJobs' { 'CronJob' }
                }

                $metadataMaps = Get-KubeBuddyMetadataMap -Metadata $item.metadata
                $templateMaps = if ($item.spec -and $item.spec.template) {
                    Get-KubeBuddyMetadataMap -Metadata $item.spec.template.metadata
                } elseif ($item.spec -and $item.spec.jobTemplate -and $item.spec.jobTemplate.spec -and $item.spec.jobTemplate.spec.template) {
                    Get-KubeBuddyMetadataMap -Metadata $item.spec.jobTemplate.spec.template.metadata
                } else {
                    @{ labels = @{}; annotations = @{} }
                }

                $labels = @{}
                $annotations = @{}
                foreach ($k in $metadataMaps.labels.Keys) { $labels[$k] = $metadataMaps.labels[$k] }
                foreach ($k in $templateMaps.labels.Keys) { if (-not $labels.ContainsKey($k)) { $labels[$k] = $templateMaps.labels[$k] } }
                foreach ($k in $metadataMaps.annotations.Keys) { $annotations[$k] = $metadataMaps.annotations[$k] }
                foreach ($k in $templateMaps.annotations.Keys) { if (-not $annotations.ContainsKey($k)) { $annotations[$k] = $templateMaps.annotations[$k] } }

                $helmChartLabel = Get-KubeBuddyArtifactLabelValue -Labels $labels -Keys @('helm.sh/chart')
                $helmManagedBy = Get-KubeBuddyArtifactLabelValue -Labels $labels -Keys @('app.kubernetes.io/managed-by')
                $helmReleaseName = if ($annotations.ContainsKey('meta.helm.sh/release-name')) { [string]$annotations['meta.helm.sh/release-name'] } else { '' }
                $helmReleaseNs = if ($annotations.ContainsKey('meta.helm.sh/release-namespace')) { [string]$annotations['meta.helm.sh/release-namespace'] } else { '' }
                $helmManaged = [bool]($helmChartLabel -or ($helmManagedBy -and $helmManagedBy.ToLowerInvariant() -eq 'helm') -or $helmReleaseName)
                $helmChartName = ''
                $helmChartVersion = ''
                if ($helmChartLabel -match '^(?<name>.+)-(?<version>v?\d[\w\.\-\+]*)$') {
                    $helmChartName = [string]$matches.name
                    $helmChartVersion = [string]$matches.version
                }
                elseif ($helmChartLabel) {
                    $helmChartName = [string]$helmChartLabel
                }

                $ns = [string]($item.metadata.namespace ?? 'cluster-wide')
                $name = [string]($item.metadata.name ?? '')
                if (-not $name) { continue }

                $entry = @{
                    kind = $workloadKind
                    namespace = $ns
                    name = $name
                    display = "$workloadKind/$name"
                    helmManaged = $helmManaged
                    helmChartName = $helmChartName
                    helmChartVersion = $helmChartVersion
                    helmReleaseName = $helmReleaseName
                    helmReleaseNamespace = if ($helmReleaseNs) { $helmReleaseNs } else { $ns }
                }
                $index.workloads[(Get-ResourceKey -Kind $workloadKind -Namespace $ns -Name $name)] = $entry
            }
        }

        foreach ($rs in (Get-ObjectArray -Value $KubeData.ReplicaSets)) {
            if (-not $rs -or -not $rs.metadata) { continue }
            $owner = Get-OwnerRef -Metadata $rs.metadata
            if (-not $owner -or [string]$owner.kind -ne 'Deployment') { continue }
            $ns = [string]($rs.metadata.namespace ?? 'default')
            $name = [string]($rs.metadata.name ?? '')
            if (-not $name) { continue }
            $index.rsToDeployment[(Get-ResourceKey -Kind 'ReplicaSet' -Namespace $ns -Name $name)] = @{
                kind = 'Deployment'
                name = [string]$owner.name
                display = "Deployment/$($owner.name)"
            }
        }

        foreach ($pod in (Get-ObjectArray -Value $KubeData.Pods)) {
            if (-not $pod -or -not $pod.metadata) { continue }
            $ns = [string]($pod.metadata.namespace ?? 'default')
            $name = [string]($pod.metadata.name ?? '')
            if (-not $name) { continue }

            $owner = Get-OwnerRef -Metadata $pod.metadata
            $topKind = 'Pod'
            $topName = $name
            $topDisplay = "Pod/$name"

            if ($owner) {
                $ownerKind = [string]$owner.kind
                $ownerName = [string]$owner.name
                if ($ownerKind -eq 'ReplicaSet') {
                    $rsKey = Get-ResourceKey -Kind 'ReplicaSet' -Namespace $ns -Name $ownerName
                    if ($index.rsToDeployment.ContainsKey($rsKey)) {
                        $deployment = $index.rsToDeployment[$rsKey]
                        $topKind = 'Deployment'
                        $topName = [string]$deployment.name
                        $topDisplay = $deployment.display
                    }
                    else {
                        $topKind = 'ReplicaSet'
                        $topName = $ownerName
                        $topDisplay = "ReplicaSet/$ownerName"
                    }
                }
                else {
                    $ownerKey = Get-ResourceKey -Kind $ownerKind -Namespace $ns -Name $ownerName
                    if ($index.workloads.ContainsKey($ownerKey)) {
                        $topKind = $index.workloads[$ownerKey].kind
                        $topName = $index.workloads[$ownerKey].name
                        $topDisplay = $index.workloads[$ownerKey].display
                    }
                    else {
                        $topKind = $ownerKind
                        $topName = $ownerName
                        $topDisplay = "$ownerKind/$ownerName"
                    }
                }
            }

            $index.podByName[("pod|{0}|{1}" -f $ns.ToLowerInvariant(), $name.ToLowerInvariant())] = @{
                namespace = $ns
                podName = $name
                podDisplay = "Pod/$name"
                topKind = $topKind
                topName = $topName
                topDisplay = $topDisplay
            }
        }

        return $index
    }

    function Resolve-AutomaticAffectedResource {
        param(
            [object]$Item,
            [hashtable]$ResourceIndex
        )

        $namespace = [string](Get-CheckValue -Check $Item -Name 'Namespace')
        if (-not $namespace -or $namespace -eq '(cluster)') { $namespace = 'cluster-wide' }

        $resourceRef = [string](Get-CheckValue -Check $Item -Name 'Resource')
        $podName = [string](Get-CheckValue -Check $Item -Name 'Pod')
        $workloadKind = ''
        $workloadName = ''

        foreach ($field in @('Deployment', 'StatefulSet', 'DaemonSet', 'Job', 'CronJob', 'Workload')) {
            $value = [string](Get-CheckValue -Check $Item -Name $field)
            if (-not $value) { continue }
            switch ($field) {
                'Deployment' { $workloadKind = 'Deployment'; $workloadName = $value }
                'StatefulSet' { $workloadKind = 'StatefulSet'; $workloadName = $value }
                'DaemonSet' { $workloadKind = 'DaemonSet'; $workloadName = $value }
                'Job' { $workloadKind = 'Job'; $workloadName = $value }
                'CronJob' { $workloadKind = 'CronJob'; $workloadName = $value }
                default {
                    if ($value -match '^(?<kind>[A-Za-z]+)/(?<name>.+)$') {
                        $workloadKind = [string]$matches.kind
                        $workloadName = [string]$matches.name
                    }
                    else {
                        $workloadName = $value
                    }
                }
            }
            if ($workloadName) { break }
        }

        if (-not $podName -and $resourceRef -match '^(pod|pods?)/(?<name>.+)$') {
            $podName = [string]$matches.name
        }
        elseif (-not $workloadName -and $resourceRef -match '^(?<kind>deployment|statefulset|daemonset|job|cronjob|replicaset|pod|storageclass|persistentvolumeclaim|persistentvolume|service|ingress|namespace|node)s?/(?<name>.+)$') {
            $kindMatch = [string]$matches.kind
            $nameMatch = [string]$matches.name
            switch ($kindMatch.ToLowerInvariant()) {
                'pod' { $podName = $nameMatch }
                default {
                    $workloadKind = (Get-Culture).TextInfo.ToTitleCase($kindMatch.ToLowerInvariant())
                    $workloadName = $nameMatch
                }
            }
        }

        $topDisplay = ''
        $sourceDisplay = ''
        $helmDisplay = ''

        if ($podName -and $ResourceIndex.podByName.ContainsKey(("pod|{0}|{1}" -f $namespace.ToLowerInvariant(), $podName.ToLowerInvariant()))) {
            $podEntry = $ResourceIndex.podByName[("pod|{0}|{1}" -f $namespace.ToLowerInvariant(), $podName.ToLowerInvariant())]
            $sourceDisplay = $podEntry.podDisplay
            $topDisplay = [string]$podEntry.topDisplay
            $ownerKey = Get-ResourceKey -Kind $podEntry.topKind -Namespace $namespace -Name $podEntry.topName
            if ($ResourceIndex.workloads.ContainsKey($ownerKey)) {
                $helmDisplay = Get-HelmDescriptor -Entry $ResourceIndex.workloads[$ownerKey]
            }
        }
        elseif ($workloadKind -and $workloadName) {
            $topDisplay = "$workloadKind/$workloadName"
            $sourceDisplay = $topDisplay
            $ownerKey = Get-ResourceKey -Kind $workloadKind -Namespace $namespace -Name $workloadName
            if ($ResourceIndex.workloads.ContainsKey($ownerKey)) {
                $helmDisplay = Get-HelmDescriptor -Entry $ResourceIndex.workloads[$ownerKey]
            }
        }
        elseif ($resourceRef) {
            $sourceDisplay = $resourceRef
            $topDisplay = $resourceRef
        }
        else {
            $sourceDisplay = ($Item | Out-String).Trim()
            $topDisplay = $sourceDisplay
        }

        $display = $topDisplay
        if ($sourceDisplay -and $sourceDisplay -ne $topDisplay) {
            $display += " via $sourceDisplay"
        }
        if ($helmDisplay) {
            $display += " [$helmDisplay]"
        }

        return @{
            namespace = $namespace
            topDisplay = $topDisplay
            sourceDisplay = $sourceDisplay
            helmDisplay = $helmDisplay
            display = $display
        }
    }

    $resourceIndex = New-AutomaticResourceIndex -KubeData $KubeData

    $skuName = ''
    if ($AksClusterInfo) {
        try {
            if ($AksClusterInfo -is [hashtable] -and $AksClusterInfo.ContainsKey('sku')) {
                $skuName = [string]($AksClusterInfo.sku.name ?? '')
            }
            elseif ($AksClusterInfo.PSObject.Properties['sku']) {
                $skuName = [string]($AksClusterInfo.sku.name ?? '')
            }
        }
        catch {
            $skuName = ''
        }
    }

    if ($skuName -and $skuName.ToLowerInvariant() -eq 'automatic') {
        return [pscustomobject]@{
            summary = [pscustomobject]@{
                clusterName = $ClusterName
                status = 'skipped'
                statusLabel = 'Skipped'
                blockerCount = 0
                warningCount = 0
                alignmentFailedCount = 0
                alignmentPassedCount = 0
                actionPlanPath = ''
                skipped = $true
                message = 'This readiness assessment is skipped because the source cluster SKU is already AKS Automatic.'
            }
            blockers = @()
            warnings = @()
            alignment = [pscustomobject]@{
                status = 'skipped'
                total = 0
                passed = 0
                failed = 0
                items = @()
            }
            actionPlan = @()
            targetClusterBuildNotes = @()
        }
    }

    $allChecks = @($YamlChecks) + @($AksChecks)
    $relevantChecks = @(
        $allChecks | Where-Object {
            $relevance = [string](Get-CheckValue -Check $_ -Name 'AutomaticRelevance')
            $relevance -in @('blocker', 'warning', 'alignment')
        }
    )

    $failedRelevant = @(
        $relevantChecks | Where-Object {
            [int](Get-CheckValue -Check $_ -Name 'Total') -gt 0
        }
    )

    $blockers = @($failedRelevant | Where-Object { [string](Get-CheckValue -Check $_ -Name 'AutomaticRelevance') -eq 'blocker' })
    $warnings = @($failedRelevant | Where-Object { [string](Get-CheckValue -Check $_ -Name 'AutomaticRelevance') -eq 'warning' })
    $alignmentChecks = @($relevantChecks | Where-Object { [string](Get-CheckValue -Check $_ -Name 'AutomaticRelevance') -eq 'alignment' })
    $alignmentFailed = @($alignmentChecks | Where-Object { [int](Get-CheckValue -Check $_ -Name 'Total') -gt 0 })
    $alignmentPassed = @($alignmentChecks | Where-Object { [int](Get-CheckValue -Check $_ -Name 'Total') -eq 0 })

    $status = if ($blockers.Count -gt 0) {
        'not_ready'
    }
    elseif ($warnings.Count -gt 0) {
        'ready_with_changes'
    }
    else {
        'ready'
    }

    $statusLabel = switch ($status) {
        'ready' { 'Ready' }
        'ready_with_changes' { 'Ready With Changes' }
        default { 'Not Ready' }
    }

    $alignmentStatus = if ($alignmentChecks.Count -eq 0) {
        'unknown'
    }
    elseif ($alignmentFailed.Count -eq 0) {
        'already_aligned'
    }
    elseif ($alignmentPassed.Count -eq 0) {
        'not_aligned'
    }
    else {
        'partially_aligned'
    }

    $convertFindings = {
        param([object[]]$Checks)

        @(
            $Checks | ForEach-Object {
                $recommendation = Get-RecommendationText -rec (Get-CheckValue -Check $_ -Name 'Recommendation') -JsonOutput
                [pscustomobject]@{
                    id = [string](Get-CheckValue -Check $_ -Name 'ID')
                    name = [string](Get-CheckValue -Check $_ -Name 'Name')
                    severity = [string](Get-CheckValue -Check $_ -Name 'Severity')
                    category = [string](Get-CheckValue -Check $_ -Name 'Category')
                    scope = [string](Get-CheckValue -Check $_ -Name 'AutomaticScope')
                    relevance = [string](Get-CheckValue -Check $_ -Name 'AutomaticRelevance')
                    reason = [string](Get-CheckValue -Check $_ -Name 'AutomaticReason')
                    total = [int](Get-CheckValue -Check $_ -Name 'Total')
                    failMessage = [string](Get-CheckValue -Check $_ -Name 'FailMessage')
                    recommendation = $recommendation
                    url = [string](Get-CheckValue -Check $_ -Name 'URL')
                    automaticAdmissionBehavior = [string](Get-CheckValue -Check $_ -Name 'AutomaticAdmissionBehavior')
                    automaticMutationOutcome = [string](Get-CheckValue -Check $_ -Name 'AutomaticMutationOutcome')
                    admissionNote = Get-AutomaticAdmissionNote `
                        -Behavior ([string](Get-CheckValue -Check $_ -Name 'AutomaticAdmissionBehavior')) `
                        -MutationOutcome ([string](Get-CheckValue -Check $_ -Name 'AutomaticMutationOutcome'))
                    samples = @(Get-CheckSamples -Check $_ -ResourceIndex $resourceIndex)
                }
            }
        )
    }

    $migrationRelevant = @($blockers + $warnings)
    $actionGroups = [ordered]@{}
    foreach ($check in $migrationRelevant) {
        $reason = [string](Get-CheckValue -Check $check -Name 'AutomaticReason')
        if (-not $reason) {
            $reason = ([string](Get-CheckValue -Check $check -Name 'ID')).ToLowerInvariant()
        }
        $phase = Get-ActionPhase -Relevance ([string](Get-CheckValue -Check $check -Name 'AutomaticRelevance')) -Scope ([string](Get-CheckValue -Check $check -Name 'AutomaticScope'))
        $key = "$phase|$reason"
        if (-not $actionGroups.Contains($key)) {
            $actionGroups[$key] = [ordered]@{
                key = $reason
                phase = $phase
                bucket = [string](Get-CheckValue -Check $check -Name 'AutomaticRelevance')
                title = Get-AutomaticReasonTitle -Reason $reason
                steps = @(Get-AutomaticReasonSteps -Reason $reason)
                checks = @()
                sampleSet = [System.Collections.Generic.HashSet[string]]::new()
                affectedResources = [System.Collections.Generic.List[object]]::new()
                totalAffected = 0
                urls = [System.Collections.Generic.HashSet[string]]::new()
                recommendations = [System.Collections.Generic.List[string]]::new()
                admissionNotes = [System.Collections.Generic.List[string]]::new()
            }
        }

        $group = $actionGroups[$key]
        if ([string](Get-CheckValue -Check $check -Name 'AutomaticRelevance') -eq 'blocker') {
            $group.bucket = 'blocker'
        }
        $group.checks += [string](Get-CheckValue -Check $check -Name 'ID')
        $group.totalAffected += [int](Get-CheckValue -Check $check -Name 'Total')
        foreach ($sample in (Get-CheckSamples -Check $check -ResourceIndex $resourceIndex)) {
            $null = $group.sampleSet.Add([string]$sample)
        }
        foreach ($affected in (Get-CheckAffectedResources -Check $check -ResourceIndex $resourceIndex)) {
            $group.affectedResources.Add($affected)
        }
        $url = [string](Get-CheckValue -Check $check -Name 'URL')
        if ($url) {
            $null = $group.urls.Add($url)
        }
        $recommendation = Get-RecommendationText -rec (Get-CheckValue -Check $check -Name 'Recommendation') -JsonOutput
        if ($recommendation -and -not $group.recommendations.Contains($recommendation)) {
            $group.recommendations.Add($recommendation)
        }
        $admissionNote = Get-AutomaticAdmissionNote `
            -Behavior ([string](Get-CheckValue -Check $check -Name 'AutomaticAdmissionBehavior')) `
            -MutationOutcome ([string](Get-CheckValue -Check $check -Name 'AutomaticMutationOutcome'))
        if ($admissionNote -and -not $group.admissionNotes.Contains($admissionNote)) {
            $group.admissionNotes.Add($admissionNote)
        }
    }

    $actionPlan = @(
        $actionGroups.Values | ForEach-Object {
            [pscustomobject]@{
                key = $_.key
                phase = $_.phase
                bucket = $_.bucket
                title = $_.title
                affectedCount = $_.totalAffected
                affectedResourceCount = @($_.affectedResources | Sort-Object namespace, workload, observedResource -Unique).Count
                steps = @($_.steps)
                checks = @($_.checks | Select-Object -Unique)
                samples = @($_.sampleSet | Select-Object -First 5)
                affectedResources = @($_.affectedResources | Sort-Object namespace, workload, observedResource -Unique | Select-Object -First 10)
                recommendations = @($_.recommendations)
                admissionNotes = @($_.admissionNotes)
                urls = @($_.urls)
            }
        }
    )

    $buildNoteGroups = [ordered]@{}
    foreach ($check in $alignmentFailed) {
        $reason = [string](Get-CheckValue -Check $check -Name 'AutomaticReason')
        if (-not $reason) {
            $reason = ([string](Get-CheckValue -Check $check -Name 'ID')).ToLowerInvariant()
        }

        if (-not $buildNoteGroups.Contains($reason)) {
            $buildNoteGroups[$reason] = [ordered]@{
                key = $reason
                title = Get-AutomaticReasonTitle -Reason $reason
                steps = @(Get-AutomaticReasonSteps -Reason $reason)
                checks = @()
                sampleSet = [System.Collections.Generic.HashSet[string]]::new()
                totalAffected = 0
                urls = [System.Collections.Generic.HashSet[string]]::new()
                recommendations = [System.Collections.Generic.List[string]]::new()
                admissionNotes = [System.Collections.Generic.List[string]]::new()
            }
        }

        $group = $buildNoteGroups[$reason]
        $group.checks += [string](Get-CheckValue -Check $check -Name 'ID')
        $group.totalAffected += [int](Get-CheckValue -Check $check -Name 'Total')
        foreach ($sample in (Get-CheckSamples -Check $check -ResourceIndex $resourceIndex)) {
            $null = $group.sampleSet.Add([string]$sample)
        }
        $url = [string](Get-CheckValue -Check $check -Name 'URL')
        if ($url) {
            $null = $group.urls.Add($url)
        }
        $recommendation = Get-RecommendationText -rec (Get-CheckValue -Check $check -Name 'Recommendation') -JsonOutput
        if ($recommendation -and -not $group.recommendations.Contains($recommendation)) {
            $group.recommendations.Add($recommendation)
        }
        $admissionNote = Get-AutomaticAdmissionNote `
            -Behavior ([string](Get-CheckValue -Check $check -Name 'AutomaticAdmissionBehavior')) `
            -MutationOutcome ([string](Get-CheckValue -Check $check -Name 'AutomaticMutationOutcome'))
        if ($admissionNote -and -not $group.admissionNotes.Contains($admissionNote)) {
            $group.admissionNotes.Add($admissionNote)
        }
    }

    $targetClusterBuildNotes = @(
        $buildNoteGroups.Values | ForEach-Object {
            [pscustomobject]@{
                key = $_.key
                title = $_.title
                affectedCount = $_.totalAffected
                steps = @($_.steps)
                checks = @($_.checks | Select-Object -Unique)
                samples = @($_.sampleSet | Select-Object -First 5)
                recommendations = @($_.recommendations)
                admissionNotes = @($_.admissionNotes)
                urls = @($_.urls)
            }
        }
    )

    $summary = [pscustomobject]@{
        clusterName = $ClusterName
        status = $status
        statusLabel = $statusLabel
        blockerCount = $blockers.Count
        warningCount = $warnings.Count
        alignmentFailedCount = $alignmentFailed.Count
        alignmentPassedCount = $alignmentPassed.Count
        actionPlanPath = if ($actionPlan.Count -gt 0) { $ActionPlanPath } else { '' }
        message = switch ($status) {
            'ready' { 'No AKS Automatic blockers were detected in the evaluated shared checks.' }
            'ready_with_changes' { 'No hard blockers were detected, but workload or platform changes are recommended before migrating to a new AKS Automatic cluster.' }
            default { 'One or more workload or platform blockers should be fixed before migrating to a new AKS Automatic cluster.' }
        }
    }

    $alignment = [pscustomobject]@{
        status = $alignmentStatus
        total = $alignmentChecks.Count
        passed = $alignmentPassed.Count
        failed = $alignmentFailed.Count
        items = & $convertFindings $alignmentFailed
    }

    return [pscustomobject]@{
        summary = $summary
        blockers = & $convertFindings $blockers
        warnings = & $convertFindings $warnings
        alignment = $alignment
        actionPlan = $actionPlan
        targetClusterBuildNotes = $targetClusterBuildNotes
    }
}

function Convert-KubeBuddyAutomaticReadinessToText {
    param([object]$Readiness)

    if (-not $Readiness) { return @() }

    $lines = @()
    $lines += '[🤖 AKS Automatic Migration Readiness]'
    $lines += "Status: $($Readiness.summary.statusLabel)"
    if ($Readiness.summary.skipped) {
        $lines += $Readiness.summary.message
        return $lines
    }
    $lines += "Blockers: $($Readiness.summary.blockerCount)"
    $lines += "Warnings: $($Readiness.summary.warningCount)"
    $lines += "AKS Alignment Passed: $($Readiness.summary.alignmentPassedCount)"
    $lines += "AKS Alignment Failed: $($Readiness.summary.alignmentFailedCount)"
    $lines += "Note: This assesses migration to a new AKS Automatic cluster."

    if ($Readiness.blockers.Count -gt 0) {
        $lines += ''
        $lines += 'Blockers'
        foreach ($finding in $Readiness.blockers) {
            $lines += "- [$($finding.id)] $($finding.name) ($($finding.total) affected)"
            if ($finding.recommendation) {
                $lines += "  Recommendation: $($finding.recommendation)"
            }
            if ($finding.admissionNote) {
                $lines += "  AKS Automatic behavior: $($finding.admissionNote)"
            }
        }
    }

    if ($Readiness.warnings.Count -gt 0) {
        $lines += ''
        $lines += 'Warnings'
        foreach ($finding in $Readiness.warnings) {
            $lines += "- [$($finding.id)] $($finding.name) ($($finding.total) affected)"
            if ($finding.recommendation) {
                $lines += "  Recommendation: $($finding.recommendation)"
            }
            if ($finding.admissionNote) {
                $lines += "  AKS Automatic behavior: $($finding.admissionNote)"
            }
        }
    }

    if ($Readiness.alignment.items.Count -gt 0) {
        $lines += ''
        $lines += 'AKS Alignment Advisory'
        foreach ($finding in $Readiness.alignment.items) {
            $lines += "- [$($finding.id)] $($finding.name)"
            if ($finding.recommendation) {
                $lines += "  Recommendation: $($finding.recommendation)"
            }
            if ($finding.admissionNote) {
                $lines += "  AKS Automatic behavior: $($finding.admissionNote)"
            }
        }
    }

    if ($Readiness.actionPlan.Count -gt 0) {
        $lines += ''
        $lines += 'Action Plan'
        foreach ($action in $Readiness.actionPlan) {
            $phase = if ($action.phase -eq 'fix_before_migration') { 'Fix Before Migration' } else { 'Target Cluster Build' }
            $lines += "- [$phase] $($action.title) ($($action.affectedCount) affected)"
            foreach ($rec in $action.recommendations | Select-Object -First 1) {
                $lines += "  Recommendation: $rec"
            }
            foreach ($note in $action.admissionNotes | Select-Object -First 1) {
                $lines += "  AKS Automatic behavior: $note"
            }
            foreach ($step in @($action.steps)) {
                $lines += "  Step: $step"
            }
            foreach ($url in @($action.urls)) {
                $lines += "  Docs: $url"
            }
        }
    }

    if ($Readiness.summary.actionPlanPath) {
        $lines += ''
        $lines += "Action Plan File: $($Readiness.summary.actionPlanPath)"
    }

    return $lines
}

function Convert-KubeBuddyAutomaticReadinessToHtml {
    param([object]$Readiness)

    if (-not $Readiness) { return '' }

    $statusClass = switch ($Readiness.summary.status) {
        'ready' { 'healthy' }
        'ready_with_changes' { 'warning' }
        'skipped' { 'unknown' }
        default { 'critical' }
    }

    if ($Readiness.summary.skipped) {
        return @"
<div class="collapsible-container aks-automatic-readiness">
  <details id="aksAutomaticReadiness">
    <summary>AKS Automatic Migration Readiness <span class="status-pill unknown">Skipped</span></summary>
    <div class="table-container">
      <div class="compatibility unknown"><strong>Skipped</strong> - $($Readiness.summary.message)</div>
    </div>
  </details>
</div>
"@
    }

    $renderFindingRows = {
        param([object[]]$Items)

        if (-not $Items -or $Items.Count -eq 0) {
            return '<tr><td colspan="5">None</td></tr>'
        }

        ($Items | ForEach-Object {
            $samples = @($_.samples) -join ', '
            "<tr><td><a href='#$($_.id)'>$($_.id)</a></td><td>$($_.name)</td><td>$($_.total)</td><td>$($_.recommendation)</td><td>$samples</td></tr>"
        }) -join "`n"
    }

    $actionPlanLink = if ($Readiness.summary.actionPlanPath) {
        $leaf = [System.IO.Path]::GetFileName($Readiness.summary.actionPlanPath)
        "<p><a href='$leaf' target='_blank'>Open detailed AKS Automatic action plan</a></p>"
    }
    else {
        ''
    }

    return @"
<div class="collapsible-container aks-automatic-readiness">
  <details id="aksAutomaticReadiness">
    <summary>AKS Automatic Migration Readiness <span class="status-pill $statusClass">$($Readiness.summary.statusLabel)</span></summary>
    <div class="table-container">
      <div class="compatibility $statusClass"><strong>$($Readiness.summary.statusLabel)</strong> - $($Readiness.summary.message)</div>
      <div class="hero-metrics">
        <div class="metric-card critical"><div class="card-content"><p>🚫 Blockers: <strong>$($Readiness.summary.blockerCount)</strong></p></div></div>
        <div class="metric-card warning"><div class="card-content"><p>⚠️ Warnings: <strong>$($Readiness.summary.warningCount)</strong></p></div></div>
        <div class="metric-card normal"><div class="card-content"><p>✅ Aligned Checks: <strong>$($Readiness.summary.alignmentPassedCount)</strong></p></div></div>
      </div>
      <p>This view is derived from existing Kubernetes and AKS shared checks and focuses on readiness for a <strong>new AKS Automatic cluster</strong>.</p>
      $actionPlanLink
      <h3>Fix Before Migration</h3>
      <div class="table-container">
        <table>
          <thead><tr><th>ID</th><th>Check</th><th>Affected</th><th>Recommendation</th><th>Examples</th></tr></thead>
          <tbody>
            $(& $renderFindingRows $Readiness.blockers)
          </tbody>
        </table>
      </div>
      <h3>Warnings</h3>
      <div class="table-container">
        <table>
          <thead><tr><th>ID</th><th>Check</th><th>Affected</th><th>Recommendation</th><th>Examples</th></tr></thead>
          <tbody>
            $(& $renderFindingRows $Readiness.warnings)
          </tbody>
        </table>
      </div>
    </div>
  </details>
</div>
"@
}

function Get-KubeBuddyAutomaticClusterBuildResources {
    @(
        [pscustomobject]@{
            title = 'Azure portal'
            description = 'Official AKS Automatic quickstart with the portal flow for creating a new cluster.'
            url = 'https://learn.microsoft.com/en-us/azure/aks/automatic/quick-automatic-managed-network'
        }
        [pscustomobject]@{
            title = 'Azure CLI'
            description = 'Official AKS Automatic quickstart using az aks create --sku automatic.'
            url = 'https://learn.microsoft.com/en-us/azure/aks/automatic/quick-automatic-managed-network'
        }
        [pscustomobject]@{
            title = 'Bicep'
            description = 'Official AKS Automatic quickstart section with a Bicep example for a managed cluster using sku.name = Automatic.'
            url = 'https://learn.microsoft.com/en-us/azure/aks/automatic/quick-automatic-managed-network'
        }
        [pscustomobject]@{
            title = 'Terraform (AzAPI reference)'
            description = 'Official managedClusters template reference showing sku.name values, including Automatic, for Terraform AzAPI-based deployments.'
            url = 'https://learn.microsoft.com/en-us/azure/templates/microsoft.containerservice/2025-05-02-preview/managedclusters'
        }
    )
}

function Get-KubeBuddyAutomaticManifestExample {
    param([string]$Reason)

    switch ($Reason) {
        'image_tag' {
            return @"
apiVersion: apps/v1
kind: Deployment
metadata:
  name: app
spec:
  template:
    spec:
      containers:
        - name: app
          image: contoso/app:1.2.3
"@
        }
        'resource_requests' {
            return @"
resources:
  requests:
    cpu: 200m
    memory: 256Mi
  limits:
    memory: 256Mi
"@
        }
        'health_probes' {
            return @"
readinessProbe:
  httpGet:
    path: /healthz
    port: 8080
livenessProbe:
  httpGet:
    path: /healthz
    port: 8080
"@
        }
        'pod_spread' {
            return @"
topologySpreadConstraints:
  - maxSkew: 1
    topologyKey: kubernetes.io/hostname
    whenUnsatisfiable: DoNotSchedule
    labelSelector:
      matchLabels:
        app: my-app
"@
        }
        'host_ports' {
            return @"
ports:
  - containerPort: 8080
---
apiVersion: v1
kind: Service
metadata:
  name: app
spec:
  selector:
    app: my-app
  ports:
    - port: 80
      targetPort: 8080
"@
        }
        'seccomp' {
            return @"
securityContext:
  seccompProfile:
    type: RuntimeDefault
"@
        }
        'proc_mount' {
            return @"
securityContext:
  procMount: Default
"@
        }
        'apparmor' {
            return @"
metadata:
  annotations:
    container.apparmor.security.beta.kubernetes.io/app: runtime/default
"@
        }
        'capabilities' {
            return @"
securityContext:
  capabilities:
    drop:
      - ALL
"@
        }
        'service_selector' {
            return @"
apiVersion: v1
kind: Service
metadata:
  name: app
spec:
  selector:
    app: my-app
    component: web
"@
        }
        'gateway_api' {
            return @"
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: app-gateway
spec:
  gatewayClassName: approuting-istio
  listeners:
    - name: http
      protocol: HTTP
      port: 80
      hostname: app.example.com
---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: app-route
spec:
  parentRefs:
    - name: app-gateway
  hostnames:
    - app.example.com
  rules:
    - matches:
        - path:
            type: PathPrefix
            value: /
      backendRefs:
        - name: app
          port: 80
"@
        }
        'host_namespace' {
            return @"
spec:
  hostNetwork: false
  hostPID: false
  hostIPC: false
"@
        }
        'host_path' {
            return @"
volumes:
  - name: app-data
    persistentVolumeClaim:
      claimName: app-data
"@
        }
        'storage_csi' {
            return @"
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: managed-csi
provisioner: disk.csi.azure.com
"@
        }
        default {
            return ''
        }
    }
}

function New-KubeBuddyAutomaticActionPlanHtml {
    param(
        [string]$OutputPath,
        [object]$Readiness,
        [string]$ClusterName = ''
    )

    if (-not $OutputPath -or -not $Readiness) { return }

    $today = (Get-Date).ToUniversalTime().ToString("MMMM dd, yyyy HH:mm:ss 'UTC'")
    $moduleRoot = Split-Path -Parent $PSScriptRoot
    $sharedCssPath = Join-Path $moduleRoot 'Private/html/report-styles.css'
    $sharedCss = if (Test-Path $sharedCssPath) { Get-Content -Path $sharedCssPath -Raw } else { '' }
    $themeBootstrap = @"
<script>
(() => {
  try {
    const saved = localStorage.getItem('kb_report_theme');
    if (saved === 'radar') {
      document.documentElement.setAttribute('data-kb-theme', 'radar');
    } else {
      document.documentElement.removeAttribute('data-kb-theme');
    }
  } catch (error) {
    document.documentElement.removeAttribute('data-kb-theme');
  }
})();
</script>
"@
    $clusterBuildResources = Get-KubeBuddyAutomaticClusterBuildResources
    $clusterBuildResourceCards = ($clusterBuildResources | ForEach-Object {
        "<li><strong>$($_.title)</strong> - $($_.description) <a href='$($_.url)' target='_blank'>Open Microsoft Learn</a></li>"
    }) -join "`n"
    $hasGatewayAction = @($Readiness.actionPlan | Where-Object { $_.key -eq 'gateway_api' }).Count -gt 0
    $migrationSteps = @(
        '<li><strong>Step 1:</strong> Fix all blocker findings in source manifests, Helm values, and workload definitions before creating the destination cluster.</li>',
        '<li><strong>Step 2:</strong> Review warning findings and clean up the items that could cause operational drift, security warnings, or migration rework after cutover.</li>',
        $(if ($hasGatewayAction) {
            '<li><strong>Step 3:</strong> Migrate north-south traffic from legacy Ingress assumptions to Gateway API resources and validate the target routing model before production cutover.</li>'
        } else {
            '<li><strong>Step 3:</strong> Prepare the target application routing model and confirm north-south traffic dependencies before building the new cluster.</li>'
        }),
        '<li><strong>Step 4:</strong> Create the new AKS Automatic cluster using one of the supported Microsoft Learn deployment paths below.</li>',
        '<li><strong>Step 5:</strong> Deploy workloads into the new cluster, validate health and traffic behavior, then perform cutover and decommission the old environment when ready.</li>'
    ) -join "`n"
    $renderActionCards = {
        param([object[]]$Actions)

        if (-not $Actions -or $Actions.Count -eq 0) {
            return ''
        }

        ($Actions | ForEach-Object {
            $recommendations = @($_.recommendations | ForEach-Object { "<li>$_</li>" }) -join ''
            $steps = @($_.steps | ForEach-Object { "<li>$_</li>" }) -join ''
            $docs = @($_.urls | ForEach-Object { "<li><a href='$_' target='_blank'>$_</a></li>" }) -join ''
            $example = [System.Net.WebUtility]::HtmlEncode((Get-KubeBuddyAutomaticManifestExample -Reason $_.key))
            $exampleSection = if ($example) { "<h4>Manifest example</h4><pre><code>$example</code></pre>" } else { '' }
            $affectedRows = @($_.affectedResources | ForEach-Object {
                $helmCell = if ($_.helmSource) { $_.helmSource } else { '-' }
                "<tr><td>$($_.namespace)</td><td>$($_.workload)</td><td>$($_.observedResource)</td><td>$helmCell</td></tr>"
            }) -join ''
            $affectedSection = if ($affectedRows) {
                $resourceSummary = if ($_.affectedResourceCount -lt $_.affectedCount) {
                    "$($_.affectedCount) total findings were grouped into $($_.affectedResourceCount) unique source resources to update."
                } else {
                    "Showing $($_.affectedResourceCount) affected resources."
                }
                @"
<h4>Affected resources</h4>
<p class="action-plan-meta">$resourceSummary</p>
<div class="table-container action-resource-table">
  <table>
    <thead><tr><th>Namespace</th><th>Workload</th><th>Observed Resource</th><th>Helm Source</th></tr></thead>
    <tbody>$affectedRows</tbody>
  </table>
</div>
"@
            } else { '' }
            @"
<section class="action-plan-card">
  <div class="action-plan-card-header">
    <h3>$($_.title)</h3>
    <span class="action-plan-count">$($_.affectedResourceCount) resources</span>
  </div>
  <div class="action-plan-card-body">
    <h4>Recommendation</h4>
    <ul>$recommendations</ul>
    <h4>Steps</h4>
    <ul>$steps</ul>
    $affectedSection
    $exampleSection
    <h4>Docs</h4>
    <ul>$docs</ul>
  </div>
</section>
"@
        }) -join "`n"
    }
    $blockerActions = @($Readiness.actionPlan | Where-Object { $_.bucket -eq 'blocker' })
    $warningActions = @($Readiness.actionPlan | Where-Object { $_.bucket -ne 'blocker' })
    $blockerActionCards = if ($blockerActions.Count -gt 0) { & $renderActionCards $blockerActions } else { '<p>No blocker-driven migration actions were identified.</p>' }
    $warningActionCards = if ($warningActions.Count -gt 0) { & $renderActionCards $warningActions } else { '<p>No warning-only migration actions were identified.</p>' }

    $html = @"
<!DOCTYPE html>
<html lang='en'>
<head>
<meta charset='UTF-8'>
<meta name='viewport' content='width=device-width, initial-scale=1.0'>
<title>AKS Automatic Action Plan</title>
$themeBootstrap
<style>
$sharedCss
body { margin: 0; padding: 0; }
.action-plan-page { max-width: 1350px; margin: 0 auto; padding: 24px; }
.action-plan-intro { margin-bottom: 24px; }
.action-plan-links { margin-top: 16px; }
.action-plan-links ul { margin-top: 12px; }
.action-plan-links li + li { margin-top: 10px; }
.migration-sequence { margin-top: 18px; }
.migration-sequence li + li { margin-top: 10px; }
table { width: 100%; border-collapse: collapse; }
th, td { padding: 12px; text-align: left; vertical-align: top; }
small { color: #64748b; display: block; margin-top: 8px; }
ul { margin: 0; padding-left: 18px; }
.action-plan-section { margin-top: 24px; }
.action-plan-card {
  margin-top: 16px;
  padding: 18px 20px;
  border-radius: 12px;
  background: linear-gradient(180deg, rgba(255, 255, 255, 0.98), rgba(245, 247, 250, 0.98));
  border: 1px solid rgba(55, 71, 79, 0.12);
  box-shadow: var(--shadow-sm);
}
.action-plan-card-header {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 12px;
  margin-bottom: 12px;
}
.action-plan-card-header h3 {
  margin: 0;
}
.action-plan-count {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  padding: 6px 10px;
  border-radius: 999px;
  background: rgba(0, 113, 255, 0.1);
  color: var(--brand-blue);
  font-size: 13px;
  font-weight: 600;
  white-space: nowrap;
}
.action-plan-meta {
  margin: 0 0 10px;
  color: var(--subtle-on-dark);
  font-size: 13px;
}
.action-plan-card-body > h4:first-child {
  margin-top: 0;
}
pre {
  margin: 12px 0 0;
  padding: 14px 16px;
  border-radius: var(--border-radius);
  background: rgba(15, 23, 42, 0.92);
  color: #e2e8f0;
  overflow-x: auto;
  white-space: pre;
}
code {
  font-family: SFMono-Regular, Consolas, "Liberation Mono", Menlo, monospace;
  font-size: 13px;
}
pre code {
  display: block;
  margin: 0;
  padding: 0;
  background: transparent;
  color: inherit;
  border-radius: 0;
  box-shadow: none;
  white-space: pre;
  line-height: 1.6;
}
td h4 {
  margin: 14px 0 8px;
}
html[data-kb-theme="radar"] .action-plan-page { max-width: 1440px; }
html[data-kb-theme="radar"] .action-plan-intro,
html[data-kb-theme="radar"] .action-plan-section {
  background: transparent;
}
html[data-kb-theme="radar"] .action-plan-card {
  background: linear-gradient(180deg, rgba(39, 52, 73, 0.96), rgba(33, 46, 66, 0.96));
  border: 1px solid #3f5677;
  box-shadow: 0 10px 22px rgba(8, 18, 34, 0.24);
}
html[data-kb-theme="radar"] .action-plan-count {
  background: rgba(0, 194, 255, 0.14);
  color: #9de6ff;
  border: 1px solid rgba(0, 194, 255, 0.35);
}
html[data-kb-theme="radar"] .action-plan-meta {
  color: #9ba9be;
}
html[data-kb-theme="radar"] pre {
  background: rgba(11, 22, 43, 0.96);
  border: 1px solid rgba(0, 186, 255, 0.2);
}
</style>
</head>
<body>
  <div class="wrapper">
    <div class="main-content">
      <div class="header">
        <div class="header-inner">
          <div class="header-top">
            <div>
              <span>AKS Automatic Action Plan: $ClusterName</span>
              <br>
              <span style="font-size: 12px;">
                Powered by
                <img src="https://raw.githubusercontent.com/KubeDeckio/KubeBuddy/refs/heads/main/images/reportheader%20(2).png" alt="KubeBuddy Logo" style="height: 70px; vertical-align: middle;">
              </span>
            </div>
            <div style="text-align: right; font-size: 13px; line-height: 1.4;">
              <div>Generated on: <strong>$today</strong></div>
              <div>This action plan is intended for migration to a <strong>new AKS Automatic cluster</strong>.</div>
            </div>
          </div>
        </div>
      </div>
      <div class="action-plan-page">
        <div class="container action-plan-intro">
      <h1>AKS Automatic Action Plan</h1>
      <p><strong>Cluster:</strong> $ClusterName</p>
      <div class="compatibility $(if ($Readiness.summary.status -eq 'not_ready') { 'critical' } elseif ($Readiness.summary.status -eq 'ready_with_changes') { 'warning' } else { 'healthy' })"><strong>$($Readiness.summary.statusLabel)</strong> - $($Readiness.summary.message)</div>
      <div class="hero-metrics">
        <div class="metric-card critical"><div class="card-content"><p>🚫 Blockers: <strong>$($Readiness.summary.blockerCount)</strong></p></div></div>
        <div class="metric-card warning"><div class="card-content"><p>⚠️ Warnings: <strong>$($Readiness.summary.warningCount)</strong></p></div></div>
      </div>
      <div class="action-plan-links">
        <h2>Suggested Migration Sequence</h2>
        <ul class="migration-sequence">
          $migrationSteps
        </ul>
      </div>
      <div class="action-plan-links">
        <h2>Build a New AKS Automatic Cluster</h2>
        <p>Use these Microsoft Learn references when you build the destination cluster for this migration. The official quickstart currently covers the Azure portal, Azure CLI, and Bicep flows. For Terraform, the official Learn reference is the managed cluster AzAPI schema that exposes <code>sku.name = Automatic</code>.</p>
        <ul>
          $clusterBuildResourceCards
        </ul>
      </div>
        </div>
    <div class="container action-plan-section">
      <h2>Fix Before Migration</h2>
      <p>These actions are driven by blocker findings and should be completed before deploying workloads to a new AKS Automatic cluster.</p>
      <div class="action-plan-cards">
        $blockerActionCards
      </div>
    </div>
    <div class="container action-plan-section">
      <h2>Warnings to Review</h2>
      <p>These actions come from warning findings. They do not block migration by themselves, but resolving them reduces drift, warnings, and post-cutover rework.</p>
      <div class="action-plan-cards">
        $warningActionCards
      </div>
    </div>
      </div>
    </div>
    <footer class="footer">
      <a href="https://kubedeck.io" target="_blank">
        Created by
        <img src="https://raw.githubusercontent.com/KubeDeckio/KubeBuddy/refs/heads/main/images/reportheader%20(2).png" alt="KubeBuddy" class="logo">
      </a>
      <a href="https://kubebuddy.io" target="_blank">KubeBuddy Documentation</a>
    </footer>
  </div>
</body>
</html>
"@

    Set-Content -Path $OutputPath -Value $html -Encoding UTF8
}
