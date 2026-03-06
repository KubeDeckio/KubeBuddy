function Get-KubeBuddyRadarConfig {
    $defaults = @{
        enabled                = $false
        api_base_url           = "https://radar.kubebuddy.io/api/kb-radar/v1"
        environment            = "prod"
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
        [string]$RadarApiPasswordEnv
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
        api_user_env     = if ($RadarApiUserEnv) { $RadarApiUserEnv } else { $config.api_user_env }
        api_password_env = if ($RadarApiPasswordEnv) { $RadarApiPasswordEnv } else { $config.api_password_env }
        upload_timeout_seconds = [int]$config.upload_timeout_seconds
        upload_retries   = [int]$config.upload_retries
    }
}

function Get-KubeBuddyRadarAuthHeaders {
    param([hashtable]$RadarSettings)

    $userEnv = [string]$RadarSettings.api_user_env
    $passwordEnv = [string]$RadarSettings.api_password_env

    $user = [Environment]::GetEnvironmentVariable($userEnv)
    $password = [Environment]::GetEnvironmentVariable($passwordEnv)

    if (-not $user -or -not $password) {
        throw "Radar credentials missing. Set env vars '$userEnv' and '$passwordEnv'."
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
