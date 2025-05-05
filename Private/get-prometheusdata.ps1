function Get-PrometheusData {
    param (
        [Parameter(Mandatory)] [string]$Query,
        [Parameter(Mandatory)] [string]$Url,
        [string]$Mode = "local", # local | basic | bearer | azure
        [string]$Username,
        [string]$Password,
        [string]$BearerTokenEnv,
        [switch]$UseRange,
        [string]$StartTime,
        [string]$EndTime,
        [string]$Step = "5m"
    )

    Write-Host "📡 Querying Prometheus ($Mode mode)..."
    $headers = @{}

    try {
        switch ($Mode.ToLower()) {
            "basic" {
                if (-not $Username -or -not $Password) {
                    throw "Username and Password must be provided for basic auth."
                }
                $headers["Authorization"] = "Basic " + [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes("${Username}:${Password}"))
            }
            "bearer" {
                if (-not $BearerTokenEnv) { throw "Bearer token environment variable name must be provided." }
                $token = $Env:BearerTokenEnv
                if (-not $token) { throw "Bearer token not found in environment variable: $BearerTokenEnv" }
                $headers["Authorization"] = "Bearer $token"
            }
            "azure" {
                Write-Host "🔐 Authenticating with Azure..."
                if ($env:AZURE_CLIENT_ID -and $env:AZURE_CLIENT_SECRET -and $env:AZURE_TENANT_ID) {
                    $body = @{ grant_type = "client_credentials"; client_id = $env:AZURE_CLIENT_ID; client_secret = $env:AZURE_CLIENT_SECRET; resource = "https://prometheus.monitor.azure.com/" }
                    $tokenResponse = Invoke-RestMethod -Method POST -Uri "https://login.microsoftonline.com/$($env:AZURE_TENANT_ID)/oauth2/token" -Body $body
                    $headers["Authorization"] = "Bearer $($tokenResponse.access_token)"
                }
                else {
                    if (-not (Get-Command az -ErrorAction SilentlyContinue)) { throw "Azure CLI not found, and SPN not set." }
                    $token = az account get-access-token --resource https://prometheus.monitor.azure.com --query accessToken -o tsv
                    if (-not $token) { throw "Failed to obtain Azure token via az CLI." }
                    $headers["Authorization"] = "Bearer $token"
                }
            }
            "local" { }
            default { throw "Unsupported mode: $Mode" }
        }

        $encodedQuery = [uri]::EscapeDataString($Query)
        $uri = if ($UseRange -and $StartTime -and $EndTime) {
            "$Url/api/v1/query_range?query=$encodedQuery&start=$StartTime&end=$EndTime&step=$Step"
        }
        else {
            "$Url/api/v1/query?query=$encodedQuery"
        }

        $response = Invoke-RestMethod -Uri $uri -Headers $headers -TimeoutSec 10
        if ($response.status -ne "success") {
            throw "Query failed: $($response.error ?? 'Unknown error')"
        }

        return [PSCustomObject]@{
            Query   = $Query
            Mode    = $Mode
            Url     = $Url
            Results = $response.data.result
        }
    }
    catch {
        Write-Host "❌ Failed to query Prometheus: $_" -ForegroundColor Red
        return $null
    }
}
