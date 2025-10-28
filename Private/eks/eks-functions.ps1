function Invoke-EKSBestPractices {
    param (
        [string]$Region,
        [string]$ClusterName,
        [switch]$FailedOnly,
        [switch]$Html,
        [switch]$Json,
        [switch]$Text,
        [object]$KubeData
    )

    function Validate-Context {
        param ($Region, $ClusterName)
        if ($KubeData) { return $true }
        $currentContext = kubectl config current-context 2>$null
        $eksContext = "arn:aws:eks:$($Region):*:cluster/$ClusterName"
        if ($currentContext -notlike "*$ClusterName*") {
            Write-Host "🔄 Setting kubectl context for EKS..." -ForegroundColor Yellow
            try {
                aws eks update-kubeconfig --region $Region --name $ClusterName
            } catch {
                Write-Host "❌ Failed to set EKS context." -ForegroundColor Red
                throw
            }
        }
        # Validate
        $nsCheck = kubectl get ns -o name 2>&1
        if ($nsCheck -match "error" -or $nsCheck -match "authorization") {
            Write-Host "❌ Auth error with kubectl." -ForegroundColor Red
            throw "kubectl context/auth failed."
        }
        Write-Host "✅ Context verified: $ClusterName" -ForegroundColor Green
        return $true
    }

    function Get-EKSClusterInfo {
        param (
            [string]$Region,
            [string]$ClusterName,
            [object]$KubeData
        )
        Write-Host -NoNewline "`n🤖 Fetching EKS cluster details..." -ForegroundColor Cyan
        $clusterInfo = $null
        $constraints = @()
        try {
            if ($KubeData -and $KubeData.EksCluster) {
                $clusterInfo = $KubeData.EksCluster
                $constraints = if ($KubeData.Constraints) { $KubeData.Constraints } else { @() }
                Write-Host "`r🤖 Using cached/mock EKS cluster data. " -ForegroundColor Green
            }
            else {
                # If no cached data, we need to fetch it - but this should be rare since
                # KubeData should be collected first via Get-KubeData
                Write-Host "`r🤖 No cached data found. Consider using Get-KubeData first for better performance." -ForegroundColor Yellow
                
                # Basic cluster info only - full data collection should happen in Get-KubeData
                $clusterInfo = Get-EKSCluster -Region $Region -Name $ClusterName | ConvertTo-Json | ConvertFrom-Json
                Write-Host "`r🤖 Basic cluster data fetched.     " -ForegroundColor Green
                Write-Host -NoNewline "`n🤖 Fetching Kubernetes constraints..." -ForegroundColor Cyan
                $constraints = kubectl get constraints -A -o json | ConvertFrom-Json | Select-Object -ExpandProperty items
                Write-Host "`r🤖 Constraints fetched." -ForegroundColor Green
            }
            $clusterInfo | Add-Member -MemberType NoteProperty -Name "KubeData" -Value @{ Constraints = $constraints }
            return $clusterInfo
        }
        catch {
            Write-Host "`r❌ Error retrieving EKS or constraint data: $($_.Exception.Message)" -ForegroundColor Red
            return $null
        }
    }

    # Load EKS check files from checks/
    $checksFolder = Join-Path -Path $PSScriptRoot -ChildPath "checks/"
    $checks = @()
    if (Test-Path $checksFolder) {
        $checkFiles = Get-ChildItem -Path $checksFolder -Filter "*.ps1" -ErrorAction SilentlyContinue
        foreach ($file in $checkFiles) {
            try { . $file.FullName } catch { Write-Warning "Failed to load $($file.Name): $_" }
        }
        Get-Variable -Name "*Checks" -ErrorAction SilentlyContinue | ForEach-Object {
            if ($_.Value -is [array]) { $checks += $_.Value }
        }
        $checks = $checks | Group-Object -Property ID | ForEach-Object { $_.Group[0] }
    } else {
        Write-Warning "No EKS checks folder found at $checksFolder."
        $checks = @()
    }
    if ($checks.Count -eq 0) {
        Write-Warning "No EKS checks loaded. Using empty check set."
        $checks = @()
    }

    # You can reuse your Run-Checks and Display-Results functions with minor tweaks if needed

    # Main Execution Flow
    if ($Text) { Write-Host -NoNewline "`n🤖 Starting EKS Best Practices Check...`n" -ForegroundColor Cyan }
    try {
        Validate-Context -Region $Region -ClusterName $ClusterName
        $clusterInfo = Get-EKSClusterInfo -Region $Region -ClusterName $ClusterName -KubeData $KubeData
        if (-not $clusterInfo) { throw "Failed to retrieve EKS cluster info." }
        $checkResults = Run-Checks -clusterInfo $clusterInfo
        if ($Json) { return Display-Results -categories $checkResults -FailedOnly:$FailedOnly -Json }
        elseif ($Html) { return Display-Results -categories $checkResults -FailedOnly:$FailedOnly -Html }
        elseif ($Text) { $results = Display-Results -categories $checkResults -FailedOnly:$FailedOnly -Text; return $results }
        else { Display-Results -categories $checkResults -FailedOnly:$FailedOnly }
    }
    catch {
        Write-Error "❌ Error running EKS Best Practices: $_"
        if ($Json) {
            return @{
                Total = 0
                Items = @(@{
                        ID      = "EKSBestPractices"
                        Name    = "EKS Best Practices"
                        Message = "Error running EKS checks: $_"
                        Total   = 0
                        Items   = @()
                    })
            }
        }
        throw
    }
    if ($Text) { Write-Host "`r✅ EKS Best Practices Check Completed." -ForegroundColor Green }
}