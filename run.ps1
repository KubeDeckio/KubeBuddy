Import-Module KubeBuddy

# Required values
$KubeConfigPath = $env:KUBECONFIG_PATH
$OutputPath     = "/app/Reports"
$Yes            = $true  # Always true, required for script logic

# Optional values
$ClusterName    = $env:CLUSTER_NAME
$ResourceGroup  = $env:RESOURCE_GROUP
$SubscriptionId = $env:SUBSCRIPTION_ID
$ExcludeNS      = $env:EXCLUDE_NAMESPACES -eq "true"
$HtmlReport     = $env:HTML_REPORT -eq "true"
$txtReport      = $env:TXT_REPORT -eq "true"
$jsonReport     = $env:JSON_REPORT -eq "true"
# Default AKS to false unless explicitly set to "true"
$Aks            = if ($env:AKS_MODE -eq "true") { $true } else { $false }
$AzureToken     = $env:AZURE_TOKEN

# Require at least one report format
if (-not ($HtmlReport -or $txtReport -or $jsonReport)) {
    Write-Error "You must enable at least one report format: HTML_REPORT, TXT_REPORT, or JSON_REPORT."
    exit 1
}

# Validate kubeconfig (required in all cases)
if (-not $KubeConfigPath -or -not (Test-Path $KubeConfigPath)) {
    Write-Error "Kubeconfig not found at $KubeConfigPath. Please provide a valid KUBECONFIG_PATH."
    exit 1
}

# Validate AKS-specific parameters (required only if AKS mode is enabled)
if ($Aks) {
    if (-not $ClusterName -or -not $ResourceGroup -or -not $SubscriptionId) {
        Write-Error "AKS mode is enabled but missing required environment variables: CLUSTER_NAME, RESOURCE_GROUP, SUBSCRIPTION_ID"
        exit 1
    }
    if (-not $AzureToken) {
        Write-Error "AKS mode is enabled but missing required environment variable: AZURE_TOKEN"
        exit 1
    }
    # Set Azure access token only if AKS mode is enabled
    $env:AZURE_ACCESS_TOKEN = $AzureToken
}

# Setup kubectl to use the kubeconfig
$env:KUBECONFIG = $KubeConfigPath

# Log the start of the script
if ($Aks) {
    Write-Host "Starting KubeBuddy analysis for cluster: $ClusterName in resource group: $ResourceGroup (AKS mode)" -ForegroundColor Green
} else {
    Write-Host "Starting KubeBuddy analysis (non-AKS mode)" -ForegroundColor Green
}

# Call the main function with the provided parameters
$parameters = @{
    ClusterName       = $ClusterName
    ResourceGroup     = $ResourceGroup
    SubscriptionId    = $SubscriptionId
    ExcludeNamespaces = $ExcludeNS
    HtmlReport        = $HtmlReport
    txtReport         = $txtReport
    jsonReport        = $jsonReport
    Aks               = $Aks
    outputpath        = $OutputPath
    yes               = $Yes
}

try {
    Invoke-KubeBuddy @parameters

    # Show resolved full output path
    $fullPath = Resolve-Path $OutputPath
    Write-Host "KubeBuddy analysis completed successfully." -ForegroundColor Green
    Write-Host "`nReport saved in the folder you mounted (e.g. -v ~/myfolder:/app/Reports) on your host." -ForegroundColor Green
}
catch {
    Write-Error "KubeBuddy analysis failed: $_"
    exit 1
}
