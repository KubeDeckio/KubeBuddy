# Ensure KubeBuddy module is loaded
Import-Module KubeBuddy -ErrorAction Stop

# Required values
$KubeConfigPath = $env:KUBECONFIG
$OriginalKubeConfigPath = "/tmp/kubeconfig-original"
$OutputPath = "/app/Reports"
$Yes = $true

# Optional values
$ClusterName = $env:CLUSTER_NAME
$ResourceGroup = $env:RESOURCE_GROUP
$SubscriptionId = $env:SUBSCRIPTION_ID
$ExcludeNS = $env:EXCLUDE_NAMESPACES -eq "true"
$HtmlReport = $env:HTML_REPORT -eq "true"
$txtReport = $env:TXT_REPORT -eq "true"
$jsonReport = $env:JSON_REPORT -eq "true"
$Aks = $env:AKS_MODE -eq "true"
$ClientId = $env:AZURE_CLIENT_ID
$ClientSecret = $env:AZURE_CLIENT_SECRET
$TenantId = $env:AZURE_TENANT_ID
$UseAksRestApi = $env:USE_AKS_REST_API -eq "true"
$ConfigPath = $env:KUBEBUDDY_CONFIG_PATH
$RadarUpload = $env:RADAR_UPLOAD -eq "true"
$RadarCompare = $env:RADAR_COMPARE -eq "true"
$RadarFetchConfig = $env:RADAR_FETCH_CONFIG -eq "true"
$RadarConfigId = $env:RADAR_CONFIG_ID
$RadarApiBaseUrl = $env:RADAR_API_BASE_URL
$RadarEnvironment = $env:RADAR_ENVIRONMENT
$RadarApiUserEnv = $env:RADAR_API_USER_ENV
$RadarApiSecretEnv = $env:RADAR_API_PASSWORD_ENV

# Optional list values (comma-separated)
$AdditionalExcludedNamespaces = @()
if ($env:ADDITIONAL_EXCLUDED_NAMESPACES) {
    $AdditionalExcludedNamespaces = @(
        $env:ADDITIONAL_EXCLUDED_NAMESPACES.Split(',') |
        ForEach-Object { $_.Trim() } |
        Where-Object { $_ }
    )
}

# AI values
$OpenAIKey = $env:OPENAI_API_KEY  # New: capture OpenAI key
if ($OpenAIKey) {
    $env:OpenAIKey = $OpenAIKey   # PSAI uses this
}

# ─── Prometheus options ───────────────────────────────────────────────
$IncludePrometheus = $env:INCLUDE_PROMETHEUS -eq "true"
$PrometheusUrl = $env:PROMETHEUS_URL
$PrometheusMode = $env:PROMETHEUS_MODE
$PrometheusBearerTokenEnv = $env:PROMETHEUS_BEARER_TOKEN_ENV
# Convert username/password to PSCredential
$PrometheusCredential = $null
if ($env:PROMETHEUS_USERNAME -and $env:PROMETHEUS_PASSWORD) {
    # Suppress the plaintext ConvertTo-SecureString rule
    $securePassword = ConvertTo-SecureString $env:PROMETHEUS_PASSWORD -AsPlainText -Force  # PSScriptAnalyzerSuppress PSUseConvertToSecureStringWithPlainText
    $PrometheusCredential = New-Object System.Management.Automation.PSCredential ($env:PROMETHEUS_USERNAME, $securePassword)
}


# Require at least one report format
if (-not ($HtmlReport -or $txtReport -or $jsonReport)) {
    Write-Error "You must enable at least one report format: HTML_REPORT, TXT_REPORT, or JSON_REPORT."
    exit 1
}

# Radar upload/compare always works with JSON payloads.
# Enforce JSON_REPORT in container mode so behavior is explicit and predictable.
if (($RadarUpload -or $RadarCompare) -and -not $jsonReport) {
    Write-Error "RADAR_UPLOAD/RADAR_COMPARE requires JSON_REPORT=true in container mode."
    exit 1
}

# Validate KUBECONFIG is set
if (-not $KubeConfigPath) {
    Write-Error "KUBECONFIG environment variable not set."
    exit 1
}

