function Get-KubeBuddyRadarConfig {
    $defaults = @{
        enabled                = $false
        api_base_url           = "https://radar.kubebuddy.io/api/kb-radar/v1"
        environment            = "prod"
        api_user               = ""
        api_password           = ""
        api_user_env           = "KUBEBUDDY_RADAR_API_USER"
        api_password_env       = "KUBEBUDDY_RADAR_API_PASSWORD"
        upload_timeout_seconds = 30
        upload_retries         = 2
    }

    $configPath = Get-KubeBuddyConfigPath
    if (-not (Test-Path $configPath)) {
        return $defaults
    }

    try {
        $config = Get-Content -Raw $configPath | ConvertFrom-Yaml
        $radar = $config.radar
        if (-not $radar) {
            return $defaults
        }

        return @{
            enabled                = [bool]($radar.enabled ?? $defaults.enabled)
            api_base_url           = [string]($radar.api_base_url ?? $defaults.api_base_url)
            environment            = [string]($radar.environment ?? $defaults.environment)
            api_user               = [string]($radar.api_user ?? $defaults.api_user)
            api_password           = [string]($radar.api_password ?? $defaults.api_password)
            api_user_env           = [string]($radar.api_user_env ?? $defaults.api_user_env)
            api_password_env       = [string]($radar.api_password_env ?? $defaults.api_password_env)
            upload_timeout_seconds = [int]($radar.upload_timeout_seconds ?? $defaults.upload_timeout_seconds)
            upload_retries         = [int]($radar.upload_retries ?? $defaults.upload_retries)
        }
    }
    catch {
        return $defaults
    }
}

function Resolve-KubeBuddyRadarSettings {
    param(
        [switch]$RadarUpload,
        [switch]$RadarCompare,
        [string]$RadarApiBaseUrl,
        [string]$RadarEnvironment,
        [string]$RadarApiUserEnv,
        [string]$RadarApiSecretEnv
    )

    $config = Get-KubeBuddyRadarConfig

    $enabled = [bool]$config.enabled
    if ($RadarUpload -or $RadarCompare) {
        $enabled = $true
    }

    return @{
        enabled          = $enabled
        compare_enabled  = [bool]$RadarCompare
        upload_enabled   = [bool]$RadarUpload
        api_base_url     = if ($RadarApiBaseUrl) { $RadarApiBaseUrl } else { $config.api_base_url }
        environment      = if ($RadarEnvironment) { $RadarEnvironment } else { $config.environment }
        api_user         = [string]$config.api_user
        api_password     = [string]$config.api_password
        api_user_env     = if ($RadarApiUserEnv) { $RadarApiUserEnv } else { $config.api_user_env }
        api_password_env = if ($RadarApiSecretEnv) { $RadarApiSecretEnv } else { $config.api_password_env }
        upload_timeout_seconds = [int]$config.upload_timeout_seconds
        upload_retries   = [int]$config.upload_retries
    }
}

function Invoke-KubeBuddyRadarGetConfig {
    param(
        [hashtable]$RadarSettings,
        [string]$ConfigId
    )

    if (-not $RadarSettings.enabled) {
        throw "Radar config fetch requires Radar to be enabled."
    }

    if ([string]::IsNullOrWhiteSpace($ConfigId)) {
        throw "Radar config fetch requires -RadarConfigId."
    }

    $headers = Get-KubeBuddyRadarAuthHeaders -RadarSettings $RadarSettings
    $baseUrl = [string]$RadarSettings.api_base_url
    if ([string]::IsNullOrWhiteSpace($baseUrl)) {
        throw "Radar API base URL is empty. Set radar.api_base_url or pass -RadarApiBaseUrl."
    }

    $endpoint = "{0}/cluster-configs/{1}" -f $baseUrl.Trim().TrimEnd('/'), [Uri]::EscapeDataString($ConfigId)
    $configUri = $null
    if (-not [Uri]::TryCreate($endpoint, [UriKind]::Absolute, [ref]$configUri)) {
        throw "Invalid Radar config URI: $endpoint"
    }

    return Invoke-RestMethod -Uri $configUri -Method Get -Headers $headers -TimeoutSec ([Math]::Max([int]$RadarSettings.upload_timeout_seconds, 5))
}

