function Get-PrometheusHeaders {
    param (
        [string]$Mode,
        [System.Management.Automation.PSCredential]$Credential,
        [string]$BearerTokenEnv
    )

    $headers = @{}

    switch ($Mode.ToLower()) {
        "basic" {
            if (-not $Credential) {
                throw "Credential is required for basic authentication."
            }
            $username = $Credential.UserName
            $password = $Credential.GetNetworkCredential().Password
            $pair = "$username:$password"
            $headers["Authorization"] = "Basic " + [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes($pair))
        }
        "bearer" {
            if (-not $BearerTokenEnv) { throw "Bearer token env var name required." }
            $token = $Env:$BearerTokenEnv
            if (-not $token) { throw "Token not found in env var: $BearerTokenEnv" }
            $headers["Authorization"] = "Bearer $token"
        }
        "azure" {
            Write-Host "🔐 Authenticating with Azure..."
            if ($env:AZURE_CLIENT_ID -and $env:AZURE_CLIENT_SECRET -and $env:AZURE_TENANT_ID) {
                $body = @{
                    grant_type    = "client_credentials"
                    client_id     = $env:AZURE_CLIENT_ID
                    client_secret = $env:AZURE_CLIENT_SECRET
                    resource      = "https://prometheus.monitor.azure.com/"
                }
                $tokenResponse = Invoke-RestMethod -Method POST -Uri "https://login.microsoftonline.com/$($env:AZURE_TENANT_ID)/oauth2/token" -Body $body
                $headers["Authorization"] = "Bearer $($tokenResponse.access_token)"
            }
            else {
                if (-not (Get-Command az -ErrorAction SilentlyContinue)) {
                    throw "Azure CLI not found and SPN not set."
                }
                $token = az account get-access-token --resource https://prometheus.monitor.azure.com --query accessToken -o tsv
                if (-not $token) { throw "Failed to obtain Azure token." }
                $headers["Authorization"] = "Bearer $token"
            }
        }
        "local" {
            # No auth headers needed
        }
        default {
            throw "Unsupported auth mode: $Mode"
        }
    }

    return $headers
}

function Get-PrometheusData {
    param (
        [Parameter(Mandatory)]
        [string]$Query,

        [Parameter(Mandatory)]
        [string]$Url,

        [hashtable]$Headers   = @{},
        [switch]   $UseRange,
        [string]  $StartTime,
        [string]  $EndTime,
        [string]  $Step       = "5m",

        [int]
        $TimeoutSec = 30
    )

    try {
        $encodedQuery = [uri]::EscapeDataString($Query)
        $uri = if ($UseRange -and $StartTime -and $EndTime) {
            "$Url/api/v1/query_range?query=$encodedQuery&start=$StartTime&end=$EndTime&step=$Step"
        } else {
            "$Url/api/v1/query?query=$encodedQuery"
        }

        $response = Invoke-RestMethod -Uri $uri -Headers $Headers -TimeoutSec $TimeoutSec
        if ($response.status -ne "success") {
            throw "Query failed: $($response.error ?? 'Unknown error')"
        }

        return [PSCustomObject]@{
            Query   = $Query
            Url     = $Url
            Results = $response.data.result
        }
    }
    catch {
        Write-Host "❌ Prometheus query failed: $_" -ForegroundColor Red
        return [PSCustomObject]@{
            Query   = $Query
            Url     = $Url
            Results = @()
        }
    }
}
