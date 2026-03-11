function Get-KubeBuddyImageParts {
    param(
        [string]$Image
    )

    $raw = [string]$Image
    if ([string]::IsNullOrWhiteSpace($raw)) {
        return @{
            fullRef = ''
            name = ''
            tag = ''
            digest = ''
            currentVersion = ''
        }
    }

    $fullRef = $raw.Trim()
    $nameTag = $fullRef
    $digest = ''
    if ($nameTag.Contains('@')) {
        $split = $nameTag.Split('@', 2)
        $nameTag = $split[0]
        $digest = if ($split.Count -gt 1) { [string]$split[1] } else { '' }
    }

    $lastSlash = $nameTag.LastIndexOf('/')
    $lastColon = $nameTag.LastIndexOf(':')
    $name = $nameTag
    $tag = ''
    if ($lastColon -gt $lastSlash) {
        $name = $nameTag.Substring(0, $lastColon)
        $tag = $nameTag.Substring($lastColon + 1)
    }

    $currentVersion = if ($tag) { $tag } elseif ($digest) { $digest } else { '' }

    return @{
        fullRef = $fullRef
        name = $name
        tag = $tag
        digest = $digest
        currentVersion = $currentVersion
    }
}

function Get-KubeBuddyArtifactLabelValue {
    param(
        [hashtable]$Labels,
        [string[]]$Keys
    )

    if (-not $Labels -or -not $Keys) {
        return ''
    }

    foreach ($k in $Keys) {
        if ($Labels.ContainsKey($k) -and -not [string]::IsNullOrWhiteSpace([string]$Labels[$k])) {
            return [string]$Labels[$k]
        }
    }
    return ''
}

function Get-KubeBuddyMetadataMap {
    param(
        [object]$Metadata
    )

    $labels = @{}
    $annotations = @{}

    if ($Metadata -and $Metadata.labels) {
        foreach ($p in $Metadata.labels.PSObject.Properties) {
            $labels[[string]$p.Name] = [string]$p.Value
        }
    }

    if ($Metadata -and $Metadata.annotations) {
        foreach ($p in $Metadata.annotations.PSObject.Properties) {
            $annotations[[string]$p.Name] = [string]$p.Value
        }
    }

    return @{
        labels = $labels
        annotations = $annotations
    }
}