# Validate mounted kubeconfig file exists
if (-not (Test-Path $OriginalKubeConfigPath)) {
    Write-Error "Original kubeconfig not found at $OriginalKubeConfigPath. Please mount the kubeconfig file to /tmp/kubeconfig-original."
    exit 1
}

# Copy the original kubeconfig to a writable location
Write-Host "📘 Copying kubeconfig from $OriginalKubeConfigPath to $KubeConfigPath..." -ForegroundColor Cyan
try {
    $KubeConfigDir = Split-Path $KubeConfigPath -Parent
    New-Item -ItemType Directory -Path $KubeConfigDir -Force | Out-Null
    Copy-Item -Path $OriginalKubeConfigPath -Destination $KubeConfigPath -Force
    chmod 600 $KubeConfigPath
}
catch {
    Write-Error "Failed to prepare kubeconfig: $_"
    exit 1
}

# Set KUBECONFIG
$env:KUBECONFIG = $KubeConfigPath
Write-Host "📘 Using kubeconfig: $KubeConfigPath" -ForegroundColor Cyan

# Validate AKS-specific input
if ($Aks) {
    if (-not $ClusterName -or -not $ResourceGroup -or -not $SubscriptionId) {
        Write-Error "AKS mode is enabled but missing: CLUSTER_NAME, RESOURCE_GROUP or SUBSCRIPTION_ID"
        exit 1
    }
    if (-not $ClientId -or -not $ClientSecret -or -not $TenantId) {
        Write-Error "AKS mode is enabled but missing SPN credentials: AZURE_CLIENT_ID, AZURE_CLIENT_SECRET, AZURE_TENANT_ID"
        exit 1
    }

    # Convert kubeconfig using SPN
    Write-Host "🔐 Converting kubeconfig to use Service Principal credentials..." -ForegroundColor Cyan
    try {
        kubelogin convert-kubeconfig `
            -l spn `
            --client-id $ClientId `
            --client-secret $ClientSecret `
            --tenant-id $TenantId
        if ($LASTEXITCODE -ne 0) {
            throw "kubelogin failed with exit code $LASTEXITCODE"
        }
        Write-Host "✅ Kubeconfig converted for SPN." -ForegroundColor Green
    }
    catch {
        Write-Error "kubelogin SPN conversion failed: $_"
        exit 1
    }
}

# Run KubeBuddy
$parameters = @{
    ClusterName              = $ClusterName
    ResourceGroup            = $ResourceGroup
    SubscriptionId           = $SubscriptionId
    ExcludeNamespaces        = $ExcludeNS
    HtmlReport               = $HtmlReport
    txtReport                = $txtReport
    jsonReport               = $jsonReport
    Aks                      = $Aks
    outputpath               = $OutputPath
    yes                      = $Yes
    UseAksRestApi            = $UseAksRestApi
    ConfigPath               = $ConfigPath
    AdditionalExcludedNamespaces = $AdditionalExcludedNamespaces
    IncludePrometheus        = $IncludePrometheus
    PrometheusUrl            = $PrometheusUrl
    PrometheusMode           = $PrometheusMode
    PrometheusCredential     = $PrometheusCredential
    PrometheusBearerTokenEnv = $PrometheusBearerTokenEnv
    RadarUpload              = $RadarUpload
    RadarCompare             = $RadarCompare
    RadarFetchConfig         = $RadarFetchConfig
    RadarConfigId            = $RadarConfigId
    RadarApiBaseUrl          = $RadarApiBaseUrl
    RadarEnvironment         = $RadarEnvironment
    RadarApiUserEnv          = $RadarApiUserEnv
    RadarApiSecretEnv        = $RadarApiSecretEnv
}

try {
    # Run Invoke-KubeBuddy with parameters
    $null = Invoke-KubeBuddy @parameters

    # Check if the output file exists
    $fullPath = Resolve-Path $OutputPath -ErrorAction SilentlyContinue
    if ($fullPath) {
        Write-Host "`n🤖 Thank you for Using KubeBuddy. Have a nice day!" -ForegroundColor Green
    }
    else {
        Write-Host "`n❌ No report generated. Check for errors above." -ForegroundColor Red
        exit 1
    }
}
catch {
    Write-Host "`n❌ KubeBuddy analysis failed: $_" -ForegroundColor Red
    exit 1
}
