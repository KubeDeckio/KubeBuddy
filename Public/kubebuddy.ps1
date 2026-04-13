$script:KubeBuddyModuleVersion = "v0.0.4"

function Resolve-KubeBuddyNativeCommand {
    $moduleRoot = Split-Path -Parent $PSScriptRoot
    $candidates = @()

    if ($env:KUBEBUDDY_BINARY) {
        $candidates += $env:KUBEBUDDY_BINARY
    }

    $candidates += @(
        (Join-Path $moduleRoot "kubebuddy"),
        (Join-Path $moduleRoot "kubebuddy.exe"),
        (Join-Path $moduleRoot "bin/kubebuddy"),
        (Join-Path $moduleRoot "bin/kubebuddy.exe")
    )

    foreach ($candidate in $candidates) {
        if ($candidate -and (Test-Path $candidate)) {
            return @{
                FilePath        = (Resolve-Path $candidate).Path
                PrefixArguments = @()
                WorkingDirectory = $moduleRoot
            }
        }
    }

    $command = Get-Command kubebuddy -ErrorAction SilentlyContinue
    if ($command) {
        return @{
            FilePath         = $command.Source
            PrefixArguments  = @()
            WorkingDirectory = (Get-Location).Path
        }
    }

    $goCommand = Get-Command go -ErrorAction SilentlyContinue
    $goMain = Join-Path $moduleRoot "cmd/kubebuddy/main.go"
    if ($goCommand -and (Test-Path $goMain)) {
        return @{
            FilePath         = $goCommand.Source
            PrefixArguments  = @("run", (Join-Path $moduleRoot "cmd/kubebuddy"))
            WorkingDirectory = $moduleRoot
        }
    }

    throw "Unable to locate the native KubeBuddy CLI. Install the kubebuddy binary, set KUBEBUDDY_BINARY, or run from the repository root with Go installed."
}

function Invoke-KubeBuddyNativeCommand {
    param(
        [string[]]$Arguments,
        [hashtable]$Environment = @{},
        [string]$WorkingDirectory
    )

    $command = Resolve-KubeBuddyNativeCommand
    $previousLocation = $null
    $savedEnvironment = @{}

    try {
        foreach ($entry in $Environment.GetEnumerator()) {
            $savedEnvironment[$entry.Key] = [Environment]::GetEnvironmentVariable($entry.Key)
            [Environment]::SetEnvironmentVariable($entry.Key, [string]$entry.Value)
        }

        $targetDirectory = if ($WorkingDirectory) { $WorkingDirectory } else { $command.WorkingDirectory }
        if ($targetDirectory) {
            $previousLocation = Get-Location
            Set-Location $targetDirectory
        }

        & $command.FilePath @($command.PrefixArguments + $Arguments) | Out-Host
        return [int]$LASTEXITCODE
    }
    finally {
        if ($previousLocation) {
            Set-Location $previousLocation
        }
        foreach ($entry in $savedEnvironment.GetEnumerator()) {
            [Environment]::SetEnvironmentVariable($entry.Key, $entry.Value)
        }
    }
}

function Move-KubeBuddyGeneratedReports {
    param(
        [string]$OutputDirectory,
        [string]$BaseName,
        [string[]]$Extensions
    )

    if (-not (Test-Path $OutputDirectory)) {
        return
    }

    foreach ($extension in $Extensions) {
        $latest = Get-ChildItem -Path $OutputDirectory -Filter "kubebuddy-report-*.$extension" -File -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTimeUtc -Descending |
            Select-Object -First 1
        if (-not $latest) {
            continue
        }
        $target = Join-Path $OutputDirectory "$BaseName.$extension"
        if ($latest.FullName -ne $target) {
            Move-Item -Path $latest.FullName -Destination $target -Force
        }
    }
}