function Get-KubeBuddyRadarArtifactInventory {
    param(
        [object]$KubeData,
        [switch]$ExcludeNamespaces
    )

    $imagesByKey = @{}
    $helmByKey = @{}
    $appsByKey = @{}
    $inventorySource = if ($KubeData -and $KubeData.RawArtifactInventory) { $KubeData.RawArtifactInventory } else { $KubeData }
    $excludedNamespaces = @()
    $excludedSet = @{}
    $omittedWorkloads = 0
    $omittedNamespaceMap = @{}

    if ($ExcludeNamespaces) {
        $excludedNamespaces = @(Get-ExcludedNamespaces)
        foreach ($ns in $excludedNamespaces) {
            if (-not [string]::IsNullOrWhiteSpace([string]$ns)) {
                $excludedSet[[string]$ns.ToLowerInvariant()] = $true
            }
        }
    }

    $workloadSets = @(
        @{ Kind = 'Deployment'; Items = @($inventorySource.Deployments) },
        @{ Kind = 'StatefulSet'; Items = @($inventorySource.StatefulSets) },
        @{ Kind = 'DaemonSet'; Items = @($inventorySource.DaemonSets) },
        @{ Kind = 'Job'; Items = @($inventorySource.Jobs) },
        @{ Kind = 'CronJob'; Items = @($inventorySource.CronJobs) },
        @{ Kind = 'Pod'; Items = @($inventorySource.Pods) }
    )

    foreach ($set in $workloadSets) {
        foreach ($item in @($set.Items)) {
            if (-not $item) { continue }

            $kind = [string]$set.Kind
            $metadata = $item.metadata
            $namespace = if ($metadata.namespace) { [string]$metadata.namespace } else { 'cluster-wide' }
            $workloadName = if ($metadata.name) { [string]$metadata.name } else { 'unknown' }

            if ($ExcludeNamespaces -and $excludedSet.ContainsKey($namespace.ToLowerInvariant())) {
                $omittedWorkloads++
                $omittedNamespaceMap[$namespace] = $true
                continue
            }

            $metaMaps = Get-KubeBuddyMetadataMap -Metadata $metadata
            $labels = @{}
            $annotations = @{}
            foreach ($k in $metaMaps.labels.Keys) { $labels[$k] = $metaMaps.labels[$k] }
            foreach ($k in $metaMaps.annotations.Keys) { $annotations[$k] = $metaMaps.annotations[$k] }

            $spec = $item.spec
            $templateMetadata = $null
            $podSpec = $null
            if ($kind -eq 'Pod') {
                $podSpec = $spec
            }
            elseif ($kind -eq 'CronJob') {
                $templateMetadata = $spec.jobTemplate.spec.template.metadata
                $podSpec = $spec.jobTemplate.spec.template.spec
            }
            else {
                $templateMetadata = $spec.template.metadata
                $podSpec = $spec.template.spec
            }

            if ($templateMetadata) {
                $templateMaps = Get-KubeBuddyMetadataMap -Metadata $templateMetadata
                foreach ($k in $templateMaps.labels.Keys) {
                    if (-not $labels.ContainsKey($k)) { $labels[$k] = $templateMaps.labels[$k] }
                }
                foreach ($k in $templateMaps.annotations.Keys) {
                    if (-not $annotations.ContainsKey($k)) { $annotations[$k] = $templateMaps.annotations[$k] }
                }
            }

            $helmChartLabel = Get-KubeBuddyArtifactLabelValue -Labels $labels -Keys @('helm.sh/chart')
            $helmManagedBy = Get-KubeBuddyArtifactLabelValue -Labels $labels -Keys @('app.kubernetes.io/managed-by')
            $helmReleaseName = if ($annotations.ContainsKey('meta.helm.sh/release-name')) { [string]$annotations['meta.helm.sh/release-name'] } else { '' }
            $helmReleaseNs = if ($annotations.ContainsKey('meta.helm.sh/release-namespace')) { [string]$annotations['meta.helm.sh/release-namespace'] } else { '' }
            $isHelmManaged = [bool]($helmChartLabel -or ($helmManagedBy -and $helmManagedBy.ToLowerInvariant() -eq 'helm') -or $helmReleaseName)
            $helmChartName = ''
            $helmChartVersion = ''
            if ($helmChartLabel -match '^(?<name>.+)-(?<version>v?\d[\w\.\-\+]*)$') {
                $helmChartName = [string]$matches.name
                $helmChartVersion = [string]$matches.version
            }
            elseif ($helmChartLabel) {
                $helmChartName = [string]$helmChartLabel
            }

            $managedByValue = Get-KubeBuddyArtifactLabelValue -Labels $labels -Keys @('app.kubernetes.io/managed-by')
            $partOfValue = Get-KubeBuddyArtifactLabelValue -Labels $labels -Keys @('app.kubernetes.io/part-of')
            $controllerOwnerName = Get-KubeBuddyArtifactLabelValue -Labels $labels -Keys @(
                'gateway.envoyproxy.io/owning-gateway-name',
                'argocd.argoproj.io/instance',
                'kustomize.toolkit.fluxcd.io/name'
            )
            $controllerOwnerNamespace = Get-KubeBuddyArtifactLabelValue -Labels $labels -Keys @(
                'gateway.envoyproxy.io/owning-gateway-namespace',
                'kustomize.toolkit.fluxcd.io/namespace'
            )
            $isControllerManaged = [bool](
                $managedByValue -and
                $managedByValue.ToLowerInvariant() -ne 'helm' -and
                $managedByValue.ToLowerInvariant() -ne 'kubernetes'
            )

            $appName = Get-KubeBuddyArtifactLabelValue -Labels $labels -Keys @('app.kubernetes.io/name', 'app')
            $appVersion = Get-KubeBuddyArtifactLabelValue -Labels $labels -Keys @('app.kubernetes.io/version', 'app.kubernetes.io/app-version', 'appVersion', 'version')
            if ($appName -and $appVersion) {
                $appKey = ("{0}|{1}|{2}" -f $appName.ToLowerInvariant(), $appVersion.ToLowerInvariant(), $namespace.ToLowerInvariant())
                if (-not $appsByKey.ContainsKey($appKey)) {
                    $appsByKey[$appKey] = [PSCustomObject]@{
                        name = $appName
                        version = $appVersion
                        namespace = $namespace
                        workloadKind = $kind
                        workloadName = $workloadName
                        source = 'k8s_labels'
                        managedByHelm = $isHelmManaged
                        helmChartName = $helmChartName
                        helmReleaseName = $helmReleaseName
                        managedBy = $managedByValue
                        managedByController = $isControllerManaged
                        controllerOwnerName = $controllerOwnerName
                        controllerOwnerNamespace = if ($controllerOwnerNamespace) { $controllerOwnerNamespace } else { $namespace }
                        partOf = $partOfValue
                    }
                }
            }

            if ($helmChartLabel -or ($helmManagedBy -and $helmManagedBy.ToLowerInvariant() -eq 'helm')) {
                $chartName = $helmChartName
                $chartVersion = $helmChartVersion
                if (-not $chartName) {
                    $chartName = if ($appName) { $appName } else { $workloadName }
                }
                $helmKey = ("{0}|{1}|{2}|{3}" -f $chartName.ToLowerInvariant(), $chartVersion.ToLowerInvariant(), $helmReleaseName.ToLowerInvariant(), $namespace.ToLowerInvariant())
                if (-not $helmByKey.ContainsKey($helmKey)) {
                    $helmByKey[$helmKey] = [PSCustomObject]@{
                        name = $chartName
                        version = $chartVersion
                        releaseName = $helmReleaseName
                        releaseNamespace = if ($helmReleaseNs) { $helmReleaseNs } else { $namespace }
                        namespace = $namespace
                        workloadKind = $kind
                        workloadName = $workloadName
                        source = if ($helmChartLabel) { 'helm.sh/chart' } else { 'app.kubernetes.io/managed-by=Helm' }
                    }
                }
            }

            if (-not $podSpec) { continue }
            $containers = @($podSpec.containers) + @($podSpec.initContainers)
            foreach ($container in @($containers)) {
                if (-not $container) { continue }
                $imageRef = [string]$container.image
                if ([string]::IsNullOrWhiteSpace($imageRef)) { continue }

                $parts = Get-KubeBuddyImageParts -Image $imageRef
                if (-not $parts.fullRef) { continue }

                $imageKey = $parts.fullRef.ToLowerInvariant()
                if (-not $imagesByKey.ContainsKey($imageKey)) {
                    $imagesByKey[$imageKey] = [PSCustomObject]@{
                        fullRef = $parts.fullRef
                        name = $parts.name
                        tag = $parts.tag
                        digest = $parts.digest
                        currentVersion = $parts.currentVersion
                        namespace = $namespace
                        workloadKind = $kind
                        workloadName = $workloadName
                        containerName = [string]$container.name
                        source = 'workload_spec'
                        managedByHelm = $isHelmManaged
                        helmChartName = $helmChartName
                        helmReleaseName = $helmReleaseName
                        managedBy = $managedByValue
                        managedByController = $isControllerManaged
                        controllerOwnerName = $controllerOwnerName
                        controllerOwnerNamespace = if ($controllerOwnerNamespace) { $controllerOwnerNamespace } else { $namespace }
                        partOf = $partOfValue
                    }
                }
            }
        }
    }

    $images = @($imagesByKey.Values | Sort-Object fullRef)
    $helmCharts = @($helmByKey.Values | Sort-Object name, version, namespace)
    $apps = @($appsByKey.Values | Sort-Object name, version, namespace)

    return @{
        images = $images
        helmCharts = $helmCharts
        apps = $apps
        meta = @{
            excludedNamespacesApplied = [bool]$ExcludeNamespaces
            excludedNamespaces = @($excludedNamespaces)
            omittedWorkloads = [int]$omittedWorkloads
            omittedNamespaces = @($omittedNamespaceMap.Keys | Sort-Object)
        }
        summary = @{
            images = $images.Count
            helmCharts = $helmCharts.Count
            apps = $apps.Count
            total = $images.Count + $helmCharts.Count + $apps.Count
        }
    }
}

