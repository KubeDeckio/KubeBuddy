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
        [object]$KubeData
    )

    $imagesByKey = @{}
    $helmByKey = @{}
    $appsByKey = @{}

    $workloadSets = @(
        @{ Kind = 'Deployment'; Items = @($KubeData.Deployments) },
        @{ Kind = 'StatefulSet'; Items = @($KubeData.StatefulSets) },
        @{ Kind = 'DaemonSet'; Items = @($KubeData.DaemonSets) },
        @{ Kind = 'Job'; Items = @($KubeData.Jobs) },
        @{ Kind = 'CronJob'; Items = @($KubeData.CronJobs) },
        @{ Kind = 'Pod'; Items = @($KubeData.Pods.items) }
    )

    foreach ($set in $workloadSets) {
        foreach ($item in @($set.Items)) {
            if (-not $item) { continue }

            $kind = [string]$set.Kind
            $metadata = $item.metadata
            $namespace = if ($metadata.namespace) { [string]$metadata.namespace } else { 'cluster-wide' }
            $workloadName = if ($metadata.name) { [string]$metadata.name } else { 'unknown' }

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
                    }
                }
            }

            $helmChartLabel = Get-KubeBuddyArtifactLabelValue -Labels $labels -Keys @('helm.sh/chart')
            $helmManagedBy = Get-KubeBuddyArtifactLabelValue -Labels $labels -Keys @('app.kubernetes.io/managed-by')
            $helmReleaseName = if ($annotations.ContainsKey('meta.helm.sh/release-name')) { [string]$annotations['meta.helm.sh/release-name'] } else { '' }
            $helmReleaseNs = if ($annotations.ContainsKey('meta.helm.sh/release-namespace')) { [string]$annotations['meta.helm.sh/release-namespace'] } else { '' }
            if ($helmChartLabel -or ($helmManagedBy -and $helmManagedBy.ToLowerInvariant() -eq 'helm')) {
                $chartName = $helmChartLabel
                $chartVersion = ''
                if ($helmChartLabel -match '^(?<name>.+)-(?<version>v?\d[\w\.\-\+]*)$') {
                    $chartName = [string]$matches.name
                    $chartVersion = [string]$matches.version
                }
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
        summary = @{
            images = $images.Count
            helmCharts = $helmCharts.Count
            apps = $apps.Count
            total = $images.Count + $helmCharts.Count + $apps.Count
        }
    }
}

function Convert-KubeBuddyRadarArtifactInventoryToText {
    param(
        [hashtable]$Inventory
    )

    if (-not $Inventory) {
        return @()
    }

    $lines = @()
    $lines += ""
    $lines += "[📡 Radar Artifact Inventory (Pro)]"
    $lines += "Images: $($Inventory.summary.images) | Helm Charts: $($Inventory.summary.helmCharts) | Apps: $($Inventory.summary.apps) | Total: $($Inventory.summary.total)"

    $lines += ""
    $lines += "[Images]"
    if ($Inventory.images.Count -eq 0) {
        $lines += "- None found."
    }
    else {
        foreach ($img in $Inventory.images) {
            $lines += "- Image: $($img.fullRef) | Version: $($img.currentVersion) | Namespace: $($img.namespace) | Workload: $($img.workloadKind)/$($img.workloadName) | Container: $($img.containerName)"
        }
    }

    $lines += ""
    $lines += "[Helm Charts]"
    if ($Inventory.helmCharts.Count -eq 0) {
        $lines += "- None found."
    }
    else {
        foreach ($chart in $Inventory.helmCharts) {
            $version = if ($chart.version) { $chart.version } else { 'unknown' }
            $release = if ($chart.releaseName) { $chart.releaseName } else { 'unknown' }
            $lines += "- Chart: $($chart.name) | Version: $version | Release: $release | Namespace: $($chart.namespace) | Workload: $($chart.workloadKind)/$($chart.workloadName)"
        }
    }

    $lines += ""
    $lines += "[Apps]"
    if ($Inventory.apps.Count -eq 0) {
        $lines += "- None found."
    }
    else {
        foreach ($app in $Inventory.apps) {
            $lines += "- App: $($app.name) | Version: $($app.version) | Namespace: $($app.namespace) | Workload: $($app.workloadKind)/$($app.workloadName)"
        }
    }

    return $lines
}

function Convert-KubeBuddyRadarArtifactInventoryToHtml {
    param(
        [hashtable]$Inventory
    )

    if (-not $Inventory) {
        return ""
    }

    $imageRows = if ($Inventory.images.Count -gt 0) {
        ($Inventory.images | ForEach-Object {
            "<tr><td>$($_.fullRef)</td><td>$($_.currentVersion)</td><td>$($_.namespace)</td><td>$($_.workloadKind)/$($_.workloadName)</td><td>$($_.containerName)</td></tr>"
        }) -join "`n"
    }
    else {
        "<tr><td colspan='5'>No container images detected.</td></tr>"
    }

    $chartRows = if ($Inventory.helmCharts.Count -gt 0) {
        ($Inventory.helmCharts | ForEach-Object {
            $version = if ($_.version) { $_.version } else { 'unknown' }
            $release = if ($_.releaseName) { $_.releaseName } else { 'unknown' }
            "<tr><td>$($_.name)</td><td>$version</td><td>$release</td><td>$($_.namespace)</td><td>$($_.workloadKind)/$($_.workloadName)</td></tr>"
        }) -join "`n"
    }
    else {
        "<tr><td colspan='5'>No Helm charts detected.</td></tr>"
    }

    $appRows = if ($Inventory.apps.Count -gt 0) {
        ($Inventory.apps | ForEach-Object {
            "<tr><td>$($_.name)</td><td>$($_.version)</td><td>$($_.namespace)</td><td>$($_.workloadKind)/$($_.workloadName)</td><td>$($_.source)</td></tr>"
        }) -join "`n"
    }
    else {
        "<tr><td colspan='5'>No app labels with versions detected.</td></tr>"
    }

    return @"
<h2>Radar Artifact Inventory (Pro)</h2>
<p>This section is included because Radar mode is enabled for this run. It captures deterministic image, Helm chart, and app versions from Kubernetes workload specs and labels.</p>
<div class="hero-metrics">
  <div class="metric-card default"><div class="card-content"><p>🧱 Images: <strong>$($Inventory.summary.images)</strong></p></div></div>
  <div class="metric-card default"><div class="card-content"><p>⎈ Helm Charts: <strong>$($Inventory.summary.helmCharts)</strong></p></div></div>
  <div class="metric-card default"><div class="card-content"><p>📦 Apps: <strong>$($Inventory.summary.apps)</strong></p></div></div>
  <div class="metric-card default"><div class="card-content"><p>📊 Total: <strong>$($Inventory.summary.total)</strong></p></div></div>
</div>

<h3>Container Images</h3>
<div class="table-container">
  <table>
    <thead><tr><th>Image</th><th>Version</th><th>Namespace</th><th>Workload</th><th>Container</th></tr></thead>
    <tbody>
      $imageRows
    </tbody>
  </table>
</div>

<h3>Helm Charts</h3>
<div class="table-container">
  <table>
    <thead><tr><th>Chart</th><th>Version</th><th>Release</th><th>Namespace</th><th>Workload</th></tr></thead>
    <tbody>
      $chartRows
    </tbody>
  </table>
</div>

<h3>Apps</h3>
<div class="table-container">
  <table>
    <thead><tr><th>App</th><th>Version</th><th>Namespace</th><th>Workload</th><th>Source</th></tr></thead>
    <tbody>
      $appRows
    </tbody>
  </table>
</div>
"@
}