function Invoke-KubeBuddy {
    [CmdletBinding()]
    param (
        [switch]$HtmlReport,
        [switch]$txtReport,
        [switch]$jsonReport,
        [switch]$CsvReport,
        [switch]$Aks,
        [switch]$ExcludeNamespaces,
        [string[]]$AdditionalExcludedNamespaces,
        [switch]$yes,
        [string]$SubscriptionId,
        [string]$ResourceGroup,
        [string]$ClusterName,
        [string]$outputpath,
        [switch]$UseAksRestApi,
        [string]$ConfigPath,
        [switch]$IncludePrometheus,
        [string]$PrometheusUrl,
        [string]$PrometheusMode,
        [string]$PrometheusBearerTokenEnv,
        [System.Management.Automation.PSCredential]$PrometheusCredential,
        [switch]$RadarUpload,
        [switch]$RadarCompare,
        [switch]$RadarFetchConfig,
        [string]$RadarConfigId,
        [string]$RadarApiBaseUrl,
        [string]$RadarEnvironment,
        [string]$RadarApiUserEnv,
        [string]$RadarApiSecretEnv
    )

    if (-not ($HtmlReport -or $txtReport -or $jsonReport -or $CsvReport)) {
        $HtmlReport = $true
    }

    $extensions = @()
    if ($HtmlReport) { $extensions += "html" }
    if ($txtReport) { $extensions += "txt" }
    if ($jsonReport) { $extensions += "json" }
    if ($CsvReport) { $extensions += "csv" }

    $requestedOutputPath = $outputpath
    if (-not $requestedOutputPath) {
        $requestedOutputPath = Join-Path -Path $HOME -ChildPath "kubebuddy-report"
    }

    $reportDirectory = $requestedOutputPath
    $reportBaseName = $null
    $outputExtension = [IO.Path]::GetExtension($requestedOutputPath)
    if ($outputExtension) {
        $reportDirectory = Split-Path -Parent $requestedOutputPath
        if (-not $reportDirectory) {
            $reportDirectory = (Get-Location).Path
        }
        $reportBaseName = [IO.Path]::GetFileNameWithoutExtension($requestedOutputPath)
    }

    if (-not (Test-Path $reportDirectory)) {
        New-Item -ItemType Directory -Path $reportDirectory -Force | Out-Null
    }

    $arguments = @("run")
    if ($HtmlReport) { $arguments += "--html-report" }
    if ($txtReport) { $arguments += "--txt-report" }
    if ($jsonReport) { $arguments += "--json-report" }
    if ($CsvReport) { $arguments += "--csv-report" }
    if ($Aks) { $arguments += "--aks" }
    if ($ExcludeNamespaces) { $arguments += "--exclude-namespaces" }
    if ($yes) { $arguments += "--yes" }
    if ($UseAksRestApi) { $arguments += "--use-aks-rest-api" }
    if ($IncludePrometheus) { $arguments += "--include-prometheus" }
    if ($RadarUpload) { $arguments += "--radar-upload" }
    if ($RadarCompare) { $arguments += "--radar-compare" }
    if ($RadarFetchConfig) { $arguments += "--radar-fetch-config" }

    if ($SubscriptionId) { $arguments += @("--subscription-id", $SubscriptionId) }
    if ($ResourceGroup) { $arguments += @("--resource-group", $ResourceGroup) }
    if ($ClusterName) { $arguments += @("--cluster-name", $ClusterName) }
    if ($ConfigPath) { $arguments += @("--config-path", $ConfigPath) }
    if ($PrometheusUrl) { $arguments += @("--prometheus-url", $PrometheusUrl) }
    if ($PrometheusMode) { $arguments += @("--prometheus-mode", $PrometheusMode) }
    if ($PrometheusBearerTokenEnv) { $arguments += @("--prometheus-bearer-token-env", $PrometheusBearerTokenEnv) }
    if ($RadarConfigId) { $arguments += @("--radar-config-id", $RadarConfigId) }
    if ($RadarApiBaseUrl) { $arguments += @("--radar-api-base-url", $RadarApiBaseUrl) }
    if ($RadarEnvironment) { $arguments += @("--radar-environment", $RadarEnvironment) }
    if ($RadarApiUserEnv) { $arguments += @("--radar-api-user-env", $RadarApiUserEnv) }
    if ($RadarApiSecretEnv) { $arguments += @("--radar-api-secret-env", $RadarApiSecretEnv) }
    foreach ($namespace in @($AdditionalExcludedNamespaces)) {
        if ($namespace) {
            $arguments += @("--additional-excluded-namespaces", $namespace)
        }
    }
    $arguments += @("--output-path", $reportDirectory)

    $environment = @{}
    if ($PrometheusCredential) {
        $environment["PROMETHEUS_USERNAME"] = $PrometheusCredential.UserName
        $environment["PROMETHEUS_PASSWORD"] = $PrometheusCredential.GetNetworkCredential().Password
        if (-not $PrometheusMode) {
            $arguments += @("--prometheus-mode", "basic")
        }
    }

    $exitCode = Invoke-KubeBuddyNativeCommand -Arguments $arguments -Environment $environment -WorkingDirectory (Get-Location).Path
    if ($exitCode -ne 0) {
        throw "Native KubeBuddy CLI exited with code $exitCode."
    }

    if ($reportBaseName) {
        Move-KubeBuddyGeneratedReports -OutputDirectory $reportDirectory -BaseName $reportBaseName -Extensions $extensions
    }
}