function Get-KubeBuddyRadarFreshnessLookup {
    param(
        [object]$Freshness
    )

    $lookup = @{}
    if (-not $Freshness -or -not $Freshness.items) {
        return $lookup
    }

    foreach ($item in @($Freshness.items)) {
        if (-not $item) { continue }

        $artifactType = [string]($item.artifact_type ?? '')
        $artifactKey = [string]($item.artifact_key ?? '')
        $currentVersion = Normalize-KubeBuddyRadarVersion -Version ([string]($item.current_version ?? ''))
        if ([string]::IsNullOrWhiteSpace($artifactType) -or [string]::IsNullOrWhiteSpace($artifactKey)) {
            continue
        }

        $fullKey = ("{0}|{1}|{2}" -f $artifactType.ToLowerInvariant(), $artifactKey.ToLowerInvariant(), $currentVersion.ToLowerInvariant())
        $baseKey = ("{0}|{1}" -f $artifactType.ToLowerInvariant(), $artifactKey.ToLowerInvariant())
        $lookup[$fullKey] = $item
        $lookup[$baseKey] = $item
    }

    return $lookup
}

function Get-KubeBuddyRadarArtifactFreshnessItem {
    param(
        [hashtable]$FreshnessLookup,
        [string]$ArtifactType,
        [string]$ArtifactKey,
        [string]$CurrentVersion
    )

    if (-not $FreshnessLookup) {
        return $null
    }

    $normalizedVersion = Normalize-KubeBuddyRadarVersion -Version ([string]$CurrentVersion)
    $fullKey = ("{0}|{1}|{2}" -f $ArtifactType.ToLowerInvariant(), $ArtifactKey.ToLowerInvariant(), $normalizedVersion)
    if ($FreshnessLookup.ContainsKey($fullKey)) {
        return $FreshnessLookup[$fullKey]
    }

    $baseKey = ("{0}|{1}" -f $ArtifactType.ToLowerInvariant(), $ArtifactKey.ToLowerInvariant())
    if ($FreshnessLookup.ContainsKey($baseKey)) {
        return $FreshnessLookup[$baseKey]
    }

    return $null
}