function Invoke-KubeBuddyRadarGetConfigFile {
    param(
        [hashtable]$RadarSettings,
        [string]$ConfigId
    )

    if (-not $RadarSettings.enabled) {
        throw "Radar config fetch requires Radar to be enabled."
    }

    if ([string]::IsNullOrWhiteSpace($ConfigId)) {
        throw "Radar config fetch requires -RadarConfigId."
    }

    $headers = Get-KubeBuddyRadarAuthHeaders -RadarSettings $RadarSettings
    $baseUrl = [string]$RadarSettings.api_base_url
    if ([string]::IsNullOrWhiteSpace($baseUrl)) {
        throw "Radar API base URL is empty. Set radar.api_base_url or pass -RadarApiBaseUrl."
    }

    $endpoint = "{0}/cluster-configs/{1}/config-file" -f $baseUrl.Trim().TrimEnd('/'), [Uri]::EscapeDataString($ConfigId)
    $configUri = $null
    if (-not [Uri]::TryCreate($endpoint, [UriKind]::Absolute, [ref]$configUri)) {
        throw "Invalid Radar config-file URI: $endpoint"
    }

    return Invoke-RestMethod -Uri $configUri -Method Get -Headers $headers -TimeoutSec ([Math]::Max([int]$RadarSettings.upload_timeout_seconds, 5))
}

function Get-KubeBuddyRadarAuthHeaders {
    param([hashtable]$RadarSettings)

    $user = [string]$RadarSettings.api_user
    $password = [string]$RadarSettings.api_password

    if (-not $user -or -not $password) {
        $userEnv = [string]$RadarSettings.api_user_env
        $passwordEnv = [string]$RadarSettings.api_password_env
        $user = [Environment]::GetEnvironmentVariable($userEnv)
        $password = [Environment]::GetEnvironmentVariable($passwordEnv)
    }

    if (-not $user -or -not $password) {
        $userEnv = [string]$RadarSettings.api_user_env
        $passwordEnv = [string]$RadarSettings.api_password_env
        throw "Radar credentials missing. Set radar.api_user/api_password in config or env vars '$userEnv' and '$passwordEnv'."
    }

    $raw = "${user}:${password}"
    $encoded = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($raw))

    return @{
        Authorization = "Basic $encoded"
        "Content-Type" = "application/json"
    }
}

function New-KubeBuddyRadarUploadPayload {
    param(
        [string]$ReportPath,
        [string]$ModuleVersion,
        [hashtable]$RadarSettings
    )

    if (-not (Test-Path $ReportPath)) {
        throw "JSON report path not found: $ReportPath"
    }

    $report = Get-Content -Raw $ReportPath | ConvertFrom-Json -Depth 30
    $metadata = $report.metadata
    $startedAt = [DateTime]::UtcNow
    $clusterName = [string]($metadata.clusterName ?? "")
    if ([string]::IsNullOrWhiteSpace($clusterName)) {
        $clusterName = [string]($metadata.aks.clusterName ?? "")
    }
    if ([string]::IsNullOrWhiteSpace($clusterName)) {
        $clusterName = "unknown"
    }
    return @{
        source = "kubebuddy-cli"
        source_version = $ModuleVersion
        environment = $RadarSettings.environment
        cluster = @{
            name = $clusterName
            provider = if ($metadata.aks) { "aks" } else { "kubernetes" }
            region = [string]($metadata.aks.location ?? "")
        }
        run = @{
            started_at = $startedAt.ToString("yyyy-MM-ddTHH:mm:ssZ")
            finished_at = [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ")
            duration_seconds = 0
        }
        report = $report
    }
}

function Invoke-KubeBuddyRadarUpload {
    param(
        [string]$ReportPath,
        [string]$ModuleVersion,
        [hashtable]$RadarSettings
    )

    if (-not $RadarSettings.enabled -or -not $RadarSettings.upload_enabled) {
        return $null
    }

    $headers = Get-KubeBuddyRadarAuthHeaders -RadarSettings $RadarSettings
    $payload = New-KubeBuddyRadarUploadPayload -ReportPath $ReportPath -ModuleVersion $ModuleVersion -RadarSettings $RadarSettings
    $body = $payload | ConvertTo-Json -Depth 40

    $baseUrl = [string]$RadarSettings.api_base_url
    if ([string]::IsNullOrWhiteSpace($baseUrl)) {
        throw "Radar API base URL is empty. Set radar.api_base_url or pass -RadarApiBaseUrl."
    }
    $baseUrl = $baseUrl.Trim()
    $endpoint = "{0}/cluster-reports" -f $baseUrl.TrimEnd('/')
    $uploadUri = $null
    if (-not [Uri]::TryCreate($endpoint, [UriKind]::Absolute, [ref]$uploadUri)) {
        throw "Invalid Radar upload URI: $endpoint"
    }
    $retries = [Math]::Max([int]$RadarSettings.upload_retries, 0)
    $timeout = [Math]::Max([int]$RadarSettings.upload_timeout_seconds, 5)

    for ($attempt = 0; $attempt -le $retries; $attempt++) {
        try {
            return Invoke-RestMethod -Uri $uploadUri -Method Post -Headers $headers -Body $body -TimeoutSec $timeout
        }
        catch {
            if ($attempt -ge $retries) {
                throw
            }
            Start-Sleep -Seconds 1
        }
    }
}

function Invoke-KubeBuddyRadarCompare {
    param(
        [hashtable]$RadarSettings,
        [string]$ToRunId
    )

    if (-not $RadarSettings.enabled -or -not $RadarSettings.compare_enabled) {
        return $null
    }

    $headers = Get-KubeBuddyRadarAuthHeaders -RadarSettings $RadarSettings
    $baseUrl = [string]$RadarSettings.api_base_url
    if ([string]::IsNullOrWhiteSpace($baseUrl)) {
        throw "Radar API base URL is empty. Set radar.api_base_url or pass -RadarApiBaseUrl."
    }
    $baseUrl = $baseUrl.Trim()
    $base = "{0}/cluster-reports/compare" -f $baseUrl.TrimEnd('/')

    $params = @()
    if ($ToRunId) {
        $params += "to_run_id=$([Uri]::EscapeDataString($ToRunId))"
    }

    $uriString = "${base}?" + ($params -join '&')
    $compareUri = $null
    if (-not [Uri]::TryCreate($uriString, [UriKind]::Absolute, [ref]$compareUri)) {
        throw "Invalid Radar compare URI: $uriString"
    }

    return Invoke-RestMethod -Uri $compareUri -Method Get -Headers $headers -TimeoutSec ([Math]::Max([int]$RadarSettings.upload_timeout_seconds, 5))
}

function Invoke-KubeBuddyRadarFreshness {
    param(
        [hashtable]$RadarSettings,
        [string]$RunId
    )

    if (-not $RadarSettings.enabled -or -not $RadarSettings.upload_enabled) {
        return $null
    }

    if ([string]::IsNullOrWhiteSpace($RunId)) {
        return $null
    }

    $headers = Get-KubeBuddyRadarAuthHeaders -RadarSettings $RadarSettings
    $baseUrl = [string]$RadarSettings.api_base_url
    if ([string]::IsNullOrWhiteSpace($baseUrl)) {
        throw "Radar API base URL is empty. Set radar.api_base_url or pass -RadarApiBaseUrl."
    }
    $baseUrl = $baseUrl.Trim()
    $endpoint = "{0}/cluster-reports/{1}/freshness" -f $baseUrl.TrimEnd('/'), [Uri]::EscapeDataString($RunId)

    $freshnessUri = $null
    if (-not [Uri]::TryCreate($endpoint, [UriKind]::Absolute, [ref]$freshnessUri)) {
        throw "Invalid Radar freshness URI: $endpoint"
    }

    return Invoke-RestMethod -Uri $freshnessUri -Method Get -Headers $headers -TimeoutSec ([Math]::Max([int]$RadarSettings.upload_timeout_seconds, 5))
}

function Get-KubeBuddyRadarSemverCompare {
    param(
        [string]$Current,
        [string]$Latest
    )

    $a = [string]$Current
    $b = [string]$Latest
    if ([string]::IsNullOrWhiteSpace($a) -or [string]::IsNullOrWhiteSpace($b)) {
        return $null
    }

    $a = $a.Trim().TrimStart('v', 'V')
    $b = $b.Trim().TrimStart('v', 'V')
    if ($a -notmatch '^\d+(\.\d+){0,2}$' -or $b -notmatch '^\d+(\.\d+){0,2}$') {
        return $null
    }

    $aParts = $a -split '\.'
    $bParts = $b -split '\.'
    while ($aParts.Count -lt 3) { $aParts += '0' }
    while ($bParts.Count -lt 3) { $bParts += '0' }

    $aNorm = "{0}.{1}.{2}" -f $aParts[0], $aParts[1], $aParts[2]
    $bNorm = "{0}.{1}.{2}" -f $bParts[0], $bParts[1], $bParts[2]

    try {
        $aVer = [System.Version]::Parse($aNorm)
        $bVer = [System.Version]::Parse($bNorm)
        return $aVer.CompareTo($bVer)
    }
    catch {
        return $null
    }
}

function Convert-KubeBuddyRadarNormalizedText {
    param([string]$Value)
    if ([string]::IsNullOrWhiteSpace($Value)) { return '' }
    return ([regex]::Replace($Value.ToLowerInvariant(), '[^a-z0-9]+', ' ')).Trim()
}

function Get-KubeBuddyRadarTokens {
    param([string]$Value)
    $norm = Convert-KubeBuddyRadarNormalizedText -Value $Value
    if (-not $norm) { return @() }
    return @($norm.Split(' ') | Where-Object { $_ -and $_.Length -ge 3 } | Sort-Object -Unique)
}

function Get-KubeBuddyRadarArtifactSearchTerms {
    param([pscustomobject]$Artifact)

    $terms = @()
    $key = [string]$Artifact.artifact_key
    $display = [string]$Artifact.display_name
    $workloadName = [string]$Artifact.workload_name
    $namespace = [string]$Artifact.namespace
    $helmChartName = [string]$Artifact.helm_chart_name
    $managedBy = [string]$Artifact.managed_by
    $controllerOwnerName = [string]$Artifact.controller_owner_name
    $partOf = [string]$Artifact.part_of

    if ($Artifact.artifact_type -eq 'image' -and $key) {
        $imageName = $key
        if ($imageName.Contains('@')) { $imageName = $imageName.Split('@', 2)[0] }
        if ($imageName.Contains(':')) { $imageName = $imageName.Substring(0, $imageName.LastIndexOf(':')) }
        $parts = $imageName.Split('/')
        $terms += $parts[$parts.Count - 1]
        if ($parts.Count -gt 1) { $terms += $parts[$parts.Count - 2] }
    }

    $terms += @($key, $display, $workloadName, $namespace, $helmChartName, $managedBy, $controllerOwnerName, $partOf)
    $expanded = @()
    foreach ($t in $terms) {
        if ([string]::IsNullOrWhiteSpace($t)) { continue }
        $expanded += $t
        $expanded += ($t -replace '[-_]+helm$', '')
        $expanded += ($t -replace '[-_]+chart$', '')
        $expanded += ($t -replace '[-_]+operator$', '')
    }

    return @($expanded | Where-Object { $_ -and $_.Trim() -ne '' } | Sort-Object -Unique)
}

function Get-KubeBuddyRadarProjectMatchScore {
    param(
        [object]$Project,
        [string[]]$Terms
    )

    if (-not $Project) { return -1 }
    $name = Convert-KubeBuddyRadarNormalizedText -Value ([string]($Project.name ?? ''))
    $repo = Convert-KubeBuddyRadarNormalizedText -Value ([string]($Project.repo_url ?? ''))
    $nameTokens = @(Get-KubeBuddyRadarTokens -Value $name)
    $repoTokens = @(Get-KubeBuddyRadarTokens -Value $repo)
    $projectTokens = @($nameTokens + $repoTokens | Sort-Object -Unique)

    $score = 0
    foreach ($term in @($Terms)) {
        $normTerm = Convert-KubeBuddyRadarNormalizedText -Value $term
        if (-not $normTerm) { continue }
        if ($name -eq $normTerm) { $score += 120 }
        elseif ($name.Contains($normTerm)) { $score += 70 }
        elseif ($repo.Contains($normTerm)) { $score += 50 }

        $termTokens = @(Get-KubeBuddyRadarTokens -Value $normTerm)
        $overlap = @($termTokens | Where-Object { $_ -in $projectTokens })
        $score += ($overlap.Count * 8)
    }

    return $score
}

function Convert-KubeBuddyRadarSemverInfo {
    param([string]$Version)

    $v = [string]$Version
    if ([string]::IsNullOrWhiteSpace($v)) { return $null }
    $v = $v.Trim()

    if ($v -notmatch '^[vV]?(?<maj>\d+)\.(?<min>\d+)\.(?<pat>\d+)(?<suffix>[-+].*)?$') {
        return $null
    }

    $core = "{0}.{1}.{2}" -f $matches.maj, $matches.min, $matches.pat
    try {
        $verObj = [System.Version]::Parse($core)
    }
    catch {
        return $null
    }

    return [PSCustomObject]@{
        raw = $v
        core = $core
        version_obj = $verObj
        major = [int]$matches.maj
        minor = [int]$matches.min
        patch = [int]$matches.pat
        is_stable = [string]::IsNullOrWhiteSpace([string]$matches.suffix)
    }
}

function Get-KubeBuddyRadarBestLatestVersion {
    param(
        [object[]]$ReleaseItems,
        [string]$CurrentVersion
    )

    $parsed = @()
    foreach ($r in @($ReleaseItems)) {
        if (-not $r -or -not $r.version) { continue }
        $sv = Convert-KubeBuddyRadarSemverInfo -Version ([string]$r.version)
        if ($sv) {
            $parsed += [PSCustomObject]@{
                raw = [string]$r.version
                semver = $sv
            }
        }
    }

    $stable = @($parsed | Where-Object { $_.semver.is_stable } | Sort-Object @{Expression = { $_.semver.version_obj }; Descending = $true})
    if ($stable.Count -eq 0) {
        return @{
            compare_version = ''
            global_latest_version = ''
            mode = 'none'
        }
    }

    $globalLatest = [string]$stable[0].raw
    $currentSemver = Convert-KubeBuddyRadarSemverInfo -Version $CurrentVersion
    if (-not $currentSemver) {
        return @{
            compare_version = $globalLatest
            global_latest_version = $globalLatest
            mode = 'global'
        }
    }

    $trackMatches = @($stable | Where-Object { $_.semver.major -eq $currentSemver.major -and $_.semver.minor -eq $currentSemver.minor })
    if ($trackMatches.Count -gt 0) {
        return @{
            compare_version = [string]$trackMatches[0].raw
            global_latest_version = $globalLatest
            mode = 'same_minor'
        }
    }

    return @{
        compare_version = $globalLatest
        global_latest_version = $globalLatest
        mode = 'global'
    }
}

function Invoke-KubeBuddyRadarDirectArtifactLookup {
    param(
        [string]$ReportPath,
        [hashtable]$RadarSettings
    )

    if (-not $RadarSettings.enabled) {
        return $null
    }
    if ([string]::IsNullOrWhiteSpace($ReportPath) -or -not (Test-Path $ReportPath)) {
        return $null
    }

    $headers = Get-KubeBuddyRadarAuthHeaders -RadarSettings $RadarSettings
    $baseUrl = [string]$RadarSettings.api_base_url
    if ([string]::IsNullOrWhiteSpace($baseUrl)) {
        return $null
    }
    $baseUrl = $baseUrl.Trim().TrimEnd('/')

    $report = Get-Content -Raw -Path $ReportPath | ConvertFrom-Json -Depth 60
    if (-not $report.artifacts) {
        return $null
    }

    $candidates = @()
    foreach ($img in @($report.artifacts.images)) {
        $candidates += [PSCustomObject]@{
            artifact_type   = 'image'
            artifact_key    = [string]$img.fullRef
            display_name    = [string]$img.fullRef
            current_version = [string]$img.currentVersion
            namespace = [string]$img.namespace
            workload_name = [string]$img.workloadName
            managed_by_helm = [bool]$img.managedByHelm
            helm_chart_name = [string]$img.helmChartName
            managed_by = [string]$img.managedBy
            managed_by_controller = [bool]$img.managedByController
            controller_owner_name = [string]$img.controllerOwnerName
            controller_owner_namespace = [string]$img.controllerOwnerNamespace
            part_of = [string]$img.partOf
        }
    }
    foreach ($chart in @($report.artifacts.helmCharts)) {
        $candidates += [PSCustomObject]@{
            artifact_type   = 'helm_chart'
            artifact_key    = [string]$chart.name
            display_name    = [string]$chart.name
            current_version = [string]$chart.version
            namespace = [string]$chart.namespace
            workload_name = [string]$chart.workloadName
            managed_by_helm = $false
            helm_chart_name = [string]$chart.name
            managed_by = ''
            managed_by_controller = $false
            controller_owner_name = ''
            controller_owner_namespace = ''
            part_of = ''
        }
    }
    # App label artifacts are intentionally excluded from direct version lookup to reduce noise.

    $unique = @{}
    foreach ($c in $candidates) {
        if ([string]::IsNullOrWhiteSpace($c.artifact_key)) { continue }
        $k = ("{0}|{1}|{2}" -f $c.artifact_type, $c.artifact_key.ToLowerInvariant(), ([string]$c.current_version).ToLowerInvariant())
        if (-not $unique.ContainsKey($k)) { $unique[$k] = $c }
    }

    $projectCache = @{}
    $releaseCache = @{}
    $helmStatusByNamespaceChart = @{}
    $helmStatusByNamespaceWorkload = @{}
    $items = @()

    $orderedArtifacts = @(
        @($unique.Values | Where-Object { $_.artifact_type -eq 'helm_chart' }) +
        @($unique.Values | Where-Object { $_.artifact_type -ne 'helm_chart' })
    )

    foreach ($artifact in $orderedArtifacts) {
        $terms = Get-KubeBuddyRadarArtifactSearchTerms -Artifact $artifact
        $project = $null

        $inheritedFromHelm = $false
        $inheritedHelm = $null
        if ($artifact.artifact_type -ne 'helm_chart' -and [bool]$artifact.managed_by_helm) {
            $nsKey = Convert-KubeBuddyRadarNormalizedText -Value ([string]$artifact.namespace)
            $chartKey = Convert-KubeBuddyRadarNormalizedText -Value ([string]$artifact.helm_chart_name)
            $workloadKey = Convert-KubeBuddyRadarNormalizedText -Value ([string]$artifact.workload_name)
            if ($chartKey) {
                $lookupKey = "$nsKey|$chartKey"
                if ($helmStatusByNamespaceChart.ContainsKey($lookupKey)) {
                    $inheritedFromHelm = $true
                    $inheritedHelm = $helmStatusByNamespaceChart[$lookupKey]
                }
            }
            if (-not $inheritedFromHelm -and $workloadKey) {
                $lookupKey = "$nsKey|$workloadKey"
                if ($helmStatusByNamespaceWorkload.ContainsKey($lookupKey)) {
                    $inheritedFromHelm = $true
                    $inheritedHelm = $helmStatusByNamespaceWorkload[$lookupKey]
                }
            }
        }

        if (-not $inheritedFromHelm) {
            $best = $null
            $bestScore = -1
            foreach ($searchTerm in @($terms)) {
                if ([string]::IsNullOrWhiteSpace($searchTerm)) { continue }
                $cacheKey = $searchTerm.ToLowerInvariant()
                $projectList = @()
                if ($projectCache.ContainsKey($cacheKey)) {
                    $projectList = @($projectCache[$cacheKey])
                }
                else {
                    $searchUri = "{0}/projects?search={1}&per_page=20" -f $baseUrl, [Uri]::EscapeDataString($searchTerm)
                    $resp = Invoke-RestMethod -Uri $searchUri -Method Get -Headers $headers -TimeoutSec ([Math]::Max([int]$RadarSettings.upload_timeout_seconds, 5))
                    $projectList = @($resp.items)
                    $projectCache[$cacheKey] = $projectList
                }

                foreach ($p in $projectList) {
                    $score = Get-KubeBuddyRadarProjectMatchScore -Project $p -Terms $terms
                    if ($score -gt $bestScore) {
                        $bestScore = $score
                        $best = $p
                    }
                }
            }
            if ($bestScore -ge 20) {
                $project = $best
            }
        } else {
            $project = $null
        }

        $latest = ''
        $globalLatest = ''
        $source = ''
        $productId = 0
        $compareMode = ''
        if ($inheritedFromHelm -and $inheritedHelm) {
            $latest = [string]($inheritedHelm.latest_version ?? '')
            $globalLatest = [string]($inheritedHelm.global_latest_version ?? '')
            $source = [string]($inheritedHelm.source ?? '')
            $productId = [int]($inheritedHelm.source_product_id ?? 0)
            $compareMode = 'inherited_helm'
        }
        elseif ($project -and $project.id) {
            $productId = [int]$project.id
            $source = [string]$project.name
            $releaseType = if ($artifact.artifact_type -eq 'helm_chart') { 'helm' } else { 'app' }
            $releaseCacheKey = ("{0}|{1}" -f $productId, $releaseType)
            if ($releaseCache.ContainsKey($releaseCacheKey)) {
                $cached = $releaseCache[$releaseCacheKey]
                $latest = [string]($cached.compare_version ?? '')
                $globalLatest = [string]($cached.global_latest_version ?? '')
                $compareMode = [string]($cached.mode ?? '')
            }
            else {
                $relUri = "{0}/projects/{1}/releases?type={2}&per_page=30" -f $baseUrl, $productId, $releaseType
                $relResp = Invoke-RestMethod -Uri $relUri -Method Get -Headers $headers -TimeoutSec ([Math]::Max([int]$RadarSettings.upload_timeout_seconds, 5))
                $latestChoice = Get-KubeBuddyRadarBestLatestVersion -ReleaseItems @($relResp.items) -CurrentVersion ([string]$artifact.current_version)
                $latest = [string]($latestChoice.compare_version ?? '')
                $globalLatest = [string]($latestChoice.global_latest_version ?? '')
                $compareMode = [string]($latestChoice.mode ?? '')
                if (-not $latest -and $project.latest_version) {
                    $latest = [string]$project.latest_version
                    $globalLatest = $latest
                    $compareMode = 'global'
                }
                $releaseCache[$releaseCacheKey] = $latestChoice
            }
        }

        $current = [string]$artifact.current_version
        $status = 'unknown'
        $confidence = 0.40
        $reason = 'No matching monitored project found in Radar catalog.'

        if (-not [string]::IsNullOrWhiteSpace($latest) -and -not [string]::IsNullOrWhiteSpace($current)) {
            $cmp = Get-KubeBuddyRadarSemverCompare -Current $current -Latest $latest
            if ($null -eq $cmp) {
                $status = 'unknown'
                $confidence = 0.45
                $reason = 'Unable to semver-compare current and latest versions.'
            }
            elseif ($cmp -ge 0) {
                $status = 'up_to_date'
                $confidence = 0.90
                if ($compareMode -eq 'same_minor' -and $globalLatest -and $globalLatest -ne $latest) {
                    $reason = "Up to date in current minor track ($latest). Newer release available: $globalLatest."
                }
                elseif ($compareMode -eq 'inherited_helm') {
                    $reason = "Inherited from Helm chart status."
                }
                else {
                    $reason = 'Current version is equal to or newer than latest catalog entry.'
                }
            }
            else {
                $currParts = ($current.TrimStart('v', 'V') -split '\.') | ForEach-Object { [int]$_ }
                $latestParts = ($latest.TrimStart('v', 'V') -split '\.') | ForEach-Object { [int]$_ }
                $majorGap = ($latestParts[0] -as [int]) - ($currParts[0] -as [int])
                if ($majorGap -gt 0) {
                    $status = 'major_behind'
                    $reason = 'Latest major version is newer than current.'
                }
                else {
                    $status = 'minor_behind'
                    $reason = 'Latest minor/patch version is newer than current.'
                }
                $confidence = 0.85
            }
        }
        elseif (-not [string]::IsNullOrWhiteSpace($latest)) {
            $reason = 'Current version missing for comparison.'
        }
        elseif ([bool]$artifact.managed_by_controller) {
            $status = 'covered_by_controller'
            $confidence = 0.70
            if ([string]::IsNullOrWhiteSpace([string]$artifact.managed_by)) {
                $reason = 'Workload is controller-managed and tracked at platform/controller level.'
            }
            else {
                $reason = "Workload is controller-managed by '$($artifact.managed_by)' and tracked at platform/controller level."
            }
        }

        $items += [PSCustomObject]@{
            artifact_key = [string]$artifact.artifact_key
            artifact_type = [string]$artifact.artifact_type
            display_name = [string]$artifact.display_name
            current_version = $current
            latest_version = [string]$latest
            status = [string]$status
            confidence = [double]$confidence
            reason = [string]$reason
            source = [string]$source
            source_product_id = [int]$productId
            is_monitored = -not [string]::IsNullOrWhiteSpace($latest)
            global_latest_version = [string]$globalLatest
            compare_mode = [string]$compareMode
            inherited_from_helm = [bool]$inheritedFromHelm
        }

        if ($artifact.artifact_type -eq 'helm_chart') {
            $nsKey = Convert-KubeBuddyRadarNormalizedText -Value ([string]$artifact.namespace)
            $chartKey = Convert-KubeBuddyRadarNormalizedText -Value ([string]$artifact.artifact_key)
            $workloadKey = Convert-KubeBuddyRadarNormalizedText -Value ([string]$artifact.workload_name)
            if ($nsKey -and $chartKey) {
                $helmStatusByNamespaceChart["$nsKey|$chartKey"] = $items[-1]
            }
            if ($nsKey -and $workloadKey) {
                $helmStatusByNamespaceWorkload["$nsKey|$workloadKey"] = $items[-1]
            }
        }
    }

    $summary = @{
        up_to_date = 0
        minor_behind = 0
        major_behind = 0
        unknown = 0
    }
    foreach ($i in $items) {
        $s = [string]$i.status
        if ($s -eq 'covered_by_helm' -or $s -eq 'covered_by_controller') { continue }
        if ($summary.ContainsKey($s)) { $summary[$s]++ } else { $summary.unknown++ }
    }

    return @{
        processing_status = 'ready'
        summary = $summary
        items = $items
        source = 'direct_lookup'
    }
}

function Write-KubeBuddyRadarCompareSummary {
    param([object]$Compare)

    if (-not $Compare) {
        return
    }

    Write-Host "`n📈 Radar Compare" -ForegroundColor Cyan
    if ($null -ne $Compare.score_delta) {
        Write-Host ("   Score Delta: {0}" -f $Compare.score_delta) -ForegroundColor Cyan
    }
    if ($null -ne $Compare.new_findings_count) {
        Write-Host ("   New Findings: {0}" -f $Compare.new_findings_count) -ForegroundColor Yellow
    }
    if ($null -ne $Compare.resolved_findings_count) {
        Write-Host ("   Resolved Findings: {0}" -f $Compare.resolved_findings_count) -ForegroundColor Green
    }
    if ($null -ne $Compare.regressed_findings_count) {
        Write-Host ("   Regressed Findings: {0}" -f $Compare.regressed_findings_count) -ForegroundColor Red
    }
}