function Normalize-KubeBuddyRadarVersion {
    param(
        [string]$Version
    )

    $v = [string]$Version
    if ([string]::IsNullOrWhiteSpace($v)) {
        return ''
    }
    $trimmed = $v.Trim().ToLowerInvariant()
    if ($trimmed.StartsWith('v') -and $trimmed.Length -gt 1 -and [char]::IsDigit($trimmed[1])) {
        return $trimmed.Substring(1)
    }
    return $trimmed
}

function Merge-KubeBuddyHelmChartRows {
    param(
        [object[]]$HelmCharts
    )

    $rows = @($HelmCharts)
    if ($rows.Count -eq 0) {
        return @()
    }

    $statusRank = @{
        'major_behind' = 4
        'minor_behind' = 3
        'unknown' = 2
        'up_to_date' = 1
    }
    $map = @{}

    foreach ($chart in $rows) {
        if (-not $chart) { continue }
        $name = [string]($chart.name ?? '')
        $ns = [string]($chart.namespace ?? $chart.releaseNamespace ?? '')
        $key = ("{0}|{1}" -f $name.ToLowerInvariant(), $ns.ToLowerInvariant())
        if ([string]::IsNullOrWhiteSpace($name)) { continue }

        if (-not $map.ContainsKey($key)) {
            $map[$key] = $chart
            continue
        }

        $cur = $map[$key]
        $curStatus = [string]($cur.freshnessStatus ?? 'unknown')
        $nextStatus = [string]($chart.freshnessStatus ?? 'unknown')
        $curRank = if ($statusRank.ContainsKey($curStatus)) { [int]$statusRank[$curStatus] } else { 0 }
        $nextRank = if ($statusRank.ContainsKey($nextStatus)) { [int]$statusRank[$nextStatus] } else { 0 }
        if ($nextRank -gt $curRank) {
            $map[$key] = $chart
            $cur = $chart
        }

        if ([string]::IsNullOrWhiteSpace([string]($cur.releaseName ?? '')) -and -not [string]::IsNullOrWhiteSpace([string]($chart.releaseName ?? ''))) {
            $cur.releaseName = [string]$chart.releaseName
        }
        if ([string]::IsNullOrWhiteSpace([string]($cur.latestVersion ?? '')) -and -not [string]::IsNullOrWhiteSpace([string]($chart.latestVersion ?? ''))) {
            $cur.latestVersion = [string]$chart.latestVersion
        }
    }

    return @($map.Values | Sort-Object name, namespace)
}

function Get-KubeBuddyRadarArtifactRecommendation {
    param(
        [string]$Status,
        [string]$Latest,
        [bool]$IsMonitored = $false
    )

    $statusNorm = ([string]$Status).Trim().ToLowerInvariant()
    $latestNorm = ([string]$Latest).Trim()
    if ($statusNorm -eq 'major_behind' -or $statusNorm -eq 'minor_behind') {
        if (-not [string]::IsNullOrWhiteSpace($latestNorm) -and $latestNorm -ne 'not monitored') {
            return "Update recommended. Target $latestNorm and review breaking changes."
        }
        return "Update recommended. Review latest release notes and breaking changes."
    }
    if ($statusNorm -eq 'up_to_date') {
        return "Up to date. Keep monitoring for new releases."
    }
    if ($IsMonitored -or (-not [string]::IsNullOrWhiteSpace($latestNorm) -and $latestNorm -ne 'not monitored')) {
        return "Best-effort version compare. Review release notes before updating."
    }
    return "Not monitored in catalog yet. Request this artifact to be added."
}

function Convert-KubeBuddyRadarArtifactInventoryToText {
    param(
        [hashtable]$Inventory,
        [object]$Freshness
    )

    return @()

    $lines = @()
    $freshnessLookup = Get-KubeBuddyRadarFreshnessLookup -Freshness $Freshness
    $helmChartsMerged = Merge-KubeBuddyHelmChartRows -HelmCharts @($Inventory.helmCharts)
    $lines += ""
    $lines += "[📦 Outdated Artifacts]"
    $lines += "Best-effort version matching from chart/image names and tags. Results are indicative, not guaranteed 100% accurate."
    $lines += "Helm Charts: $($helmChartsMerged.Count) | Images: $($Inventory.summary.images)"
    if ($Inventory.meta -and [int]($Inventory.meta.omittedWorkloads ?? 0) -gt 0) {
        $lines += "Excluded namespaces omitted $([int]$Inventory.meta.omittedWorkloads) workload(s) from inventory: $((@($Inventory.meta.omittedNamespaces) -join ', '))"
    }
    if ($Freshness -and $Freshness.summary) {
        $lines += "Freshness: Up-to-date $($Freshness.summary.up_to_date) | Minor behind $($Freshness.summary.minor_behind) | Major behind $($Freshness.summary.major_behind) | Unknown $($Freshness.summary.unknown)"
    }

    $lines += ""
    $lines += "[Helm Charts]"
    if ($helmChartsMerged.Count -eq 0) {
        $lines += "- None found."
    }
    else {
        foreach ($chart in $helmChartsMerged) {
            $version = if ($chart.version) { $chart.version } else { 'unknown' }
            $release = if ($chart.releaseName) { $chart.releaseName } else { 'unknown' }
            $freshnessItem = Get-KubeBuddyRadarArtifactFreshnessItem -FreshnessLookup $freshnessLookup -ArtifactType 'helm_chart' -ArtifactKey ([string]$chart.name) -CurrentVersion ([string]$version)
            $latest = if ($freshnessItem -and $freshnessItem.latest_version) { [string]$freshnessItem.latest_version } elseif ($chart.latestVersion) { [string]$chart.latestVersion } else { 'not monitored' }
            $status = if ($freshnessItem -and $freshnessItem.status) { [string]$freshnessItem.status } elseif ($chart.freshnessStatus) { [string]$chart.freshnessStatus } else { 'unknown' }
            $isMonitored = ($freshnessItem -and ( -not [string]::IsNullOrWhiteSpace([string]($freshnessItem.latest_version ?? '')) -or -not [string]::IsNullOrWhiteSpace([string]($freshnessItem.source ?? '')) )) -or ($latest -ne 'not monitored')
            $recommendation = Get-KubeBuddyRadarArtifactRecommendation -Status $status -Latest $latest -IsMonitored:$isMonitored
            $lines += "- Chart: $($chart.name) | Version: $version | Latest: $latest | Status: $status | Release: $release | Namespace: $($chart.namespace) | Workload: $($chart.workloadKind)/$($chart.workloadName) | Recommendation: $recommendation"
        }
    }

    $lines += ""
    $lines += "[Container Images]"
    if ($Inventory.images.Count -eq 0) {
        $lines += "- None found."
    }
    else {
        foreach ($img in $Inventory.images) {
            $freshnessItem = Get-KubeBuddyRadarArtifactFreshnessItem -FreshnessLookup $freshnessLookup -ArtifactType 'image' -ArtifactKey ([string]$img.fullRef) -CurrentVersion ([string]$img.currentVersion)
            if ($freshnessItem -and [bool]($freshnessItem.inherited_from_helm ?? $false)) {
                continue
            }
            if ($freshnessItem -and [string]($freshnessItem.status ?? '') -eq 'covered_by_controller') {
                continue
            }
            $latest = if ($freshnessItem -and $freshnessItem.latest_version) { [string]$freshnessItem.latest_version } elseif ($img.latestVersion) { [string]$img.latestVersion } else { 'not monitored' }
            $status = if ($freshnessItem -and $freshnessItem.status) { [string]$freshnessItem.status } elseif ($img.freshnessStatus) { [string]$img.freshnessStatus } else { 'unknown' }
            $isMonitored = ($freshnessItem -and ( -not [string]::IsNullOrWhiteSpace([string]($freshnessItem.latest_version ?? '')) -or -not [string]::IsNullOrWhiteSpace([string]($freshnessItem.source ?? '')) )) -or ($latest -ne 'not monitored')
            $recommendation = Get-KubeBuddyRadarArtifactRecommendation -Status $status -Latest $latest -IsMonitored:$isMonitored
            $lines += "- Image: $($img.fullRef) | Version: $($img.currentVersion) | Latest: $latest | Status: $status | Namespace: $($img.namespace) | Workload: $($img.workloadKind)/$($img.workloadName) | Container: $($img.containerName) | Recommendation: $recommendation"
        }
    }

    return $lines
}

function Convert-KubeBuddyRadarArtifactInventoryToHtml {
    param(
        [hashtable]$Inventory,
        [object]$Freshness
    )

    return ""

    $freshnessLookup = Get-KubeBuddyRadarFreshnessLookup -Freshness $Freshness
    $helmChartsMerged = Merge-KubeBuddyHelmChartRows -HelmCharts @($Inventory.helmCharts)
    $freshnessSummaryHtml = ""
    if ($Freshness -and $Freshness.summary) {
        $freshnessSummaryHtml = @"
<div class="hero-metrics">
  <div class="metric-card normal"><div class="card-content"><p>✅ Up to date: <strong>$($Freshness.summary.up_to_date)</strong></p></div></div>
  <div class="metric-card warning"><div class="card-content"><p>🟨 Minor behind: <strong>$($Freshness.summary.minor_behind)</strong></p></div></div>
  <div class="metric-card critical"><div class="card-content"><p>🟥 Major behind: <strong>$($Freshness.summary.major_behind)</strong></p></div></div>
  <div class="metric-card default"><div class="card-content"><p>❔ Unknown: <strong>$($Freshness.summary.unknown)</strong></p></div></div>
</div>
"@
    }

    $imageRowsCollection = @()
    $omittedImagesCoveredByHelm = 0
    if ($Inventory.images.Count -gt 0) {
        foreach ($img in $Inventory.images) {
            $freshnessItem = Get-KubeBuddyRadarArtifactFreshnessItem -FreshnessLookup $freshnessLookup -ArtifactType 'image' -ArtifactKey ([string]$img.fullRef) -CurrentVersion ([string]$img.currentVersion)
            if ($freshnessItem -and [bool]($freshnessItem.inherited_from_helm ?? $false)) {
                $omittedImagesCoveredByHelm++
                continue
            }
            if ($freshnessItem -and [string]($freshnessItem.status ?? '') -eq 'covered_by_controller') {
                $omittedImagesCoveredByHelm++
                continue
            }
            $latest = if ($freshnessItem -and $freshnessItem.latest_version) { [string]$freshnessItem.latest_version } elseif ($img.latestVersion) { [string]$img.latestVersion } else { 'not monitored' }
            $status = if ($freshnessItem -and $freshnessItem.status) { [string]$freshnessItem.status } elseif ($img.freshnessStatus) { [string]$img.freshnessStatus } else { 'unknown' }
            $isMonitored = ($freshnessItem -and ( -not [string]::IsNullOrWhiteSpace([string]($freshnessItem.latest_version ?? '')) -or -not [string]::IsNullOrWhiteSpace([string]($freshnessItem.source ?? '')) )) -or ($latest -ne 'not monitored')
            $recommendation = Get-KubeBuddyRadarArtifactRecommendation -Status $status -Latest $latest -IsMonitored:$isMonitored
            $imageRowsCollection += "<tr><td>$($img.fullRef)</td><td>$($img.currentVersion)</td><td>$latest</td><td>$status</td><td>$($img.namespace)</td><td>$($img.workloadKind)/$($img.workloadName)</td><td>$($img.containerName)</td><td>$recommendation</td></tr>"
        }
    }
    $imageRows = if ($imageRowsCollection.Count -gt 0) {
        $imageRowsCollection -join "`n"
    } else {
        "<tr><td colspan='8'>No standalone container images detected (all covered by Helm chart checks or none detected).</td></tr>"
    }

    $chartRows = if ($helmChartsMerged.Count -gt 0) {
        ($helmChartsMerged | ForEach-Object {
            $version = if ($_.version) { $_.version } else { 'unknown' }
            $release = if ($_.releaseName) { $_.releaseName } else { 'unknown' }
            $freshnessItem = Get-KubeBuddyRadarArtifactFreshnessItem -FreshnessLookup $freshnessLookup -ArtifactType 'helm_chart' -ArtifactKey ([string]$_.name) -CurrentVersion ([string]$version)
            $latest = if ($freshnessItem -and $freshnessItem.latest_version) { [string]$freshnessItem.latest_version } elseif ($_.latestVersion) { [string]$_.latestVersion } else { 'not monitored' }
            $status = if ($freshnessItem -and $freshnessItem.status) { [string]$freshnessItem.status } elseif ($_.freshnessStatus) { [string]$_.freshnessStatus } else { 'unknown' }
            $isMonitored = ($freshnessItem -and ( -not [string]::IsNullOrWhiteSpace([string]($freshnessItem.latest_version ?? '')) -or -not [string]::IsNullOrWhiteSpace([string]($freshnessItem.source ?? '')) )) -or ($latest -ne 'not monitored')
            $recommendation = Get-KubeBuddyRadarArtifactRecommendation -Status $status -Latest $latest -IsMonitored:$isMonitored
            "<tr><td>$($_.name)</td><td>$version</td><td>$latest</td><td>$status</td><td>$release</td><td>$($_.namespace)</td><td>$($_.workloadKind)/$($_.workloadName)</td><td>$recommendation</td></tr>"
        }) -join "`n"
    }
    else {
        "<tr><td colspan='8'>No Helm charts detected.</td></tr>"
    }

    return @"
<h2>Outdated Artifacts</h2>
<p>This section is included because Radar mode is enabled for this run. It captures deterministic image, Helm chart, and app versions from Kubernetes workload specs and labels.</p>
<p><strong>Best effort:</strong> version matching is based on artifact names and tags. Results are indicative and may not be 100% accurate.</p>
$(if ($Inventory.meta -and [int]($Inventory.meta.omittedWorkloads ?? 0) -gt 0) { "<p><strong>Excluded namespaces:</strong> omitted $([int]$Inventory.meta.omittedWorkloads) workload(s) from inventory: $((@($Inventory.meta.omittedNamespaces) -join ', ')).</p>" } else { "" })
$freshnessSummaryHtml
<div class="hero-metrics">
  <div class="metric-card default"><div class="card-content"><p>⎈ Helm Charts: <strong>$($helmChartsMerged.Count)</strong></p></div></div>
  <div class="metric-card default"><div class="card-content"><p>🧱 Images: <strong>$($Inventory.summary.images)</strong></p></div></div>
  <div class="metric-card default"><div class="card-content"><p>📊 Tracked: <strong>$([int]$Inventory.summary.images + [int]$helmChartsMerged.Count)</strong></p></div></div>
</div>

<h3>Helm Charts</h3>
<div class="table-container">
  <table>
    <thead><tr><th>Chart</th><th>Version</th><th>Latest</th><th>Status</th><th>Release</th><th>Namespace</th><th>Workload</th><th>Recommendation</th></tr></thead>
    <tbody>
      $chartRows
    </tbody>
  </table>
</div>

<h3>Container Images</h3>
<div class="table-container">
  <table>
    <thead><tr><th>Image</th><th>Version</th><th>Latest</th><th>Status</th><th>Namespace</th><th>Workload</th><th>Container</th><th>Recommendation</th></tr></thead>
    <tbody>
      $imageRows
    </tbody>
  </table>
</div>
"@
}

function Update-KubeBuddyJsonReportWithRadarFreshness {
    param(
        [string]$ReportPath,
        [object]$Freshness
    )

    if ([string]::IsNullOrWhiteSpace($ReportPath) -or -not (Test-Path $ReportPath) -or -not $Freshness) {
        return
    }

    try {
        $json = Get-Content -Raw -Path $ReportPath | ConvertFrom-Json -Depth 60
        if (-not $json.radar) {
            $json | Add-Member -NotePropertyName radar -NotePropertyValue ([PSCustomObject]@{}) -Force
        }
        $json.radar | Add-Member -NotePropertyName freshness -NotePropertyValue $Freshness -Force
        $json.radar | Add-Member -NotePropertyName freshnessFetchedAt -NotePropertyValue ((Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")) -Force

        $lookup = Get-KubeBuddyRadarFreshnessLookup -Freshness $Freshness
        if ($json.artifacts) {
            foreach ($img in @($json.artifacts.images)) {
                if (-not $img) { continue }
                $current = [string]($img.currentVersion ?? '')
                $match = Get-KubeBuddyRadarArtifactFreshnessItem -FreshnessLookup $lookup -ArtifactType 'image' -ArtifactKey ([string]$img.fullRef) -CurrentVersion $current
                $img | Add-Member -NotePropertyName latestVersion -NotePropertyValue ([string]($match.latest_version ?? '')) -Force
                $img | Add-Member -NotePropertyName freshnessStatus -NotePropertyValue ([string]($match.status ?? 'unknown')) -Force
                $img | Add-Member -NotePropertyName freshnessConfidence -NotePropertyValue ([double]($match.confidence ?? 0)) -Force
                $img | Add-Member -NotePropertyName freshnessReason -NotePropertyValue ([string]($match.reason ?? '')) -Force
                $img | Add-Member -NotePropertyName freshnessSource -NotePropertyValue ([string]($match.source ?? '')) -Force
                $img | Add-Member -NotePropertyName globalLatestVersion -NotePropertyValue ([string]($match.global_latest_version ?? '')) -Force
                $img | Add-Member -NotePropertyName compareMode -NotePropertyValue ([string]($match.compare_mode ?? '')) -Force
                $img | Add-Member -NotePropertyName inheritedFromHelm -NotePropertyValue ([bool]($match.inherited_from_helm ?? $false)) -Force
            }

            foreach ($chart in @($json.artifacts.helmCharts)) {
                if (-not $chart) { continue }
                $current = [string]($chart.version ?? '')
                $match = Get-KubeBuddyRadarArtifactFreshnessItem -FreshnessLookup $lookup -ArtifactType 'helm_chart' -ArtifactKey ([string]$chart.name) -CurrentVersion $current
                $chart | Add-Member -NotePropertyName latestVersion -NotePropertyValue ([string]($match.latest_version ?? '')) -Force
                $chart | Add-Member -NotePropertyName freshnessStatus -NotePropertyValue ([string]($match.status ?? 'unknown')) -Force
                $chart | Add-Member -NotePropertyName freshnessConfidence -NotePropertyValue ([double]($match.confidence ?? 0)) -Force
                $chart | Add-Member -NotePropertyName freshnessReason -NotePropertyValue ([string]($match.reason ?? '')) -Force
                $chart | Add-Member -NotePropertyName freshnessSource -NotePropertyValue ([string]($match.source ?? '')) -Force
                $chart | Add-Member -NotePropertyName globalLatestVersion -NotePropertyValue ([string]($match.global_latest_version ?? '')) -Force
                $chart | Add-Member -NotePropertyName compareMode -NotePropertyValue ([string]($match.compare_mode ?? '')) -Force
                $chart | Add-Member -NotePropertyName inheritedFromHelm -NotePropertyValue ([bool]($match.inherited_from_helm ?? $false)) -Force
            }

            # Apps are intentionally not enriched in direct lookup mode to reduce noise.
        }

        $json | ConvertTo-Json -Depth 60 | Set-Content -Encoding UTF8 -Path $ReportPath
    }
    catch {
        Write-Host "⚠️ Could not update JSON report with Radar freshness data: $($_.Exception.Message)" -ForegroundColor Yellow
    }
}
